# Contributing

## Setup

1. Xcode 27.
2. `cp Configuration/Local.example.xcconfig Configuration/Local.xcconfig` and put your Team ID in it.
3. Open the project, pick your iPhone, run. Paste a Gemini key on first launch.

If `xcode-select` on your Mac points at the Command Line Tools, prefix `xcodebuild` with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Rules that exist for a reason

**No warnings.** The build is clean; keep it clean.

**Main actor by default.** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` is on, so every closure is main-actor isolated unless you say otherwise. Any callback that runs on the audio render thread, a capture queue, URLSession or Core Motion has to be `@Sendable`. Forget it and the app traps in `swift_task_checkIsolated` the first time the callback fires. That's the crash to suspect whenever a new callback goes in.

Don't keep a closure inside a `Mutex` and read it back with `withLock`; each read re-wraps it and the stack eventually blows. `NSLock` and a plain property, like `MicPipeline` does.

**Audio changes need a phone in your hand.** Test a normal call, speakerphone, a Bluetooth headset, an incoming call in the middle, locking the screen, and yanking the headset out.

**Glass only on floating things.** Buttons and bars get `glassEffect` / `.glass`; content sits on plain backgrounds. No glass on glass.

**Every control gets an Arabic and an English `accessibilityLabel`.** State changes the user can't see go through `announce(_:)`. Before opening a PR, turn on VoiceOver with the screen curtain and use the thing.

**Nothing personal in the repo.** No keys, Team IDs, UDIDs. Signing lives in the ignored `Local.xcconfig`.

## Talking to the model

Wire types are in `LiveMessages.swift`, the session in `GeminiLiveClient.swift`, the watch logic in `SpeechFeedbackOrchestrator.swift`.

- `[WATCH]` messages are private instructions from the app. Keep new ones short, say what the attached frame is, and always leave the `nothing_changed` exit. Never send one before the previous turn's `turnComplete`.
- Tools use Gemini's uppercase schema types (`OBJECT`, `BOOLEAN`, `STRING`). 3.1 only does synchronous tool calls; answer them right away.
- Field names come from https://ai.google.dev/api/live. One wrong field and the whole setup message is rejected, and the user just sees a failed call.

## Diagnostics

`vlog("category", "message")` from any thread writes to the in-app log and to `Documents/vocavision-diagnostics.log`. Settings → Diagnostics shows and shares it. Never log the key.

Pull it off a device:

```bash
xcrun devicectl device copy from --device <udid> \
  --domain-type appDataContainer --domain-identifier com.vocavision.VocaVision \
  --source Documents/vocavision-diagnostics.log --destination .
```

## Detectors

`SceneChangeDetector` and `ScreenWatcher` are plain CoreGraphics/Vision and compile on macOS with `swiftc`, which is how I test them: a stub `vlog`, a `main.swift` that draws synthetic frames (a menu with a highlight bar that jumps, a brightness ramp with no content change, a blob crossing a static scene), and assertions on what comes out. Worth doing before touching the thresholds.
