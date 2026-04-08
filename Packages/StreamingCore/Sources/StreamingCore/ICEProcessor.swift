// ICEProcessor.swift
// Defines ice processor.
//

import Foundation
import StratixModels

// MARK: - ICE Processor
// Mirrors ice.ts — handles Teredo IPv6 NAT traversal for xHome streaming.
//
// Xbox home streaming servers often send Teredo IPv6 addresses (2001::/32).
// The ICE processor extracts the embedded IPv4 client address and port,
// synthesising two extra host candidates so NAT traversal works.
//
// Teredo address structure (RFC 4380):
//   Bits  0- 31: 0x20010000 (Teredo prefix)
//   Bits 32- 63: Teredo server IPv4
//   Bits 64- 79: Flags
//   Bits 80- 95: Obfuscated client UDP port (XOR 0xFFFF)
//   Bits 96-127: Obfuscated client IPv4    (XOR each byte with 0xFF)

public struct ICEProcessor: Sendable {

    public init() {}

    // MARK: - Process remote candidates

    /// Expands remote ICE candidates, adding synthetic host candidates derived from
    /// Teredo addresses. Mirrors ice.ts setRemoteCandidates().
    public func expandCandidates(_ candidates: [IceCandidatePayload]) -> [IceCandidatePayload] {
        var expandedCandidates: [IceCandidatePayload] = []
        for candidate in candidates {
            if candidate.candidate == "a=end-of-candidates" { continue }

            let parts = candidate.candidate.components(separatedBy: " ")
            guard parts.count > 4 else {
                expandedCandidates.append(candidate)
                continue
            }

            let address = parts[4]
            if address.hasPrefix("2001:"),
               let (ipv4, port) = extractTeredoEndpoint(address) {
                expandedCandidates.append(IceCandidatePayload(
                    candidate: "a=candidate:10 1 UDP 1 \(ipv4) 9002 typ host ",
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid
                ))
                expandedCandidates.append(IceCandidatePayload(
                    candidate: "a=candidate:11 1 UDP 1 \(ipv4) \(port) typ host ",
                    sdpMLineIndex: candidate.sdpMLineIndex,
                    sdpMid: candidate.sdpMid
                ))
            }

            expandedCandidates.append(candidate)
        }
        return expandedCandidates
    }

    // MARK: - Teredo extraction

    /// Extracts the client IPv4 and UDP port embedded in a Teredo address.
    /// Returns nil if the address cannot be parsed.
    public func extractTeredoEndpoint(_ ipv6: String) -> (ipv4: String, port: Int)? {
        // Expand and parse the 16-byte Teredo address
        guard let bytes = expandIPv6(ipv6), bytes.count == 16 else { return nil }

        // Bytes 10-11: obfuscated port (XOR 0xFFFF)
        let portObf = (UInt16(bytes[10]) << 8) | UInt16(bytes[11])
        let port = Int(portObf ^ 0xFFFF)

        // Bytes 12-15: obfuscated client IPv4 (XOR each byte with 0xFF)
        let a = bytes[12] ^ 0xFF
        let b = bytes[13] ^ 0xFF
        let c = bytes[14] ^ 0xFF
        let d = bytes[15] ^ 0xFF
        let ipv4 = "\(a).\(b).\(c).\(d)"

        return (ipv4, port)
    }

    // MARK: - IPv6 expansion

    /// Expands a compressed IPv6 string into exactly 16 bytes.
    func expandIPv6(_ ipv6: String) -> [UInt8]? {
        var addr = in6_addr()
        let status = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: in6_addr.self, capacity: 1) { ptr in
                inet_pton(AF_INET6, ipv6, ptr)
            }
        }
        guard status == 1 else { return nil }
        return withUnsafeBytes(of: addr) { Array($0) }
    }
}
