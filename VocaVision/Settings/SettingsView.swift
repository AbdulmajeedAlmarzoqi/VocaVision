import SwiftUI

struct SettingsView: View {
    @Environment(APIKeyStore.self) private var apiKeyStore
    @State private var draftKey: String = ""
    @State private var showSheet: Bool = false
    @State private var validationState: ValidationState = .idle
    @State private var isShowingClearConfirm: Bool = false

    enum ValidationState: Equatable {
        case idle
        case validating
        case success
        case failure(String)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    apiKeyRow
                } header: {
                    Text(tr(ar: "مفتاح Gemini API", en: "Gemini API key"))
                        .accessibilityBilingual(
                            tr(ar: "مفتاح Gemini API", en: "Gemini API key"),
                            englishTokens: ["Gemini", "API"]
                        )
                } footer: {
                    let footer = tr(
                        ar: "المفتاح ينحفظ بأمان داخل سلسلة مفاتيح iOS، وما يستخدم إلا للتواصل مع خوادم Google.",
                        en: "Your key is stored securely in the iOS keychain and is used only to talk to Google's servers."
                    )
                    Text(footer)
                        .accessibilityBilingual(footer, englishTokens: ["iOS", "Google"])
                }

                Section {
                    NavigationLink {
                        CustomizationView()
                    } label: {
                        Label(tr(ar: "تخصيص Voca", en: "Customize Voca"), systemImage: "slider.horizontal.3")
                    }
                    .accessibilityHint(tr(
                        ar: "يفتح إعدادات الصوت واللغة وطريقة الشغل",
                        en: "Opens voice, language, and operating mode settings"
                    ))
                } header: {
                    Text(tr(ar: "التخصيص", en: "Customization"))
                } footer: {
                    Text(tr(
                        ar: "اضبط صوت Voca، ولغتها ولهجتها، وطريقة شغلها (وفيه وضع «تعليمات خاصّة» تكتب فيه اللي يناسبك).",
                        en: "Adjust Voca's voice, language, dialect, and operating mode (including a custom-instructions mode you can write yourself)."
                    ))
                }

                Section {
                    NavigationLink {
                        PrivacyPolicyView()
                    } label: {
                        Label(tr(ar: "سياسة الخصوصية", en: "Privacy policy"), systemImage: "hand.raised.fill")
                    }
                    .accessibilityHint(tr(
                        ar: "يعرض ما يُرسل إلى Google Gemini أثناء المكالمة",
                        en: "Shows what is sent to Google Gemini during a call"
                    ))

                    Link(destination: DataSharingConsent.providerTermsURL) {
                        Label(tr(ar: "شروط Gemini API", en: "Gemini API terms"), systemImage: "link")
                    }
                } header: {
                    Text(tr(ar: "الخصوصية", en: "Privacy"))
                } footer: {
                    Text(tr(
                        ar: "أثناء المكالمة تُرسل صور الكاميرا وصوتك إلى Google Gemini بمفتاحك الخاص. VocaVision لا يحتفظ بأي بيانات ولا يرسلها لأي جهة أخرى.",
                        en: "During a call, camera frames and your voice are sent to Google Gemini with your own key. VocaVision keeps no data and sends nothing to anyone else."
                    ))
                }

                Section {
                    NavigationLink {
                        DiagnosticsView()
                    } label: {
                        Label(tr(ar: "سجلّ التشخيص", en: "Diagnostics log"), systemImage: "stethoscope")
                    }
                    .accessibilityHint(tr(
                        ar: "يعرض السجلّ المباشر للأحداث ويتيح مشاركته لو صار فيه أي مشكلة",
                        en: "Shows the live event log and lets you share it if anything goes wrong"
                    ))

                    Link(destination: URL(string: "https://aistudio.google.com/app/apikey")!) {
                        Label(tr(ar: "الحصول على مفتاح API", en: "Get an API key"), systemImage: "key.fill")
                    }
                    .accessibilityHint(tr(
                        ar: "يفتح Google AI Studio في المتصفّح",
                        en: "Opens Google AI Studio in the browser"
                    ))
                } header: {
                    Text(tr(ar: "المساعدة", en: "Help"))
                }
            }
            .navigationTitle(tr(ar: "الإعدادات", en: "Settings"))
            .scrollEdgeEffectStyle(.soft, for: .top)
            .sheet(isPresented: $showSheet, onDismiss: resetSheet) {
                apiKeySheet
            }
            .confirmationDialog(
                tr(ar: "تبي تحذف المفتاح؟", en: "Delete the key?"),
                isPresented: $isShowingClearConfirm,
                titleVisibility: .visible
            ) {
                Button(tr(ar: "حذف المفتاح", en: "Delete key"), role: .destructive) {
                    apiKeyStore.clear()
                }
                Button(tr(ar: "إلغاء", en: "Cancel"), role: .cancel) {}
            } message: {
                Text(tr(
                    ar: "راح تحتاج تدخّل مفتاح Gemini من جديد قبل أي مكالمة.",
                    en: "You'll need to enter a Gemini key again before the next call."
                ))
            }
        }
    }

    private var apiKeyRow: some View {
        Group {
            if apiKeyStore.hasKey {
                let connectedLabel = tr(ar: "متّصل بـ Gemini", en: "Connected to Gemini")
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(AppTheme.success)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(connectedLabel)
                            .font(.body.weight(.medium))
                        Text(tr(
                            ar: "اضغط «تعديل» تغيّر المفتاح.",
                            en: "Tap \"Edit\" to change the key."
                        ))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityBilingual(connectedLabel, englishTokens: ["Gemini"])
                .accessibilityHint(tr(
                    ar: "اضغط تعديل عشان تغيّر المفتاح المحفوظ",
                    en: "Tap Edit to change the stored key"
                ))

                Button {
                    showSheet = true
                } label: {
                    Label(tr(ar: "تعديل المفتاح", en: "Edit key"), systemImage: "pencil")
                }
                .accessibilityHint(tr(
                    ar: "يفتح صفحة عشان تدخّل مفتاح Gemini جديد",
                    en: "Opens a page to enter a new Gemini key"
                ))

                Button(role: .destructive) {
                    isShowingClearConfirm = true
                } label: {
                    Label(tr(ar: "حذف المفتاح", en: "Delete key"), systemImage: "trash")
                }
                .accessibilityHint(tr(
                    ar: "يحذف مفتاح Gemini المحفوظ من الجهاز",
                    en: "Removes the stored Gemini key from this device"
                ))
            } else {
                Button {
                    showSheet = true
                } label: {
                    Label(tr(ar: "إضافة مفتاح API", en: "Add API key"), systemImage: "plus.circle.fill")
                }
                .accessibilityHint(tr(
                    ar: "يفتح صفحة عشان تضيف مفتاح Gemini",
                    en: "Opens a page to add a Gemini key"
                ))
            }
        }
    }

    private var apiKeySheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("AIza...", text: $draftKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .environment(\.layoutDirection, .leftToRight)
                        .accessibilityBilingual(
                            tr(ar: "مفتاح Gemini API", en: "Gemini API key"),
                            englishTokens: ["Gemini", "API"]
                        )
                        .accessibilityHint(tr(
                            ar: "الصق المفتاح من Google AI Studio",
                            en: "Paste the key from Google AI Studio"
                        ))
                } footer: {
                    validationFooter
                }

                Section {
                    Button(action: validateAndSave) {
                        HStack {
                            if validationState == .validating {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.trailing, AppTheme.Spacing.xs)
                            }
                            Text(buttonTitle)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(draftKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || validationState == .validating)
                    .accessibilityHint(tr(
                        ar: "يتأكد من المفتاح مع Google ثم يحفظه في سلسلة المفاتيح",
                        en: "Verifies the key with Google and saves it to the keychain"
                    ))
                }
            }
            .navigationTitle(apiKeyStore.hasKey
                             ? tr(ar: "تعديل المفتاح", en: "Edit key")
                             : tr(ar: "إضافة المفتاح", en: "Add key"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(tr(ar: "إلغاء", en: "Cancel")) { showSheet = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var buttonTitle: String {
        if validationState == .validating {
            return tr(ar: "جاري التحقّق…", en: "Verifying…")
        }
        return apiKeyStore.hasKey
            ? tr(ar: "حفظ التعديل", en: "Save changes")
            : tr(ar: "تحقّق وحفظ", en: "Verify and save")
    }

    @ViewBuilder
    private var validationFooter: some View {
        switch validationState {
        case .idle:
            Text(tr(
                ar: "VocaVision راح يتواصل مع Gemini ويتأكد من المفتاح قبل ما يحفظه.",
                en: "VocaVision will contact Gemini to verify the key before saving it."
            ))
        case .validating:
            Label(tr(ar: "جاري التحقّق مع Google…", en: "Verifying with Google…"),
                  systemImage: "arrow.triangle.2.circlepath")
        case .success:
            Label(tr(ar: "تمّ التحقّق من المفتاح وحفظه.", en: "Key verified and saved."),
                  systemImage: "checkmark.seal.fill")
                .foregroundStyle(AppTheme.success)
        case .failure(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.danger)
        }
    }

    private func validateAndSave() {
        let key = draftKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        validationState = .validating

        Task {
            do {
                try await GeminiClient.validate(apiKey: key)
                if apiKeyStore.save(key) {
                    validationState = .success
                    announce(tr(ar: "تمّ التحقّق من المفتاح وحفظه", en: "Key verified and saved"))
                    try? await Task.sleep(for: .milliseconds(700))
                    showSheet = false
                } else {
                    validationState = .failure(tr(
                        ar: "ما قدرت أحفظ المفتاح. حاول مرة ثانية.",
                        en: "Couldn't save the key. Please try again."
                    ))
                }
            } catch {
                let message = (error as? GeminiClient.ValidationError)?.userMessage
                    ?? tr(
                        ar: "ما قدرت أتحقّق من المفتاح. تأكد من النت وحاول مرة ثانية.",
                        en: "Couldn't verify the key. Check your connection and try again."
                    )
                validationState = .failure(message)
                announce(message, highPriority: true)
            }
        }
    }

    private func resetSheet() {
        draftKey = ""
        validationState = .idle
    }
}

#Preview {
    SettingsView()
        .environment(APIKeyStore())
        .environment(CustomizationStore())
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
