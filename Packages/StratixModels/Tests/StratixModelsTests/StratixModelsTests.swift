// StratixModelsTests.swift
// Exercises stratix models behavior.
//

import Testing
import Foundation
import StratixModels

// MARK: - StratixModels Tests

@Suite("GamepadButtons")
struct GamepadButtonsTests {

    @Test func canCombineButtons() {
        let buttons: GamepadButtons = [.a, .b, .dpadUp]
        #expect(buttons.contains(.a))
        #expect(buttons.contains(.b))
        #expect(buttons.contains(.dpadUp))
        #expect(!buttons.contains(.x))
    }

    @Test func nexusBitIsCorrect() {
        #expect(GamepadButtons.nexus.rawValue == 0x0002)
    }

    @Test func menuBitIsCorrect() {
        #expect(GamepadButtons.menu.rawValue == 0x0004)
    }

    @Test func allButtonMasksAreUnique() {
        let allButtons: [GamepadButtons] = [
            .nexus, .menu, .view, .a, .b, .x, .y,
            .dpadUp, .dpadDown, .dpadLeft, .dpadRight,
            .leftShoulder, .rightShoulder, .leftThumb, .rightThumb
        ]
        let rawValues = allButtons.map { $0.rawValue }
        let unique = Set(rawValues)
        #expect(unique.count == allButtons.count)
    }
}

@Suite("StreamError")
struct StreamErrorTests {

    @Test func descriptionContainsCode() {
        let error = StreamError(code: .webrtc, message: "ICE failed")
        #expect(error.description.contains("webrtc"))
        #expect(error.description.contains("ICE failed"))
    }

    @Test func networkErrorDescriptionContainsNetwork() {
        let error = StreamError(code: .network, message: "offline")
        #expect(error.description.contains("network"))
    }
}

@Suite("StreamLifecycleState")
struct StreamLifecycleStateTests {

    @Test func connectedDistinctFromDisconnected() {
        #expect(StreamLifecycleState.connected != .disconnected)
        #expect(StreamLifecycleState.idle != .provisioning)
    }

    @Test func failedStatesWithDifferentErrors() {
        let e1 = StreamLifecycleState.failed(StreamError(code: .webrtc, message: "A"))
        let e2 = StreamLifecycleState.failed(StreamError(code: .network, message: "B"))
        #expect(e1 != e2)
    }
}

@Suite("DataChannelKind")
struct DataChannelKindTests {

    @Test func allCasesHasFourEntries() {
        #expect(DataChannelKind.allCases.count == 4)
    }

    @Test func rawValues() {
        #expect(DataChannelKind.input.rawValue == "input")
        #expect(DataChannelKind.control.rawValue == "control")
        #expect(DataChannelKind.message.rawValue == "message")
        #expect(DataChannelKind.chat.rawValue == "chat")
    }
}

@Suite("StreamKind")
struct StreamKindTests {

    @Test func rawValues() {
        #expect(StreamKind.cloud.rawValue == "cloud")
        #expect(StreamKind.home.rawValue == "home")
    }
}

@Suite("StreamingConfig")
struct StreamingConfigTests {

    @Test func defaultCodecOrderStartsWithH264High() {
        let config = StreamingConfig()
        #expect(config.preferredVideoCodecOrder.first == .h264High)
    }

    @Test func stereoEnabledByDefault() {
        #expect(StreamingConfig().stereoAudioEnabled == true)
    }

    @Test func keyframeIntervalIsDefault5() {
        #expect(StreamingConfig().keyframeRequestIntervalSeconds == 5)
    }
}

@Suite("IceCandidatePayload")
struct IceCandidatePayloadTests {

    @Test func codableRoundtrip() throws {
        let c = IceCandidatePayload(
            candidate: "a=candidate:1 1 UDP 2130706431 192.168.1.1 8080 typ host",
            sdpMLineIndex: 0,
            sdpMid: "0"
        )
        let data = try JSONEncoder().encode(c)
        let decoded = try JSONDecoder().decode(IceCandidatePayload.self, from: data)
        #expect(decoded == c)
    }
}

@Suite("StreamResolutionMode")
struct StreamResolutionModeTests {
    @Test func osNameMapping() {
        #expect(StreamResolutionMode.auto.osName == "android")
        #expect(StreamResolutionMode.p720.osName == "android")
        #expect(StreamResolutionMode.p1080.osName == "windows")
        #expect(StreamResolutionMode.p1080HQ.osName == "tizen")
    }
}

@Suite("CloudLibraryProductDetail")
struct CloudLibraryProductDetailTests {
    @Test func decodesLegacyPayloadWithoutMediaAssets() throws {
        let json = #"""
        {
          "productId": "9TEST",
          "title": "Halo",
          "capabilityLabels": ["4K"],
          "genreLabels": ["Action"],
          "galleryImageURLs": ["https://images.example.com/1.jpg"],
          "trailers": []
        }
        """#

        let decoded = try JSONDecoder().decode(CloudLibraryProductDetail.self, from: Data(json.utf8))
        #expect(decoded.productId == "9TEST")
        #expect(decoded.mediaAssets.isEmpty)
        #expect(decoded.achievementSummary == nil)
    }

    @Test func achievementSummary_unlockPercentIsComputed() {
        let summary = TitleAchievementSummary(
            titleId: "title",
            totalAchievements: 20,
            unlockedAchievements: 7
        )
        #expect(summary.unlockPercent == 35)
    }
}
