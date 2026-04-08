// StreamRegionDiagnosticsResolver.swift
// Defines stream region diagnostics resolver for the Streaming surface.
//

import Foundation
import XCloudAPI

struct StreamRegionDiagnosticsResolver {
    private let launchConfigurationService: StreamLaunchConfigurationService
    private let resolver: ((String, [LoginRegion]) -> String?)?

    init(
        launchConfigurationService: StreamLaunchConfigurationService = StreamLaunchConfigurationService(),
        resolver: ((String, [LoginRegion]) -> String?)? = nil
    ) {
        self.launchConfigurationService = launchConfigurationService
        self.resolver = resolver
    }

    func regionOverrideDiagnostics(
        rawValue: String,
        availableRegions: [LoginRegion]
    ) -> String? {
        resolver?(rawValue, availableRegions)
            ?? launchConfigurationService.regionOverrideDiagnostics(
                rawValue: rawValue,
                availableRegions: availableRegions
            )
    }
}
