// XboxWebRequestSupport.swift
// Provides shared support for xbox web request.
//

import Foundation

// Endpoint inventory (runtime callers):
// - MicrosoftAuthService: login.microsoftonline.com, login.live.com, user.auth.xboxlive.com, xsts.auth.xboxlive.com, *.gssv-play-prod.xboxlive.com
// - XCloudAPIClient: {region}.core.gssv-play-prod.xboxlive.com (/v6/servers/home, /v2/titles, /v5/sessions/*)
// - GamePassCatalogClient: catalog.gamepass.com (/v3/products)
// - XboxWebProfileClient: profile.xboxlive.com (/users/me/profile/settings, /users/batch/profile/settings)
// - XboxWebPresenceClient: userpresence.xboxlive.com (/users/me)
// - XboxSocialPeopleClient: social.xboxlive.com (/users/{ownerId}/people)
// - XboxComProductDetailsClient: emerald.xboxservices.com (/xboxcomfd/productdetails/{productId})
// - XboxAchievementsClient: achievements.xboxlive.com (/users/xuid({xuid})/history/titles, /users/xuid({xuid})/achievements)
enum XboxWebRequestSupport {
    static func makeRequest(
        url: URL,
        method: String = "GET",
        contractVersion: String,
        credentials: XboxWebCredentials,
        contentType: String? = nil,
        body: Data? = nil
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(contractVersion, forHTTPHeaderField: "x-xbl-contract-version")
        request.setValue("XBL3.0 x=\(credentials.uhs);\(credentials.token)", forHTTPHeaderField: "Authorization")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let body {
            request.httpBody = body
        }
        return request
    }

    static func performData(
        session: URLSession,
        request: URLRequest
    ) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<empty>"
            throw APIError.httpError((response as? HTTPURLResponse)?.statusCode ?? 0, body)
        }
        return data
    }
}
