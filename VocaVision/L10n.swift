import Foundation
import SwiftUI

/// Single source of truth for the UI language. Computed once at first
/// access and cached for the lifetime of the process — `Locale.current`
/// only changes when the user backgrounds the app and edits iOS
/// Settings, which kills the process anyway, so the cache is safe.
///
/// Rule: if the device's primary language is Arabic, the UI is Arabic.
/// Anything else (English, French, Spanish, Chinese, …) gets the
/// English UI, which is the broader fallback.
nonisolated enum AppLanguage {
    /// True iff the in-app UI should render in English.
    static let isEnglish: Bool = {
        // We honour the bundle's resolved localization first (which
        // iOS already picked using user preferences + dev region), then
        // fall back to a direct check on `Locale.current` — this
        // matters for previews and unit tests where the bundle hasn't
        // been fully resolved yet.
        if let bundleLang = Bundle.main.preferredLocalizations.first {
            return !bundleLang.hasPrefix("ar")
        }
        return Locale.current.language.languageCode?.identifier != "ar"
    }()
}

/// Picks the right string based on the resolved app language. Mirrors
/// the `displayLocalised` pattern used by `VoiceCatalog`,
/// `LanguageCatalog`, `PromptPreset`, and `UserProfile.Gender`.
///
/// Usage:
/// ```swift
/// Text(tr(ar: "ابدأ المكالمة", en: "Start Call"))
/// ```
nonisolated func tr(ar: String, en: String) -> String {
    AppLanguage.isEnglish ? en : ar
}

/// Same as `tr`, but returns a SwiftUI `Text` directly so call sites
/// don't need to wrap it themselves.
nonisolated func trText(ar: String, en: String) -> Text {
    Text(tr(ar: ar, en: en))
}

/// True iff the resolved app language is English. Cached after the
/// first call.
nonisolated var isEnglishLocale: Bool {
    AppLanguage.isEnglish
}
