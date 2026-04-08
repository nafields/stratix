# Future Work

This document is an honest inventory of what is not done yet in Stratix, and what would make it meaningfully better. If you are looking for a meaningful contribution to make, this is a good place to start.

These are real open threads — not vague aspirations, not a secret roadmap. They are the places where the current code is deliberately conservative, incomplete, or rough. Some are well-defined enough to pick up directly. Others need design work before implementation. All of them would genuinely improve the project.

**How to use this doc:** Read it as an invitation. Find the area you care most about, then read the relevant architecture docs to understand the current shape before proposing changes. A PR that solves one of these gaps cleanly — well-tested, within the right package layer, with updated docs — is a high-value contribution.

See also [`FEATURE_INVENTORY.md`](FEATURE_INVENTORY.md) for the authoritative status of what is currently implemented.

## Public Open-Source Readiness

Near-term follow-up still makes sense in:

- polishing public onboarding and contributor docs
- improving first-time build and setup experience
- continuing to remove private-local assumptions from tests, previews, and scripts
- tightening public-safe examples and sample data

This is one of the highest-value categories right now because the repo is moving toward a more visible public state.

## Product And Platform Work

Reasonable future work includes:

- continuing cleanup of remaining compatibility-era names in secondary surfaces where it is safe to change them
- more polished release-side packaging and public distribution posture
- deliberate follow-through on bundle and signing alignment where it affects distribution surfaces

## Input And Controller Support

Potential next steps:

- richer controller remapping support
- broader controller-profile handling
- multi-controller support instead of the current single-primary-controller emphasis
- more device-specific controller affordances where tvOS and `GameController` support them well

## Streaming And Runtime

Likely future work:

- tighter reconnect and recovery behavior
- continued cleanup of duplicated or wrapper-heavy runtime control paths
- more profiling and polish around renderer selection and stream startup timing
- clearer diagnostics export and runtime inspection workflows

## Library, Shell, And Presentation

Likely future work:

- continued cleanup of dense CloudLibrary shell and projection seams
- more preview and fixture depth for complex shell/detail routes
- further readability cleanup in large controllers and projection builders

## Security And Public Safety

Still reasonable:

- continued audit of public-safe sample data and fixtures
- careful auth and token-storage review as the repo hardens
- explicit release-side plan for signing, provisioning, and public distribution implications

## Documentation

Ongoing documentation work should:

- keep `Docs/` aligned with the live tree
- treat `Docs_to_update/` as input, not published truth
- merge useful explanation depth forward instead of duplicating stale docs forever
- keep AGENTS, tooling docs, and contributor docs aligned as names and paths settle

## What Is Not The Goal

This file should not turn into:

- a giant modernization graveyard
- a dump of every possible idea
- a substitute for accurate current docs

If something is already obsolete, finished, or contradicted by the live repo, it should be removed instead of preserved here as clutter.

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [TESTING.md](TESTING.md)
- [REPO_POLICIES.md](REPO_POLICIES.md)
- [../SECURITY.md](../SECURITY.md)
