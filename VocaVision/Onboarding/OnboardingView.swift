import SwiftUI

struct OnboardingView: View {
    let onContinue: () -> Void

    private let features: [Feature] = Feature.all

    var body: some View {
        ZStack {
            BrandBackground()

            VStack(spacing: AppTheme.Spacing.lg) {
                header
                    .padding(.top, AppTheme.Spacing.xl)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: AppTheme.Spacing.md) {
                        ForEach(features) { feature in
                            FeatureCard(feature: feature)
                        }
                    }
                    .padding(.horizontal, AppTheme.Spacing.lg)
                }
                .scrollEdgeEffectStyle(.soft, for: .vertical)
            }
            .safeAreaBar(edge: .bottom) {
                continueButton
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.sm)
            }
        }
        .accessibilityAction(.escape) { onContinue() }
    }

    private var header: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(AppTheme.accent.gradient)
                .accessibilityHidden(true)

            Text(tr(ar: "هلا والله، حيّاك في VocaVision", en: "Welcome to VocaVision"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
                .accessibilityMultilingual(
                    .ar(isEnglishLocale ? "" : "هلا والله، حيّاك في "),
                    .en(isEnglishLocale ? "Welcome to VocaVision" : "VocaVision")
                )

            Text(tr(ar: "خلِّ Voca عيونك.", en: "Let Voca be your eyes."))
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityMultilingual(
                    .ar(isEnglishLocale ? "Let " : "خلِّ "),
                    .en("Voca"),
                    .ar(isEnglishLocale ? " be your eyes." : " عيونك.")
                )
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
    }

    private var continueButton: some View {
        let label = tr(ar: "متابعة", en: "Continue")
        let notice = tr(
            ar: "بمتابعتك فأنت توافق على سياسة الخصوصية: أثناء المكالمة تُرسل صور الكاميرا وصوتك إلى Google Gemini بمفتاحك الخاص لتصف لك Voca ما حولك. تقدر تقرأ السياسة كاملة من الإعدادات.",
            en: "By continuing you agree to the privacy policy: during a call, camera frames and your voice are sent to Google Gemini with your own key so Voca can describe your surroundings. You can read the full policy in Settings."
        )
        return VStack(spacing: AppTheme.Spacing.sm) {
            Text(notice)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityBilingual(notice, englishTokens: ["Google Gemini", "Voca"])
            Button(action: onContinue) {
            Text(label)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
        }
            .buttonStyle(.glassProminent)
            .accessibilityLabel(label)
            .accessibilityHint(tr(
                ar: "يؤكد موافقتك على سياسة الخصوصية ويفتح الشاشة الرئيسية",
                en: "Confirms the privacy policy and opens the home screen"
            ))
        }
    }
}

private struct Feature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
    let accessibilityString: AttributedString

    init(symbol: String, title: String, detail: String, englishWords: [String]) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.accessibilityString = makeBilingualString("\(title). \(detail)", englishTokens: englishWords)
    }

    static let all: [Feature] = [
        Feature(
            symbol: "video.fill",
            title: tr(ar: "مكالمة مباشرة بالكاميرا", en: "Live camera call"),
            detail: tr(
                ar: "ابدأ مكالمة مع Voca واسمعها توصف لك كل شي تشوفه الكاميرا، بصوت طبيعي وفي وقته.",
                en: "Start a call with Voca and hear her describe everything the camera sees, in a natural voice and in real time."
            ),
            englishWords: ["Voca"]
        ),
        Feature(
            symbol: "waveform",
            title: tr(ar: "حوار صوتي ذهاب وإياب", en: "Two-way voice dialog"),
            detail: tr(
                ar: "تكلّم مع Voca وراح ترد عليك على طول، وإذا قاطعتها بصوتك توقف وتسمعك.",
                en: "Talk to Voca and she answers right away. Interrupt at any time and she stops to listen."
            ),
            englishWords: ["Voca"]
        ),
        Feature(
            symbol: "wand.and.stars",
            title: tr(ar: "ذكية وتمشي على كلامك", en: "Smart and follows your rules"),
            detail: tr(
                ar: "اعطها قواعدك، مثلاً: «اقرأ لي بس الخيار اللي عليه التحديد»، وراح تمشي عليها بالحرف.",
                en: "Give her your rules — e.g. \"only read the highlighted option\" — and she'll follow them to the letter."
            ),
            englishWords: []
        ),
        Feature(
            symbol: "accessibility",
            title: tr(ar: "متوافق مع قارئ الشاشة", en: "VoiceOver-friendly"),
            detail: tr(
                ar: "كل عنصر في التطبيق مكتوب ومجهّز عشان يشتغل تمام مع VoiceOver.",
                en: "Every element in the app is written and tuned to work great with VoiceOver."
            ),
            englishWords: ["VoiceOver"]
        )
    ]
}

private struct FeatureCard: View {
    let feature: Feature

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: feature.symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.15), in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(feature.title)
                    .font(.headline)
                Text(feature.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(feature.accessibilityString))
    }
}

#Preview {
    OnboardingView(onContinue: {})
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
