// ICEProcessorTests.swift
// Exercises ice processor behavior.
//

import Testing
@testable import StreamingCore
import StratixModels

// MARK: - ICE Processor Tests
//
// Verifies Teredo IPv6 address extraction and candidate expansion.

@Suite
struct ICEProcessorTests {

    let processor = ICEProcessor()

    // MARK: - Teredo extraction

    @Test func extractTeredoEndpoint_knownAddress() {
        let (ipv4, port) = buildTeredoAndExtract(clientIPv4: "192.0.2.45", clientPort: 40000)
        #expect(ipv4 == "192.0.2.45")
        #expect(port == 40000)
    }

    @Test func extractTeredoEndpoint_loopback() {
        let (ipv4, port) = buildTeredoAndExtract(clientIPv4: "10.0.0.1", clientPort: 9002)
        #expect(ipv4 == "10.0.0.1")
        #expect(port == 9002)
    }

    // MARK: - Candidate expansion

    @Test func expandCandidates_normalCandidate_passesThrough() {
        let c = IceCandidatePayload(
            candidate: "a=candidate:1 1 UDP 2130706431 192.168.1.1 54321 typ host",
            sdpMLineIndex: 0,
            sdpMid: "0"
        )
        let result = processor.expandCandidates([c])
        #expect(result.count == 1)
        #expect(result[0].candidate == c.candidate)
    }

    @Test func expandCandidates_teredoCandidate_addsSyntheticCandidates() {
        let teredoAddr = makeTeredoAddress(clientIPv4: "10.0.0.1", clientPort: 9002)
        let c = IceCandidatePayload(
            candidate: "a=candidate:5 1 UDP 100 \(teredoAddr) 3480 typ relay",
            sdpMLineIndex: 0,
            sdpMid: "0"
        )
        let result = processor.expandCandidates([c])
        // Should produce 2 synthetic + 1 original = 3
        #expect(result.count == 3)

        let synthetic9002 = result.first { $0.candidate.contains("9002") }
        #expect(synthetic9002 != nil, "Should have synthetic candidate on port 9002")
        #expect(synthetic9002!.candidate.contains("10.0.0.1"))
    }

    @Test func expandCandidates_endOfCandidates_filtered() {
        let c = IceCandidatePayload(candidate: "a=end-of-candidates", sdpMLineIndex: 0, sdpMid: "0")
        let result = processor.expandCandidates([c])
        #expect(result.count == 0)
    }

    // MARK: - IPv6 expansion

    @Test func expandIPv6_loopback() {
        let bytes = processor.expandIPv6("::1")
        #expect(bytes?.count == 16)
        #expect(bytes![15] == 1)
    }

    @Test func expandIPv6_invalid_returnsNil() {
        let bytes = processor.expandIPv6("not-an-ipv6")
        #expect(bytes == nil)
    }

    // MARK: - Helpers

    /// Builds a real Teredo IPv6 string and runs extraction through the processor.
    private func buildTeredoAndExtract(clientIPv4: String, clientPort: Int) -> (String, Int) {
        let addr = makeTeredoAddress(clientIPv4: clientIPv4, clientPort: clientPort)
        guard let result = processor.extractTeredoEndpoint(addr) else {
            Issue.record("extractTeredoEndpoint returned nil for \(addr)")
            return ("", 0)
        }
        return result
    }

    /// Constructs a Teredo IPv6 address that encodes the given IPv4 and port.
    private func makeTeredoAddress(clientIPv4: String, clientPort: Int) -> String {
        // Bytes 0-3:  Teredo prefix 2001:0000
        // Bytes 4-7:  server IPv4 (use 0.0.0.0 = 00000000)
        // Bytes 8-9:  flags (use 0000)
        // Bytes 10-11: obfuscated port
        // Bytes 12-15: obfuscated client IPv4

        let portObs = UInt16(clientPort) ^ 0xFFFF

        let ipParts = clientIPv4.split(separator: ".").compactMap { UInt8($0) }
        guard ipParts.count == 4 else { fatalError("Invalid IPv4") }
        let a = ipParts[0] ^ 0xFF
        let b = ipParts[1] ^ 0xFF
        let c = ipParts[2] ^ 0xFF
        let d = ipParts[3] ^ 0xFF

        return String(format: "2001:0000:0000:0000:0000:%02x%02x:%02x%02x:%02x%02x",
                      portObs >> 8, portObs & 0xFF,
                      a, b, c, d)
    }
}
