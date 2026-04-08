#!/usr/bin/env python3
from __future__ import annotations

from common import rel, require_paths, read_text, line_count, fail

errors: list[str] = []

required_paths = [
    rel("Packages/StratixModels/Sources/StratixModels/Achievements/AchievementModels.swift"),
    rel("Packages/StratixModels/Sources/StratixModels/CloudLibrary/CloudLibraryModels.swift"),
    rel("Packages/StratixModels/Sources/StratixModels/Identifiers/ProductID.swift"),
    rel("Packages/StratixModels/Sources/StratixModels/Identifiers/TitleID.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRendererPlainPipeline.swift"),
    rel("Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRendererLifecycle.swift"),
    rel("Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplStats.swift"),
    rel("Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplDataChannels.swift"),
    rel("Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImplTVOSAudio.swift"),
]
errors.extend(require_paths(required_paths))

fail(errors)
print("Stage 1 decomposition floor guard passed.")
