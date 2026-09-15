# Security

## Reporting a vulnerability

Don't open a public issue for security problems. Use the **Security** tab → **Report a vulnerability** and I'll get back to you within a week.

## What counts

Anything that could expose a user's API key, audio, camera frames or transcripts to anyone other than Google's Gemini API. Bugs in the change detection are normal issues.

## How the app handles secrets

- The Gemini API key lives in the iOS Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` and is never written to logs, UserDefaults or the diagnostics file.
- All network traffic goes over TLS to `generativelanguage.googleapis.com`, `ai.google.dev` and `firebase.google.com`.
- The app ships no third-party SDKs.
