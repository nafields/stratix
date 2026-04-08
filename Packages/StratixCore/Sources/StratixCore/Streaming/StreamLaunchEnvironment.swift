// StreamLaunchEnvironment.swift
// Defines stream launch environment for the Streaming surface.
//

import Foundation
import StratixModels
import XCloudAPI

struct StreamLaunchEnvironment: Sendable {
    let streamSettings: SettingsStore.StreamSettings
    let diagnosticsSettings: SettingsStore.DiagnosticsSettings
    let controllerSettings: SettingsStore.ControllerSettings
    let availableRegions: [LoginRegion]
}
