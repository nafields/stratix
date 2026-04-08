// BlockingURLProtocol.swift
// Defines blocking url protocol.
//

import Foundation
import DiagnosticsKit

public final class BlockingURLProtocol: URLProtocol {
    public static let blockedHosts: Set<String> = [
        "arc.msn.com",
        "browser.events.data.microsoft.com",
        "dc.services.visualstudio.com",
        "o427368.ingest.sentry.io",
        "mscom.demdex.net"
    ]

    public override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host?.lowercased() else { return false }
        return blockedHosts.contains(host)
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        LoggerStore.shared.incrementBlockedRequestCount()
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    public override func stopLoading() {}
}
