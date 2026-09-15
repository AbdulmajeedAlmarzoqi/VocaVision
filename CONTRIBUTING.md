# Contributing

Thanks for looking at the code. This guide covers what you need to build the app, the rules that keep it stable, and how to test the parts that are hard to test.

## Setup

1. Install Xcode 27.
2. `cp Configuration/Local.example.xcconfig Configuration/Local.xcconfig` and put your Team ID in it. The file is ignored by git.
3. Open `VocaVision.xcodeproj`, select the `VocaVision` scheme and a physical iPhone, and run.
4. Paste a Gemini API key on first launch.

If `xcode-select` on your Mac points at the Command Line Tools rather than Xcode, prefix `xcodebuild` and `xcrun` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Ground rules

**Zero warnings.** The build is clean and pull requests that add a warning are sent back.

**Main actor by default.** The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every type and closure is main-actor isolated unless it says otherwise. Anything that runs on another thread must be marked:

- Callbacks handed to AVAudioEngine, AVAudioSourceNode, AVCaptureSession, URLSession or CoreMotion must be `@Sendable`. A closure that is implicitly `@MainActor` and gets called from the audio render thread traps in `swift_task_checkIsolated`. That was the first crash this project shipped, and it is the one to look for when a new callback is added.
- Classes used from those threads are `nonisolated final class … : Sendable` (or `@unchecked Sendable` with a lock and a comment saying why).
- Do not store a closure inside a `Mutex` and read it back with `withLock`. Each read re-wraps the closure and the stack eventually overflows. Use `NSLock` plus a plain property, as `MicPipeline` does.

**Audio.** `CallAudioEngine` and `PlaybackRingBuffer` are tuned against real devices. Change them only with a device in hand and test: normal call, speakerphone, Bluetooth headset, an incoming phone call mid-session, locking the screen, and pulling the headset out.

**Liquid Glass.** Glass goes on floating controls and bars (`glassEffect`, `.buttonStyle(.glass)`, `GlassEffectContainer`). Content sits on plain or material backgrounds. Never put glass on glass.

**Accessibility is the product.** Every interactive element gets an Arabic and an English `accessibilityLabel` and, where the action is not obvious, a hint. Brand names are tagged as English through `accessibilityBilingual` so VoiceOver switches voices. State changes the user cannot see are announced through `announce(_:)`. Before opening a pull request, turn VoiceOver on and use the feature with the screen curtain enabled.

**No secrets, no identifiers.** Nothing in the repository may contain an API key, a Team ID, a device UDID or a personal email. Signing lives in the ignored `Local.xcconfig`.

## Talking to the model

Everything the app sends to Gemini is in `LiveMessages.swift` (wire types) and `GeminiLiveClient.swift` (session). Two protocols matter:

- **`[WATCH]` pings** are private messages from the app. If you add a new kind, keep it short and imperative, tell the model what the attached frame is, and always give it the `nothing_changed` exit. Never send a ping while `modelIsSpeaking` or before the previous ping's `turnComplete`; a ping during generation cancels the generation.
- **Tools** are declared in `SpeechFeedbackOrchestrator.toolDeclarations` using Gemini's uppercase schema types (`OBJECT`, `BOOLEAN`, `STRING`). Gemini 3.1 only supports synchronous tool calls; respond immediately.

Field names and enum values come from the API reference at https://ai.google.dev/api/live. When in doubt, check the reference rather than a blog post; the setup message is rejected as a whole if any field is wrong, and the user just sees a failed call.

## Diagnostics

The app keeps a log in memory and in `Documents/vocavision-diagnostics.log`, viewable and shareable from Settings → Diagnostics. Write to it with `vlog("category", "message", level:)` from any thread. Prefixes used so far: `🎬` for watch pings, `🎥` for the video stream, `🗣`/`🤖` for transcripts, `🔁` for reconnects. Never log the API key.

To pull the log from a connected device without the app:

```bash
xcrun devicectl device copy from --device <udid> \
  --domain-type appDataContainer --domain-identifier com.vocavision.VocaVision \
  --source Documents/vocavision-diagnostics.log --destination .
```

## Testing the detectors on macOS

`SceneChangeDetector` and `ScreenWatcher` are plain Swift over CoreGraphics and Vision, so they compile on macOS. A quick harness looks like this:

```bash
mkdir harness && cd harness
cp ../VocaVision/Services/SceneChangeDetector.swift ../VocaVision/Services/ScreenWatcher.swift .
cat > stub.swift <<'SWIFT'
import Foundation
enum DiagLevel { case debug, info, notice, warning, error }
nonisolated func vlog(_ c: String, _ m: String, level: DiagLevel = .info) { print("[\(c)] \(m)") }
SWIFT
sed -i '' -E 's/level: \.(debug|info|notice|warning|error)\)/level: DiagLevel.\1)/g' *.swift
# write main.swift that feeds synthetic frames, then:
swiftc -O -swift-version 5 SceneChangeDetector.swift ScreenWatcher.swift stub.swift main.swift -o harness
```

Synthetic frames that have caught real bugs: a moving 3 px highlight band on a static menu, a global brightness ramp with no content change, a small blob moving across an otherwise static scene (the old z-score normalisation let it register in every cell), and a rectangle nested inside a larger one (the detector used to lock onto the inner one).

## Pull requests

Keep them focused. Describe what changed and why, note what you tested on a device, and fill in the checklist in the template. If a change affects how the app sounds with VoiceOver, say what the user hears.
