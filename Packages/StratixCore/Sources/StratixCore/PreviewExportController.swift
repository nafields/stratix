// PreviewExportController.swift
// Defines the preview export controller.
//

import Foundation
import Observation

public enum PreviewExportControllerError: LocalizedError {
    case missingSource

    public var errorDescription: String? {
        switch self {
        case .missingSource:
            return "Preview export source is unavailable."
        }
    }
}

@Observable
@MainActor
public final class PreviewExportController {
    @ObservationIgnored private let previewExportService: PreviewExportService
    @ObservationIgnored private var source: (any PreviewExportSource)?

    public init(previewExportService: PreviewExportService = PreviewExportService()) {
        self.previewExportService = previewExportService
    }

    func attach(_ source: any PreviewExportSource) {
        self.source = source
    }

    @discardableResult
    public func exportPreviewDataDump(refreshBeforeExport: Bool = true) async throws -> URL {
        guard let source else {
            throw PreviewExportControllerError.missingSource
        }
        return try await previewExportService.exportPreviewDump(
            source: source,
            refreshBeforeExport: refreshBeforeExport
        )
    }
}
