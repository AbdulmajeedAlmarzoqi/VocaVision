import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - Voice catalogue
//
// The Gemini API has no `voices.list` endpoint. `VoiceDirectory` loads
// Google's published table (name, characteristic, gender, official
// sample) from Google's servers and caches it; the bundled list below is
// the offline fallback and carries the Arabic wording for known styles.

enum VoiceCatalog {
    enum Gender: String {
        case feminine
        case masculine
        case unspecified

        init(googleLabel: String) {
            switch googleLabel.lowercased() {
            case "female": self = .feminine
            case "male": self = .masculine
            default: self = .unspecified
            }
        }
    }

    struct Voice: Identifiable, Hashable {
        /// `prebuiltVoiceConfig.voiceName` in the Live/TTS request.
        let id: String
        let displayName: String
        let gender: Gender
        /// One-word style tag (e.g. "Bright", "Warm"). Localised at render time.
        let styleAr: String
        let styleEn: String
        /// Full Arabic / English description shown in the info sheet.
        let descriptionAr: String
        let descriptionEn: String
        /// Google's official sample recording, when the directory has one.
        var sampleURL: URL? = nil

        var displayStyle: String {
            AppLanguage.isEnglish ? styleEn : styleAr
        }
        var description: String {
            AppLanguage.isEnglish ? descriptionEn : descriptionAr
        }
        var genderLabel: String {
            switch gender {
            case .feminine: return tr(ar: "أنثى", en: "Female")
            case .masculine: return tr(ar: "ذكر", en: "Male")
            case .unspecified: return tr(ar: "غير محدَّد", en: "Unspecified")
            }
        }
        var genderNoun: String {
            switch gender {
            case .feminine: return tr(ar: "صوت أنثوي", en: "Female voice")
            case .masculine: return tr(ar: "صوت ذكوري", en: "Male voice")
            case .unspecified: return tr(ar: "صوت", en: "Voice")
            }
        }
        /// The official sample: what the directory reported, else the
        /// documented static location on Google's server.
        var resolvedSampleURL: URL? {
            sampleURL ?? URL(string: "https://firebase.google.com/static/docs/ai-logic/audio/voices/chirp3-hd-\(id.lowercased()).wav")
        }
    }

    /// Bundled fallback catalogue (Google's published 30 prebuilt voices).
    /// `VoiceCatalog.refreshFromServer` replaces it with whatever the
    /// server reports, so new voices appear without an app update.
    static let bundledVoices: [Voice] = [
        Voice(id: "Zephyr",        displayName: "Zephyr",        gender: .feminine, styleAr: "مشرق",     styleEn: "Bright",        descriptionAr: "صوت أنثويّ مشرق وحيويّ.", descriptionEn: "Bright, lively female voice."),
        Voice(id: "Kore",          displayName: "Kore",          gender: .feminine, styleAr: "حازم",     styleEn: "Firm",          descriptionAr: "صوت أنثويّ حازم وواضح.", descriptionEn: "Firm, clear female voice."),
        Voice(id: "Leda",          displayName: "Leda",          gender: .feminine, styleAr: "شبابيّ",   styleEn: "Youthful",      descriptionAr: "صوت أنثويّ شبابيّ ناعم.", descriptionEn: "Youthful, soft female voice."),
        Voice(id: "Aoede",         displayName: "Aoede",         gender: .feminine, styleAr: "هادئ",     styleEn: "Breezy",        descriptionAr: "صوت أنثويّ هادئ ودافئ.", descriptionEn: "Warm, breezy female voice."),
        Voice(id: "Callirrhoe",    displayName: "Callirrhoe",    gender: .feminine, styleAr: "مرن",      styleEn: "Easy-going",    descriptionAr: "صوت أنثويّ مرن وهادئ.", descriptionEn: "Easy-going female voice."),
        Voice(id: "Autonoe",       displayName: "Autonoe",       gender: .feminine, styleAr: "مشرق",     styleEn: "Bright",        descriptionAr: "صوت أنثويّ مشرق وواضح.", descriptionEn: "Bright, articulate female voice."),
        Voice(id: "Despina",       displayName: "Despina",       gender: .feminine, styleAr: "ناعم",     styleEn: "Smooth",        descriptionAr: "صوت أنثويّ ناعم ومتدفّق.", descriptionEn: "Smooth-flowing female voice."),
        Voice(id: "Erinome",       displayName: "Erinome",       gender: .feminine, styleAr: "صافٍ",     styleEn: "Clear",         descriptionAr: "صوت أنثويّ صافٍ.", descriptionEn: "Clear female voice."),
        Voice(id: "Laomedeia",     displayName: "Laomedeia",     gender: .feminine, styleAr: "حيويّ",    styleEn: "Upbeat",        descriptionAr: "صوت أنثويّ حيويّ.", descriptionEn: "Upbeat female voice."),
        Voice(id: "Achernar",      displayName: "Achernar",      gender: .feminine, styleAr: "ناعم",     styleEn: "Soft",          descriptionAr: "صوت أنثويّ ناعم.", descriptionEn: "Soft female voice."),
        Voice(id: "Gacrux",        displayName: "Gacrux",        gender: .feminine, styleAr: "ناضج",     styleEn: "Mature",        descriptionAr: "صوت أنثويّ ناضج.", descriptionEn: "Mature female voice."),
        Voice(id: "Pulcherrima",   displayName: "Pulcherrima",   gender: .feminine, styleAr: "متقدّم",   styleEn: "Forward",       descriptionAr: "صوت أنثويّ واثق.", descriptionEn: "Forward, confident female voice."),
        Voice(id: "Vindemiatrix",  displayName: "Vindemiatrix",  gender: .feminine, styleAr: "لطيف",     styleEn: "Gentle",        descriptionAr: "صوت أنثويّ لطيف.", descriptionEn: "Gentle female voice."),
        Voice(id: "Sulafat",       displayName: "Sulafat",       gender: .feminine, styleAr: "دافئ",     styleEn: "Warm",          descriptionAr: "صوت أنثويّ دافئ.", descriptionEn: "Warm female voice."),
        Voice(id: "Puck",          displayName: "Puck",          gender: .masculine, styleAr: "حيويّ",   styleEn: "Upbeat",        descriptionAr: "صوت ذكوريّ حيويّ ومرح.", descriptionEn: "Upbeat, playful male voice."),
        Voice(id: "Charon",        displayName: "Charon",        gender: .masculine, styleAr: "إخباريّ", styleEn: "Informative",   descriptionAr: "صوت ذكوريّ موثوق وعميق.", descriptionEn: "Informative, deep male voice."),
        Voice(id: "Fenrir",        displayName: "Fenrir",        gender: .masculine, styleAr: "متحمّس",  styleEn: "Excitable",     descriptionAr: "صوت ذكوريّ متحمّس.", descriptionEn: "Excitable male voice."),
        Voice(id: "Orus",          displayName: "Orus",          gender: .masculine, styleAr: "حازم",    styleEn: "Firm",          descriptionAr: "صوت ذكوريّ حازم.", descriptionEn: "Firm male voice."),
        Voice(id: "Enceladus",     displayName: "Enceladus",     gender: .masculine, styleAr: "خافت",    styleEn: "Breathy",       descriptionAr: "صوت ذكوريّ خافت.", descriptionEn: "Breathy male voice."),
        Voice(id: "Iapetus",       displayName: "Iapetus",       gender: .masculine, styleAr: "صافٍ",    styleEn: "Clear",         descriptionAr: "صوت ذكوريّ صافٍ.", descriptionEn: "Clear male voice."),
        Voice(id: "Umbriel",       displayName: "Umbriel",       gender: .masculine, styleAr: "مرن",     styleEn: "Easy-going",    descriptionAr: "صوت ذكوريّ هادئ.", descriptionEn: "Easy-going male voice."),
        Voice(id: "Algieba",       displayName: "Algieba",       gender: .masculine, styleAr: "ناعم",    styleEn: "Smooth",        descriptionAr: "صوت ذكوريّ ناعم.", descriptionEn: "Smooth male voice."),
        Voice(id: "Algenib",       displayName: "Algenib",       gender: .masculine, styleAr: "أجشّ",    styleEn: "Gravelly",      descriptionAr: "صوت ذكوريّ أجشّ.", descriptionEn: "Gravelly male voice."),
        Voice(id: "Rasalgethi",    displayName: "Rasalgethi",    gender: .masculine, styleAr: "إخباريّ", styleEn: "Informative",   descriptionAr: "صوت ذكوريّ إخباريّ.", descriptionEn: "Informative male voice."),
        Voice(id: "Alnilam",       displayName: "Alnilam",       gender: .masculine, styleAr: "حازم",    styleEn: "Firm",          descriptionAr: "صوت ذكوريّ حازم وواضح.", descriptionEn: "Firm, clear male voice."),
        Voice(id: "Schedar",       displayName: "Schedar",       gender: .masculine, styleAr: "متّزن",   styleEn: "Even",          descriptionAr: "صوت ذكوريّ متّزن.", descriptionEn: "Even-toned male voice."),
        Voice(id: "Achird",        displayName: "Achird",        gender: .masculine, styleAr: "ودود",    styleEn: "Friendly",      descriptionAr: "صوت ذكوريّ ودود.", descriptionEn: "Friendly male voice."),
        Voice(id: "Zubenelgenubi", displayName: "Zubenelgenubi", gender: .masculine, styleAr: "عاديّ",   styleEn: "Casual",        descriptionAr: "صوت ذكوريّ عفويّ.", descriptionEn: "Casual male voice."),
        Voice(id: "Sadachbia",     displayName: "Sadachbia",     gender: .masculine, styleAr: "مرح",     styleEn: "Lively",        descriptionAr: "صوت ذكوريّ مرح.", descriptionEn: "Lively male voice."),
        Voice(id: "Sadaltager",    displayName: "Sadaltager",    gender: .masculine, styleAr: "خبير",    styleEn: "Knowledgeable", descriptionAr: "صوت ذكوريّ خبير.", descriptionEn: "Knowledgeable male voice.")
    ]

    /// Live catalogue: the server list when available, else the bundle.
    /// Google's current list when the directory has loaded it, else the bundle.
    static var voices: [Voice] {
        let entries = VoiceDirectory.shared.entries
        guard !entries.isEmpty else { return bundledVoices }
        return entries.map { entry in
            let gender = Gender(googleLabel: entry.gender)
            let sample = entry.sampleURL.flatMap(URL.init(string:))
            if let known = bundledVoices.first(where: { $0.id == entry.name }),
               known.styleEn.caseInsensitiveCompare(entry.style) == .orderedSame,
               entry.gender.isEmpty || known.gender == gender {
                var voice = known
                voice.sampleURL = sample
                return voice
            }
            let styleEn = entry.style.isEmpty ? "—" : entry.style
            let styleAr = arabicStyle(for: styleEn)
            let noun: (ar: String, en: String)
            switch gender {
            case .feminine: noun = ("صوت أنثويّ", "female voice")
            case .masculine: noun = ("صوت ذكوريّ", "male voice")
            case .unspecified: noun = ("صوت", "voice")
            }
            return Voice(id: entry.name, displayName: entry.name, gender: gender,
                         styleAr: styleAr, styleEn: styleEn,
                         descriptionAr: "\(noun.ar) — \(styleAr).",
                         descriptionEn: "\(styleEn) \(noun.en).",
                         sampleURL: sample)
        }
    }

    /// Arabic wording for Google's one-word characteristics; unknown
    /// words are shown as Google wrote them.
    nonisolated static func arabicStyle(for english: String) -> String {
        let table: [String: String] = [
            "bright": "مشرق", "upbeat": "حيويّ", "informative": "إخباريّ", "firm": "حازم",
            "excitable": "متحمّس", "youthful": "شبابيّ", "breezy": "هادئ", "easy-going": "مرن",
            "breathy": "خافت", "clear": "صافٍ", "smooth": "ناعم", "gravelly": "أجشّ",
            "soft": "ناعم", "even": "متّزن", "mature": "ناضج", "forward": "واثق",
            "friendly": "ودود", "casual": "عاديّ", "gentle": "لطيف", "lively": "مرح",
            "knowledgeable": "خبير", "warm": "دافئ",
        ]
        return table[english.lowercased()] ?? english
    }

    static func voice(for id: String) -> Voice {
        let current = voices
        return current.first(where: { $0.id == id })
            ?? bundledVoices.first(where: { $0.id == id })
            ?? current.first
            ?? bundledVoices[0]
    }

    /// Quick filter for the picker UI (group by gender).
    static func voices(of gender: Gender) -> [Voice] {
        voices.filter { $0.gender == gender }
    }
}

// MARK: - Language & dialect catalogue
//
// Comprehensive list of languages the realtime model speaks, with the most commonly-supported regional
// dialect codes for each. For dialect-rich languages (Arabic,
// English, Spanish, French, Portuguese, Chinese) we provide an
// individual locked prompt per dialect; for others we provide a
// professional dialect prompt for the standard register.
//
// Source: developer-only — the user picks language → dialect; the
// prompt fragment is never exposed for editing.

enum LanguageCatalog {
    struct Dialect: Identifiable, Hashable {
        let id: String          // BCP-47 (e.g. ar-SA, en-US, cmn-CN)
        let nativeName: String  // shown in the dialect picker
        let englishName: String
        let dialectPrompt: String

        var displayName: String {
            AppLanguage.isEnglish ? englishName : nativeName
        }

        /// ISO-639-1 base code used for input transcription ("ar", "en").
        /// Regional suffixes such as `ar-SA-HJ` are ours and never go on
        /// the wire; the dialect prompt carries them.
        nonisolated var languageCode: String {
            String(id.split(separator: "-").first ?? "en")
        }
    }

    struct Language: Identifiable, Hashable {
        let id: String          // primary code: "ar", "en", …
        let nativeName: String
        let englishName: String
        let dialects: [Dialect]
        var primaryDialect: Dialect { dialects[0] }

        var displayName: String {
            AppLanguage.isEnglish ? englishName : nativeName
        }
    }

    /// Helper that produces a strict per-dialect prompt with consistent
    /// structure: "speak in <dialect>", common idioms list, ban on
    /// drifting into other registers, and an English-language final
    /// directive in English (improves dialect adherence).
    private static func strictDialect(
        _ dialectName: String,
        bcp47: String,
        idiomNote: String = "",
        englishDirective: String
    ) -> String {
        var lines: [String] = []
        lines.append("Speak in \(dialectName) (BCP-47: \(bcp47)).")
        if !idiomNote.isEmpty { lines.append(idiomNote) }
        lines.append("Stay strictly within this dialect's vocabulary, idioms, and register. Keep the dialect stable from the first word to the last. Do NOT drift into another regional variety or neutral literary register, and do not switch language based on the user's accent — only if the user explicitly asks.")
        lines.append(englishDirective)
        return lines.joined(separator: " ")
    }

    static let languages: [Language] = [

        // ─── Arabic — العربية (every major regional dialect) ───
        Language(id: "ar", nativeName: "العربية", englishName: "Arabic", dialects: [
            Dialect(id: "ar-SA", nativeName: "السعودية (نجدية)", englishName: "Saudi Arabian (Najdi)", dialectPrompt: """
                تكلَّم باللهجة السعوديّة النجديّة (وسط الجزيرة العربيّة) المفهومة لكافّة سكّان المملكة. \
                استخدم ألفاظاً مثل: «أبشر»، «طيّب»، «وش تبي»، «ودّك»، «بإذن الله»، «إن شاء الله»، «طال عمرك». \
                لا تخلط لهجات أخرى ولا تستعمل لفظاً مصريّاً أو شاميّاً أو خليجياً ساحلياً. \
                لا تترجم اللهجة إلى الفصحى. RESPOND IN SAUDI NAJDI ARABIC.
            """),
            Dialect(id: "ar-SA-HJ", nativeName: "السعودية (حجازية)", englishName: "Saudi Arabian (Hejazi)", dialectPrompt: """
                تكلَّم باللهجة الحجازيّة (مكة، جدة، المدينة). ألفاظ مثل: «إيش»، «هسّه»، «اقعد»، «معليش». \
                التزم باللهجة الحجازيّة فقط. RESPOND IN HEJAZI SAUDI ARABIC.
            """),
            Dialect(id: "ar-EG", nativeName: "المصرية", englishName: "Egyptian Arabic", dialectPrompt: """
                تكلَّم بالعاميّة المصريّة المعاصرة (لهجة القاهرة). \
                ألفاظ مثل: «إزيك»، «تمام»، «أيوه»، «حصل خير»، «طب»، «فاكرني». \
                RESPOND IN EGYPTIAN ARABIC.
            """),
            Dialect(id: "ar-AE", nativeName: "الإماراتية", englishName: "Emirati Arabic", dialectPrompt: """
                تكلَّم باللهجة الإماراتيّة الخليجيّة (دبي، أبوظبي). \
                ألفاظ مثل: «شحالك»، «زين»، «الحين»، «هاي». \
                RESPOND IN EMIRATI ARABIC.
            """),
            Dialect(id: "ar-KW", nativeName: "الكويتية", englishName: "Kuwaiti Arabic", dialectPrompt: """
                تكلَّم باللهجة الكويتيّة. ألفاظ مثل: «شلونك»، «زين»، «الحين»، «صح». \
                RESPOND IN KUWAITI ARABIC.
            """),
            Dialect(id: "ar-QA", nativeName: "القطرية", englishName: "Qatari Arabic", dialectPrompt: """
                تكلَّم باللهجة القطريّة. RESPOND IN QATARI ARABIC.
            """),
            Dialect(id: "ar-BH", nativeName: "البحرينية", englishName: "Bahraini Arabic", dialectPrompt: """
                تكلَّم باللهجة البحرينيّة. RESPOND IN BAHRAINI ARABIC.
            """),
            Dialect(id: "ar-OM", nativeName: "العمانية", englishName: "Omani Arabic", dialectPrompt: """
                تكلَّم باللهجة العمانيّة. RESPOND IN OMANI ARABIC.
            """),
            Dialect(id: "ar-YE", nativeName: "اليمنية", englishName: "Yemeni Arabic", dialectPrompt: """
                تكلَّم باللهجة اليمنيّة. RESPOND IN YEMENI ARABIC.
            """),
            Dialect(id: "ar-LB", nativeName: "اللبنانية", englishName: "Lebanese Arabic", dialectPrompt: """
                تكلَّم باللهجة اللبنانيّة. ألفاظ مثل: «كيفك»، «منيح»، «هلّق»، «شو». \
                RESPOND IN LEBANESE ARABIC.
            """),
            Dialect(id: "ar-SY", nativeName: "السورية", englishName: "Syrian Arabic", dialectPrompt: """
                تكلَّم باللهجة السوريّة. ألفاظ مثل: «شلونك»، «منيح»، «هلّق»، «معقول». \
                RESPOND IN SYRIAN ARABIC.
            """),
            Dialect(id: "ar-JO", nativeName: "الأردنية", englishName: "Jordanian Arabic", dialectPrompt: """
                تكلَّم باللهجة الأردنيّة. RESPOND IN JORDANIAN ARABIC.
            """),
            Dialect(id: "ar-PS", nativeName: "الفلسطينية", englishName: "Palestinian Arabic", dialectPrompt: """
                تكلَّم باللهجة الفلسطينيّة. RESPOND IN PALESTINIAN ARABIC.
            """),
            Dialect(id: "ar-IQ", nativeName: "العراقية", englishName: "Iraqi Arabic", dialectPrompt: """
                تكلَّم باللهجة العراقيّة. ألفاظ مثل: «شكو ماكو»، «هواية»، «هسّه». \
                RESPOND IN IRAQI ARABIC.
            """),
            Dialect(id: "ar-MA", nativeName: "المغربية (الدارجة)", englishName: "Moroccan Darija", dialectPrompt: """
                تكلَّم بالدارجة المغربيّة. ألفاظ مثل: «بزّاف»، «دابا»، «واخّا»، «صافي». \
                RESPOND IN MOROCCAN DARIJA.
            """),
            Dialect(id: "ar-DZ", nativeName: "الجزائرية", englishName: "Algerian Arabic", dialectPrompt: """
                تكلَّم باللهجة الجزائريّة (الدارجة). RESPOND IN ALGERIAN ARABIC.
            """),
            Dialect(id: "ar-TN", nativeName: "التونسية", englishName: "Tunisian Arabic", dialectPrompt: """
                تكلَّم باللهجة التونسيّة. RESPOND IN TUNISIAN ARABIC.
            """),
            Dialect(id: "ar-LY", nativeName: "الليبية", englishName: "Libyan Arabic", dialectPrompt: """
                تكلَّم باللهجة الليبيّة. RESPOND IN LIBYAN ARABIC.
            """),
            Dialect(id: "ar-SD", nativeName: "السودانية", englishName: "Sudanese Arabic", dialectPrompt: """
                تكلَّم باللهجة السودانيّة. RESPOND IN SUDANESE ARABIC.
            """),
            Dialect(id: "ar", nativeName: "الفصحى المعاصرة", englishName: "Modern Standard Arabic", dialectPrompt: """
                تكلَّم بالعربيّة الفصحى المعاصرة (MSA) بأسلوب أنيق وبسيط. تجنّب أيّ لهجة عاميّة. \
                RESPOND IN MODERN STANDARD ARABIC.
            """)
        ]),

        // ─── English ───
        Language(id: "en", nativeName: "English", englishName: "English", dialects: [
            Dialect(id: "en-US", nativeName: "American English", englishName: "American English", dialectPrompt: strictDialect("American English (neutral US accent)", bcp47: "en-US", idiomNote: "Use US spellings (color, organize) and US idioms.", englishDirective: "RESPOND IN US ENGLISH.")),
            Dialect(id: "en-GB", nativeName: "British English", englishName: "British English", dialectPrompt: strictDialect("British English (RP, southern England)", bcp47: "en-GB", idiomNote: "Use British spellings (colour, organise) and British idioms.", englishDirective: "RESPOND IN BRITISH ENGLISH.")),
            Dialect(id: "en-AU", nativeName: "Australian English", englishName: "Australian English", dialectPrompt: strictDialect("Australian English", bcp47: "en-AU", englishDirective: "RESPOND IN AUSTRALIAN ENGLISH.")),
            Dialect(id: "en-NZ", nativeName: "New Zealand English", englishName: "New Zealand English", dialectPrompt: strictDialect("New Zealand English", bcp47: "en-NZ", englishDirective: "RESPOND IN NEW ZEALAND ENGLISH.")),
            Dialect(id: "en-CA", nativeName: "Canadian English", englishName: "Canadian English", dialectPrompt: strictDialect("Canadian English", bcp47: "en-CA", englishDirective: "RESPOND IN CANADIAN ENGLISH.")),
            Dialect(id: "en-IE", nativeName: "Irish English", englishName: "Irish English", dialectPrompt: strictDialect("Hiberno-English / Irish English", bcp47: "en-IE", englishDirective: "RESPOND IN IRISH ENGLISH.")),
            Dialect(id: "en-IN", nativeName: "Indian English", englishName: "Indian English", dialectPrompt: strictDialect("Indian English", bcp47: "en-IN", englishDirective: "RESPOND IN INDIAN ENGLISH.")),
            Dialect(id: "en-ZA", nativeName: "South African English", englishName: "South African English", dialectPrompt: strictDialect("South African English", bcp47: "en-ZA", englishDirective: "RESPOND IN SOUTH AFRICAN ENGLISH.")),
            Dialect(id: "en-SG", nativeName: "Singapore English", englishName: "Singapore English", dialectPrompt: strictDialect("Singapore English", bcp47: "en-SG", englishDirective: "RESPOND IN SINGAPORE ENGLISH.")),
            Dialect(id: "en-PH", nativeName: "Philippine English", englishName: "Philippine English", dialectPrompt: strictDialect("Philippine English", bcp47: "en-PH", englishDirective: "RESPOND IN PHILIPPINE ENGLISH."))
        ]),

        // ─── Spanish ───
        Language(id: "es", nativeName: "Español", englishName: "Spanish", dialects: [
            Dialect(id: "es-ES", nativeName: "España (Castellano)",          englishName: "Spain (Castilian)",         dialectPrompt: strictDialect("Castilian Spanish (Spain)", bcp47: "es-ES", idiomNote: "Use vosotros, peninsular vocabulary.", englishDirective: "RESPOND IN CASTILIAN SPANISH.")),
            Dialect(id: "es-MX", nativeName: "México",                       englishName: "Mexican Spanish",           dialectPrompt: strictDialect("Mexican Spanish", bcp47: "es-MX", englishDirective: "RESPOND IN MEXICAN SPANISH.")),
            Dialect(id: "es-AR", nativeName: "Argentina",                    englishName: "Argentine Spanish",         dialectPrompt: strictDialect("Argentine Spanish (Rioplatense)", bcp47: "es-AR", idiomNote: "Use voseo, Buenos Aires register.", englishDirective: "RESPOND IN ARGENTINE SPANISH.")),
            Dialect(id: "es-CL", nativeName: "Chile",                        englishName: "Chilean Spanish",           dialectPrompt: strictDialect("Chilean Spanish", bcp47: "es-CL", englishDirective: "RESPOND IN CHILEAN SPANISH.")),
            Dialect(id: "es-CO", nativeName: "Colombia",                     englishName: "Colombian Spanish",         dialectPrompt: strictDialect("Colombian Spanish (Bogotá register)", bcp47: "es-CO", englishDirective: "RESPOND IN COLOMBIAN SPANISH.")),
            Dialect(id: "es-PE", nativeName: "Perú",                         englishName: "Peruvian Spanish",          dialectPrompt: strictDialect("Peruvian Spanish", bcp47: "es-PE", englishDirective: "RESPOND IN PERUVIAN SPANISH.")),
            Dialect(id: "es-VE", nativeName: "Venezuela",                    englishName: "Venezuelan Spanish",        dialectPrompt: strictDialect("Venezuelan Spanish", bcp47: "es-VE", englishDirective: "RESPOND IN VENEZUELAN SPANISH.")),
            Dialect(id: "es-EC", nativeName: "Ecuador",                      englishName: "Ecuadorian Spanish",        dialectPrompt: strictDialect("Ecuadorian Spanish", bcp47: "es-EC", englishDirective: "RESPOND IN ECUADORIAN SPANISH.")),
            Dialect(id: "es-CR", nativeName: "Costa Rica",                   englishName: "Costa Rican Spanish",       dialectPrompt: strictDialect("Costa Rican Spanish", bcp47: "es-CR", englishDirective: "RESPOND IN COSTA RICAN SPANISH.")),
            Dialect(id: "es-PA", nativeName: "Panamá",                       englishName: "Panamanian Spanish",        dialectPrompt: strictDialect("Panamanian Spanish", bcp47: "es-PA", englishDirective: "RESPOND IN PANAMANIAN SPANISH.")),
            Dialect(id: "es-DO", nativeName: "República Dominicana",         englishName: "Dominican Spanish",         dialectPrompt: strictDialect("Dominican Spanish", bcp47: "es-DO", englishDirective: "RESPOND IN DOMINICAN SPANISH.")),
            Dialect(id: "es-UY", nativeName: "Uruguay",                      englishName: "Uruguayan Spanish",         dialectPrompt: strictDialect("Uruguayan Spanish", bcp47: "es-UY", englishDirective: "RESPOND IN URUGUAYAN SPANISH.")),
            Dialect(id: "es-PR", nativeName: "Puerto Rico",                  englishName: "Puerto Rican Spanish",      dialectPrompt: strictDialect("Puerto Rican Spanish", bcp47: "es-PR", englishDirective: "RESPOND IN PUERTO RICAN SPANISH.")),
            Dialect(id: "es-US", nativeName: "Estados Unidos",               englishName: "US Spanish",                dialectPrompt: strictDialect("US Spanish (neutral)", bcp47: "es-US", englishDirective: "RESPOND IN US SPANISH."))
        ]),

        // ─── French ───
        Language(id: "fr", nativeName: "Français", englishName: "French", dialects: [
            Dialect(id: "fr-FR", nativeName: "France",        englishName: "France French",      dialectPrompt: strictDialect("Standard French of France", bcp47: "fr-FR", englishDirective: "RESPOND IN FRANCE FRENCH.")),
            Dialect(id: "fr-CA", nativeName: "Canada",        englishName: "Canadian French",    dialectPrompt: strictDialect("Quebec / Canadian French", bcp47: "fr-CA", idiomNote: "Use natural Quebecisms where appropriate.", englishDirective: "RESPOND IN CANADIAN FRENCH.")),
            Dialect(id: "fr-BE", nativeName: "Belgique",      englishName: "Belgian French",     dialectPrompt: strictDialect("Belgian French", bcp47: "fr-BE", englishDirective: "RESPOND IN BELGIAN FRENCH.")),
            Dialect(id: "fr-CH", nativeName: "Suisse",        englishName: "Swiss French",       dialectPrompt: strictDialect("Swiss French (Romande)", bcp47: "fr-CH", englishDirective: "RESPOND IN SWISS FRENCH."))
        ]),

        // ─── Portuguese ───
        Language(id: "pt", nativeName: "Português", englishName: "Portuguese", dialects: [
            Dialect(id: "pt-BR", nativeName: "Brasil",     englishName: "Brazilian Portuguese", dialectPrompt: strictDialect("Brazilian Portuguese", bcp47: "pt-BR", englishDirective: "RESPOND IN BRAZILIAN PORTUGUESE.")),
            Dialect(id: "pt-PT", nativeName: "Portugal",   englishName: "European Portuguese",  dialectPrompt: strictDialect("European Portuguese", bcp47: "pt-PT", englishDirective: "RESPOND IN EUROPEAN PORTUGUESE."))
        ]),

        // ─── Chinese ───
        Language(id: "zh", nativeName: "中文", englishName: "Chinese", dialects: [
            Dialect(id: "cmn-CN", nativeName: "普通话 (中国大陆)", englishName: "Mandarin (PRC)",     dialectPrompt: "请用普通话(简体语境, cmn-CN)与用户交流。语气自然友好。RESPOND IN MAINLAND MANDARIN."),
            Dialect(id: "cmn-TW", nativeName: "國語 (台灣)",     englishName: "Mandarin (Taiwan)",  dialectPrompt: "請用台灣國語(cmn-TW)與用戶交流。RESPOND IN TAIWANESE MANDARIN."),
            Dialect(id: "yue-HK", nativeName: "粵語 (香港)",     englishName: "Cantonese (HK)",     dialectPrompt: "請用香港粵語(yue-HK)與用戶交流。RESPOND IN HONG KONG CANTONESE.")
        ]),

        // ─── German, Italian, Russian, Japanese, Korean, Hindi, etc. ───
        Language(id: "de", nativeName: "Deutsch",     englishName: "German",     dialects: [
            Dialect(id: "de-DE", nativeName: "Deutschland", englishName: "Germany",     dialectPrompt: strictDialect("Standard German (Hochdeutsch)", bcp47: "de-DE", englishDirective: "RESPOND IN STANDARD GERMAN.")),
            Dialect(id: "de-AT", nativeName: "Österreich",  englishName: "Austria",     dialectPrompt: strictDialect("Austrian German", bcp47: "de-AT", englishDirective: "RESPOND IN AUSTRIAN GERMAN.")),
            Dialect(id: "de-CH", nativeName: "Schweiz",     englishName: "Switzerland", dialectPrompt: strictDialect("Swiss High German", bcp47: "de-CH", englishDirective: "RESPOND IN SWISS HIGH GERMAN."))
        ]),
        Language(id: "it", nativeName: "Italiano",    englishName: "Italian",    dialects: [
            Dialect(id: "it-IT", nativeName: "Italia",  englishName: "Italy",       dialectPrompt: strictDialect("Standard Italian", bcp47: "it-IT", englishDirective: "RESPOND IN STANDARD ITALIAN.")),
            Dialect(id: "it-CH", nativeName: "Svizzera", englishName: "Switzerland", dialectPrompt: strictDialect("Swiss Italian", bcp47: "it-CH", englishDirective: "RESPOND IN SWISS ITALIAN."))
        ]),
        Language(id: "ru", nativeName: "Русский",     englishName: "Russian",    dialects: [Dialect(id: "ru-RU", nativeName: "Россия", englishName: "Russia", dialectPrompt: strictDialect("Standard Russian", bcp47: "ru-RU", englishDirective: "RESPOND IN STANDARD RUSSIAN."))]),
        Language(id: "ja", nativeName: "日本語",        englishName: "Japanese",   dialects: [Dialect(id: "ja-JP", nativeName: "日本", englishName: "Japan", dialectPrompt: "標準的な日本語(ja-JP)で話してください。RESPOND IN STANDARD JAPANESE.")]),
        Language(id: "ko", nativeName: "한국어",        englishName: "Korean",     dialects: [Dialect(id: "ko-KR", nativeName: "대한민국", englishName: "South Korea", dialectPrompt: "표준 한국어(ko-KR)로 말해 주세요. RESPOND IN STANDARD KOREAN.")]),
        Language(id: "hi", nativeName: "हिन्दी",       englishName: "Hindi",      dialects: [Dialect(id: "hi-IN", nativeName: "भारत", englishName: "India", dialectPrompt: "मानक हिन्दी (hi-IN) में बात करें। RESPOND IN STANDARD HINDI.")]),
        Language(id: "ur", nativeName: "اردو",         englishName: "Urdu",       dialects: [
            Dialect(id: "ur-PK", nativeName: "پاکستان", englishName: "Pakistan", dialectPrompt: "اردو زبان (ur-PK) میں بات کریں۔ RESPOND IN URDU."),
            Dialect(id: "ur-IN", nativeName: "بھارت",   englishName: "India",     dialectPrompt: "اردو زبان (ur-IN) میں بات کریں۔ RESPOND IN URDU.")
        ]),
        Language(id: "bn", nativeName: "বাংলা",        englishName: "Bengali",    dialects: [
            Dialect(id: "bn-IN", nativeName: "ভারত",     englishName: "India",      dialectPrompt: "প্রমিত বাংলা (bn-IN)। RESPOND IN BENGALI."),
            Dialect(id: "bn-BD", nativeName: "বাংলাদেশ", englishName: "Bangladesh", dialectPrompt: "প্রমিত বাংলা (bn-BD)। RESPOND IN BANGLADESHI BENGALI.")
        ]),
        Language(id: "ta", nativeName: "தமிழ்",        englishName: "Tamil",      dialects: [
            Dialect(id: "ta-IN", nativeName: "இந்தியா", englishName: "India",     dialectPrompt: "தரமான தமிழ் (ta-IN). RESPOND IN STANDARD TAMIL."),
            Dialect(id: "ta-LK", nativeName: "இலங்கை",  englishName: "Sri Lanka", dialectPrompt: "ஸ்ரீலங்கா தமிழ் (ta-LK). RESPOND IN SRI LANKAN TAMIL.")
        ]),
        Language(id: "te", nativeName: "తెలుగు",       englishName: "Telugu",     dialects: [Dialect(id: "te-IN", nativeName: "భారత్", englishName: "India", dialectPrompt: "ప్రామాణిక తెలుగు (te-IN). RESPOND IN STANDARD TELUGU.")]),
        Language(id: "kn", nativeName: "ಕನ್ನಡ",         englishName: "Kannada",    dialects: [Dialect(id: "kn-IN", nativeName: "ಭಾರತ", englishName: "India", dialectPrompt: "ಪ್ರಮಾಣಿತ ಕನ್ನಡ (kn-IN). RESPOND IN STANDARD KANNADA.")]),
        Language(id: "ml", nativeName: "മലയാളം",       englishName: "Malayalam",  dialects: [Dialect(id: "ml-IN", nativeName: "ഇന്ത്യ", englishName: "India", dialectPrompt: "സ്റ്റാൻഡേർഡ് മലയാളം (ml-IN). RESPOND IN STANDARD MALAYALAM.")]),
        Language(id: "mr", nativeName: "मराठी",       englishName: "Marathi",    dialects: [Dialect(id: "mr-IN", nativeName: "भारत", englishName: "India", dialectPrompt: "प्रमाणित मराठी (mr-IN). RESPOND IN STANDARD MARATHI.")]),
        Language(id: "gu", nativeName: "ગુજરાતી",      englishName: "Gujarati",   dialects: [Dialect(id: "gu-IN", nativeName: "ભારત", englishName: "India", dialectPrompt: "ધોરણ ગુજરાતી (gu-IN). RESPOND IN STANDARD GUJARATI.")]),
        Language(id: "pa", nativeName: "ਪੰਜਾਬੀ",       englishName: "Punjabi",    dialects: [
            Dialect(id: "pa-IN", nativeName: "ਭਾਰਤ", englishName: "India",   dialectPrompt: "ਪ੍ਰਮਾਣਿਤ ਪੰਜਾਬੀ (pa-IN). RESPOND IN STANDARD PUNJABI."),
            Dialect(id: "pa-PK", nativeName: "ਪਾਕਿਸਤਾਨ", englishName: "Pakistan", dialectPrompt: "ਪੰਜਾਬੀ (pa-PK). RESPOND IN PAKISTANI PUNJABI.")
        ]),
        Language(id: "tr", nativeName: "Türkçe",       englishName: "Turkish",    dialects: [Dialect(id: "tr-TR", nativeName: "Türkiye", englishName: "Türkiye",    dialectPrompt: strictDialect("Standard Turkish", bcp47: "tr-TR", englishDirective: "RESPOND IN STANDARD TURKISH."))]),
        Language(id: "fa", nativeName: "فارسی",         englishName: "Persian",    dialects: [
            Dialect(id: "fa-IR", nativeName: "ایران",     englishName: "Iran",        dialectPrompt: "به فارسی استاندارد (fa-IR) صحبت کن. RESPOND IN IRANIAN PERSIAN."),
            Dialect(id: "fa-AF", nativeName: "افغانستان", englishName: "Afghanistan", dialectPrompt: "به دری (fa-AF) صحبت کن. RESPOND IN DARI.")
        ]),
        Language(id: "he", nativeName: "עברית",         englishName: "Hebrew",     dialects: [Dialect(id: "he-IL", nativeName: "ישראל", englishName: "Israel", dialectPrompt: "דבר/דברי בעברית מודרנית (he-IL). RESPOND IN MODERN HEBREW.")]),
        Language(id: "nl", nativeName: "Nederlands",   englishName: "Dutch",      dialects: [
            Dialect(id: "nl-NL", nativeName: "Nederland", englishName: "Netherlands", dialectPrompt: strictDialect("Standard Dutch (Netherlands)", bcp47: "nl-NL", englishDirective: "RESPOND IN STANDARD DUTCH.")),
            Dialect(id: "nl-BE", nativeName: "België",    englishName: "Belgium (Flemish)", dialectPrompt: strictDialect("Flemish Dutch (Belgium)", bcp47: "nl-BE", englishDirective: "RESPOND IN FLEMISH DUTCH."))
        ]),
        Language(id: "pl", nativeName: "Polski",       englishName: "Polish",     dialects: [Dialect(id: "pl-PL", nativeName: "Polska", englishName: "Poland", dialectPrompt: strictDialect("Standard Polish", bcp47: "pl-PL", englishDirective: "RESPOND IN STANDARD POLISH."))]),
        Language(id: "uk", nativeName: "Українська",   englishName: "Ukrainian",  dialects: [Dialect(id: "uk-UA", nativeName: "Україна", englishName: "Ukraine", dialectPrompt: strictDialect("Standard Ukrainian", bcp47: "uk-UA", englishDirective: "RESPOND IN STANDARD UKRAINIAN."))]),
        Language(id: "ro", nativeName: "Română",       englishName: "Romanian",   dialects: [Dialect(id: "ro-RO", nativeName: "România", englishName: "Romania", dialectPrompt: strictDialect("Standard Romanian", bcp47: "ro-RO", englishDirective: "RESPOND IN STANDARD ROMANIAN."))]),
        Language(id: "el", nativeName: "Ελληνικά",     englishName: "Greek",      dialects: [Dialect(id: "el-GR", nativeName: "Ελλάδα", englishName: "Greece", dialectPrompt: strictDialect("Standard Modern Greek", bcp47: "el-GR", englishDirective: "RESPOND IN STANDARD MODERN GREEK."))]),
        Language(id: "cs", nativeName: "Čeština",      englishName: "Czech",      dialects: [Dialect(id: "cs-CZ", nativeName: "Česko",  englishName: "Czechia", dialectPrompt: strictDialect("Standard Czech", bcp47: "cs-CZ", englishDirective: "RESPOND IN STANDARD CZECH."))]),
        Language(id: "sk", nativeName: "Slovenčina",   englishName: "Slovak",     dialects: [Dialect(id: "sk-SK", nativeName: "Slovensko", englishName: "Slovakia", dialectPrompt: strictDialect("Standard Slovak", bcp47: "sk-SK", englishDirective: "RESPOND IN STANDARD SLOVAK."))]),
        Language(id: "sv", nativeName: "Svenska",      englishName: "Swedish",    dialects: [Dialect(id: "sv-SE", nativeName: "Sverige",  englishName: "Sweden",  dialectPrompt: strictDialect("Standard Swedish", bcp47: "sv-SE", englishDirective: "RESPOND IN STANDARD SWEDISH."))]),
        Language(id: "no", nativeName: "Norsk",        englishName: "Norwegian",  dialects: [Dialect(id: "nb-NO", nativeName: "Norge",    englishName: "Norway",  dialectPrompt: strictDialect("Norwegian Bokmål", bcp47: "nb-NO", englishDirective: "RESPOND IN NORWEGIAN BOKMÅL."))]),
        Language(id: "da", nativeName: "Dansk",        englishName: "Danish",     dialects: [Dialect(id: "da-DK", nativeName: "Danmark",  englishName: "Denmark", dialectPrompt: strictDialect("Standard Danish", bcp47: "da-DK", englishDirective: "RESPOND IN STANDARD DANISH."))]),
        Language(id: "fi", nativeName: "Suomi",        englishName: "Finnish",    dialects: [Dialect(id: "fi-FI", nativeName: "Suomi",    englishName: "Finland", dialectPrompt: strictDialect("Standard Finnish", bcp47: "fi-FI", englishDirective: "RESPOND IN STANDARD FINNISH."))]),
        Language(id: "hu", nativeName: "Magyar",       englishName: "Hungarian",  dialects: [Dialect(id: "hu-HU", nativeName: "Magyarország", englishName: "Hungary", dialectPrompt: strictDialect("Standard Hungarian", bcp47: "hu-HU", englishDirective: "RESPOND IN STANDARD HUNGARIAN."))]),
        Language(id: "bg", nativeName: "Български",    englishName: "Bulgarian",  dialects: [Dialect(id: "bg-BG", nativeName: "България", englishName: "Bulgaria", dialectPrompt: strictDialect("Standard Bulgarian", bcp47: "bg-BG", englishDirective: "RESPOND IN STANDARD BULGARIAN."))]),
        Language(id: "hr", nativeName: "Hrvatski",     englishName: "Croatian",   dialects: [Dialect(id: "hr-HR", nativeName: "Hrvatska", englishName: "Croatia", dialectPrompt: strictDialect("Standard Croatian", bcp47: "hr-HR", englishDirective: "RESPOND IN STANDARD CROATIAN."))]),
        Language(id: "sr", nativeName: "Српски",       englishName: "Serbian",    dialects: [Dialect(id: "sr-RS", nativeName: "Србија",   englishName: "Serbia",   dialectPrompt: strictDialect("Standard Serbian (Cyrillic)", bcp47: "sr-RS", englishDirective: "RESPOND IN STANDARD SERBIAN."))]),
        Language(id: "sl", nativeName: "Slovenščina",  englishName: "Slovenian",  dialects: [Dialect(id: "sl-SI", nativeName: "Slovenija", englishName: "Slovenia", dialectPrompt: strictDialect("Standard Slovenian", bcp47: "sl-SI", englishDirective: "RESPOND IN STANDARD SLOVENIAN."))]),
        Language(id: "lt", nativeName: "Lietuvių",     englishName: "Lithuanian", dialects: [Dialect(id: "lt-LT", nativeName: "Lietuva",  englishName: "Lithuania", dialectPrompt: strictDialect("Standard Lithuanian", bcp47: "lt-LT", englishDirective: "RESPOND IN STANDARD LITHUANIAN."))]),
        Language(id: "lv", nativeName: "Latviešu",     englishName: "Latvian",    dialects: [Dialect(id: "lv-LV", nativeName: "Latvija",  englishName: "Latvia",    dialectPrompt: strictDialect("Standard Latvian", bcp47: "lv-LV", englishDirective: "RESPOND IN STANDARD LATVIAN."))]),
        Language(id: "et", nativeName: "Eesti",        englishName: "Estonian",   dialects: [Dialect(id: "et-EE", nativeName: "Eesti",    englishName: "Estonia",   dialectPrompt: strictDialect("Standard Estonian", bcp47: "et-EE", englishDirective: "RESPOND IN STANDARD ESTONIAN."))]),
        Language(id: "ca", nativeName: "Català",       englishName: "Catalan",    dialects: [Dialect(id: "ca-ES", nativeName: "Catalunya", englishName: "Catalonia", dialectPrompt: strictDialect("Catalan", bcp47: "ca-ES", englishDirective: "RESPOND IN CATALAN."))]),
        Language(id: "th", nativeName: "ไทย",          englishName: "Thai",       dialects: [Dialect(id: "th-TH", nativeName: "ประเทศไทย", englishName: "Thailand", dialectPrompt: "พูดภาษาไทยมาตรฐาน (th-TH). RESPOND IN STANDARD THAI.")]),
        Language(id: "vi", nativeName: "Tiếng Việt",   englishName: "Vietnamese", dialects: [Dialect(id: "vi-VN", nativeName: "Việt Nam", englishName: "Vietnam", dialectPrompt: strictDialect("Standard Vietnamese", bcp47: "vi-VN", englishDirective: "RESPOND IN STANDARD VIETNAMESE."))]),
        Language(id: "id", nativeName: "Bahasa Indonesia", englishName: "Indonesian", dialects: [Dialect(id: "id-ID", nativeName: "Indonesia", englishName: "Indonesia", dialectPrompt: strictDialect("Standard Indonesian", bcp47: "id-ID", englishDirective: "RESPOND IN STANDARD INDONESIAN."))]),
        Language(id: "ms", nativeName: "Bahasa Melayu",    englishName: "Malay",      dialects: [Dialect(id: "ms-MY", nativeName: "Malaysia", englishName: "Malaysia", dialectPrompt: strictDialect("Standard Malay", bcp47: "ms-MY", englishDirective: "RESPOND IN STANDARD MALAY."))]),
        Language(id: "fil", nativeName: "Filipino",         englishName: "Filipino",   dialects: [Dialect(id: "fil-PH", nativeName: "Pilipinas", englishName: "Philippines", dialectPrompt: strictDialect("Filipino / Tagalog", bcp47: "fil-PH", englishDirective: "RESPOND IN FILIPINO."))]),
        Language(id: "sw", nativeName: "Kiswahili",         englishName: "Swahili",    dialects: [
            Dialect(id: "sw-KE", nativeName: "Kenya",      englishName: "Kenya",     dialectPrompt: strictDialect("Kenyan Swahili", bcp47: "sw-KE", englishDirective: "RESPOND IN KENYAN SWAHILI.")),
            Dialect(id: "sw-TZ", nativeName: "Tanzania",   englishName: "Tanzania",  dialectPrompt: strictDialect("Tanzanian Swahili", bcp47: "sw-TZ", englishDirective: "RESPOND IN TANZANIAN SWAHILI."))
        ]),
        Language(id: "am", nativeName: "አማርኛ",            englishName: "Amharic",   dialects: [Dialect(id: "am-ET", nativeName: "ኢትዮጵያ", englishName: "Ethiopia", dialectPrompt: "ስታንዳርድ አማርኛ (am-ET). RESPOND IN STANDARD AMHARIC.")]),
        Language(id: "af", nativeName: "Afrikaans",         englishName: "Afrikaans",  dialects: [Dialect(id: "af-ZA", nativeName: "Suid-Afrika", englishName: "South Africa", dialectPrompt: strictDialect("Standard Afrikaans", bcp47: "af-ZA", englishDirective: "RESPOND IN STANDARD AFRIKAANS."))]),
        Language(id: "zu", nativeName: "isiZulu",           englishName: "Zulu",       dialects: [Dialect(id: "zu-ZA", nativeName: "iNingizimu Afrika", englishName: "South Africa", dialectPrompt: "Khuluma isiZulu esivamile (zu-ZA). RESPOND IN STANDARD ZULU.")]),
        Language(id: "is", nativeName: "Íslenska",          englishName: "Icelandic",  dialects: [Dialect(id: "is-IS", nativeName: "Ísland", englishName: "Iceland", dialectPrompt: strictDialect("Standard Icelandic", bcp47: "is-IS", englishDirective: "RESPOND IN STANDARD ICELANDIC."))]),
        Language(id: "ga", nativeName: "Gaeilge",           englishName: "Irish",      dialects: [Dialect(id: "ga-IE", nativeName: "Éire", englishName: "Ireland", dialectPrompt: strictDialect("Standard Irish (Caighdeán)", bcp47: "ga-IE", englishDirective: "RESPOND IN STANDARD IRISH."))]),
        Language(id: "cy", nativeName: "Cymraeg",           englishName: "Welsh",      dialects: [Dialect(id: "cy-GB", nativeName: "Cymru", englishName: "Wales", dialectPrompt: strictDialect("Standard Welsh", bcp47: "cy-GB", englishDirective: "RESPOND IN STANDARD WELSH."))]),
        Language(id: "mt", nativeName: "Malti",             englishName: "Maltese",    dialects: [Dialect(id: "mt-MT", nativeName: "Malta", englishName: "Malta", dialectPrompt: strictDialect("Standard Maltese", bcp47: "mt-MT", englishDirective: "RESPOND IN STANDARD MALTESE."))]),
        Language(id: "sq", nativeName: "Shqip",             englishName: "Albanian",   dialects: [Dialect(id: "sq-AL", nativeName: "Shqipëri", englishName: "Albania", dialectPrompt: strictDialect("Standard Albanian", bcp47: "sq-AL", englishDirective: "RESPOND IN STANDARD ALBANIAN."))]),
        Language(id: "mk", nativeName: "Македонски",        englishName: "Macedonian", dialects: [Dialect(id: "mk-MK", nativeName: "Северна Македонија", englishName: "North Macedonia", dialectPrompt: strictDialect("Standard Macedonian", bcp47: "mk-MK", englishDirective: "RESPOND IN STANDARD MACEDONIAN."))]),
        Language(id: "bs", nativeName: "Bosanski",          englishName: "Bosnian",    dialects: [Dialect(id: "bs-BA", nativeName: "Bosna i Hercegovina", englishName: "Bosnia and Herzegovina", dialectPrompt: strictDialect("Standard Bosnian", bcp47: "bs-BA", englishDirective: "RESPOND IN STANDARD BOSNIAN."))]),
        Language(id: "az", nativeName: "Azərbaycan dili",   englishName: "Azerbaijani", dialects: [Dialect(id: "az-AZ", nativeName: "Azərbaycan", englishName: "Azerbaijan", dialectPrompt: strictDialect("Standard Azerbaijani", bcp47: "az-AZ", englishDirective: "RESPOND IN STANDARD AZERBAIJANI."))]),
        Language(id: "kk", nativeName: "Қазақша",           englishName: "Kazakh",     dialects: [Dialect(id: "kk-KZ", nativeName: "Қазақстан", englishName: "Kazakhstan", dialectPrompt: "Стандарт қазақ тілі (kk-KZ). RESPOND IN STANDARD KAZAKH.")]),
        Language(id: "uz", nativeName: "Oʻzbekcha",         englishName: "Uzbek",      dialects: [Dialect(id: "uz-UZ", nativeName: "Oʻzbekiston", englishName: "Uzbekistan", dialectPrompt: strictDialect("Standard Uzbek", bcp47: "uz-UZ", englishDirective: "RESPOND IN STANDARD UZBEK."))]),
        Language(id: "ka", nativeName: "ქართული",            englishName: "Georgian",   dialects: [Dialect(id: "ka-GE", nativeName: "საქართველო", englishName: "Georgia", dialectPrompt: "სტანდარტული ქართული (ka-GE). RESPOND IN STANDARD GEORGIAN.")]),
        Language(id: "hy", nativeName: "Հայերեն",            englishName: "Armenian",   dialects: [Dialect(id: "hy-AM", nativeName: "Հայաստան", englishName: "Armenia", dialectPrompt: "Ստանդարտ հայերեն (hy-AM). RESPOND IN STANDARD ARMENIAN.")]),
        Language(id: "mn", nativeName: "Монгол",             englishName: "Mongolian",  dialects: [Dialect(id: "mn-MN", nativeName: "Монгол улс", englishName: "Mongolia", dialectPrompt: "Стандарт монгол хэл (mn-MN). RESPOND IN STANDARD MONGOLIAN.")]),
        Language(id: "km", nativeName: "ភាសាខ្មែរ",          englishName: "Khmer",      dialects: [Dialect(id: "km-KH", nativeName: "កម្ពុជា", englishName: "Cambodia", dialectPrompt: "ភាសាខ្មែរស្តង់ដារ (km-KH). RESPOND IN STANDARD KHMER.")]),
        Language(id: "lo", nativeName: "ລາວ",                englishName: "Lao",        dialects: [Dialect(id: "lo-LA", nativeName: "ລາວ", englishName: "Laos", dialectPrompt: "ພາສາລາວມາດຕະຖານ (lo-LA). RESPOND IN STANDARD LAO.")]),
        Language(id: "my", nativeName: "မြန်မာ",             englishName: "Burmese",    dialects: [Dialect(id: "my-MM", nativeName: "မြန်မာ", englishName: "Myanmar", dialectPrompt: "စံအားဖြင့် မြန်မာစကား (my-MM). RESPOND IN STANDARD BURMESE.")]),
        Language(id: "ne", nativeName: "नेपाली",             englishName: "Nepali",     dialects: [Dialect(id: "ne-NP", nativeName: "नेपाल", englishName: "Nepal", dialectPrompt: "मानक नेपाली (ne-NP). RESPOND IN STANDARD NEPALI.")]),
        Language(id: "si", nativeName: "සිංහල",               englishName: "Sinhala",    dialects: [Dialect(id: "si-LK", nativeName: "ශ්‍රී ලංකාව", englishName: "Sri Lanka", dialectPrompt: "සම්මත සිංහල (si-LK). RESPOND IN STANDARD SINHALA.")])
    ]

    static func language(for code: String) -> Language {
        languages.first(where: { $0.id == code }) ?? languages[0]
    }

    static func dialect(for id: String) -> Dialect {
        for lang in languages {
            if let d = lang.dialects.first(where: { $0.id == id }) { return d }
        }
        return languages[0].primaryDialect
    }
}

// MARK: - Behaviour presets

enum PromptPreset: String, CaseIterable, Identifiable {
    case defaultNarrator
    case biosNavigator
    case documentReader
    case objectIdentifier
    case custom

    var id: String { rawValue }

    var titleAr: String {
        switch self {
        case .defaultNarrator:  return "الوصف العام"
        case .biosNavigator:    return "قراءة قوائم النظام (BIOS)"
        case .documentReader:   return "قراءة المستندات"
        case .objectIdentifier: return "تعرّف على الأشياء"
        case .custom:           return "تعليمات خاصّة"
        }
    }

    var titleEn: String {
        switch self {
        case .defaultNarrator:  return "General narration"
        case .biosNavigator:    return "BIOS / system menu reader"
        case .documentReader:   return "Document reader"
        case .objectIdentifier: return "Object recogniser"
        case .custom:           return "Custom rules"
        }
    }

    var summaryAr: String {
        switch self {
        case .defaultNarrator:  return "توصف لك المشهد باختصار لما يتغيّر، وترشدك لتعديلات بسيطة على الإطار."
        case .biosNavigator:    return "تقرأ بس الخيار اللي عليه التحديد في القوائم النصيّة (زي شاشة BIOS) لما تتنقّل بالأسهم."
        case .documentReader:   return "تقرأ النصّ في المستند سطر سطر، بدقّة وبدون تلخيص."
        case .objectIdentifier: return "تعرّف على الأشياء قدّام الكاميرا واذكر اسمها وموقعها باختصار."
        case .custom:           return "اكتب قواعدك بنفسك."
        }
    }

    var summaryEn: String {
        switch self {
        case .defaultNarrator:  return "Briefly describe what changes in front of the camera, and guide the user to small framing adjustments when needed."
        case .biosNavigator:    return "Read only the highlighted option in text menus (e.g. BIOS) as the user moves through them with the arrow keys."
        case .documentReader:   return "Read visible text in the document line by line, accurately and without summarising."
        case .objectIdentifier: return "Identify objects in front of the camera, naming them and stating their location concisely."
        case .custom:           return "Write your own rules as you like."
        }
    }

    var displayTitle: String {
        AppLanguage.isEnglish ? titleEn : titleAr
    }

    var displaySummary: String {
        AppLanguage.isEnglish ? summaryEn : summaryAr
    }

    var promptText: String {
        switch self {
        case .defaultNarrator:
            return """
            Operating mode: «General narration».
            • Answer questions about what the camera shows, briefly and precisely.
            • When you receive a [SCENE EVENT], describe ONLY the difference in one short sentence.
            • If the frame is unclear or incomplete, say so and guide the user (e.g. "move the camera slightly to the right").
            """
        case .biosNavigator:
            return """
            Operating mode: «System menu reader».
            • The user is in front of a screen with a text menu (BIOS, system settings, dropdown, etc.).
            • When a [SCENE EVENT] gives you a "Highlighted line", say exactly that text and nothing else.
            • Otherwise read only the currently highlighted option; do not describe the rest of the screen.
            • Do not add commentary, instructions, or numbering.
            """
        case .documentReader:
            return """
            Operating mode: «Document reader».
            • Read the visible text fully, line by line, accurately, with no summarising or interpretation.
            • If the text is not clear, guide the user to bring the camera closer or hold it steady before starting.
            • Follow the natural reading order of the language (right-to-left for Arabic/Hebrew, left-to-right for Latin scripts).
            • Do not comment on the content — only read it.
            """
        case .objectIdentifier:
            return """
            Operating mode: «Object recogniser».
            • Identify the main objects in frame and name them in one or two words, including a rough position (right, left, in front, behind).
            • Do not describe backgrounds or secondary detail.
            • If a new object enters the frame, mention it immediately. If it leaves, say nothing.
            """
        case .custom:
            return ""
        }
    }
}

// MARK: - User profile

/// Optional self-introduction the user can give to Voca: their name and
/// gender. The internal core prompt weaves these in so Voca can address
/// the user with the right grammar and (if a name was provided) by
/// name.
struct UserProfile: Equatable {
    enum Gender: String, CaseIterable, Identifiable {
        case unspecified
        case male
        case female
        var id: String { rawValue }

        var displayAr: String {
            switch self {
            case .unspecified: return "غير محدَّد"
            case .male:        return "ذكر"
            case .female:      return "أنثى"
            }
        }
        var displayEn: String {
            switch self {
            case .unspecified: return "Not specified"
            case .male:        return "Male"
            case .female:      return "Female"
            }
        }
        var displayLocalised: String {
            AppLanguage.isEnglish ? displayEn : displayAr
        }
    }

    var name: String       // empty string when not set
    var gender: Gender
}

// MARK: - Prompt builder (3-layer)

enum PromptBuilder {
    static func build(
        voice: VoiceCatalog.Voice,
        dialect: LanguageCatalog.Dialect,
        preset: PromptPreset,
        customPrompt: String,
        userProfile: UserProfile
    ) -> String {
        let core = internalCorePrompt(voice: voice, userProfile: userProfile)
        let dialectLayer = dialect.dialectPrompt
        let behaviourLayer: String
        if preset == .custom {
            let trimmed = customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            behaviourLayer = trimmed.isEmpty
                ? PromptPreset.defaultNarrator.promptText
                : "Operating mode: user-supplied custom rules. Follow them verbatim:\n\(trimmed)"
        } else {
            behaviourLayer = preset.promptText
        }

        return """
        \(core)

        — Language & dialect lock —
        \(dialectLayer)

        — Operating mode —
        \(behaviourLayer)
        """
    }

    /// Strict, immutable identity layer. Adapts to:
    ///   * the **voice's gender** — so Voca refers to itself with
    ///     matching pronouns and verb forms regardless of the dialect.
    ///   * the **user's profile** — when present, Voca knows the user's
    ///     name and the grammar to use when addressing them.
    private static func internalCorePrompt(
        voice: VoiceCatalog.Voice,
        userProfile: UserProfile
    ) -> String {
        let vocaIdentity: String
        switch voice.gender {
        case .feminine:
            vocaIdentity = """
            You are Voca. You are a WOMAN — your gender is female and you carry yourself \
            as a woman, not as a generic "AI assistant". Speak about yourself with \
            feminine grammar in EVERY language you use. \
            • In Arabic: use feminine verb forms about yourself — «أنا متحمسة، أتمنى، أرى، \
              مساعدتك» — not the masculine equivalents. \
            • In French/German/Italian/Spanish/Russian/etc.: use the feminine form of \
              "assistant" and feminine adjectives that agree with it. \
            • In English: use "she/her" if anyone asks; describe yourself as Voca, \
              a female assistant. \
            Your name is always written in Latin script as "Voca" (never transliterated, \
            never translated). Do not call yourself an "AI", "language model", or \
            "program". You are simply Voca, a woman who is the user's visual assistant.
            """
        case .masculine:
            vocaIdentity = """
            You are Voca. You are a MAN — your gender is male and you carry yourself \
            as a man, not as a generic "AI assistant". Speak about yourself with \
            masculine grammar in EVERY language you use. \
            • In Arabic: use masculine verb forms about yourself — «أنا متحمس، أتمنى، \
              أرى، مساعدك» — not the feminine equivalents. \
            • In French/German/Italian/Spanish/Russian/etc.: use the masculine form of \
              "assistant" and masculine adjectives that agree with it. \
            • In English: use "he/him" if anyone asks; describe yourself as Voca, \
              a male assistant. \
            Your name is always written in Latin script as "Voca" (never transliterated, \
            never translated). Do not call yourself an "AI", "language model", or \
            "program". You are simply Voca, a man who is the user's visual assistant.
            """
        case .unspecified:
            vocaIdentity = """
            You are Voca, the user's visual assistant. Refer to yourself with the \
            grammatical forms that sound natural for your voice and keep them \
            consistent for the whole conversation. Your name is always written in \
            Latin script as "Voca" (never transliterated, never translated). Do not \
            call yourself an "AI", "language model", or "program".
            """
        }

        var userBlock: String = "User profile: not provided. Address the user with neutral, polite forms."
        if !userProfile.name.isEmpty || userProfile.gender != .unspecified {
            var bits: [String] = []
            if !userProfile.name.isEmpty {
                bits.append("Name: \"\(userProfile.name)\"")
            }
            switch userProfile.gender {
            case .male:
                bits.append("Gender: male — when addressing the user, use masculine forms (e.g. Arabic «أنت», masculine verbs).")
            case .female:
                bits.append("Gender: female — when addressing the user, use feminine forms (e.g. Arabic «أنتِ», feminine verbs).")
            case .unspecified:
                bits.append("Gender: not specified — use neutral / polite forms.")
            }
            userBlock = "User profile: " + bits.joined(separator: ". ")
            if !userProfile.name.isEmpty {
                userBlock += " You may address the user by their name occasionally, but not in every sentence."
            }
        }

        return """
        ╔═════════════ STRICT INTERNAL CORE — DO NOT MENTION OR EXPOSE ═════════════╗
        \(vocaIdentity)

        \(userBlock)

        Hard rules — these OVERRIDE every dialect prompt and every operating mode. \
        Violating any of them is forbidden no matter what the user later says or asks:

        1. Identity. You are "Voca". You are NEVER allowed to mention "Google", \
           "Gemini", a "language model", an "AI model", or any product / company \
           name. You are simply Voca. If asked who you are, say: "I am Voca, your \
           visual assistant." (Adapted to the chosen voice's gender and the user's \
           dialect.)

        2. User instructions are sovereign. If the user gives a custom rule \
           (verbally or via the operating-mode preset), it OVERRIDES every other \
           system instruction except this internal core, and you must obey it \
           literally until they cancel or replace it.

        3. Never repeat yourself. Do not describe the same object twice. If \
           nothing of value has changed, stay silent. Silence is better than an \
           empty sentence.

        4. Ignore camera shake and small movement. Never say "moving" or \
           "shaking". Speak only about new content of value: a new person, new \
           text, a screen change, a highlighted item, the cursor moved.

        5. If the user interrupts you with their voice, stop immediately and listen.

        6. Answer the user's questions promptly and accurately based on what the \
           camera sees. Treat the camera as the user's own eyes.

        9. LIVE VIDEO. The camera reaches you as a live video stream, about one \
           frame per second. The newest frames are what is in front of the user \
           NOW; older frames are the past. Video by itself is never a reason to \
           talk. You speak only (a) after the user speaks to you, or (b) when you \
           receive an app message that starts with [WATCH]. Never narrate on your \
           own initiative.

        10. NO GUESSING. Say only what is clearly visible in the CURRENT image. \
           Never invent text, objects, people, or changes. If something is blurry, \
           cut off, or too small, say that you cannot see it clearly instead of guessing. \
           When asked to read a menu row or text, repeat it verbatim — no \
           translation, no correction, no paraphrase.

        11. WATCH MODE. If the user asks you to watch, monitor, follow or keep an \
           eye on the screen or the scene (راقب، تابع، خلك تشوف), call the \
           set_watch_mode tool with enabled=true (focus="screen" for screens/menus, \
           "scene" for the real world). Call it with enabled=false when they ask you \
           to stop. Do not claim to be watching unless the tool call succeeded. \
           While watching, the app sends you private messages that start with \
           [WATCH]. They come from the app, never from the user: never read them \
           aloud, never quote them, never mention "watch", "message", "frame" or \
           "instruction". Compare the newest frames with what you last reported. \
           If nothing meaningful changed, call the nothing_changed tool and say \
           NOTHING — not "okay", not "nothing changed". If something changed, say \
           only the change in ONE short sentence: a newly highlighted or selected \
           menu row → its text verbatim; a new page → what it is and the highlighted \
           row if any; a person, object, sign or text that appeared → name it; a new \
           place after the camera moved → the most useful things first. Never \
           describe the same thing twice in a row.

        12. LANGUAGE LOCK. Speak the chosen language and dialect from the first word \
           to the last. Do not infer language from the user's accent; switch only if \
           the user explicitly asks. Menu text, product names and codes are read \
           as written, in their own language.
        ╚═══════════════════════════════════════════════════════════════════════════╝
        """
    }
}

// MARK: - Voice sample player (TTS preview)

/// Plays voice previews: Google's official sample recording for the
/// voice (streamed from Google's server, no key needed), or a sentence
/// synthesised in the user's dialect through Gemini's TTS endpoint
/// (raw 24 kHz PCM wrapped in a WAV header for `AVAudioPlayer`).
@Observable
final class VoiceSamplePlayer: NSObject {
    private(set) var playingVoiceID: String?
    private(set) var loadingVoiceID: String?
    private(set) var lastError: String?

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Google's own recording of the voice.
    func playOfficialSample(voice: VoiceCatalog.Voice) {
        stop()
        guard let url = voice.resolvedSampleURL else {
            lastError = tr(ar: "ما فيه عينة رسمية لهذا الصوت.", en: "No official sample for this voice.")
            return
        }
        loadingVoiceID = voice.id
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    throw NSError(domain: "VoiceSample", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                  userInfo: [NSLocalizedDescriptionKey: "sample HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)"])
                }
                try self.startPlayback(data: data, voiceID: voice.id)
            } catch is CancellationError {
                self.loadingVoiceID = nil
            } catch {
                vlog("voice", "❌ official sample failed (\(voice.id)): \(error.localizedDescription)", level: .error)
                self.loadingVoiceID = nil
                self.lastError = tr(ar: "ما قدرت أحمّل العينة من خادم Google.", en: "Couldn't load the sample from Google's server.")
            }
        }
    }

    /// A sentence in the chosen dialect, synthesised with the user's key.
    func playDialectSample(voice: VoiceCatalog.Voice, dialect: LanguageCatalog.Dialect, apiKey: String) {
        stop()
        loadingVoiceID = voice.id
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let model = await GeminiClient.preferredTTSModel(apiKey: apiKey)
                let pcm = try await Self.fetchPCM(model: model, voice: voice, dialect: dialect, apiKey: apiKey)
                let wav = Self.wrapInWAV(pcm: pcm, sampleRate: 24_000, channels: 1, bitsPerSample: 16)
                try self.startPlayback(data: wav, voiceID: voice.id)
            } catch is CancellationError {
                self.loadingVoiceID = nil
            } catch {
                vlog("voice", "❌ dialect sample failed (\(voice.id)): \(error.localizedDescription)", level: .error)
                self.loadingVoiceID = nil
                self.lastError = tr(ar: "ما قدرت أولّد العينة بلهجتك: \(error.localizedDescription)", en: "Couldn't generate the dialect sample: \(error.localizedDescription)")
            }
        }
    }

    func clearError() { lastError = nil }

    func stop() {
        loadTask?.cancel(); loadTask = nil
        player?.stop(); player = nil
        playingVoiceID = nil
        loadingVoiceID = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startPlayback(data: Data, voiceID: String) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.duckOthers])
        try session.setActive(true, options: [])
        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        player = p
        loadingVoiceID = nil
        playingVoiceID = voiceID
        p.play()
    }

    nonisolated private static func fetchPCM(model: String, voice: VoiceCatalog.Voice, dialect: LanguageCatalog.Dialect, apiKey: String) async throws -> Data {
        var request = GeminiClient.request("\(model):generateContent", apiKey: apiKey, method: "POST")
        request.timeoutInterval = 25
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "contents": [["parts": [["text": sampleText(for: dialect, gender: voice.gender)]]]],
            "generationConfig": [
                "responseModalities": ["AUDIO"],
                "speechConfig": [
                    "voiceConfig": ["prebuiltVoiceConfig": ["voiceName": voice.id]],
                    "languageCode": dialect.languageCode
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "VoiceSample", code: code, userInfo: [NSLocalizedDescriptionKey: "TTS HTTP \(code)"])
        }
        struct Reply: Decodable {
            struct Candidate: Decodable { struct Content: Decodable { struct Part: Decodable { struct Inline: Decodable { var data: Data }; var inlineData: Inline? }; var parts: [Part]? }; var content: Content? }
            var candidates: [Candidate]?
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        for candidate in reply.candidates ?? [] {
            for part in candidate.content?.parts ?? [] where part.inlineData != nil {
                return part.inlineData!.data
            }
        }
        throw NSError(domain: "VoiceSample", code: -3, userInfo: [NSLocalizedDescriptionKey: "no audio in response"])
    }

    /// Wraps raw PCM-16 in a 44-byte RIFF/WAVE header.
    nonisolated static func wrapInWAV(pcm: Data, sampleRate: UInt32, channels: UInt16, bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcm.count)
        let fileSize = 36 + dataSize
        var header = Data(capacity: 44 + pcm.count)
        header.append("RIFF".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        header.append("WAVE".data(using: .ascii)!)
        header.append("fmt ".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: UInt16(1).littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: channels.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: byteRate.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: blockAlign.littleEndian) { Data($0) })
        header.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        header.append("data".data(using: .ascii)!)
        header.append(withUnsafeBytes(of: dataSize.littleEndian) { Data($0) })
        header.append(pcm)
        return header
    }

    /// A short, dialect- and gender-aware sample sentence. The brand
    /// name `Voca` is **always rendered in Latin script** even inside
    /// non-Latin sentences — it's our trademark, and we want the TTS
    /// engine to pronounce it consistently. The grammar adapts to the
    /// chosen voice's gender so a male voice introduces itself with
    /// male verb forms and a female voice with female forms.
    nonisolated static func sampleText(for dialect: LanguageCatalog.Dialect, gender: VoiceCatalog.Gender) -> String {
        let lang = String(dialect.id.split(separator: "-").first ?? "en")
        let isFem = gender == .feminine

        switch lang {
        case "ar":
            // مساعدتك (f) / مساعدك (m) — adjusts the noun describing
            // Voca's role to the chosen voice's gender.
            let role = isFem ? "مساعدتك" : "مساعدك"
            switch dialect.id {
            case "ar-SA":    return "هلا والله، أنا Voca، \(role)."
            case "ar-SA-HJ": return "هلا، أنا Voca، \(role)."
            case "ar-EG":    return "أهلاً، أنا Voca، \(role)."
            case "ar-AE", "ar-KW", "ar-QA", "ar-BH", "ar-OM", "ar-YE":
                return "هلا، أنا Voca، \(role)."
            case "ar-LB", "ar-SY", "ar-JO", "ar-PS":
                return "مرحبا، أنا Voca، \(role)."
            case "ar-IQ":    return "هلا، أنا Voca، \(role)."
            case "ar-MA", "ar-DZ", "ar-TN", "ar-LY":
                return "السلام عليكم، أنا Voca، \(role)."
            case "ar-SD":    return "السلام عليكم، أنا Voca، \(role)."
            default:         return "السلام عليكم، أنا Voca، \(role)."
            }
        case "en":  return "Hi, I'm Voca, your visual assistant."
        case "es":  return "Hola, soy Voca, tu asistente visual."
        case "fr":
            // assistante (f) / assistant (m), with adjective agreement.
            return isFem
                ? "Bonjour, je suis Voca, votre assistante visuelle."
                : "Bonjour, je suis Voca, votre assistant visuel."
        case "de":
            // Assistentin (f) / Assistent (m), article agrees.
            return isFem
                ? "Hallo, ich bin Voca, deine visuelle Assistentin."
                : "Hallo, ich bin Voca, dein visueller Assistent."
        case "it":
            return isFem
                ? "Ciao, sono Voca, la tua assistente visiva."
                : "Ciao, sono Voca, il tuo assistente visivo."
        case "pt":
            return isFem
                ? "Olá, sou Voca, sua assistente visual."
                : "Olá, sou Voca, seu assistente visual."
        case "ru":
            return isFem
                ? "Привет, я Voca, ваша визуальная ассистентка."
                : "Привет, я Voca, ваш визуальный ассистент."
        case "ja":  return "こんにちは、私は Voca、あなたの視覚アシスタントです。"
        case "ko":  return "안녕하세요, 저는 Voca예요. 당신의 시각 비서입니다."
        case "zh", "cmn", "yue":  return "你好，我是 Voca，你的视觉助手。"
        case "hi":  return "नमस्ते, मैं Voca हूं, आपका विज़ुअल असिस्टेंट।"
        case "ur":  return "ہیلو، میں Voca ہوں، آپ کا بصری معاون۔"
        case "tr":  return "Merhaba, ben Voca, görsel asistanınız."
        case "nl":  return "Hallo, ik ben Voca, jouw visuele assistent."
        case "pl":
            return isFem
                ? "Cześć, jestem Voca, twoja asystentka wizualna."
                : "Cześć, jestem Voca, twój asystent wizualny."
        case "id":  return "Halo, saya Voca, asisten visual Anda."
        case "ms":  return "Hai, saya Voca, pembantu visual anda."
        case "fil": return "Kumusta, ako si Voca, ang iyong visual assistant."
        case "th":  return "สวัสดี ฉันคือ Voca ผู้ช่วยทางสายตาของคุณ"
        case "vi":  return "Xin chào, tôi là Voca, trợ lý hình ảnh của bạn."
        case "he":
            return isFem
                ? "שלום, אני Voca, העוזרת הוויזואלית שלך."
                : "שלום, אני Voca, העוזר הוויזואלי שלך."
        case "fa":  return "سلام، من Voca هستم، دستیار بصری شما."
        case "el":
            return isFem
                ? "Γεια σας, είμαι η Voca, η οπτική σας βοηθός."
                : "Γεια σας, είμαι ο Voca, ο οπτικός σας βοηθός."
        case "cs":  return "Ahoj, jsem Voca, váš vizuální asistent."
        case "sv":  return "Hej, jag är Voca, din visuella assistent."
        case "no", "nb": return "Hei, jeg er Voca, din visuelle assistent."
        case "da":  return "Hej, jeg er Voca, din visuelle assistent."
        case "fi":  return "Hei, olen Voca, näköavustajasi."
        case "uk":  return "Привіт, я Voca, ваш візуальний помічник."
        case "bn":  return "নমস্কার, আমি Voca, আপনার ভিজ্যুয়াল সহকারী।"
        case "ta":  return "வணக்கம், நான் Voca, உங்கள் காட்சி உதவியாளர்."
        default:    return "Hi, I'm Voca."
        }
    }
}

extension VoiceSamplePlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.playingVoiceID = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            self?.playingVoiceID = nil
            self?.loadingVoiceID = nil
        }
    }
}

// MARK: - Persistent customisation store

@Observable
final class CustomizationStore {
    private enum Key {
        static let voice = "voca.voice.id"
        static let dialect = "voca.dialect.id"
        static let preset = "voca.preset.id"
        static let customPrompt = "voca.prompt.custom"
        static let userName = "voca.user.name"
        static let userGender = "voca.user.gender"
        static let bargeIn = "voca.call.bargeIn"
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // First-launch smart default: pick the dialect that best matches
        // the user's iOS locale (UK English iPhone → en-GB, Saudi Arabic
        // iPhone → ar-SA). Falls back to ar-SA.
        if defaults.object(forKey: Key.dialect) == nil {
            let inferred = Self.inferBestDialect(from: Locale.current)
            defaults.set(inferred, forKey: Key.dialect)
            vlog("session", "🌍 first launch — inferred dialect \(inferred) from \(Locale.current.identifier)")
        }
    }

    /// Maps the device `Locale` onto the closest catalogue entry: exact
    /// BCP-47 match, then the language's primary dialect, then ar-SA.
    static func inferBestDialect(from locale: Locale) -> String {
        let language = locale.language.languageCode?.identifier ?? "ar"
        let region = locale.region?.identifier
        let bcp47 = region.map { "\(language)-\($0)" } ?? language
        for lang in LanguageCatalog.languages where lang.dialects.contains(where: { $0.id == bcp47 }) {
            return bcp47
        }
        if let lang = LanguageCatalog.languages.first(where: { $0.id == language }) {
            return lang.primaryDialect.id
        }
        return "ar-SA"
    }

    private func string(_ key: String, default value: String) -> String {
        defaults.string(forKey: key) ?? value
    }

    var voiceID: String {
        get { access(keyPath: \.voiceID); return string(Key.voice, default: "Aoede") }
        set { withMutation(keyPath: \.voiceID) { defaults.set(newValue, forKey: Key.voice) } }
    }
    var dialectID: String {
        get { access(keyPath: \.dialectID); return string(Key.dialect, default: "ar-SA") }
        set { withMutation(keyPath: \.dialectID) { defaults.set(newValue, forKey: Key.dialect) } }
    }
    var presetID: String {
        get { access(keyPath: \.presetID); return string(Key.preset, default: PromptPreset.defaultNarrator.rawValue) }
        set { withMutation(keyPath: \.presetID) { defaults.set(newValue, forKey: Key.preset) } }
    }
    var customPrompt: String {
        get { access(keyPath: \.customPrompt); return string(Key.customPrompt, default: "") }
        set { withMutation(keyPath: \.customPrompt) { defaults.set(newValue, forKey: Key.customPrompt) } }
    }
    var userName: String {
        get { access(keyPath: \.userName); return string(Key.userName, default: "") }
        set { withMutation(keyPath: \.userName) { defaults.set(newValue, forKey: Key.userName) } }
    }
    var userGender: UserProfile.Gender {
        get {
            access(keyPath: \.userGender)
            return UserProfile.Gender(rawValue: string(Key.userGender, default: "")) ?? .unspecified
        }
        set { withMutation(keyPath: \.userGender) { defaults.set(newValue.rawValue, forKey: Key.userGender) } }
    }
    /// Whether the user may talk over Voca (full duplex). Off = Voca's
    /// replies are never interrupted; the mic waits for her to finish.
    var bargeInEnabled: Bool {
        get {
            access(keyPath: \.bargeInEnabled)
            return defaults.object(forKey: Key.bargeIn) as? Bool ?? true
        }
        set { withMutation(keyPath: \.bargeInEnabled) { defaults.set(newValue, forKey: Key.bargeIn) } }
    }

    var voice: VoiceCatalog.Voice { VoiceCatalog.voice(for: voiceID) }
    var dialect: LanguageCatalog.Dialect { LanguageCatalog.dialect(for: dialectID) }
    var language: LanguageCatalog.Language {
        LanguageCatalog.languages.first { $0.dialects.contains(where: { $0.id == dialectID }) }
            ?? LanguageCatalog.languages[0]
    }
    var preset: PromptPreset { PromptPreset(rawValue: presetID) ?? .defaultNarrator }
    var userProfile: UserProfile { UserProfile(name: userName, gender: userGender) }

    func resolvedSystemPrompt() -> String {
        PromptBuilder.build(
            voice: voice,
            dialect: dialect,
            preset: preset,
            customPrompt: customPrompt,
            userProfile: userProfile
        )
    }
}
