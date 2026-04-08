# AGENTS.override.md — Auth/

This directory owns the two pre-authentication screens. It has no state objects of its own — auth state lives in `AppCoordinator` (StratixCore).

**Modernization contract reference:** If auth-surface work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `AuthView.swift` | Sign-in landing screen. Uses `GamePassAmbientBackground`, STRATIX wordmark, and a GamePass-styled sign-in button. |
| `DeviceCodeView.swift` | Device code / QR code screen. Shown after the user initiates sign-in. Reads `DeviceCodeInfo` from AppCoordinator state. |

---

## Design

Both views use the ambient background + dark theme. The design system components to use here:
- `GamePassAmbientBackground` — full-screen ambient background
- `GlassCard` — frosted glass panels
- `GamePassTVButtonStyle()` — press animation on buttons
- `FocusAwareView` — for custom focus ring styling
- `.gamePassFocusRing(isFocused:cornerRadius:)` — focus ring modifier
- `.gamePassDisableSystemFocusEffect()` — disable default tvOS focus animation

---

## Rules

1. Auth views do not own auth state. They read from and dispatch actions through `AppCoordinator` environment objects.
2. Do not add a separate view model for auth screens. The state is thin and already in `AppCoordinator`.
3. There are no unit tests specific to auth views — they are covered by `AppSmokeTests.swift` which tests that auth state transitions reach the correct view.
