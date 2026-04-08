// AuthenticatedShellDynamicTypeSmokeTests.swift
// Exercises authenticated shell dynamic type smoke behavior.
//

import XCTest
import SwiftUI

#if canImport(Stratix)
@testable import Stratix
#endif

final class AuthenticatedShellDynamicTypeSmokeTests: XCTestCase {
    @MainActor
    func testAuthenticatedShellEffectiveDynamicTypeSizePreservesAmbientSizeWhenLargeTextIsOff() {
        XCTAssertEqual(
            authenticatedShellEffectiveDynamicTypeSize(base: .large, largeTextEnabled: false),
            .large
        )
        XCTAssertEqual(
            authenticatedShellEffectiveDynamicTypeSize(base: .accessibility2, largeTextEnabled: false),
            .accessibility2
        )
    }

    @MainActor
    func testAuthenticatedShellEffectiveDynamicTypeSizeRaisesMinimumWhenLargeTextIsOn() {
        XCTAssertEqual(
            authenticatedShellEffectiveDynamicTypeSize(base: .large, largeTextEnabled: true),
            .xLarge
        )
        XCTAssertEqual(
            authenticatedShellEffectiveDynamicTypeSize(base: .xSmall, largeTextEnabled: true),
            .xLarge
        )
        XCTAssertEqual(
            authenticatedShellEffectiveDynamicTypeSize(base: .accessibility2, largeTextEnabled: true),
            .accessibility2
        )
    }
}
