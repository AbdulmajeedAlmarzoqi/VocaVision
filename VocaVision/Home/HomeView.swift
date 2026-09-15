import SwiftUI

struct HomeView: View {
    @Environment(APIKeyStore.self) private var apiKeyStore
    @State private var isPresentingCall = false
    @State private var isShowingMissingKeyAlert = false

    var body: some View {
        NavigationStack {
            ZStack {
                BrandBackground()

                VStack(spacing: AppTheme.Spacing.xl) {
                    Spacer(minLength: AppTheme.Spacing.md)
                    heroCard
                    Spacer()
                    callButton
                    helperText
                        .padding(.bottom, AppTheme.Spacing.lg)
                }
                .padding(.horizontal, AppTheme.Spacing.lg)
            }
            .navigationTitle(Text(verbatim: "VocaVision"))
            .navigationSubtitle(tr(ar: "عيونك الذكية", en: "Your smart eyes"))
            .fullScreenCover(isPresented: $isPresentingCall) {
                CallView(onEndCall: { isPresentingCall = false })
            }
            .alert(
                tr(ar: "لازم مفتاح API الأول", en: "API key required"),
                isPresented: $isShowingMissingKeyAlert
            ) {
                Button(tr(ar: "تمام", en: "OK"), role: .cancel) {}
            } message: {
                Text(tr(
                    ar: "روح للإعدادات وحُط مفتاح Gemini قبل ما تبدأ المكالمة.",
                    en: "Go to Settings and add your Gemini key before starting a call."
                ))
            }
        }
    }

    private var heroCard: some View {
        let title = tr(ar: "خلّني أكون عيونك", en: "Let me be your eyes")
        let subtitle = tr(
            ar: "ابدأ المكالمة، وVoca توصف لك كل اللي قدّامك من الكاميرا — لحظة بلحظة.",
            en: "Start the call and Voca will describe everything in front of the camera — moment by moment."
        )
        return VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "eye.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(AppTheme.accent.gradient)
                .accessibilityHidden(true)

            Text(title)
                .font(.title.bold())
                .multilineTextAlignment(.center)

            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .contentCard(padding: AppTheme.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityBilingual("\(title). \(subtitle)", englishTokens: ["Voca"])
        .accessibilityAddTraits(.isHeader)
    }

    private var callButton: some View {
        Button {
            if apiKeyStore.hasKey {
                isPresentingCall = true
            } else {
                isShowingMissingKeyAlert = true
            }
        } label: {
            VStack(spacing: AppTheme.Spacing.xs) {
                Image(systemName: "video.fill")
                    .font(.system(size: 36, weight: .semibold))
                Text(tr(ar: "ابدأ المكالمة", en: "Start Call"))
                    .font(.title3.weight(.semibold))
            }
            .frame(width: 176, height: 176)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .accessibilityLabel(tr(ar: "ابدأ المكالمة", en: "Start Call"))
        .accessibilityHint(apiKeyStore.hasKey
                           ? tr(ar: "يفتح مكالمة مباشرة مع Voca", en: "Opens a live call with Voca")
                           : tr(ar: "محتاج مفتاح API. روح للإعدادات.", en: "API key required. Go to Settings."))
    }

    private var helperText: some View {
        Group {
            if apiKeyStore.hasKey {
                let connected = tr(ar: "المفتاح جاهز — Voca بانتظارك", en: "Key ready — Voca is waiting")
                Label(connected, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(AppTheme.success)
                    .accessibilityElement(children: .combine)
                    .accessibilityBilingual(connected, englishTokens: ["Voca"])
            } else {
                let missing = tr(ar: "محتاج مفتاح API — روح للإعدادات", en: "API key required — go to Settings")
                Label(missing, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppTheme.warning)
                    .accessibilityElement(children: .combine)
                    .accessibilityBilingual(missing, englishTokens: ["API"])
            }
        }
        .font(.subheadline)
        .padding(.horizontal, AppTheme.Spacing.md)
        .padding(.vertical, AppTheme.Spacing.sm)
        .glassEffect()
    }
}

#Preview {
    HomeView()
        .environment(APIKeyStore())
        .environment(CustomizationStore())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
