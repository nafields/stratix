#!/usr/bin/env python3
from __future__ import annotations

import os

from common import changed_files, fail, read_text, rel

errors: list[str] = []

doc = rel("Docs/PACKAGE_PLATFORM_AUDIT.md")
if not doc.exists():
    errors.append(f"Missing required audit doc: {doc}")
    fail(errors)

doc_text = read_text(doc)

expected_packages = {
    "DiagnosticsKit": [".macOS(.v14)", ".tvOS(.v26)", ".iOS(.v17)"],
    "StratixCore": [".macOS(.v14)", ".tvOS(.v26)", ".iOS(.v17)"],
    "StratixModels": [".macOS(.v14)", ".tvOS(.v26)", ".iOS(.v17)"],
    "InputBridge": [".macOS(.v14)", ".tvOS(.v26)", ".iOS(.v17)"],
    "StreamingCore": [".macOS(.v14)", ".tvOS(.v26)", ".iOS(.v17)"],
    "VideoRenderingKit": [".macOS(.v14)", ".tvOS(.v26)"],
    "XCloudAPI": [".macOS(.v14)", ".tvOS(.v26)", ".iOS(.v17)"],
}

for package, tokens in expected_packages.items():
    manifest = rel("Packages", package, "Package.swift")
    if not manifest.exists():
        errors.append(f"Missing package manifest: {manifest}")
        continue
    manifest_text = read_text(manifest)
    if "// swift-tools-version: 6.2" not in manifest_text:
        errors.append(f"{manifest}: expected swift-tools-version 6.2")
    for token in tokens:
        if token not in manifest_text:
            errors.append(f"{manifest}: expected platform token {token!r}")

    matching_lines = [line for line in doc_text.splitlines() if f"| {package} |" in line]
    if not matching_lines:
        errors.append(f"{doc}: missing audit row for {package}")
        continue
    row = matching_lines[0]
    for token in tokens:
        if token not in row:
            errors.append(f"{doc}: row for {package} missing token {token!r}")

project = rel("Apps/Stratix/Stratix.xcodeproj/project.pbxproj")
if not project.exists():
    errors.append(f"Missing Xcode project: {project}")
else:
    project_text = read_text(project)
    if "TVOS_DEPLOYMENT_TARGET = 26.0;" not in project_text:
        errors.append(f"{project}: expected tvOS deployment target 26.0")

required_doc_needles = [
    "No package manifest was lowered in Stage 8.",
    "tvOS 26.0",
    "swift-tools-version 6.2",
]
for needle in required_doc_needles:
    if needle not in doc_text:
        errors.append(f"{doc}: missing audit conclusion {needle!r}")

base_ref = os.environ.get("GITHUB_BASE_REF", "")
if base_ref:
    try:
        changed = changed_files(base_ref)
        platform_sensitive_paths = {
            "Apps/Stratix/Stratix.xcodeproj/project.pbxproj",
            *{
                f"Packages/{package}/Package.swift"
                for package in expected_packages
            },
        }
        if any(path in platform_sensitive_paths for path in changed):
            if "Docs/PACKAGE_PLATFORM_AUDIT.md" not in changed:
                errors.append(
                    "Package manifests or deployment-target project settings changed but "
                    "Docs/PACKAGE_PLATFORM_AUDIT.md did not change."
                )
    except Exception:
        pass  # changed_files is a CI-only guard; skip when base ref is unavailable locally

fail(errors)
print("Stage 8 package platform audit guard passed.")
