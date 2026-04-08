# Concurrency Exceptions

This document records the places in Stratix where the standard Swift 6.2 concurrency model cannot be satisfied without a safety escape hatch — specifically `@unchecked Sendable` and `nonisolated(unsafe)`.

## What These Exceptions Are

Swift 6.2 with strict concurrency set to `complete` gives you a strong guarantee: if your code compiles, the compiler has verified that you are not accidentally sharing mutable state across actor boundaries. This is enormously valuable, and it is the reason the repo enforces it.

But the compiler's guarantees only cover Swift's type system. At the boundary between Swift and Objective-C frameworks — particularly WebRTC, AVFoundation, and Metal — the compiler cannot see the real ownership model. The framework objects do not conform to `Sendable`, not because they are unsafe, but because they predate Swift concurrency and were never annotated.

`@unchecked Sendable` is the escape hatch for this situation. It tells the compiler: "I have manually verified that this is safe to send across actor boundaries, even though you cannot prove it." The "unchecked" part is your responsibility.

**This is not a routine tool.** Every use of `@unchecked Sendable` or `nonisolated(unsafe)` in this repo must be documented here. If you add one without adding an entry here, the CI guard will flag it. Before adding a new exception, ask: can this be restructured to fit the normal model? Can value types or explicit actor boundaries be used instead? If the answer is genuinely no, document why.

The normal rules in this repo:

- prefer explicit actor isolation
- prefer value types that can conform to `Sendable`
- prefer explicit `@MainActor` and `@Sendable` boundaries
- treat `@unchecked Sendable` and `nonisolated(unsafe)` as exceptional tools, not routine convenience

## Why This Document Exists

Stratix builds with Swift 6.2 and strict concurrency checking set to `complete`. That is a real design constraint in the repo, not a style preference.

Most production code should fit inside that model cleanly. The exceptions documented here exist because Swift cannot fully express the ownership model of certain framework-controlled objects at the boundary between:

- WebRTC Objective-C types
- Metal renderer delegates and resources
- AVFoundation sample-buffer display types

Those seams need explicit review and explicit containment.

## Current Approved Production Exceptions

The current allowlist, as enforced by the repo guard, is:

- [`Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift`](../Apps/Stratix/Sources/Stratix/Features/Streaming/Rendering/SampleBufferDisplayRenderer.swift)
- [`Apps/Stratix/Sources/Stratix/Integration/WebRTC/MetalVideoRenderer.swift`](../Apps/Stratix/Sources/Stratix/Integration/WebRTC/MetalVideoRenderer.swift)
- [`Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift`](../Apps/Stratix/Sources/Stratix/Integration/WebRTC/WebRTCClientImpl.swift)

These are the only production files currently allowed to use `@unchecked Sendable`.

## Why These Three Files Are Allowed

### WebRTCClientImpl

This file sits at the concrete bridge boundary between the app and framework-owned WebRTC objects. Swift cannot statically prove sendability for those objects in a meaningful way because the real ownership model is partly outside Swift’s type system.

That does not make it “safe by default.” It means the exception is contained at the bridge instead of spreading through app or package logic.

### MetalVideoRenderer

This file bridges Swift concurrency expectations with renderer delegate lifetimes and Metal-driven callback behavior. The seam is narrow, framework-heavy, and performance-sensitive.

Again, the goal is containment: keep the exception at the renderer bridge rather than normalizing it across unrelated code.

### SampleBufferDisplayRenderer

This file bridges into `AVSampleBufferDisplayLayer` and related sample-buffer display ownership that Swift cannot fully model as pure sendable state.

The exception exists because the renderer boundary is framework-owned, not because the repo allows relaxed concurrency as a general habit.

## What Is Not Allowed

Outside the approved bridge surfaces:

- production code must not use `nonisolated(unsafe)`
- production code must not add new `@unchecked Sendable` conformances casually
- contributors should not widen a bridge exception into general-purpose controller, workflow, or view code

If a concurrency issue appears elsewhere, the default response should be:

1. move the state to the correct actor
2. narrow the ownership boundary
3. use value types or explicit `Sendable` conformance
4. only document an exception if the framework seam truly requires it

## How The Repo Enforces This

The current guard is:

- [`Tools/ci/check_concurrency_exceptions.py`](../Tools/ci/check_concurrency_exceptions.py)

That guard checks:

- production code does not use `nonisolated(unsafe)`
- `@unchecked Sendable` appears only in the approved files
- the documented allowlist stays in sync with what actually exists in the code

## How To Propose A New Exception

Do not add one first and explain later.

Instead, document:

1. which framework-owned boundary makes normal isolation impossible
2. why actor isolation or a value-type redesign will not work
3. how the exception will stay narrow
4. what validation or runtime behavior proves the change is still safe enough for this repo

Then update this document and the enforcing guard in the same change if the exception is genuinely necessary.

## Related Docs

- [ARCHITECTURE.md](ARCHITECTURE.md)
- [REPO_POLICIES.md](REPO_POLICIES.md)
- [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
