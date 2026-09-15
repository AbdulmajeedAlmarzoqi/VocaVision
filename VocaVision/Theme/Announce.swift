import Accessibility
import Foundation

/// VoiceOver announcement through the SwiftUI-era API. Brand names
/// listed in `englishTokens` are tagged `en-US` so VoiceOver switches
/// voice mid-sentence instead of spelling them out in Arabic.
@MainActor
func announce(_ text: String, englishTokens: [String] = [], highPriority: Bool = false) {
    var attributed = englishTokens.isEmpty
        ? AttributedString(text)
        : makeBilingualString(text, englishTokens: englishTokens)
    attributed.accessibilitySpeechAnnouncementPriority = highPriority ? .high : .default
    AccessibilityNotification.Announcement(attributed).post()
}
