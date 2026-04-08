// StreamContextTypedIDTests.swift
// Exercises stream context typed id behavior.
//

import Testing
import StratixModels
@testable import Stratix
@testable import StratixCore

@Suite
struct StreamContextTypedIDTests {
    @Test
    func streamContext_cloudCarriesTypedTitleID() {
        let titleID = TitleID("abc123")
        let context = StreamContext.cloud(titleId: titleID)

        switch context {
        case .cloud(let storedTitleID):
            #expect(storedTitleID == titleID)
        case .home:
            Issue.record("Expected cloud stream context")
        }

        switch context.id {
        case .cloud(let storedTitleID):
            #expect(storedTitleID == titleID)
        case .home:
            Issue.record("Expected typed cloud stream identity")
        }
    }

    @Test
    func streamLaunchTarget_buildsTypedRuntimeContext() {
        let titleID = TitleID("typed-title")
        let target = StreamLaunchTarget.cloud(titleID)

        #expect(target.runtimeContext == .cloud(titleId: titleID))
    }
}
