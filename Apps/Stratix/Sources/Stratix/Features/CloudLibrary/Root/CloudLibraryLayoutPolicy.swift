// CloudLibraryLayoutPolicy.swift
// Defines cloud library layout policy for the CloudLibrary / Root surface.
//

import CoreGraphics

struct CloudLibraryLayoutPolicy {
    func shellContentHorizontalPadding(
        browseRoute: CloudLibraryBrowseRoute,
        utilityRoute: ShellUtilityRoute?
    ) -> CGFloat {
        browseRouteSpacing(
            browseRoute: browseRoute,
            utilityRoute: utilityRoute,
            value: StratixTheme.Layout.outerPadding
        )
    }

    func shellContentTopPadding(
        browseRoute: CloudLibraryBrowseRoute,
        utilityRoute: ShellUtilityRoute?
    ) -> CGFloat {
        browseRouteSpacing(
            browseRoute: browseRoute,
            utilityRoute: utilityRoute,
            value: StratixTheme.Shell.contentTopPadding
        )
    }

    func shellContentLeadingAdjustment(
        browseRoute: CloudLibraryBrowseRoute,
        utilityRoute: ShellUtilityRoute?
    ) -> CGFloat {
        browseRouteSpacing(
            browseRoute: browseRoute,
            utilityRoute: utilityRoute,
            value: StratixTheme.Shell.browseRouteLeadingInset
        )
    }

    private func browseRouteSpacing(
        browseRoute: CloudLibraryBrowseRoute,
        utilityRoute: ShellUtilityRoute?,
        value: CGFloat
    ) -> CGFloat {
        guard utilityRoute == nil, browseRoute != .home, browseRoute != .consoles else {
            return 0
        }
        return value
    }
}
