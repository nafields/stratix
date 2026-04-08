# Preview Standards

This document defines the preview baseline for SwiftUI work in the live `Stratix` repo.

Previews matter here because the app has a large SwiftUI surface, a heavy runtime stack, and multiple flows that would be slow or brittle to inspect only through full app boot. Good previews make UI iteration faster and make public contributors more productive.

## Core Rule

Major SwiftUI views should remain previewable without:

- live authentication
- live network calls
- full app boot
- personal local state
- hidden dependency on a previously signed-in environment

If a view can only render after full runtime boot, the preview setup is probably too coupled.

## What Good Previews Look Like In This Repo

Good previews in Stratix are:

- deterministic
- synthetic and public-safe
- named by user-visible state instead of implementation detail
- stable enough to catch layout or visual drift during normal development

That means preview fixtures should prefer route state, view state, and synthetic models over controller boot or ad hoc network wiring.

## Recommended Coverage

### Scene-level views

Scene-level views should usually cover:

- loading
- content
- empty or fallback state
- error or unavailable state
- one dense or stress state when relevant

### Reusable components

Reusable UI components should usually cover:

- default
- focused
- long-content
- missing-image or fallback state when relevant

### Streaming and overlay surfaces

These should usually cover:

- disconnected or waiting state
- active playback state
- overlay visible state
- compact stats or diagnostics state when available

## Data Rules

Preview data should be:

- synthetic
- deterministic
- safe to publish

Do not use:

- real gamertags
- real account identifiers
- real device names
- copied private environment values

If existing preview data contains private or ambiguous values, replace it with clearly synthetic values rather than documenting the leak as acceptable.

## Naming Convention

Use preview names that describe what the user would see:

- `Home - Loading`
- `Home - Dense Rails`
- `Detail - Rich Content`
- `Profile - Cached`
- `Settings - Diagnostics Pane`
- `Stream Overlay - Connected`

Avoid preview names that only restate the implementation type name with no state context.

## Relationship To Tests

Previews and test fixtures should cooperate where practical, but they do not need to share exactly the same architecture.

The important thing is that both:

- are stable
- are synthetic
- can reproduce useful states without live services

Preview ergonomics should not be sacrificed just to imitate a test harness structure that is awkward for UI work.

## Priority Areas In This Repo

Preview quality matters most in:

- CloudLibrary route views
- shell and side-rail surfaces
- settings panes
- stream overlay presentation
- shared reusable SwiftUI components

These are the areas where a contributor is most likely to want fast visual iteration without booting the full app.

## Current Practical Guidance

- prefer reusable preview state builders over inline one-off sample data when the view is complex
- keep preview setup close to the view unless shared fixtures materially reduce noise
- avoid preview-only code paths that distort how the real view works
- if a view needs a large amount of setup to preview, that is often a design smell worth revisiting

## Related Docs

- [UI_ARCHITECTURE.md](UI_ARCHITECTURE.md)
- [OBSERVATION.md](OBSERVATION.md)
- [TESTING.md](TESTING.md)
