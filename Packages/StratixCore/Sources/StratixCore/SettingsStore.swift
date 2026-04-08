// SettingsStore.swift
// Defines the settings store.
//

import Foundation
import Observation
import StratixModels

@Observable
@MainActor
public final class SettingsStore {

    public struct ShellSettings: Sendable, Equatable {
        public var profileName: String
        public var profileImageURLString: String
        /// Local display override for Xbox presence: "Auto", "Online", or "Offline".
        /// Used when presence write API is unavailable. Falls back to live Xbox presence when "Auto".
        public var profilePresenceOverride: String
        public var rememberLastSection: Bool
        public var lastDestinationRawValue: String
        public var lastSettingsCategoryRawValue: String
        public var quickResumeTile: Bool
        public var focusGlowIntensity: Double
        public var guideTranslucency: Double

        public init(
            profileName: String = "Player",
            profileImageURLString: String = "",
            profilePresenceOverride: String = "Auto",
            rememberLastSection: Bool = true,
            lastDestinationRawValue: String = "home",
            lastSettingsCategoryRawValue: String = "playback",
            quickResumeTile: Bool = true,
            focusGlowIntensity: Double = 0.85,
            guideTranslucency: Double = 0.82
        ) {
            self.profileName = profileName
            self.profileImageURLString = profileImageURLString
            self.profilePresenceOverride = profilePresenceOverride
            self.rememberLastSection = rememberLastSection
            self.lastDestinationRawValue = lastDestinationRawValue
            self.lastSettingsCategoryRawValue = lastSettingsCategoryRawValue
            self.quickResumeTile = quickResumeTile
            self.focusGlowIntensity = focusGlowIntensity
            self.guideTranslucency = guideTranslucency
        }
    }

    public struct LibrarySettings: Sendable, Equatable {
        public var autoRefreshEnabled: Bool
        public var autoRefreshTTLHours: Double
        public var focusPrefetchEnabled: Bool

        public init(
            autoRefreshEnabled: Bool = true,
            autoRefreshTTLHours: Double = 12.0,
            focusPrefetchEnabled: Bool = true
        ) {
            self.autoRefreshEnabled = autoRefreshEnabled
            self.autoRefreshTTLHours = autoRefreshTTLHours
            self.focusPrefetchEnabled = focusPrefetchEnabled
        }
    }

    public struct StreamSettings: Sendable, Equatable {
        public var locale: String
        public var preferIPv6: Bool
        public var preferredRegionID: String
        public var statsHUDPosition: String
        public var qualityPreset: String
        public var codecPreference: String
        public var clientProfileOSName: String
        public var preferredResolution: String
        public var preferredFPS: String
        public var bitrateCapMbps: Double
        public var hdrEnabled: Bool
        public var lowLatencyMode: Bool
        public var showStreamStats: Bool
        public var autoReconnect: Bool
        public var packetLossProtection: Bool
        public var regionOverride: String
        public var upscalingEnabled: Bool
        public var audioBoost: Double
        public var colorRange: String
        public var safeAreaPercent: Double
        public var stereoAudio: Bool
        public var chatChannelEnabled: Bool

        public init(
            locale: String = "en-US",
            preferIPv6: Bool = true,
            preferredRegionID: String = "",
            statsHUDPosition: String = "topRight",
            qualityPreset: String = "Balanced",
            codecPreference: String = "H.264",
            clientProfileOSName: String = "Auto",
            preferredResolution: String = "1080p",
            preferredFPS: String = "60",
            bitrateCapMbps: Double = 0,
            hdrEnabled: Bool = true,
            lowLatencyMode: Bool = true,
            showStreamStats: Bool = false,
            autoReconnect: Bool = true,
            packetLossProtection: Bool = true,
            regionOverride: String = "Auto",
            upscalingEnabled: Bool = true,
            audioBoost: Double = 3.0,
            colorRange: String = "Auto",
            safeAreaPercent: Double = 100.0,
            stereoAudio: Bool = false,
            chatChannelEnabled: Bool = false
        ) {
            self.locale = locale
            self.preferIPv6 = preferIPv6
            self.preferredRegionID = preferredRegionID
            self.statsHUDPosition = statsHUDPosition
            self.qualityPreset = qualityPreset
            self.codecPreference = codecPreference
            self.clientProfileOSName = clientProfileOSName
            self.preferredResolution = preferredResolution
            self.preferredFPS = preferredFPS
            self.bitrateCapMbps = bitrateCapMbps
            self.hdrEnabled = hdrEnabled
            self.lowLatencyMode = lowLatencyMode
            self.showStreamStats = showStreamStats
            self.autoReconnect = autoReconnect
            self.packetLossProtection = packetLossProtection
            self.regionOverride = regionOverride
            self.upscalingEnabled = upscalingEnabled
            self.audioBoost = audioBoost
            self.colorRange = colorRange
            self.safeAreaPercent = safeAreaPercent
            self.stereoAudio = stereoAudio
            self.chatChannelEnabled = chatChannelEnabled
        }
    }

    public struct ControllerSettings: Sendable, Equatable {
        public var vibrationEnabled: Bool
        public var invertYAxis: Bool
        public var deadzone: Double
        public var triggerSensitivity: Double
        public var triggerInterpretationMode: StratixModels.ControllerSettings.TriggerInterpretationMode
        public var swapABButtons: Bool
        public var sensitivityBoost: Double
        public var vibrationIntensity: Double

        public init(
            vibrationEnabled: Bool = true,
            invertYAxis: Bool = false,
            deadzone: Double = 0.10,
            triggerSensitivity: Double = 0.50,
            triggerInterpretationMode: StratixModels.ControllerSettings.TriggerInterpretationMode = .auto,
            swapABButtons: Bool = false,
            sensitivityBoost: Double = 0,
            vibrationIntensity: Double = 1.0
        ) {
            self.vibrationEnabled = vibrationEnabled
            self.invertYAxis = invertYAxis
            self.deadzone = deadzone
            self.triggerSensitivity = triggerSensitivity
            self.triggerInterpretationMode = triggerInterpretationMode
            self.swapABButtons = swapABButtons
            self.sensitivityBoost = sensitivityBoost
            self.vibrationIntensity = vibrationIntensity
        }
    }

    public struct AccessibilitySettings: Sendable, Equatable {
        public var reduceMotion: Bool
        public var largeText: Bool
        public var closedCaptions: Bool
        public var highVisibilityFocus: Bool

        public init(
            reduceMotion: Bool = false,
            largeText: Bool = false,
            closedCaptions: Bool = false,
            highVisibilityFocus: Bool = false
        ) {
            self.reduceMotion = reduceMotion
            self.largeText = largeText
            self.closedCaptions = closedCaptions
            self.highVisibilityFocus = highVisibilityFocus
        }
    }

    public struct DiagnosticsSettings: Sendable, Equatable {
        public var debugHostInfo: Bool
        public var logNetworkEvents: Bool
        public var blockTracking: Bool
        public var verboseLogs: Bool
        public var useRTCMTLVideoRenderer: Bool
        public var frameProbe: Bool
        public var audioResyncWatchdogEnabled: Bool
        public var startupHapticsProbeEnabled: Bool
        public var upscalingFloorBehavior: UpscalingFloorBehavior

        public init(
            debugHostInfo: Bool = true,
            logNetworkEvents: Bool = false,
            blockTracking: Bool = false,
            verboseLogs: Bool = false,
            useRTCMTLVideoRenderer: Bool = false,
            frameProbe: Bool = false,
            audioResyncWatchdogEnabled: Bool = false,
            startupHapticsProbeEnabled: Bool = false,
            upscalingFloorBehavior: UpscalingFloorBehavior = .sampleFloor
        ) {
            self.debugHostInfo = debugHostInfo
            self.logNetworkEvents = logNetworkEvents
            self.blockTracking = blockTracking
            self.verboseLogs = verboseLogs
            self.useRTCMTLVideoRenderer = useRTCMTLVideoRenderer
            self.frameProbe = frameProbe
            self.audioResyncWatchdogEnabled = audioResyncWatchdogEnabled
            self.startupHapticsProbeEnabled = startupHapticsProbeEnabled
            self.upscalingFloorBehavior = upscalingFloorBehavior
        }
    }

    private enum Key {
        static let profileName = "guide.profile_name"
        static let profileImageURLString = "guide.profile_image_url"
        static let profilePresenceOverride = "guide.profile_presence_override"
        static let rememberLastSection = "guide.remember_last_section"
        static let lastDestinationRawValue = "stratix.shell.lastDestination"
        static let lastSettingsCategoryRawValue = "stratix.settings.lastCategory"
        static let quickResumeTile = "guide.quick_resume_tile"
        static let focusGlowIntensity = "guide.focus_glow_intensity"
        static let guideTranslucency = "guide.guide_translucency"

        static let autoRefreshEnabled = "guide.library_auto_refresh_enabled"
        static let autoRefreshTTLHours = "guide.library_auto_refresh_ttl_hours"
        static let focusPrefetchEnabled = "guide.focus_prefetch_enabled"

        static let locale = "stratix.stream.locale"
        static let preferIPv6 = "stratix.stream.preferIPv6"
        static let preferredRegionID = "stratix.stream.preferredRegionId"
        static let statsHUDPosition = "stratix.stream.statsHUDPosition"
        static let qualityPreset = "guide.stream_quality"
        static let codecPreference = "guide.codec_preference"
        static let clientProfileOSName = "guide.client_profile_os_name"
        static let preferredResolution = "guide.preferred_resolution"
        static let preferredFPS = "guide.preferred_fps"
        static let bitrateCapMbps = "guide.bitrate_cap_mbps"
        static let hdrEnabled = "guide.hdr_enabled"
        static let lowLatencyMode = "guide.low_latency_mode"
        static let showStreamStats = "guide.show_stream_stats"
        static let autoReconnect = "guide.auto_reconnect"
        static let packetLossProtection = "guide.packet_loss_protection"
        static let regionOverride = "guide.region_override"
        static let upscalingEnabled = "guide.upscaling_enabled"
        static let rendererMode = "guide.renderer_mode"
        static let sharpness = "guide.sharpness"
        static let saturation = "guide.saturation"
        static let audioBoost = "guide.audio_boost"
        static let colorRange = "guide.color_range"
        static let safeAreaPercent = "guide.safe_area"
        static let stereoAudio = "guide.stereo_audio"
        static let chatChannelEnabled = "guide.chat_channel"

        static let vibrationEnabled = "guide.enable_vibration"
        static let invertYAxis = "guide.invert_y_axis"
        static let deadzone = "guide.controller_deadzone"
        static let triggerSensitivity = "guide.trigger_sensitivity"
        static let triggerInterpretationMode = "guide.trigger_interpretation_mode"
        static let swapABButtons = "guide.swap_ab_buttons"
        static let sensitivityBoost = "guide.sensitivity_boost"
        static let vibrationIntensity = "stratix.controller.vibrationIntensity"

        static let reduceMotion = "guide.reduce_motion"
        static let largeText = "guide.large_text"
        static let closedCaptions = "guide.closed_captions"
        static let highVisibilityFocus = "guide.high_visibility_focus"

        static let debugHostInfo = "guide.debug_host_info"
        static let logNetworkEvents = "guide.log_network_events"
        static let blockTracking = "stratix.privacy.blockTracking"
        static let verboseLogs = "debug.stream.verbose_logs"
        static let useRTCMTLVideoRenderer = "debug_use_rtc_mtl_video_renderer"
        static let frameProbe = "debug_stream_frame_probe"
        static let audioResyncWatchdogEnabled = "debug.audio_resync_watchdog_enabled"
        static let startupHapticsProbeEnabled = "debug.controller.startup_haptics_probe"
        static let upscalingFloorBehavior = "stratix.debug.upscaling_floor_behavior"
        static let statsHUDMigrationKey = "stratix.migrations.guide_show_stream_stats.v1"
        static let upscalingEnabledMigrationKey = "stratix.migrations.guide_upscaling_enabled.v1"
    }

    private nonisolated static func registeredDefaults() -> [String: Any] {
        [
        Key.profileName: "Player",
        Key.profileImageURLString: "",
        Key.profilePresenceOverride: "Auto",
        Key.rememberLastSection: true,
        Key.lastDestinationRawValue: "home",
        Key.lastSettingsCategoryRawValue: "playback",
        Key.quickResumeTile: true,
        Key.focusGlowIntensity: 0.85,
        Key.guideTranslucency: 0.82,
        Key.autoRefreshEnabled: true,
        Key.autoRefreshTTLHours: 12.0,
        Key.focusPrefetchEnabled: true,
        Key.locale: "en-US",
        Key.preferIPv6: false,
        Key.preferredRegionID: "",
        Key.statsHUDPosition: "topRight",
        Key.qualityPreset: "Balanced",
        Key.codecPreference: "H.264",
        Key.clientProfileOSName: "Auto",
        Key.preferredResolution: "1080p",
        Key.preferredFPS: "60",
        Key.bitrateCapMbps: 0.0,
        Key.hdrEnabled: true,
        Key.lowLatencyMode: true,
        Key.showStreamStats: false,
        Key.autoReconnect: true,
        Key.packetLossProtection: true,
        Key.regionOverride: "Auto",
        Key.upscalingEnabled: true,
        Key.rendererMode: "metalCAS",
        Key.sharpness: 0.0,
        Key.saturation: 1.0,
        Key.audioBoost: 3.0,
        Key.colorRange: "Auto",
        Key.safeAreaPercent: 100.0,
        Key.stereoAudio: false,
        Key.chatChannelEnabled: false,
        Key.vibrationEnabled: true,
        Key.invertYAxis: false,
        Key.deadzone: 0.10,
        Key.triggerSensitivity: 0.50,
        Key.triggerInterpretationMode: StratixModels.ControllerSettings.TriggerInterpretationMode.auto.rawValue,
        Key.swapABButtons: false,
        Key.sensitivityBoost: 0.0,
        Key.vibrationIntensity: 1.0,
        Key.reduceMotion: false,
        Key.largeText: false,
        Key.closedCaptions: false,
        Key.highVisibilityFocus: false,
        Key.debugHostInfo: true,
        Key.logNetworkEvents: false,
        Key.blockTracking: false,
        Key.verboseLogs: false,
        Key.useRTCMTLVideoRenderer: false,
        Key.frameProbe: false,
        Key.audioResyncWatchdogEnabled: true,
        Key.startupHapticsProbeEnabled: true,
        Key.upscalingFloorBehavior: UpscalingFloorBehavior.sampleFloor.rawValue
        ]
    }

    public nonisolated static func snapshotShell(defaults: UserDefaults = .standard) -> ShellSettings {
        defaults.register(defaults: registeredDefaults())
        return readShell(from: defaults)
    }

    public nonisolated static func snapshotLibrary(defaults: UserDefaults = .standard) -> LibrarySettings {
        defaults.register(defaults: registeredDefaults())
        return readLibrary(from: defaults)
    }

    public nonisolated static func snapshotStream(defaults: UserDefaults = .standard) -> StreamSettings {
        defaults.register(defaults: registeredDefaults())
        return readStream(from: defaults)
    }

    public nonisolated static func snapshotController(defaults: UserDefaults = .standard) -> ControllerSettings {
        defaults.register(defaults: registeredDefaults())
        return readController(from: defaults)
    }

    public nonisolated static func snapshotAccessibility(defaults: UserDefaults = .standard) -> AccessibilitySettings {
        defaults.register(defaults: registeredDefaults())
        return readAccessibility(from: defaults)
    }

    public nonisolated static func snapshotDiagnostics(defaults: UserDefaults = .standard) -> DiagnosticsSettings {
        defaults.register(defaults: registeredDefaults())
        return readDiagnostics(from: defaults)
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var defaultsObserver: NSObjectProtocol?
    @ObservationIgnored private var isReloadingFromDefaults = false
    @ObservationIgnored public private(set) var didMigrateLegacyStatsHUDThisLaunch = false

    public var shell: ShellSettings {
        didSet {
            persist(shell, oldValue: oldValue)
        }
    }

    public var library: LibrarySettings {
        didSet {
            persist(library, oldValue: oldValue)
        }
    }

    public var stream: StreamSettings {
        didSet {
            persist(stream, oldValue: oldValue)
        }
    }

    public var controller: ControllerSettings {
        didSet {
            persist(controller, oldValue: oldValue)
        }
    }

    public var accessibility: AccessibilitySettings {
        didSet {
            persist(accessibility, oldValue: oldValue)
        }
    }

    public var diagnostics: DiagnosticsSettings {
        didSet {
            persist(diagnostics, oldValue: oldValue)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: Self.registeredDefaults())
        let appDomainName = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        self.didMigrateLegacyStatsHUDThisLaunch = Self.migrateLegacyStatsHUDKey(
            defaults: defaults,
            appDomainName: appDomainName
        )
        Self.migrateLegacyUpscalingEnabled(defaults: defaults)
        self.shell = Self.readShell(from: defaults)
        self.library = Self.readLibrary(from: defaults)
        self.stream = Self.readStream(from: defaults)
        self.controller = Self.readController(from: defaults)
        self.accessibility = Self.readAccessibility(from: defaults)
        self.diagnostics = Self.readDiagnostics(from: defaults)

        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: defaults,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadFromDefaults()
            }
        }
        defaultsObserver = observer
    }

    isolated deinit {
        if let defaultsObserver {
            NotificationCenter.default.removeObserver(defaultsObserver)
        }
    }

    public var profileImageURL: URL? {
        URL(string: shell.profileImageURLString)
    }

    public func updateProfile(name: String?, imageURLString: String?) {
        var nextShell = shell
        if let name, !name.isEmpty {
            nextShell.profileName = name
        }
        if let imageURLString {
            nextShell.profileImageURLString = imageURLString
        }
        shell = nextShell
    }

    public func buildControllerSettings() -> StratixModels.ControllerSettings {
        var settings = StratixModels.ControllerSettings()
        settings.deadzone = Float(controller.deadzone)
        settings.invertY = controller.invertYAxis
        settings.swapAB = controller.swapABButtons
        settings.triggerSensitivity = Float(controller.triggerSensitivity)
        settings.triggerInterpretationMode = controller.triggerInterpretationMode
        settings.vibrationIntensity = Float(controller.vibrationIntensity)
        return settings
    }

    private func reloadFromDefaults() {
        guard !isReloadingFromDefaults else { return }
        isReloadingFromDefaults = true
        let nextShell = Self.readShell(from: defaults)
        let nextLibrary = Self.readLibrary(from: defaults)
        let nextStream = Self.readStream(from: defaults)
        let nextController = Self.readController(from: defaults)
        let nextAccessibility = Self.readAccessibility(from: defaults)
        let nextDiagnostics = Self.readDiagnostics(from: defaults)
        if shell != nextShell { shell = nextShell }
        if library != nextLibrary { library = nextLibrary }
        if stream != nextStream { stream = nextStream }
        if controller != nextController { controller = nextController }
        if accessibility != nextAccessibility { accessibility = nextAccessibility }
        if diagnostics != nextDiagnostics { diagnostics = nextDiagnostics }
        isReloadingFromDefaults = false
    }

    private func persist(_ value: ShellSettings, oldValue: ShellSettings) {
        guard !isReloadingFromDefaults, value != oldValue else { return }
        defaults.set(value.profileName, forKey: Key.profileName)
        defaults.set(value.profileImageURLString, forKey: Key.profileImageURLString)
        defaults.set(value.profilePresenceOverride, forKey: Key.profilePresenceOverride)
        defaults.set(value.rememberLastSection, forKey: Key.rememberLastSection)
        defaults.set(value.lastDestinationRawValue, forKey: Key.lastDestinationRawValue)
        defaults.set(value.lastSettingsCategoryRawValue, forKey: Key.lastSettingsCategoryRawValue)
        defaults.set(value.quickResumeTile, forKey: Key.quickResumeTile)
        defaults.set(value.focusGlowIntensity, forKey: Key.focusGlowIntensity)
        defaults.set(value.guideTranslucency, forKey: Key.guideTranslucency)
    }

    private func persist(_ value: LibrarySettings, oldValue: LibrarySettings) {
        guard !isReloadingFromDefaults, value != oldValue else { return }
        defaults.set(value.autoRefreshEnabled, forKey: Key.autoRefreshEnabled)
        defaults.set(value.autoRefreshTTLHours, forKey: Key.autoRefreshTTLHours)
        defaults.set(value.focusPrefetchEnabled, forKey: Key.focusPrefetchEnabled)
    }

    private func persist(_ value: StreamSettings, oldValue: StreamSettings) {
        guard !isReloadingFromDefaults, value != oldValue else { return }
        defaults.set(value.locale, forKey: Key.locale)
        defaults.set(value.preferIPv6, forKey: Key.preferIPv6)
        defaults.set(value.preferredRegionID, forKey: Key.preferredRegionID)
        defaults.set(value.statsHUDPosition, forKey: Key.statsHUDPosition)
        defaults.set(value.qualityPreset, forKey: Key.qualityPreset)
        defaults.set(value.codecPreference, forKey: Key.codecPreference)
        defaults.set(value.clientProfileOSName, forKey: Key.clientProfileOSName)
        defaults.set(value.preferredResolution, forKey: Key.preferredResolution)
        defaults.set(value.preferredFPS, forKey: Key.preferredFPS)
        defaults.set(value.bitrateCapMbps, forKey: Key.bitrateCapMbps)
        defaults.set(value.hdrEnabled, forKey: Key.hdrEnabled)
        defaults.set(value.lowLatencyMode, forKey: Key.lowLatencyMode)
        defaults.set(value.showStreamStats, forKey: Key.showStreamStats)
        defaults.set(value.autoReconnect, forKey: Key.autoReconnect)
        defaults.set(value.packetLossProtection, forKey: Key.packetLossProtection)
        defaults.set(value.regionOverride, forKey: Key.regionOverride)
        defaults.set(value.upscalingEnabled, forKey: Key.upscalingEnabled)
        defaults.set(value.audioBoost, forKey: Key.audioBoost)
        defaults.set(value.colorRange, forKey: Key.colorRange)
        defaults.set(value.safeAreaPercent, forKey: Key.safeAreaPercent)
        defaults.set(value.stereoAudio, forKey: Key.stereoAudio)
        defaults.set(value.chatChannelEnabled, forKey: Key.chatChannelEnabled)
    }

    private func persist(_ value: ControllerSettings, oldValue: ControllerSettings) {
        guard !isReloadingFromDefaults, value != oldValue else { return }
        defaults.set(value.vibrationEnabled, forKey: Key.vibrationEnabled)
        defaults.set(value.invertYAxis, forKey: Key.invertYAxis)
        defaults.set(value.deadzone, forKey: Key.deadzone)
        defaults.set(value.triggerSensitivity, forKey: Key.triggerSensitivity)
        defaults.set(value.triggerInterpretationMode.rawValue, forKey: Key.triggerInterpretationMode)
        defaults.set(value.swapABButtons, forKey: Key.swapABButtons)
        defaults.set(value.sensitivityBoost, forKey: Key.sensitivityBoost)
        defaults.set(value.vibrationIntensity, forKey: Key.vibrationIntensity)
    }

    private func persist(_ value: AccessibilitySettings, oldValue: AccessibilitySettings) {
        guard !isReloadingFromDefaults, value != oldValue else { return }
        defaults.set(value.reduceMotion, forKey: Key.reduceMotion)
        defaults.set(value.largeText, forKey: Key.largeText)
        defaults.set(value.closedCaptions, forKey: Key.closedCaptions)
        defaults.set(value.highVisibilityFocus, forKey: Key.highVisibilityFocus)
    }

    private func persist(_ value: DiagnosticsSettings, oldValue: DiagnosticsSettings) {
        guard !isReloadingFromDefaults, value != oldValue else { return }
        defaults.set(value.debugHostInfo, forKey: Key.debugHostInfo)
        defaults.set(value.logNetworkEvents, forKey: Key.logNetworkEvents)
        defaults.set(value.blockTracking, forKey: Key.blockTracking)
        defaults.set(value.verboseLogs, forKey: Key.verboseLogs)
        defaults.set(value.useRTCMTLVideoRenderer, forKey: Key.useRTCMTLVideoRenderer)
        defaults.set(value.frameProbe, forKey: Key.frameProbe)
        defaults.set(value.audioResyncWatchdogEnabled, forKey: Key.audioResyncWatchdogEnabled)
        defaults.set(value.startupHapticsProbeEnabled, forKey: Key.startupHapticsProbeEnabled)
        defaults.set(value.upscalingFloorBehavior.rawValue, forKey: Key.upscalingFloorBehavior)
    }

    private nonisolated static func readShell(from defaults: UserDefaults) -> ShellSettings {
        ShellSettings(
            profileName: string(defaults, Key.profileName, fallback: "Player"),
            profileImageURLString: string(defaults, Key.profileImageURLString, fallback: ""),
            profilePresenceOverride: string(defaults, Key.profilePresenceOverride, fallback: "Auto"),
            rememberLastSection: bool(defaults, Key.rememberLastSection, fallback: true),
            lastDestinationRawValue: string(defaults, Key.lastDestinationRawValue, fallback: "home"),
            lastSettingsCategoryRawValue: string(defaults, Key.lastSettingsCategoryRawValue, fallback: "playback"),
            quickResumeTile: bool(defaults, Key.quickResumeTile, fallback: true),
            focusGlowIntensity: double(defaults, Key.focusGlowIntensity, fallback: 0.85),
            guideTranslucency: double(defaults, Key.guideTranslucency, fallback: 0.82)
        )
    }

    private nonisolated static func readLibrary(from defaults: UserDefaults) -> LibrarySettings {
        LibrarySettings(
            autoRefreshEnabled: bool(defaults, Key.autoRefreshEnabled, fallback: true),
            autoRefreshTTLHours: double(defaults, Key.autoRefreshTTLHours, fallback: 12.0),
            focusPrefetchEnabled: bool(defaults, Key.focusPrefetchEnabled, fallback: true)
        )
    }

    private nonisolated static func readStream(from defaults: UserDefaults) -> StreamSettings {
        StreamSettings(
            locale: string(defaults, Key.locale, fallback: "en-US"),
            preferIPv6: bool(defaults, Key.preferIPv6, fallback: false),
            preferredRegionID: string(defaults, Key.preferredRegionID, fallback: ""),
            statsHUDPosition: string(defaults, Key.statsHUDPosition, fallback: "topRight"),
            qualityPreset: string(defaults, Key.qualityPreset, fallback: "Balanced"),
            codecPreference: string(defaults, Key.codecPreference, fallback: "H.264"),
            clientProfileOSName: string(defaults, Key.clientProfileOSName, fallback: "Auto"),
            preferredResolution: string(defaults, Key.preferredResolution, fallback: "1080p"),
            preferredFPS: string(defaults, Key.preferredFPS, fallback: "60"),
            bitrateCapMbps: double(defaults, Key.bitrateCapMbps, fallback: 0),
            hdrEnabled: bool(defaults, Key.hdrEnabled, fallback: true),
            lowLatencyMode: bool(defaults, Key.lowLatencyMode, fallback: true),
            showStreamStats: bool(defaults, Key.showStreamStats, fallback: false),
            autoReconnect: bool(defaults, Key.autoReconnect, fallback: true),
            packetLossProtection: bool(defaults, Key.packetLossProtection, fallback: true),
            regionOverride: string(defaults, Key.regionOverride, fallback: "Auto"),
            upscalingEnabled: bool(defaults, Key.upscalingEnabled, fallback: true),
            audioBoost: double(defaults, Key.audioBoost, fallback: 3.0),
            colorRange: string(defaults, Key.colorRange, fallback: "Auto"),
            safeAreaPercent: double(defaults, Key.safeAreaPercent, fallback: 100.0),
            stereoAudio: bool(defaults, Key.stereoAudio, fallback: false),
            chatChannelEnabled: bool(defaults, Key.chatChannelEnabled, fallback: false)
        )
    }

    private nonisolated static func readController(from defaults: UserDefaults) -> ControllerSettings {
        let triggerInterpretationModeRaw = string(
            defaults,
            Key.triggerInterpretationMode,
            fallback: StratixModels.ControllerSettings.TriggerInterpretationMode.auto.rawValue
        )
        let triggerInterpretationMode =
            StratixModels.ControllerSettings.TriggerInterpretationMode(rawValue: triggerInterpretationModeRaw)
            ?? .auto

        return ControllerSettings(
            vibrationEnabled: bool(defaults, Key.vibrationEnabled, fallback: true),
            invertYAxis: bool(defaults, Key.invertYAxis, fallback: false),
            deadzone: double(defaults, Key.deadzone, fallback: 0.10),
            triggerSensitivity: double(defaults, Key.triggerSensitivity, fallback: 0.50),
            triggerInterpretationMode: triggerInterpretationMode,
            swapABButtons: bool(defaults, Key.swapABButtons, fallback: false),
            sensitivityBoost: double(defaults, Key.sensitivityBoost, fallback: 0),
            vibrationIntensity: double(defaults, Key.vibrationIntensity, fallback: 1.0)
        )
    }

    private nonisolated static func readAccessibility(from defaults: UserDefaults) -> AccessibilitySettings {
        AccessibilitySettings(
            reduceMotion: bool(defaults, Key.reduceMotion, fallback: false),
            largeText: bool(defaults, Key.largeText, fallback: false),
            closedCaptions: bool(defaults, Key.closedCaptions, fallback: false),
            highVisibilityFocus: bool(defaults, Key.highVisibilityFocus, fallback: false)
        )
    }

    private nonisolated static func readDiagnostics(from defaults: UserDefaults) -> DiagnosticsSettings {
        DiagnosticsSettings(
            debugHostInfo: bool(defaults, Key.debugHostInfo, fallback: true),
            logNetworkEvents: bool(defaults, Key.logNetworkEvents, fallback: false),
            blockTracking: bool(defaults, Key.blockTracking, fallback: false),
            verboseLogs: bool(defaults, Key.verboseLogs, fallback: false),
            useRTCMTLVideoRenderer: bool(defaults, Key.useRTCMTLVideoRenderer, fallback: false),
            frameProbe: bool(defaults, Key.frameProbe, fallback: false),
            audioResyncWatchdogEnabled: bool(defaults, Key.audioResyncWatchdogEnabled, fallback: true),
            startupHapticsProbeEnabled: bool(defaults, Key.startupHapticsProbeEnabled, fallback: true),
            upscalingFloorBehavior: UpscalingFloorBehavior(
                rawValue: string(defaults, Key.upscalingFloorBehavior, fallback: UpscalingFloorBehavior.sampleFloor.rawValue)
            ) ?? .sampleFloor
        )
    }

    private nonisolated static func string(_ defaults: UserDefaults, _ key: String, fallback: String) -> String {
        defaults.string(forKey: key) ?? fallback
    }

    private nonisolated static func bool(_ defaults: UserDefaults, _ key: String, fallback: Bool) -> Bool {
        (defaults.object(forKey: key) as? Bool) ?? fallback
    }

    private nonisolated static func double(_ defaults: UserDefaults, _ key: String, fallback: Double) -> Double {
        (defaults.object(forKey: key) as? Double) ?? fallback
    }

    @discardableResult
    private nonisolated static func migrateLegacyStatsHUDKey(
        defaults: UserDefaults,
        appDomainName: String
    ) -> Bool {
        guard !defaults.bool(forKey: Key.statsHUDMigrationKey) else { return false }
        defer { defaults.set(true, forKey: Key.statsHUDMigrationKey) }

        let hasExplicitGuideStatsValue = defaults.persistentDomain(forName: appDomainName)?[Key.showStreamStats] != nil
        guard !hasExplicitGuideStatsValue else { return false }
        guard let legacy = defaults.object(forKey: "stratix.stream.showStatsHUD") as? Bool else { return false }
        defaults.set(legacy, forKey: Key.showStreamStats)
        return true
    }

    @discardableResult
    private nonisolated static func migrateLegacyUpscalingEnabled(defaults: UserDefaults) -> Bool {
        guard !defaults.bool(forKey: Key.upscalingEnabledMigrationKey) else { return false }
        defer { defaults.set(true, forKey: Key.upscalingEnabledMigrationKey) }

        let appDomainName = Bundle.main.bundleIdentifier ?? "StratixCore"
        let hasExplicitUpscalingValue = defaults.persistentDomain(forName: appDomainName)?[Key.upscalingEnabled] != nil
        guard !hasExplicitUpscalingValue else { return false }

        let legacyMode = defaults.string(forKey: Key.rendererMode) ?? RendererModePreference.metalCAS.rawValue
        defaults.set(legacyMode != RendererModePreference.sampleBuffer.rawValue, forKey: Key.upscalingEnabled)
        return true
    }
}
