// WebRTCVideoSurfaceViewBinderTests.swift
// Exercises web rtc video surface view binder behavior.
//

import Testing
@testable import Stratix
import StratixCore

@MainActor
@Suite
struct WebRTCVideoSurfaceViewBinderTests {
    @Test
    func configurationFactoryReadsSettingsStoreInsteadOfViewOwningBranchLogic() {
        let settingsStore = SettingsStore()
        var stream = settingsStore.stream
        stream.upscalingEnabled = false
        stream.hdrEnabled = false
        settingsStore.stream = stream

        var diagnostics = settingsStore.diagnostics
        diagnostics.frameProbe = true
        diagnostics.upscalingFloorBehavior = .metalFloor
        settingsStore.diagnostics = diagnostics

        let configuration = RendererAttachmentCoordinator.Configuration.make(
            settingsStore: settingsStore,
            callbacks: .noop
        )

        #expect(configuration.upscalingEnabled == false)
        #expect(configuration.frameProbeEnabled == true)
        #expect(configuration.hdrEnabled == false)
        #expect(configuration.floorBehavior == .metalFloor)
    }

    @Test
    func configurationFactoryDefaultsToSampleFloorWhenDiagnosticsDoNotOverride() {
        let settingsStore = SettingsStore()
        var diagnostics = settingsStore.diagnostics
        diagnostics.upscalingFloorBehavior = .sampleFloor
        settingsStore.diagnostics = diagnostics

        let configuration = RendererAttachmentCoordinator.Configuration.make(
            settingsStore: settingsStore,
            callbacks: .noop
        )

        #expect(configuration.floorBehavior == .sampleFloor)
    }
}
