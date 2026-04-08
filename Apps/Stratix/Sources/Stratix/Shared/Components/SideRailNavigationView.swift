// SideRailNavigationView.swift
// Defines the side rail navigation view used in the Shared / Components surface.
//

import SwiftUI

/// Shell side rail container that coordinates account, nav, and action rows while switching
/// between collapsed and expanded rail states.
struct SideRailNavigationView: View {
    let state: SideRailNavigationViewState
    let selectedNavID: SideRailNavID
    var activeUtilityRoute: ShellUtilityRoute? = nil
    let onSelectNav: (SideRailNavID) -> Void
    var onSelectAction: (String) -> Void = { _ in }
    var onMoveFromSideRailToContent: (() -> Void)? = nil
    var surfaceID: String = "game_pass"
    var isExpanded: Binding<Bool> = .constant(false)
    var onExpansionChanged: ((Bool) -> Void)? = nil
    var forceCollapsed: Bool = false
    /// When collapsed, the rail keeps only the selected nav focusable unless callers opt out.
    var collapsedSelectedNavFocusable: Bool = true

    @FocusState var focusedTarget: SideRailFocusTarget?
    @State var didExplicitlyEnterRail = false
    @State var pendingFocusTask: Task<Void, Never>?

    /// Derived rail mode that ignores external expansion requests while force-collapsed.
    var isRailExpanded: Bool {
        !forceCollapsed && isExpanded.wrappedValue
    }

    private var railWidth: CGFloat {
        isRailExpanded ? StratixTheme.SideRail.railExpandedWidth : StratixTheme.SideRail.railCollapsedWidth
    }

    private var panelWidth: CGFloat {
        isRailExpanded ? StratixTheme.SideRail.panelExpandedWidth : StratixTheme.SideRail.panelCollapsedWidth
    }

    var body: some View {
        ZStack(alignment: .leading) {
            panelBackground
                .frame(width: panelWidth, alignment: .leading)

            VStack(alignment: .leading, spacing: 0) {
                accountClusterView
                Spacer(minLength: 0)

                navListView
                actionListView

                Spacer(minLength: 0)
            }
            .padding(.top, StratixTheme.SideRail.verticalPadding)
            .padding(.bottom, StratixTheme.SideRail.verticalPadding)
            .padding(.horizontal, StratixTheme.SideRail.horizontalPadding)
            .frame(width: railWidth)
            .frame(maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: panelWidth, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .focusSection()
        .animation(.easeOut(duration: 0.2), value: isRailExpanded)
        .onAppear {
            onExpansionChanged?(isRailExpanded)
        }
        .onChange(of: isExpanded.wrappedValue) { _, expanded in
            handleExpansionRequestChange(expanded)
        }
        .onChange(of: selectedNavID) { _, _ in
            guard !forceCollapsed else { return }
            guard !isRailExpanded else { return }
            onExpansionChanged?(false)
        }
        .onChange(of: forceCollapsed) { _, collapsed in
            handleForceCollapsedChange(collapsed)
        }
        .onChange(of: collapsedSelectedNavFocusable) { _, isFocusable in
            guard !isFocusable else { return }
            collapseRail()
        }
        .onChange(of: focusedTarget) { _, target in
            handleFocusedTargetChange(target)
        }
    }

    private var panelBackground: some View {
        Group {
            if isRailExpanded {
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.92), location: 0.0),
                        .init(color: Color.black.opacity(0.56), location: 0.58),
                        .init(color: Color.clear, location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                Color.clear
            }
        }
    }

    private func handleForceCollapsedChange(_ collapsed: Bool) {
        if collapsed {
            focusedTarget = nil
            didExplicitlyEnterRail = false
            isExpanded.wrappedValue = false
        }
        onExpansionChanged?(isRailExpanded)
    }

    /// Applies an external expansion request while preserving the force-collapsed contract.
    private func handleExpansionRequestChange(_ expanded: Bool) {
        guard !forceCollapsed else {
            if expanded {
                isExpanded.wrappedValue = false
            }
            return
        }
        if expanded {
            expandRailAndFocusPreferredTarget()
            return
        }
        collapseRail()
    }
}

#if DEBUG
#Preview("SideRailNavigationView", traits: .fixedLayout(width: 1920, height: 1080)) {
    ZStack {
        Color.black
        HStack(spacing: 24) {
            SideRailNavigationView(
                state: CloudLibraryPreviewData.sideRail,
                selectedNavID: .home,
                onSelectNav: { _ in },
                isExpanded: .constant(true)
            )
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}
#endif
