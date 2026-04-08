# Troubleshooting Guide

This guide covers the most common problems you will hit when building, running, and streaming with Stratix — and how to fix them.

Problems in this doc fall into four categories:
1. **Build and compilation** — WebRTC linking, concurrency errors, missing frameworks
2. **Authentication** — sign-in failures, expired tokens, empty library
3. **Streaming and connection** — peer connection failures, stuck sessions, input not working
4. **Audio** — silence on device, mono/stereo behavior, the octave-low bug

If you are not sure which category your problem belongs to, start by reading the console logs. Most issues leave clear fingerprints there.

## Reading the Logs

Console.app is your main diagnostic tool. When something goes wrong, the logs usually tell you exactly where the failure happened.

**How to open logs for Stratix:**

1. Connect your Apple TV via USB-C (or use the simulator)
2. Open **Console.app** on your Mac
3. Select your Apple TV or simulator from the left sidebar
4. In the search bar, filter by process name `Stratix`

**Or stream logs from the command line:**

```bash
# From a connected Apple TV:
xcrun devicectl device syslog --device <UDID> | grep Stratix

# From the simulator:
log stream --predicate 'processImagePath contains "Stratix"'
```

**Key log prefixes to know:**

| Prefix | What it covers |
|---|---|
| `[Auth]` | Token lifecycle, sign-in steps |
| `[Library]` | Library hydration, catalog fetches |
| `[Stream]` | Session lifecycle, state transitions |
| `[Session]` | xCloud/xHome session state machine |
| `[WebRTC]` | Peer connection state, ICE, SDP |
| `[WebRTC][tvOS] playout PCM callback=` | Audio unit heartbeat (every ~2.4 s) — if absent, the audio unit never started |
| `[AudioStats]` | playoutRate, jitter buffer, throughput |
| `[InputChannel]` | Input channel open, packet sends |
| `[Control]` | Control channel messages (gamepad registration, etc.) |
| `[VideoRenderer]` | Frame receipt, Metal/SampleBuffer path |

When something breaks, filter by the relevant prefix above and scan for error lines. The structure of most failures is: a state machine advances to an unexpected state, or a required initialization step never logs its "ready" line.

---

## Build & Compilation

## Build & Compilation

### "WebRTC.xcframework not found"

**Symptom:** Xcode build fails with "could not find WebRTC.xcframework" or similar framework search path error.

**Fix:**
1. Verify the file exists:
   ```bash
   ls -la ThirdParty/WebRTC/WebRTC.xcframework
   ```
2. If missing, rebuild it:
   ```bash
   cd Tools/webrtc-build
   ./sync_webrtc.sh
   ./build_webrtc_tvos.sh
   ./package_xcframework.sh
   ```
3. Ensure it is added to the Xcode project under `ThirdParty/WebRTC/` — it should be committed

See [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md) for the full rebuild guide.

---

### "Undefined symbols: _OBJC_CLASS_$_RTC*"

**Symptom:** App builds but fails to link (or crashes on launch) with linker errors about RTC symbols.

**Root cause:** `WebRTC.xcframework` was built without `rtc_enable_objc_symbol_export=true`. Without this flag, all Objective-C class symbols have hidden visibility and the linker cannot find them.

**Fix:** Rebuild using the correct GN arguments:
```bash
cd Tools/webrtc-build
./build_webrtc_tvos.sh  # script includes rtc_enable_objc_symbol_export=true
./package_xcframework.sh
```

Verify the flag is set by inspecting the build script or checking `ThirdParty/WebRTC/webrtc-version.json` for the commit metadata.

---

### "Could not build Objective-C module 'WebRTC'"

**Symptom:** `Compiling module 'WebRTC'` fails during Xcode build.

**Fix:**
1. Check that the bridging header at `Apps/Stratix/Stratix/Stratix-Bridging-Header.h` contains:
   ```objc
   #import <WebRTC/WebRTC.h>
   ```
2. In the app project settings, verify:
   - `SWIFT_OBJC_BRIDGING_HEADER = "Stratix/Stratix-Bridging-Header.h"`
   - the app target still references `../../ThirdParty/WebRTC/WebRTC.xcframework`
3. Clean derived data and rebuild: **Product → Clean Build Folder** (⌘⇧K)

---

### Swift concurrency errors after adding code

**Symptom:** New code introduces `Actor-isolated` or `Sendable` conformance errors.

**Cause:** The repo uses Swift 6.2 with `complete` concurrency checking — the strictest mode.

**Fix:**
- If the type crosses actor boundaries: add `Sendable` conformance or use value types
- If the mutation happens on the wrong actor: move to `@MainActor` or a dedicated `actor`
- **Do not** add `@unchecked Sendable` unless you have a documented justification in [CONCURRENCY_EXCEPTIONS.md](CONCURRENCY_EXCEPTIONS.md)

---

## Authentication & Sign-In

### "Error signing in: Invalid request"

**Symptom:** Device code flow fails at the token exchange step.

**Cause:** Device code expired (5 min TTL) or the Microsoft account has no Xbox Game Pass access.

**Fix:**
1. Tap the sign-in button again to get a fresh device code
2. Complete the code entry within 5 minutes
3. Verify the Microsoft account has an active Xbox Game Pass Ultimate subscription
4. Check Console.app for `[Auth]` log lines describing the failure stage

---

### "Cloud library is empty after sign-in"

**Symptom:** Sign-in succeeds and the shell loads, but no game tiles appear.

**Cause:**
- No Game Pass subscription on the account
- Entitlement API returned empty results
- Stale cached state

**Fix:**
1. Verify the account has Game Pass Ultimate active at xbox.com
2. Force a library refresh: pull-to-refresh or use the refresh button in the shell
3. Check Console.app for `[Library]` logs — look for error details on the hydration response
4. Sign out completely and sign in again

---

### "Session expired, sign in again"

**Symptom:** App shows "Your sign-in session expired" error.

**Cause:** The MSA refresh token expired (~90 day TTL) or was revoked (password change, security event).

**Fix:**
1. Sign out: open the guide overlay → Profile → Sign Out
2. Sign in again with a fresh device code
3. A new refresh token will be written to Keychain under the `stratix.*` keys, and any older `greenlight.*` entry will be migrated forward on access

---

## Streaming & Connection

### "Stream fails with MsaVeto error"

**Symptom:** Stream starts provisioning but fails immediately with code `MsaVeto`.

**Root cause:** The MSA access token expired (~1 hour TTL). The `/connect` call requires a fresh token.

**Fix:**
1. The app should automatically refresh tokens before streaming — check Console.app for `[Auth] token refresh` log lines
2. If token refresh fails, sign out and sign in to get a fresh token chain
3. Verify the cloud-stream launch path refreshes auth state before calling `StreamingSession.connect()`; the current public controller entry point is `StreamController.startCloudStream(...)`

---

### "Peer connection failed during startup"

**Symptom:** WebRTC connects momentarily then transitions to state `.failed`.

**Cause:**
- ICE candidates were not exchanged successfully
- Network changed or was lost mid-connection
- Xbox server closed the connection (usually due to a session timeout)

**Fix:**
1. Check network stability — ensure you have a stable WiFi or Ethernet connection
2. Check if xCloud is experiencing issues by trying from a browser on another device
3. The app has auto-reconnect (up to 3 attempts) — wait and see if it recovers
4. Manually stop and restart the stream: open the guide overlay → Stop

---

### "Input not working — buttons not responding in-game"

**Symptom:** Controller is connected and visible, but the game doesn't respond to button presses.

**Cause:**
- `InputChannel` failed to open or the current 125 Hz poll loop wasn't started
- The gamepad was not registered with the server via `gamepadChanged`
- Deadzone set too high

**Fix:**
1. Check Console.app for:
   ```
   [InputChannel] onOpen: sending client metadata and starting poll loop
   ```
   If this never appears, the data channel did not open correctly.
2. Check for:
   ```
   [Control] sending gamepadChanged index=0 wasAdded=true
   ```
   This must fire before input is processed by the server.
3. Check `guide.controller_deadzone` in UserDefaults — value `0.10` is default. A value too close to 1.0 would zero all input.
4. Try a different controller or the Siri Remote as a fallback

See [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md) for the full input pipeline.

---

### "Stream stuck at 'Connecting...'"

**Symptom:** Session provisioning takes longer than expected or never completes.

**Cause:**
- Session state machine stalled at `WaitingForResources` (server side queue)
- Network timeout during ICE candidate gathering (5 second max)
- Incorrect polling after MSAL auth (should poll for `Provisioned`, not `ReadyToConnect`)

**Fix:**
1. If stalled at `WaitingForResources`, wait — servers can take up to 60 seconds when busy
2. Check Console.app for the session state transitions:
   ```
   [Session] state=ReadyToConnect
   [Session] sending MSAL auth (xCloud)
   [Session] state=Provisioned
   ```
3. Force stop and try again: open guide → Stop → launch again

---

## Audio Issues

### "Complete audio silence on physical Apple TV (works in simulator)"

**Symptom:** Video plays fine, but no audio whatsoever. The issue disappears in the simulator.

**Root cause:** Patch 0008 (`inputAvailable` check bypass) is not applied in the vendored WebRTC build. On tvOS, `inputAvailable` is always `NO` (no microphone), causing `configureWebRTCSession` to return `NO` silently — the audio unit never starts.

**Diagnostic:**
1. Connect Apple TV to Mac via USB-C
2. Open Console.app → filter by device → search for:
   ```
   [WebRTC][tvOS] playout PCM callback=
   ```
3. Start streaming
4. If the log line **never appears**: the audio unit was never started → patch 0008 issue

**Fix:** Rebuild the xcframework with all 11 patches applied:
```bash
cd Tools/webrtc-build
./sync_webrtc.sh
./build_webrtc_tvos.sh
./package_xcframework.sh
```

See [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) §4 for the root cause chain.

---

### "Audio plays one octave lower than expected"

**Symptom:** Audio volume is correct but pitch is too low — sounds like half-speed playback. Present on both simulator and device.

**Root cause:** `outputNumberOfChannels=2` (stereo mode) is active, but the WebRTC AudioUnit format is still hardcoded to mono (patch 0011 not applied). FineAudioBuffer requests only half the expected audio content per callback cycle → audio plays at half speed → one octave lower.

**Quick diagnosis:**
1. Check Console.app for `[AudioStats] playoutRate=~50%` — this confirms the channel count mismatch
2. Check `guide.stereo_audio` in UserDefaults — `true` means stereo is active

**Fix:**
- **Without patch 0011 (current xcframework):** Disable "Stereo Audio" in the guide overlay. The stereo toggle must remain OFF without patch 0011.
- **With patch 0011:** Stereo mode is safe to enable. Rebuild the xcframework with patch 0011 if in doubt.

See [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md) §6 for the full call chain explaining why `channels=2` causes half-speed.

---

### "playoutRate shows ~50% in AudioStats"

**Symptom:** Console shows `[AudioStats] playoutRate=50%`.

**Root cause:** Same as the octave-low bug — `outputNumberOfChannels=2` with mono AudioUnit format.

**Fix:** See the octave-low fix above (disable stereo, or rebuild with patch 0011).

---

### "Stereo Audio toggle is ON but audio sounds mono"

**Symptom:** "Stereo Audio" is enabled in the guide, stream was restarted, but audio sounds identical to mono.

**Expected behavior:** xCloud sends stereo Opus, but WebRTC's NetEQ decoder chain downmixes to mono before the audio pipeline. With `outputChannels=2`, both L and R channels receive duplicated mono content — there is no true independent stereo. True stereo requires patching the NetEQ/Opus decoder chain, which is not currently implemented.

---

### "outputVolume = 0.0 on HDMI (is it broken?)"

**Symptom:** `AVAudioSession.outputVolume` always returns `0.0`. You suspect audio is muted.

**Expected behavior:** On tvOS HDMI output, `outputVolume` is always `0.0`. Volume is controlled by the TV or AV receiver via HDMI CEC, not by software. Use your TV remote to adjust volume.

Do not use `outputVolume` as a silence indicator on Apple TV.

---

### "MixWithOthers option was added and now audio is silent"

**Symptom:** Audio was working, then `AVAudioSessionCategoryOptionMixWithOthers` was added and audio went silent.

**Fix:** Remove `MixWithOthers` immediately. On tvOS, this causes the audio session to receive ambient priority, which sets the output volume to 0.0. The correct configuration is:
```objc
_category = AVAudioSessionCategoryPlayback;
_categoryOptions = 0;  // NO MixWithOthers
_mode = AVAudioSessionModeMoviePlayback;
```
This is applied by patch 0001. If the patch was modified, restore the above configuration.

---

## Focus & Navigation

### "Focus gets stuck — D-pad doesn't navigate away"

**Symptom:** Focus ring stays on one button. D-pad doesn't move to other interactive elements.

**Cause:**
- `.focusSection()` boundary is misconfigured — focus is trapped inside a section with only one item
- `@FocusState` value is not being updated correctly

**Fix:**
1. Check that related interactive elements are grouped in a `.focusSection()`
2. Check that `@FocusState` assignments use `DispatchQueue.main.async` when called from callbacks:
   ```swift
   // CORRECT:
   DispatchQueue.main.async { focusedTarget = .nextItem }
   // WRONG:
   focusedTarget = .nextItem  // in a callback — can miss transitions
   ```
3. If stuck after an overlay closes: the guide overlay close path should restore focus to the previous item

---

### "Guide overlay doesn't close with Menu button"

**Symptom:** The stream guide overlay is visible but pressing Menu doesn't dismiss it.

**Cause:**
- The guide view is not consuming the Menu (exit) command
- Focus is not inside the overlay — a different focus scope is handling Menu first

**Fix:**
1. Verify `StreamGuideOverlayView` applies `.onExitCommand { dismiss() }` or equivalent
2. Confirm the overlay container has focus when it opens
3. Restart the stream as a workaround if focus state gets corrupted

---

## Performance Issues

### "High input lag — buttons feel slow"

**Symptom:** 200+ ms delay between controller button press and game response.

**Cause:**
- Network latency to Xbox servers (primary cause)
- `InputChannel` poll loop delayed or blocked

**Fix:**
1. Check Console.app for `[InputChannel]` logs — confirm packets are being sent at the current 125 Hz cadence
2. Enable low-latency mode in the guide (reduces keyframe interval from 5s → 2s, improves recovery)
3. Switch from WiFi to wired Ethernet (reduces jitter)
4. Check network: ping your router to confirm <20 ms local latency

---

### "Video stuttering or frame drops"

**Symptom:** Video playback skips, freezes, or has visible artifacts.

**Cause:**
- Network congestion or packet loss
- Bitrate cap too high for current network
- NetEQ buffer underrun

**Fix:**
1. Check `[AudioStats] jbWinMs` — if consistently >150 ms (vs. normal 20–80 ms oscillation), the jitter buffer is under stress
2. Lower the bitrate cap in the guide settings
3. Try a lower resolution: 1080p → 720p
4. Switch to Ethernet if on WiFi

---

### "Memory usage keeps growing during streaming"

**Symptom:** App memory grows steadily during a stream session.

**Cause:**
- Video frame buffers not being returned to the pool
- Task lifecycle leak in streaming session

**Fix:**
1. Verify `StreamController.stopStream()` is called on exit — check Console.app for `[Stream] disconnecting`
2. Use Xcode Instruments → Allocations to identify the growing allocation type
3. Check that `StreamingSession` is being deallocated after disconnect (no retain cycle)

---

## Testing Issues

### "Package unit tests fail with RTC symbol errors on macOS"

**Symptom:** `xcodebuild test -scheme Stratix-Packages` fails with `Cannot find _OBJC_CLASS_$_RTC*`.

**Root cause:** A test target is importing or linking against `WebRTC.xcframework`, which only has tvOS slices.

**Fix:**
1. Package tests must use `MockWebRTCBridge`, not `WebRTCClientImpl`
2. Ensure `WebRTCClientImpl` is wrapped in `#if WEBRTC_AVAILABLE` in any code path reachable from tests
3. Run package tests on macOS:
   ```bash
   xcodebuild test \
     -scheme Stratix-Packages \
     -destination 'platform=macOS' \
     -configuration Debug
   ```

---

### "ShellUI tests fail with missing state"

**Symptom:** `Stratix-ShellUI` scheme tests fail because expected state is not present.

**Fix:**
1. Verify the test uses the correct launch mode flag (`StratixLaunchMode.isGamePassHomeUITestModeEnabled` or `isShellUITestModeEnabled`)
2. Check that `CloudLibraryUITestHarnessView` or `ShellUITestHarnessView` is being substituted in `RootView`
3. Use the accessibility identifier markers (`shell_ready`, `stream_exit_complete`) for synchronization rather than sleep/poll delays

---

## Getting Help

1. **Check the relevant doc** for the area:
   - Streaming issues → [STREAMING_ARCHITECTURE.md](STREAMING_ARCHITECTURE.md)
   - Audio issues → [AUDIO_ARCHITECTURE.md](AUDIO_ARCHITECTURE.md)
   - Input issues → [CONTROLLER_INPUT.md](CONTROLLER_INPUT.md)
   - UI/focus issues → [UI_ARCHITECTURE.md](UI_ARCHITECTURE.md)
   - WebRTC build issues → [WEBRTC_BUILD_REFERENCE.md](WEBRTC_BUILD_REFERENCE.md)

2. **Attach console logs** when reporting issues — include the `[AudioStats]` line and any error lines from relevant prefixes above.

3. **Include environment details:**
   - Xcode version (check: `xcode-select -p && xcrun swift --version`)
   - tvOS version on device (Settings → General → About)
   - Apple TV model (4K 2nd gen, 4K 3rd gen, etc.)
   - WebRTC revision (check `ThirdParty/WebRTC/webrtc-version.json`)
