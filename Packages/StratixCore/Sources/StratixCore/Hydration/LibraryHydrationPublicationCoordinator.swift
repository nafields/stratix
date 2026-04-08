// LibraryHydrationPublicationCoordinator.swift
// Defines the library hydration publication coordinator for the Hydration surface.
//

import Foundation

@MainActor
struct LibraryHydrationPublicationCoordinator {
    func publish(
        actions: [LibraryAction],
        plan: LibraryHydrationPublicationPlan,
        controller: LibraryController
    ) async -> LibraryHydrationPublicationResult {
        var completedStages: [LibraryHydrationStage] = []
        let primaryActions = actions.filter { !isDetailsAction($0) }
        let detailActions = actions.filter(isDetailsAction)
        let shouldApplyPrimaryAtRouteRestore = !plan.stages.contains(.mruAndHero) && !plan.stages.contains(.visibleRows)
        let shouldApplyDetailsAtPrimaryStage = !plan.stages.contains(.detailsAndSecondaryRows)
        var primaryApplied = false
        var detailsApplied = false

        func applyPrimaryIfNeeded() {
            guard !primaryApplied, !primaryActions.isEmpty else { return }
            controller.apply(primaryActions)
            primaryApplied = true
        }

        func applyDetailsIfNeeded() {
            guard !detailsApplied, !detailActions.isEmpty else { return }
            controller.apply(detailActions)
            detailsApplied = true
        }

        for stage in plan.stages {
            switch stage {
            case .authShell:
                completedStages.append(stage)

            case .routeRestore:
                if shouldApplyPrimaryAtRouteRestore {
                    applyPrimaryIfNeeded()
                    if shouldApplyDetailsAtPrimaryStage {
                        applyDetailsIfNeeded()
                    }
                }
                completedStages.append(stage)

            case .mruAndHero, .visibleRows:
                applyPrimaryIfNeeded()
                completedStages.append(stage)

            case .detailsAndSecondaryRows:
                guard !detailActions.isEmpty else { continue }
                applyDetailsIfNeeded()
                completedStages.append(stage)

            case .socialAndProfile:
                await controller.warmProfileAndSocialAfterLibraryLoad()
                completedStages.append(stage)

            case .backgroundArtwork:
                if let merchandising = controller.homeMerchandising {
                    await controller.prefetchVisibleHomeArtwork(
                        sections: controller.sections,
                        merchandising: merchandising
                    )
                }
                await controller.prefetchLibraryArtwork(controller.sections)
                completedStages.append(stage)
            }
        }

        applyPrimaryIfNeeded()
        applyDetailsIfNeeded()

        return LibraryHydrationPublicationResult(completedStages: completedStages)
    }

    private func isDetailsAction(_ action: LibraryAction) -> Bool {
        switch action {
        case .productDetailsReplaced,
             .hydrationProductDetailsStateApplied,
             .detailRevisionIncremented:
            return true
        default:
            return false
        }
    }
}
