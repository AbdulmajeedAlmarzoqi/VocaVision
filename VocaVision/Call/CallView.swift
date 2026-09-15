import SwiftUI

struct CallView: View {
    @Environment(APIKeyStore.self) private var apiKeyStore
    @Environment(CustomizationStore.self) private var customizationStore
    @State private var viewModel: CallViewModel?

    let onEndCall: () -> Void

    var body: some View {
        Group {
            if let viewModel {
                CallContent(viewModel: viewModel, onEndCall: {
                    viewModel.endCall()
                    onEndCall()
                })
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .task {
            if viewModel == nil {
                let vm = CallViewModel(apiKeyStore: apiKeyStore, customizationStore: customizationStore)
                viewModel = vm
                await vm.startCallIfNeeded()
            }
        }
    }
}

private struct CallContent: View {
    @Bindable var viewModel: CallViewModel
    let onEndCall: () -> Void

    @State private var isShowingInstructionSheet = false
    @State private var instructionDraft = ""
    @Namespace private var glassNamespace

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewView(session: viewModel.camera.session)
                .ignoresSafeArea()
                .accessibilityElement()
                .accessibilityLabel(tr(ar: "البثّ المباشر للكاميرا", en: "Live camera feed"))
                .accessibilityHint(tr(ar: "Voca توصف لك اللي تشوفه الكاميرا", en: "Voca describes what the camera is seeing"))

            // Dimming layer so clear glass stays legible over bright scenes.
            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .clear, .black.opacity(0.6)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: AppTheme.Spacing.lg) {
                topBar
                Spacer()
                transcriptArea
                controls
                    .padding(.bottom, AppTheme.Spacing.md)
            }
            .padding(.horizontal, AppTheme.Spacing.lg)

            if let error = viewModel.startupError {
                errorOverlay(error)
            }
        }
        .environment(\.colorScheme, .dark)
        .statusBarHidden(true)
        .sheet(isPresented: $isShowingInstructionSheet) {
            instructionSheet
        }
        .onChange(of: viewModel.status) { _, newValue in
            announceStatusChange(newValue)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        GlassEffectContainer(spacing: AppTheme.Spacing.md) {
            HStack {
                HStack(spacing: AppTheme.Spacing.sm) {
                    Image(systemName: "eye.fill")
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityHidden(true)
                    Text(verbatim: "Voca")
                        .font(.headline)
                    if let start = viewModel.callStartedAt {
                        Text(timerInterval: start...Date.distantFuture, countsDown: false, showsHours: false)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)
                .glassEffect()
                .accessibilityElement(children: .combine)
                .accessibilityBilingual(
                    tr(ar: "مكالمة مع Voca", en: "Call with Voca"),
                    englishTokens: ["Voca"]
                )

                Spacer()

                statusPill
            }
        }
        .padding(.top, AppTheme.Spacing.md)
    }

    private var statusPill: some View {
        let (label, color, symbol) = statusDescriptor()
        return Label(label, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, AppTheme.Spacing.md)
            .padding(.vertical, AppTheme.Spacing.sm)
            .glassEffect(.regular.tint(color.opacity(0.7)))
            .accessibilityLabel(label)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func statusDescriptor() -> (String, Color, String) {
        switch viewModel.status {
        case .idle:
            return (tr(ar: "بانتظار", en: "Idle"), .gray, "pause.circle.fill")
        case .starting:
            return (tr(ar: "جاري الاتصال", en: "Connecting"), AppTheme.warning, "arrow.triangle.2.circlepath")
        case .listening:
            return viewModel.isWatching
                ? (tr(ar: "تراقب", en: "Watching"), AppTheme.success, "eye.fill")
                : (tr(ar: "تسمعك", en: "Listening"), AppTheme.accent, "ear.fill")
        case .userSpeaking:
            return (tr(ar: "أنت تتكلّم", en: "You're speaking"), AppTheme.success, "mic.fill")
        case .modelSpeaking:
            return (tr(ar: "Voca تتكلم", en: "Voca speaking"), AppTheme.success, "waveform")
        case .reconnecting:
            return (tr(ar: "إعادة اتصال", en: "Reconnecting"), AppTheme.warning, "wifi.exclamationmark")
        case .error:
            return (tr(ar: "خطأ", en: "Error"), AppTheme.danger, "exclamationmark.triangle.fill")
        }
    }

    private func announceStatusChange(_ status: SpeechFeedbackOrchestrator.Status) {
        switch status {
        case .reconnecting:
            announce(tr(ar: "انقطع الاتصال، جاري إعادة الاتصال", en: "Connection lost, reconnecting"), highPriority: true)
        case .error(let message):
            announce(message, highPriority: true)
        default:
            break
        }
    }

    // MARK: Transcripts

    private var transcriptArea: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            let userText = viewModel.inputTranscript.isEmpty ? viewModel.interimInputTranscript : viewModel.inputTranscript
            if !userText.isEmpty {
                TranscriptBubble(
                    text: userText,
                    label: tr(ar: "صوتك", en: "You"),
                    icon: "person.fill",
                    accent: AppTheme.accent
                )
            }
            if !viewModel.outputTranscript.isEmpty {
                TranscriptBubble(
                    text: viewModel.outputTranscript,
                    label: "Voca",
                    icon: "sparkles",
                    accent: AppTheme.success
                )
            }
            if userText.isEmpty && viewModel.outputTranscript.isEmpty {
                placeholderBubble
            }
        }
    }

    private var placeholderBubble: some View {
        let text = currentPlaceholder()
        return Text(text)
            .font(.title3.weight(.medium))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.vertical, AppTheme.Spacing.md)
            .padding(.horizontal, AppTheme.Spacing.lg)
            .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.card))
            .accessibilityLabel(tr(ar: "الحالة", en: "Status"))
            .accessibilityValue(text)
            .accessibilityAddTraits(.updatesFrequently)
    }

    private func currentPlaceholder() -> String {
        switch viewModel.status {
        case .error(let message):
            return message
        case .starting:
            return tr(ar: "جاري الاتصال بـ Voca…", en: "Connecting to Voca…")
        case .listening:
            return tr(ar: "اتكلّم الحين، Voca سامعتك.", en: "Speak now — Voca is listening.")
        case .userSpeaking:
            return tr(ar: "تسمعك الحين…", en: "Listening to you…")
        case .modelSpeaking:
            return tr(ar: "Voca تتكلم…", en: "Voca is speaking…")
        case .reconnecting:
            return tr(ar: "انقطع الاتصال، لحظة وأرجع…", en: "Connection lost, reconnecting…")
        case .idle:
            return tr(ar: "جاري التجهيز…", en: "Getting ready…")
        }
    }

    // MARK: Controls

    private var controls: some View {
        GlassEffectContainer(spacing: AppTheme.Spacing.lg) {
            HStack(spacing: AppTheme.Spacing.md) {
                CallActionButton(
                    systemImage: viewModel.isMicMuted ? "mic.slash.fill" : "mic.fill",
                    glass: viewModel.isMicMuted ? .regular.tint(.white.opacity(0.9)).interactive() : .regular.interactive(),
                    foreground: viewModel.isMicMuted ? .black : .white,
                    size: 56,
                    accessibilityLabel: viewModel.isMicMuted
                        ? tr(ar: "تشغيل الميكروفون", en: "Unmute microphone")
                        : tr(ar: "كتم الميكروفون", en: "Mute microphone"),
                    accessibilityHint: viewModel.isMicMuted
                        ? tr(ar: "يرجّع صوتك إلى Voca", en: "Sends your voice back to Voca")
                        : tr(ar: "يكتم صوتك فما تسمعك Voca", en: "Mutes your voice so Voca can't hear you"),
                    action: { viewModel.toggleMicMute() }
                )
                .glassEffectID("mic", in: glassNamespace)

                CallActionButton(
                    systemImage: viewModel.isWatching ? "eye.fill" : "eye.slash.fill",
                    glass: viewModel.isWatching ? .regular.tint(AppTheme.success).interactive() : .regular.interactive(),
                    foreground: .white,
                    size: 56,
                    accessibilityLabel: viewModel.isWatching
                        ? tr(ar: "إيقاف المراقبة المباشرة", en: "Stop live watching")
                        : tr(ar: "تشغيل المراقبة المباشرة", en: "Start live watching"),
                    accessibilityHint: tr(
                        ar: "لما تكون شغّالة، Voca تبلّغك فقط لما يتغيّر شي فعلاً قدّام الكاميرا",
                        en: "When on, Voca only tells you when something really changes in front of the camera"
                    ),
                    action: { viewModel.toggleWatchMode() }
                )
                .glassEffectID("watch", in: glassNamespace)

                CallActionButton(
                    systemImage: "phone.down.fill",
                    glass: .regular.tint(AppTheme.danger).interactive(),
                    foreground: .white,
                    size: 72,
                    accessibilityLabel: tr(ar: "إنهاء المكالمة", en: "End call"),
                    accessibilityHint: tr(ar: "يقفل المكالمة ويرجعك للشاشة الرئيسية", en: "Hangs up and returns to the home screen"),
                    action: onEndCall
                )
                .glassEffectID("end", in: glassNamespace)

                CallActionButton(
                    systemImage: "text.bubble.fill",
                    glass: .regular.interactive(),
                    foreground: .white,
                    size: 56,
                    accessibilityLabel: tr(ar: "إرسال تعليمات مكتوبة", en: "Send written instruction"),
                    accessibilityHint: tr(ar: "يفتح حقلاً تكتب فيه قاعدة أو سؤالاً لـ Voca", en: "Opens a field to type a rule or question for Voca"),
                    action: { isShowingInstructionSheet = true }
                )
                .glassEffectID("text", in: glassNamespace)

                CallActionButton(
                    systemImage: "arrow.triangle.2.circlepath.camera.fill",
                    glass: .regular.interactive(),
                    foreground: .white,
                    size: 56,
                    accessibilityLabel: viewModel.cameraPosition == .back
                        ? tr(ar: "تبديل للكاميرا الأمامية", en: "Switch to front camera")
                        : tr(ar: "تبديل للكاميرا الخلفية", en: "Switch to back camera"),
                    accessibilityHint: tr(ar: "يبدّل بين الكاميرا الأمامية والخلفية", en: "Switches between the front and back cameras"),
                    action: { viewModel.switchCamera() }
                )
                .glassEffectID("camera", in: glassNamespace)
            }
        }
    }

    // MARK: Instruction sheet

    private var instructionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        tr(ar: "مثال: اقرأ لي فقط الخيار المحدَّد", en: "e.g. only read the highlighted option"),
                        text: $instructionDraft,
                        axis: .vertical
                    )
                    .lineLimit(3...6)
                    .accessibilityLabel(tr(ar: "التعليمات", en: "Instruction"))
                } footer: {
                    Text(tr(
                        ar: "Voca تلتزم بالتعليمات المكتوبة فوراً كأنك قلتها بصوتك.",
                        en: "Voca follows written instructions immediately, as if you had said them."
                    ))
                }
            }
            .navigationTitle(tr(ar: "تعليمات لـ Voca", en: "Instruction for Voca"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr(ar: "إلغاء", en: "Cancel")) { isShowingInstructionSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(tr(ar: "إرسال", en: "Send")) {
                        viewModel.sendInstruction(instructionDraft)
                        instructionDraft = ""
                        isShowingInstructionSheet = false
                    }
                    .disabled(instructionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Error

    private func errorOverlay(_ message: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: AppTheme.Spacing.md) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.danger)
                    .accessibilityHidden(true)
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Button(tr(ar: "إنهاء المكالمة", en: "End call"), role: .destructive, action: onEndCall)
                    .buttonStyle(.glassProminent)
                    .accessibilityHint(tr(ar: "يقفل المكالمة ويرجّعك للشاشة الرئيسية", en: "Hangs up and returns to the home screen"))
            }
            .padding(AppTheme.Spacing.lg)
            .background(.regularMaterial, in: .rect(cornerRadius: AppTheme.Radius.card))
            .padding(AppTheme.Spacing.lg)
            Spacer()
        }
        .background(Color.black.opacity(0.55).ignoresSafeArea())
        .accessibilityAddTraits(.isModal)
    }
}

private struct TranscriptBubble: View {
    let text: String
    let label: String
    let icon: String
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(accent, in: .circle)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.body)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.Spacing.sm)
        .padding(.horizontal, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: AppTheme.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(bilingualLabel))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private var bilingualLabel: AttributedString {
        let labelIsArabic = label.first?.isArabic ?? false
        let bodyLanguage = (text.first?.isArabic ?? false) ? "ar-SA" : "en-US"
        return makeAttributedString(from: [
            AccessibilitySegment(text: label + ": ", language: labelIsArabic ? "ar-SA" : "en-US"),
            AccessibilitySegment(text: text, language: bodyLanguage)
        ])
    }
}

private extension Character {
    var isArabic: Bool {
        unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }
    }
}

private struct CallActionButton: View {
    let systemImage: String
    let glass: Glass
    let foreground: Color
    var size: CGFloat = 68
    let accessibilityLabel: String
    let accessibilityHint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .circle)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
    }
}
