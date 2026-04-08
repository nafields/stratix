#!/usr/bin/env bash
# run_production_hardening_checks.sh
#
# Runs all production hardening validation checks for the reconciled Stratix codebase.
# Verifies structural safety guarantees, runs all real package unit tests, and
# builds the tvOS target. Designed for CI and pre-merge gates.
#
# Usage: bash Tools/test/run_production_hardening_checks.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$REPO_ROOT"

PASS=0
FAIL=0
WARN=0

pass() { echo "✅ PASS: $1"; PASS=$((PASS+1)); }
fail() { echo "❌ FAIL: $1"; FAIL=$((FAIL+1)); }
warn() { echo "⚠️ WARN: $1"; WARN=$((WARN+1)); }
section() { echo ""; echo "── $1 ──"; }

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: Production safety greps
# ─────────────────────────────────────────────────────────────────────────────
section "Production safety greps"

# 1a. forceHardcodedCloudOfferProfile must never be unconditionally true in production
if grep -rn 'forceHardcodedCloudOfferProfile\s*=\s*true' Packages/ Apps/ 2>/dev/null | grep -v '#if DEBUG' | grep -qv '^\s*//'; then
    fail "forceHardcodedCloudOfferProfile = true found outside #if DEBUG"
else
    pass "No always-on forceHardcodedCloudOfferProfile in production code"
fi

# 1b. Zero @AppStorage in MainTabView (settings must go through SettingsStore)
if grep -q '@AppStorage' Apps/Stratix/Sources/Stratix/Views/MainTabView.swift 2>/dev/null; then
    fail "@AppStorage found in MainTabView.swift — settings dual-ownership violation"
else
    pass "No @AppStorage in MainTabView.swift"
fi

# 1c. No deprecated shell views in active app sources
SHELL_VIOLATIONS=$(find Apps/Stratix/Sources \
    \( -name "EntertainmentShellRootView.swift" -o -name "HomeStreamView.swift" \) \
    2>/dev/null | wc -l | tr -d ' ')
if [ "$SHELL_VIOLATIONS" -gt 0 ]; then
    fail "Deprecated shell views found: EntertainmentShellRootView.swift or HomeStreamView.swift"
else
    pass "No deprecated shell views (no EntertainmentShellRootView, no HomeStreamView)"
fi

# 1d. No scaffold packages (stub packages with no runtime value)
SCAFFOLD_COUNT=$(find Packages/ -maxdepth 1 -type d \( -name 'AppShell' -o -name 'AppState' -o -name 'SharedUI' -o -name 'Feature*' \) 2>/dev/null | wc -l | tr -d ' ')
if [ "$SCAFFOLD_COUNT" -gt 0 ]; then
    fail "Scaffold packages found — these 3-line stubs must not exist"
else
    pass "No scaffold packages"
fi

# 1e. Unified streaming: no HomeStreamView references in active source roots
if grep -rn 'HomeStreamView\b' \
    Apps/Stratix/Sources \
    Packages/StratixCore/Sources \
    Packages/StreamingCore/Sources \
    Packages/XCloudAPI/Sources \
    Packages/InputBridge/Sources \
    2>/dev/null | grep -qv '^\s*//'; then
    fail "HomeStreamView reference found — unified streaming violated"
else
    pass "No HomeStreamView references (unified streaming preserved)"
fi

# 1f. Canonical shell composition sources must remain in the app Shell/ area
if [ ! -f "Apps/Stratix/Sources/Stratix/Shell/MainTabView.swift" ] || \
   [ ! -f "Apps/Stratix/Sources/Stratix/Shell/StratixTabContentView.swift" ]; then
    fail "Canonical top-level shell composition files are missing from app Shell/"
elif [ -f "Apps/Stratix/Sources/Stratix/Views/MainTabView.swift" ]; then
    fail "Legacy Views/MainTabView.swift reintroduced alongside canonical Shell/ composition sources"
else
    pass "Top-level shell composition remains in canonical app Shell/ sources"
fi

# 1g. Coordinator rebroadcast plumbing must not be reintroduced
if rg -n 'bindControllerObjectChanges|objectWillChange\\s*\\.sink|AnyCancellable|cancellables' \
    Packages/StratixCore/Sources/StratixCore/AppCoordinator.swift >/dev/null 2>&1; then
    fail "Coordinator rebroadcast plumbing detected in AppCoordinator.swift"
else
    pass "No coordinator rebroadcast plumbing in AppCoordinator.swift"
fi

# 1h. Production views must not observe AppCoordinator directly as primary state object
if rg -n '@(EnvironmentObject|ObservedObject)\\s+[^\\n]*AppCoordinator' \
    Apps/Stratix/Sources/Stratix/Views >/dev/null 2>&1; then
    fail "Production views observe AppCoordinator directly (fan-out regression)"
else
    pass "No production views observe AppCoordinator directly"
fi

# 1i. AppCoordinator must not expose internal workflow/service composition seams publicly
if rg -n 'public (let|var) (lifecycleCoordinator|shellBootCoordinator|consoleControllerServices|profileControllerServices|achievementsControllerServices|libraryControllerServices|inputControllerServices|streamControllerServices)\b' \
    Packages/StratixCore/Sources/StratixCore/App/AppCoordinator.swift >/dev/null 2>&1; then
    fail "AppCoordinator exposes internal workflow/service composition seams publicly"
else
    pass "AppCoordinator keeps internal workflow/service composition seams private"
fi

# 1j. Controller monolith file must stay deleted after per-domain split
if [ -f "Packages/StratixCore/Sources/StratixCore/DomainControllers.swift" ]; then
    fail "Deprecated DomainControllers.swift monolith file reintroduced"
else
    pass "No DomainControllers.swift monolith file in StratixCore sources"
fi

# 1k. App target must use StratixTheme as the sole runtime token source
if rg -n '\bGamePassTheme\b' \
    Apps/Stratix/Sources/Stratix >/dev/null 2>&1; then
    fail "GamePassTheme runtime references detected in app target (StratixTheme hard-cut violated)"
else
    pass "No GamePassTheme runtime references in app target"
fi

# 1l. Legacy chrome identifiers must not exist in runtime sources
if rg -n 'TopChrome|chrome_nav_' \
    Apps/Stratix/Sources/Stratix >/dev/null 2>&1; then
    fail "Legacy TopChrome/chrome_nav runtime references detected"
else
    pass "No legacy TopChrome/chrome_nav runtime references"
fi

# 1m. Forced CTA autofocus API must not be reintroduced
if rg -n 'defaultFocusedActionID|\\.defaultFocus\\(' \
    Apps/Stratix/Sources/Stratix >/dev/null 2>&1; then
    fail "Forced CTA autofocus API detected in app target"
else
    pass "No forced CTA autofocus API in app target"
fi

# 1n. Architecture guard suite must pass
echo "  bash Tools/dev/run_architecture_guards.sh"
if bash Tools/dev/run_architecture_guards.sh > /tmp/production_hardening_architecture.log 2>&1; then
    pass "Architecture guard suite passed"
else
    cat /tmp/production_hardening_architecture.log
    fail "Architecture guard suite FAILED"
fi

# 1o. Docs/repo portability and truth checks must pass
echo "  bash Tools/docs/run_docs_checks.sh"
if bash Tools/docs/run_docs_checks.sh > /tmp/production_hardening_docs.log 2>&1; then
    pass "Docs and repo portability checks passed"
else
    cat /tmp/production_hardening_docs.log
    fail "Docs and repo portability checks FAILED"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: File size guardrails
# ─────────────────────────────────────────────────────────────────────────────
section "File size guardrails"

check_line_count() {
    local file="$1"
    local max="$2"
    local label="$3"
    if [ ! -f "$file" ]; then
        fail "$label: file not found at $file"
        return
    fi
    local count
    count=$(wc -l < "$file")
    if [ "$count" -gt "$max" ]; then
        warn "$label: $count lines > guideline $max (advisory only)"
    else
        pass "$label: $count lines (≤ $max)"
    fi
}

check_line_count \
    "Apps/Stratix/Sources/Stratix/Shell/MainTabView.swift" \
    520 \
    "MainTabView.swift"

check_line_count \
    "Apps/Stratix/Sources/Stratix/Features/CloudLibrary/Root/CloudLibraryView.swift" \
    1200 \
    "CloudLibraryView.swift"

check_line_count \
    "Packages/StratixCore/Sources/StratixCore/App/AppCoordinator.swift" \
    600 \
    "AppCoordinator.swift"

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: Package unit tests
# ─────────────────────────────────────────────────────────────────────────────
section "Package unit tests"

echo "  bash Tools/dev/run_package_sweep.sh"
if bash Tools/dev/run_package_sweep.sh > /tmp/production_hardening_package_sweep.log 2>&1; then
    pass "Wrapper-backed package sweep succeeded"
else
    cat /tmp/production_hardening_package_sweep.log
    fail "Wrapper-backed package sweep FAILED"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: tvOS build
# ─────────────────────────────────────────────────────────────────────────────
section "tvOS build"

echo "  bash Tools/dev/run_debug_build.sh"
if bash Tools/dev/run_debug_build.sh > /tmp/production_hardening_debug_build.log 2>&1; then
    pass "Wrapper-backed tvOS workspace build succeeded"
else
    cat /tmp/production_hardening_debug_build.log
    fail "Wrapper-backed tvOS workspace build FAILED"
fi

# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: Shell regression
# ─────────────────────────────────────────────────────────────────────────────
section "Shell regression"

echo "  bash Tools/test/run_shell_visual_regression.sh"
if bash Tools/test/run_shell_visual_regression.sh > /tmp/production_hardening_shell.log 2>&1; then
    pass "Shell regression checks passed"
else
    cat /tmp/production_hardening_shell.log
    fail "Shell regression checks FAILED"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: $PASS passed, $FAIL failed, $WARN warnings"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
