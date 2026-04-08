// StreamSessionLifecycleObserverTests.swift
// Exercises stream session lifecycle observer behavior.
//

import Testing
@testable import StratixCore

@MainActor
@Suite(.serialized)
struct StreamSessionLifecycleObserverTests {
    @Test
    func bind_installsLifecycleCallbackOnSession() {
        let observer = StreamSessionLifecycleObserver()
        let session = makeStreamingSession()

        observer.bind(session: session) { _ in }

        #expect(session.onLifecycleChange != nil)
    }

    @Test
    func bind_clearsOldSessionCallbackWhenReplacingSession() {
        let observer = StreamSessionLifecycleObserver()
        let oldSession = makeStreamingSession()
        let newSession = makeStreamingSession()

        observer.bind(session: oldSession) { _ in }
        observer.bind(session: newSession) { _ in }

        #expect(oldSession.onLifecycleChange == nil)
        #expect(newSession.onLifecycleChange != nil)
    }

    @Test
    func bind_suppressesStaleCallbacksAfterSessionReplacement() {
        let observer = StreamSessionLifecycleObserver()
        let oldSession = makeStreamingSession()
        let newSession = makeStreamingSession()
        var forwarded: [StreamSessionLifecycleEvent] = []

        observer.bind(session: oldSession) { forwarded.append($0) }
        observer.bind(session: newSession) { forwarded.append($0) }
        forwarded.removeAll()

        oldSession.onLifecycleChange?(.connected)
        newSession.onLifecycleChange?(.connected)

        #expect(forwarded.count == 1)
        #expect(forwarded.first?.lifecycle == .connected)
        #expect(forwarded.first?.disconnectIntent == .reconnectable)
    }

    @Test
    func reset_clearsCurrentSessionCallback() {
        let observer = StreamSessionLifecycleObserver()
        let session = makeStreamingSession()

        observer.bind(session: session) { _ in }
        observer.reset()

        #expect(session.onLifecycleChange == nil)
    }
}
