import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.298, green: 0.522, blue: 0.957)
    static let success = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let danger = Color(red: 0.94, green: 0.30, blue: 0.30)
    static let warning = Color(red: 0.97, green: 0.75, blue: 0.20)

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 24
    }
}

extension View {
    /// Content-layer card. Liquid Glass is reserved for controls that
    /// float above content (bars, call buttons); content itself sits on
    /// a plain material so glass keeps its contrast.
    func contentCard(padding: CGFloat = AppTheme.Spacing.md) -> some View {
        self
            .padding(padding)
            .background(.regularMaterial, in: .rect(cornerRadius: AppTheme.Radius.card))
    }

    /// Bilingual accessibility label built from language-tagged
    /// segments so VoiceOver switches voice mid-sentence.
    func accessibilityMultilingual(_ segments: AccessibilitySegment...) -> some View {
        accessibilityLabel(Text(makeAttributedString(from: segments)))
    }

    /// Mostly-Arabic label with a few embedded English brand names.
    func accessibilityBilingual(_ text: String, englishTokens: [String]) -> some View {
        accessibilityLabel(Text(makeBilingualString(text, englishTokens: englishTokens)))
    }
}

/// Soft brand gradient for the content layer — the glass controls above
/// it pick the colour up dynamically.
struct BrandBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.03, green: 0.08, blue: 0.16), Color(red: 0.02, green: 0.04, blue: 0.10)]
                : [Color(red: 0.90, green: 0.94, blue: 1.00), Color(red: 0.97, green: 0.98, blue: 1.00)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// One language-tagged chunk of an accessibility label.
struct AccessibilitySegment {
    let text: String
    let language: String

    static func ar(_ text: String) -> AccessibilitySegment { .init(text: text, language: "ar-SA") }
    static func en(_ text: String) -> AccessibilitySegment { .init(text: text, language: "en-US") }
}

/// Glues language-tagged segments into one `AttributedString`. Goes
/// through `NSAttributedString` because `accessibilitySpeechLanguage`
/// only exists as an `NSAttributedString.Key`; the Swift attribute scope
/// has no typed equivalent (iOS 27 adds SSML instead).
func makeAttributedString(from segments: [AccessibilitySegment]) -> AttributedString {
    let combined = NSMutableAttributedString()
    for segment in segments {
        combined.append(NSAttributedString(
            string: segment.text,
            attributes: [.accessibilitySpeechLanguage: segment.language]
        ))
    }
    return AttributedString(combined)
}

/// Tags every occurrence of `englishTokens` as `en-US`, the rest as
/// `ar-SA`. Visible text is untouched.
func makeBilingualString(_ text: String, englishTokens: [String]) -> AttributedString {
    let combined = NSMutableAttributedString(
        string: text,
        attributes: [.accessibilitySpeechLanguage: "ar-SA"]
    )
    let nsString = text as NSString
    for token in englishTokens {
        var searchStart = 0
        while searchStart < nsString.length {
            let range = nsString.range(of: token, options: [], range: NSRange(location: searchStart, length: nsString.length - searchStart))
            if range.location == NSNotFound { break }
            combined.addAttribute(.accessibilitySpeechLanguage, value: "en-US", range: range)
            searchStart = range.location + range.length
        }
    }
    return AttributedString(combined)
}
