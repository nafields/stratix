# AGENTS.override.md — Shell/

The Shell/ directory contains the top-level authenticated shell containers. These are the views that wrap the feature content once the user is authenticated.

**Modernization contract reference:** If shell work is part of the modernization program, read `Docs/Stratix_Modernization_Contracts.md` together with the modernization plan, monolith breakdown, and file matrix before changing structure or ownership.

---

## Files

| File | Role |
|------|------|
| `AuthenticatedShellView.swift` | Top-level authenticated shell container. Hosts `CloudLibraryView`, publishes shell readiness markers, and applies shell-wide accessibility behavior. |

---

## Position in the hierarchy

```
RootView (App/)
  └── AuthenticatedShellView (Shell/)
        └── CloudLibraryView (Features/CloudLibrary/Root/)
```

The shell wraps feature content. It does not own feature state.

---

## Rules

1. Shell views read from `AppCoordinator` environment objects. They do not create state objects.
2. Shell-wide affordances live here. Feature routing (browse routes, detail paths, utility routes) lives in `Features/CloudLibrary/State/CloudLibraryRouteState`.
3. Do not add feature logic to shell views. If a new feature slice is added, add a tab or route entry here and delegate all logic to the feature's own root view.
4. `GamePassShellView` (from the earlier iteration) may still be referenced — if present, it wraps content with ambient background + TopChrome overlay. Check current usage before modifying.
