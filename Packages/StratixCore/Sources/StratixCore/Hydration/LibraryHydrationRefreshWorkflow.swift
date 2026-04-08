// LibraryHydrationRefreshWorkflow.swift
// Defines library hydration refresh workflow for the Hydration surface.
//

import Foundation
import StratixModels

@MainActor
struct LibraryHydrationRefreshWorkflow {
    func run(
        controller: LibraryController,
        reason: CloudLibraryRefreshReason,
        deferInitialRoutePublication: Bool
    ) async {
        guard !controller.isSuspendedForStreaming else { return }
        guard let tokens = controller.dependencies?.authenticatedLibraryTokens() else { return }
        guard let xcloudToken = tokens.xcloudToken, !xcloudToken.isEmpty else {
            controller.apply([
                .errorSet("Missing xCloud token."),
                .needsReauthSet(true),
                .sectionsReplaced([])
            ])
            controller.logger.error("Cloud library load failed: missing xCloud token")
            return
        }

        controller.apply([.loadingStarted, .errorSet(nil), .needsReauthSet(false)])
        defer { controller.apply(.loadingFinished) }

        do {
            let result = try await controller.hydrationOrchestrator.performLiveRefresh(
                controller: controller,
                request: controller.makeHydrationRequest(
                    trigger: .liveRefresh,
                    reason: reason,
                    deferInitialRoutePublication: deferInitialRoutePublication
                )
            )
            await controller.applyHydrationOrchestrationResult(result)
            guard !controller.isSuspendedForStreaming else { return }
            controller.hasPerformedNetworkHydrationThisSession = true
        } catch {
            let message = controller.logString(for: error)
            controller.logger.error("Cloud library load failed: \(message)")

            guard controller.isUnauthorized(error) == false else {
                controller.logger.warning("Cloud library unauthorized with cached tokens; attempting silent refresh + retry")
                await retryAfterTokenRefresh(
                    controller: controller,
                    reason: reason,
                    deferInitialRoutePublication: deferInitialRoutePublication
                )
                return
            }

            controller.apply([.needsReauthSet(false), .errorSet(error.localizedDescription)])
        }
    }

    private func retryAfterTokenRefresh(
        controller: LibraryController,
        reason: CloudLibraryRefreshReason,
        deferInitialRoutePublication: Bool
    ) async {
        do {
            guard let dependencies = controller.dependencies else {
                controller.apply([.needsReauthSet(true), .errorSet("Sign in required.")])
                return
            }
            _ = try await dependencies.refreshStreamTokens(
                logContext: "cloud library retry"
            )
            let result = try await controller.hydrationOrchestrator.performLiveRefresh(
                controller: controller,
                request: controller.makeHydrationRequest(
                    trigger: .liveRefresh,
                    reason: reason,
                    deferInitialRoutePublication: deferInitialRoutePublication
                )
            )
            await controller.applyHydrationOrchestrationResult(result)
            guard !controller.isSuspendedForStreaming else { return }
            controller.apply([.errorSet(nil), .needsReauthSet(false)])
            controller.hasPerformedNetworkHydrationThisSession = true
        } catch {
            controller.logger.error("Cloud library retry after refresh failed: \(controller.logString(for: error))")
            if controller.isUnauthorized(error) {
                controller.apply([
                    .needsReauthSet(true),
                    .errorSet("Your sign-in session expired. Sign in again to reload Game Pass.")
                ])
            } else {
                controller.apply([.needsReauthSet(false), .errorSet(error.localizedDescription)])
            }
        }
    }
}
