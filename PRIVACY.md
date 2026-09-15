# Privacy Policy

**Effective date: 15 September 2026**

VocaVision is an iPhone app that lets blind and low-vision users hold a voice call with an assistant that describes what the camera sees. This is what the app does with your data. Short version: nothing leaves your phone except what goes to Google's Gemini API under your own key, and I never see any of it.

## What the app collects

VocaVision has no server, no accounts, no analytics SDK, no crash reporter and no ads. I don't collect, receive or store anything about you.

## What stays on your phone

| Data | Where it is stored | Why |
|---|---|---|
| Your Gemini API key | iOS Keychain (device only, not synced to iCloud) | To authenticate calls to Google's API |
| Voice, dialect, preset, name and pronoun preferences | App preferences (UserDefaults) | To personalise the assistant |
| A diagnostics log (timestamps, connection events, transcripts of what you and the assistant said during a call) | The app's Documents folder | So you can share it when reporting a bug. It is only ever sent if you explicitly export it from Settings → Diagnostics |
| The cached voice directory | Application Support | So the voice list works offline |

Deleting the app deletes all of the above.

## What is sent to Google

During a call the app streams your microphone audio and camera frames (about one still image per second) to Google's Gemini Live API, using the API key you entered. Google processes that data to generate the spoken replies. Google's handling of it is governed by Google's terms and privacy policy, not by this document:

- Gemini API Terms of Service: https://ai.google.dev/gemini-api/terms
- Google Privacy Policy: https://policies.google.com/privacy

Whether Google may use your data to improve its models depends on the plan attached to your key (free tier versus paid). Check the terms above before using the app with sensitive content.

The app also downloads Google's published voice table and sample recordings from Google's documentation servers, and it validates your key against the Gemini API when you save it. No personal data is included in those requests.

## Permissions

- **Camera**: only used while a call is active, so the assistant can see what is in front of you.
- **Microphone**: only used while a call is active, so you can talk to the assistant.
- **Motion**: used to tell when you have re-aimed the phone during a call. Motion data never leaves the device.

Camera and microphone are turned off the moment a call ends.

## Children

VocaVision is not directed at children under 13 and does not knowingly collect information from them.

## Changes

Changes to this policy are published in this repository. The effective date at the top is updated with each change.

## Contact

Open an issue in this repository.
