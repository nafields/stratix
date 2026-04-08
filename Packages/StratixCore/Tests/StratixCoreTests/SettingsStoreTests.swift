// SettingsStoreTests.swift
// Exercises settings store behavior.
//

import Foundation
import Observation
import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct SettingsStoreTests {
    actor ChangeFlag {
        private var value = false

        func mark() {
            value = true
        }

        func currentValue() -> Bool {
            value
        }
    }

    @Test
    func preservesExistingGuideKeysOnInitialLoad() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.preservesExistingGuideKeysOnInitialLoad")!
        suite.removePersistentDomain(forName: "SettingsStoreTests.preservesExistingGuideKeysOnInitialLoad")
        suite.set("High Quality", forKey: "guide.stream_quality")
        suite.set(true, forKey: "guide.reduce_motion")
        suite.set("My Player", forKey: "guide.profile_name")
        suite.set(0.66, forKey: "guide.guide_translucency")
        suite.set("bottomLeft", forKey: "stratix.stream.statsHUDPosition")
        suite.set(true, forKey: "debug_use_rtc_mtl_video_renderer")

        let store = SettingsStore(defaults: suite)

        #expect(store.stream.qualityPreset == "High Quality")
        #expect(store.accessibility.reduceMotion == true)
        #expect(store.shell.profileName == "My Player")
        #expect(store.shell.guideTranslucency == 0.66)
        #expect(store.stream.statsHUDPosition == "bottomLeft")
        #expect(store.diagnostics.useRTCMTLVideoRenderer == true)
    }

    @Test
    func updatesPersistBackToDefaults() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.updatesPersistBackToDefaults")!
        suite.removePersistentDomain(forName: "SettingsStoreTests.updatesPersistBackToDefaults")

        let store = SettingsStore(defaults: suite)
        store.shell.profileName = "Wesley"
        store.shell.quickResumeTile = false
        store.library.autoRefreshTTLHours = 48.0
        store.stream.regionOverride = "US East"
        store.stream.statsHUDPosition = "bottomLeft"
        store.controller.triggerInterpretationMode = .analogOnly
        store.diagnostics.verboseLogs = true

        #expect(suite.string(forKey: "guide.profile_name") == "Wesley")
        #expect(suite.object(forKey: "guide.quick_resume_tile") as? Bool == false)
        #expect(suite.object(forKey: "guide.library_auto_refresh_ttl_hours") as? Double == 48.0)
        #expect(suite.string(forKey: "guide.region_override") == "US East")
        #expect(suite.string(forKey: "stratix.stream.statsHUDPosition") == "bottomLeft")
        #expect(suite.string(forKey: "guide.trigger_interpretation_mode") == store.controller.triggerInterpretationMode.rawValue)
        #expect(suite.object(forKey: "debug.stream.verbose_logs") as? Bool == true)
    }

    @Test
    func reloadsWhenDefaultsChangeExternally() async {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.reloadsWhenDefaultsChangeExternally")!
        suite.removePersistentDomain(forName: "SettingsStoreTests.reloadsWhenDefaultsChangeExternally")

        let store = SettingsStore(defaults: suite)
        suite.set("Competitive", forKey: "guide.stream_quality")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: suite)
        await Task.yield()

        #expect(store.stream.qualityPreset == "Competitive")
    }

    @Test
    func reloadsOnlyChangedSectionWhenDefaultsChangeExternally() async {
        let suiteName = "SettingsStoreTests.reloadsOnlyChangedSectionWhenDefaultsChangeExternally"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: suite)

        let streamInvalidated = ChangeFlag()
        let accessibilityInvalidated = ChangeFlag()

        withObservationTracking({
            _ = store.stream.qualityPreset
        }, onChange: {
            Task { await streamInvalidated.mark() }
        })

        withObservationTracking({
            _ = store.accessibility.reduceMotion
        }, onChange: {
            Task { await accessibilityInvalidated.mark() }
        })

        suite.set("Competitive", forKey: "guide.stream_quality")
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: suite)
        await Task.yield()

        #expect(store.stream.qualityPreset == "Competitive")
        #expect(await streamInvalidated.currentValue() == true)
        #expect(await accessibilityInvalidated.currentValue() == false)
    }

    @Test
    func buildsControllerSettingsAdapter() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.buildsControllerSettingsAdapter")!
        suite.removePersistentDomain(forName: "SettingsStoreTests.buildsControllerSettingsAdapter")

        let store = SettingsStore(defaults: suite)
        store.controller.deadzone = 0.24
        store.controller.invertYAxis = true
        store.controller.swapABButtons = true
        store.controller.triggerSensitivity = 0.33
        store.controller.triggerInterpretationMode = .digitalFallback
        store.controller.vibrationIntensity = 0.72

        let settings = store.buildControllerSettings()

        #expect(settings.deadzone == 0.24)
        #expect(settings.invertY == true)
        #expect(settings.swapAB == true)
        #expect(settings.triggerSensitivity == 0.33)
        #expect(settings.triggerInterpretationMode == .digitalFallback)
        #expect(settings.vibrationIntensity == 0.72)
    }

    @Test
    func migrateLegacyStatsHUDKey_migratesWhenGuideKeyMissing() {
        let suiteName = "SettingsStoreTests.migrateLegacyStatsHUDKey.migratesWhenGuideKeyMissing"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        suite.set(true, forKey: "stratix.stream.showStatsHUD")
        suite.removeObject(forKey: "guide.show_stream_stats")
        suite.removeObject(forKey: "stratix.migrations.guide_show_stream_stats.v1")

        let store = SettingsStore(defaults: suite)

        #expect(store.didMigrateLegacyStatsHUDThisLaunch == true)
        #expect(suite.object(forKey: "guide.show_stream_stats") as? Bool == true)
    }

    @Test
    func diagnostics_startupHapticsProbeRoundTrips() {
        let suiteName = "SettingsStoreTests.diagnostics.startupHapticsProbeRoundTrips"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: suite)
        store.diagnostics.startupHapticsProbeEnabled = false

        #expect(suite.object(forKey: "debug.controller.startup_haptics_probe") as? Bool == false)
        #expect(store.diagnostics.startupHapticsProbeEnabled == false)
    }

    @Test
    func migrateLegacyRendererMode_mapsSampleBufferToUpscalingDisabled() {
        let suiteName = "SettingsStoreTests.migrateLegacyRendererMode.mapsSampleBufferToUpscalingDisabled"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        suite.set("sampleBuffer", forKey: "guide.renderer_mode")
        suite.removeObject(forKey: "guide.upscaling_enabled")
        suite.removeObject(forKey: "stratix.migrations.guide_upscaling_enabled.v1")

        let store = SettingsStore(defaults: suite)

        #expect(store.stream.upscalingEnabled == false)
        #expect(suite.object(forKey: "guide.upscaling_enabled") as? Bool == false)
    }

    @Test
    func diagnostics_upscalingFloorBehaviorRoundTrips() {
        let suiteName = "SettingsStoreTests.diagnostics.upscalingFloorBehaviorRoundTrips"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let store = SettingsStore(defaults: suite)
        store.diagnostics.upscalingFloorBehavior = .metalFloor

        #expect(suite.string(forKey: "stratix.debug.upscaling_floor_behavior") == "metalFloor")
        #expect(store.diagnostics.upscalingFloorBehavior == .metalFloor)
    }
}
