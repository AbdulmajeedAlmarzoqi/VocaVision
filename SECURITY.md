# Security

## Reporting a vulnerability

Please do not open a public issue for security problems. Use GitHub's private vulnerability reporting instead: go to the **Security** tab of this repository and choose **Report a vulnerability**. You will get a reply within a week.

## What counts

Anything that could expose a user's API key, audio, camera frames or transcripts to a party other than Google's Gemini API, or that lets an attacker act on a user's behalf. Bugs in the on-device change detection are not security issues; open a normal issue for those.

## How the app handles secrets

- The Gemini API key lives in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and is never written to logs, UserDefaults or the diagnostics file.
- All network traffic goes over TLS to `generativelanguage.googleapis.com`, `ai.google.dev` and `firebase.google.com`.
- The app ships no third-party SDKs.
