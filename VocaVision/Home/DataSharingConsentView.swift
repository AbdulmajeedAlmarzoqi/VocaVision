import SwiftUI

/// Privacy policy: what leaves the device (camera frames, microphone
/// audio, typed text), to whom (Google Gemini via the user's own key),
/// and what VocaVision keeps (nothing). Agreement is given by
/// continuing past onboarding; this screen is readable any time from
/// Settings.
enum DataSharingConsent {
    nonisolated static let providerTermsURL = URL(string: "https://ai.google.dev/gemini-api/terms")!
    nonisolated static let providerPrivacyURL = URL(string: "https://policies.google.com/privacy")!
    nonisolated static let providerDataURL = URL(string: "https://ai.google.dev/gemini-api/terms#data-use-unpaid")!
}

struct PrivacyPolicyView: View {
    var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    Label {
                        Text(tr(ar: "وين تروح بياناتك", en: "Where your data goes"))
                            .font(.title2.bold())
                    } icon: {
                        Image(systemName: "hand.raised.circle.fill")
                            .foregroundStyle(AppTheme.accent)
                    }
                    .accessibilityAddTraits(.isHeader)

                    consentRow(
                        symbol: "camera.fill",
                        title: tr(ar: "صور من الكاميرا", en: "Camera frames"),
                        detail: tr(
                            ar: "أثناء المكالمة يُرسل التطبيق لقطة من الكاميرا كل ثانية تقريباً حتى تصف لك Voca ما حولك.",
                            en: "During a call the app sends a camera snapshot about once per second so Voca can describe your surroundings."
                        )
                    )
                    consentRow(
                        symbol: "mic.fill",
                        title: tr(ar: "صوتك من الميكروفون", en: "Your voice from the microphone"),
                        detail: tr(
                            ar: "كلامك يُرسل مباشرةً حتى تفهمك Voca وترد عليك. الكتم يوقف الإرسال فوراً.",
                            en: "What you say is streamed live so Voca can understand and answer you. Muting stops the stream immediately."
                        )
                    )
                    consentRow(
                        symbol: "text.bubble.fill",
                        title: tr(ar: "التعليمات المكتوبة", en: "Typed instructions"),
                        detail: tr(
                            ar: "أي تعليمات تكتبها أثناء المكالمة تُرسل كما هي.",
                            en: "Any instruction you type during a call is sent as-is."
                        )
                    )

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text(tr(ar: "إلى مَن تُرسل؟", en: "Who receives it?"))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                        Text(tr(
                            ar: "تُرسل هذه البيانات إلى خدمة Google Gemini API باستخدام مفتاح API الخاص بك، وتخضع لشروط Google وسياسة خصوصيتها. VocaVision نفسه لا يحتفظ بأي صور أو تسجيلات ولا يرسلها لأي جهة أخرى، ومفتاحك محفوظ في سلسلة مفاتيح جهازك فقط.",
                            en: "This data is sent to the Google Gemini API using your own API key and is governed by Google's terms and privacy policy. VocaVision itself keeps no images or recordings and sends nothing to anyone else; your key stays in your device's Keychain."
                        ))
                        .font(.body)
                        Text(tr(
                            ar: "تنبيه: على الباقة المجانية من Google قد يراجع بشر بعض المحتوى لتحسين الخدمة، فلا تصوّر معلومات حساسة. على الباقة المدفوعة لا يُستخدم محتواك للتحسين.",
                            en: "Note: on Google's free tier, human reviewers may read some content to improve the service, so avoid pointing the camera at sensitive information. On the paid tier your content is not used for improvement."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        Link(tr(ar: "شروط Gemini API", en: "Gemini API terms"), destination: DataSharingConsent.providerTermsURL)
                        Link(tr(ar: "سياسة خصوصية Google", en: "Google privacy policy"), destination: DataSharingConsent.providerPrivacyURL)
                        Link(tr(ar: "كيف تتعامل Google مع بيانات API", en: "How Google handles API data"), destination: DataSharingConsent.providerDataURL)
                    }
                    .contentCard()

                    Text(tr(
                        ar: "باستخدامك للتطبيق ومتابعتك من شاشة الترحيب فأنت موافق على هذه السياسة. لو ما تبي إرسال أي بيانات، لا تبدأ مكالمة.",
                        en: "By using the app and continuing past the welcome screen you agree to this policy. If you don't want any data sent, don't start a call."
                    ))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(AppTheme.Spacing.lg)
            }
            .scrollEdgeEffectStyle(.soft, for: .vertical)
            .navigationTitle(tr(ar: "سياسة الخصوصية", en: "Privacy policy"))
            .toolbarTitleDisplayMode(.inline)
    }

    private func consentRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 36, height: 36)
                .background(AppTheme.accent.opacity(0.15), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
