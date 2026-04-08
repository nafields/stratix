// SDPProcessorTests.swift
// Exercises sdp processor behavior.
//

import Testing
@testable import StreamingCore

// MARK: - SDP Processor Tests
//
// Verifies SDP string manipulation against known inputs and outputs.

@Suite
struct SDPProcessorTests {

    let processor = SDPProcessor()

    // MARK: - Bitrate injection

    @Test func setBitrate_insertsLineAfterMediaSection() {
        let sdp = """
        v=0\r
        o=- 0 0 IN IP4 127.0.0.1\r
        m=video 9 UDP/TLS/RTP/SAVPF 96\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:96 H264/90000\r
        """
        let result = processor.processLocalSDP(sdp: sdp, maxVideoBitrateKbps: 8000)
        #expect(result.contains("b=AS:8000"), "Should inject b=AS:8000 line")
    }

    @Test func setBitrate_replacesExistingBLine() {
        let sdp = """
        v=0\r
        m=video 9 UDP/TLS/RTP/SAVPF 96\r
        b=AS:4000\r
        a=rtpmap:96 H264/90000\r
        """
        let result = processor.processLocalSDP(sdp: sdp, maxVideoBitrateKbps: 10000)
        #expect(result.contains("b=AS:10000"))
        #expect(!result.contains("b=AS:4000"))
    }

    @Test func setBitrate_skipsCandCLines() {
        let sdp = """
        v=0\r
        m=audio 9 UDP/TLS/RTP/SAVPF 111\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:111 opus/48000/2\r
        """
        let result = processor.processLocalSDP(sdp: sdp, maxAudioBitrateKbps: 128)
        // b=AS:128 must come after c= line
        let lines = result.components(separatedBy: "\n")
        let cIdx = lines.firstIndex(where: { $0.hasPrefix("c=") }) ?? -1
        let bIdx = lines.firstIndex(where: { $0.hasPrefix("b=AS:") }) ?? -1
        #expect(bIdx > cIdx, "b=AS line must appear after c= line")
    }

    @Test func noBitrateLimit_doesNotInjectBLine() {
        let sdp = "v=0\r\nm=video 9 RTP 96\r\na=foo\r\n"
        let result = processor.processLocalSDP(sdp: sdp)
        #expect(!result.contains("b=AS:"))
    }

    @Test func preferredH264Codec_keepsOriginalVideoPayloadOrder() {
        let sdp = """
        v=0\r
        m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:96 H264/90000\r
        a=fmtp:96 profile-level-id=640c1f;packetization-mode=1\r
        a=rtpmap:97 rtx/90000\r
        a=fmtp:97 apt=96\r
        a=rtpmap:98 H264/90000\r
        a=fmtp:98 profile-level-id=42e01f;packetization-mode=1\r
        a=rtpmap:99 rtx/90000\r
        a=fmtp:99 apt=98\r
        """

        let result = processor.processLocalSDP(
            sdp: sdp,
            stereoAudio: false,
            preferredVideoCodec: "H264"
        )

        #expect(result.contains("m=video 9 UDP/TLS/RTP/SAVPF 96 97 98 99"))
    }

    @Test func hardcodedDefaultOfferProfile_appliesDeterministicCaps() {
        let sdp = """
        v=0\r
        m=audio 9 UDP/TLS/RTP/SAVPF 111\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:111 opus/48000/2\r
        a=fmtp:111 minptime=10;useinbandfec=1\r
        m=video 9 UDP/TLS/RTP/SAVPF 96\r
        c=IN IP4 0.0.0.0\r
        a=rtpmap:96 H264/90000\r
        a=fmtp:96 packetization-mode=1\r
        """

        let result = processor.processLocalSDPWithHardcodedDefaults(sdp: sdp)

        #expect(result.contains("b=AS:120000"), "Hardcoded default should force video bitrate cap")
        #expect(result.contains("b=AS:48000"), "Hardcoded default should force audio bitrate cap")
        #expect(result.localizedCaseInsensitiveContains("stereo=1"), "Should force stereo opus")
        #expect(result.contains("a=max-fr:60"), "Should request 60fps via max-fr")
        #expect(result.localizedCaseInsensitiveContains("profile-level-id=640029"), "Should force H.264 fallback profile-level-id")
    }

    // MARK: - Stereo audio

    @Test func stereoAudio_addsStereoClaim() {
        let sdp = """
        a=rtpmap:111 opus/48000/2\r
        a=fmtp:111 minptime=10;useinbandfec=1\r
        """
        let result = processor.processLocalSDP(sdp: sdp, stereoAudio: true)
        #expect(result.contains("useinbandfec=1;stereo=1"))
    }

    @Test func stereoAudio_disabled_doesNotModify() {
        let sdp = "a=fmtp:111 minptime=10;useinbandfec=1\r\n"
        let result = processor.processLocalSDP(sdp: sdp, stereoAudio: false)
        #expect(!result.contains("stereo=1"))
    }

    // MARK: - Remote SDP pass-through

    @Test func processRemoteSDP_returnsUnchanged() {
        let sdp = "v=0\r\no=foo bar\r\n"
        let result = processor.processRemoteSDP(sdp: sdp)
        #expect(result == sdp)
    }

    // MARK: - H.264 profile priority

    @Test func h264Priority_highProfileFirst() {
        #expect(
            processor.h264ProfilePriority(fmtp: "profile-level-id=4d0032") <
            processor.h264ProfilePriority(fmtp: "profile-level-id=42e01f")
        )
    }

    @Test func h264Priority_constrainedBaselineBeforeBaseline() {
        #expect(
            processor.h264ProfilePriority(fmtp: "profile-level-id=42e01f") <
            processor.h264ProfilePriority(fmtp: "profile-level-id=4200")
        )
    }

    @Test func h264Priority_unknownFmtp_lowestPriority() {
        #expect(processor.h264ProfilePriority(fmtp: nil) > 2)
        #expect(processor.h264ProfilePriority(fmtp: "video/VP9") > 2)
    }
}
