**What this changes**

**Why**

**Checklist**
- [ ] Builds with zero warnings (`xcodebuild ... build` prints none)
- [ ] Tested on a physical iPhone (the simulator has no camera and no voice-processing audio unit)
- [ ] Every new control has an Arabic and an English `accessibilityLabel`
- [ ] No closure that runs on an audio, camera or network thread is left implicitly `@MainActor`
- [ ] Nothing personal (keys, team IDs, device names) in the diff
