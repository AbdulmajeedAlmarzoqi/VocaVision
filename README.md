# VocaVision

<img src="Branding/VocaVision_Logo.png" alt="VocaVision" width="360">

iPhone app for blind users. You start a voice call, point the camera at something, and the assistant tells you what's there, in your own dialect. Built around VoiceOver from day one. Runs on your own Gemini API key, no server in between.

## Try it

The public beta is on TestFlight: **https://testflight.apple.com/join/PJptG4Eh**

You need an iPhone on iOS 26 or later and a free Gemini API key from [AI Studio](https://aistudio.google.com/apikey); the app asks for it on first launch. Feedback through TestFlight or the issues here, whichever you prefer.

## What it does

- Point and ask. "What's on the desk?", "read this", "which option is selected?"
- Say «راقب الشاشة» and it keeps watching. Every time the highlight moves in a BIOS menu it reads the new row, when the page changes it says so, when you turn around it describes what's in front of you now. When nothing changed it stays quiet.
- Interrupt it mid-sentence, on speakerphone too.
- Arabic first. 20 Arabic dialects with their own prompts, plus most other languages. It sticks to the one you picked instead of sliding into fusha after a pause.
- 30 voices. The list is pulled from Google's docs, with their descriptions and sample clips, so it updates itself.
- It's a real phone call as far as iOS is concerned (LiveCommunicationKit), so it keeps going with the screen locked.

## Requirements

- Xcode 27, iOS 26 or later
- An actual iPhone. It builds for the simulator, but there's no camera and no voice-processing audio unit there, so the call is pointless.
- A Gemini API key from [AI Studio](https://aistudio.google.com/apikey). The app uses `gemini-3.1-flash-live-preview` if your key can see it and falls back to the 2.5 native-audio model otherwise.

## Building

```bash
git clone https://github.com/AbdulmajeedAlmarzoqi/VocaVision.git
cd VocaVision
cp Configuration/Local.example.xcconfig Configuration/Local.xcconfig
```

Put your Team ID in `Local.xcconfig` (it's gitignored), open the project, run on your phone. Paste the key when asked.

Swift 6 language mode, main actor by default, no warnings. If you send a PR, keep it at zero.

## How it's put together

**Audio.** AVAudioEngine with voice processing on the input. The mic goes up as 16 kHz PCM in 40 ms chunks. Replies come back as 24 kHz PCM and get played through an `AVAudioSourceNode` reading from a ring buffer. The first version scheduled buffers on an `AVAudioPlayerNode` and stuttered every time a chunk showed up late; the source node renders silence on underrun instead and the problem went away.

**Video.** Frames are sent for the whole call at 1 fps (the API's ceiling), half that when you're not in watch mode. On Gemini 3.1 every frame since the last turn is part of the next one, so when you ask something the model has already seen the last few seconds.

**Watch mode.** The model doesn't speak because a frame changed; Gemini needs a prompt to start a turn. So after each turn ends the app sends a short `[WATCH]` message and the model either says what changed or calls `nothing_changed`, which is a tool and therefore silent. Sending that message while the model is still generating cancels the generation, so it never does.

What decides when to send it lives on the phone: Core Motion for "you moved and settled", a frame-diff detector with alignment and a photometric fit so a lamp turning on isn't a change, and a screen watcher that finds the display with Vision, straightens it, and crops the row whose colour just changed so the model reads exactly that line. If nothing fires for three seconds it pings anyway.

**Voices.** There's no endpoint that lists Gemini voices. `VoiceDirectory` reads the table off Google's documentation pages (name, one-word style, gender, sample wav), caches it, and refreshes once a day.

**Prompts.** `PromptBuilder` in `Settings/Customization.swift`: identity, dialect lock, preset. It's a long file; the dialect prompts are most of it.

```
VocaVision/
  Call/        call screen and view model
  Services/    Gemini client, audio engine, camera, detectors, voice directory
  Settings/    key, voice, language, presets, profile, diagnostics log
  Home/        home screen, first-launch notice, privacy text
  Theme/       colours, glass helpers, VoiceOver helpers
```

## Privacy

Your key is in the Keychain, your settings are on the device, and during a call your mic and camera go to Google under your key and Google's terms. Nothing comes to me. Full text in [PRIVACY.md](PRIVACY.md).

## Contributing

Issues and PRs welcome, see [CONTRIBUTING.md](CONTRIBUTING.md). If you use VoiceOver, your bug reports are the ones I want most.

## License

MIT
