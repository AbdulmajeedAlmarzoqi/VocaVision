import SwiftUI

// MARK: - Top-level customisation view

/// Entry point for everything the user can customise about Voca: the
/// voice, the conversational language + dialect, and the behaviour
/// (preset or custom prompt). Pushed onto the Settings stack as a
/// single navigation destination.
struct CustomizationView: View {
    @Environment(CustomizationStore.self) private var store

    var body: some View {
        List {
            userProfileSection
            voiceSection
            languageSection
            behaviourSection
            callSection
            footerSection
        }
        .navigationTitle(tr(ar: "خصّص Voca", en: "Customize Voca"))
        .toolbarTitleDisplayMode(.inline)
    }

    private var userProfileSection: some View {
        Section {
            NavigationLink {
                UserProfileEditorView()
            } label: {
                LabeledContent {
                    Text(userSummary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } label: {
                    Label(
                        tr(ar: "عرّف Voca بنفسك", en: "Tell Voca about you"),
                        systemImage: "person.crop.circle.fill"
                    )
                }
            }
            .accessibilityHint(tr(
                ar: "يفتح تعديل اسمك وجنسك عشان Voca تخاطبك صح",
                en: "Opens name + gender editing so Voca addresses you correctly"
            ))
        } header: {
            Text(tr(ar: "الملف الشخصي", en: "Profile"))
        } footer: {
            Text(tr(
                ar: "اسمك وجنسك يستخدمان داخل التطبيق فقط عشان Voca تخاطبك بالشكل الصحيح — ما تنرسل ولا تنحفظ خارج جهازك.",
                en: "Your name and gender are used inside the app only so Voca addresses you correctly — they're never sent or stored outside your device."
            ))
        }
    }

    private var userSummary: String {
        let name = store.userName.trimmingCharacters(in: .whitespacesAndNewlines)
        let gender = store.userGender.displayLocalised
        let unset = tr(ar: "غير محدّد", en: "Not set")
        if name.isEmpty {
            return store.userGender == .unspecified ? unset : gender
        }
        return store.userGender == .unspecified ? name : "\(name) — \(gender)"
    }

    private var voiceSection: some View {
        Section {
            NavigationLink {
                VoicePickerView()
            } label: {
                LabeledContent {
                    Text(store.voice.displayName)
                        .foregroundStyle(.secondary)
                } label: {
                    Label(tr(ar: "الصوت", en: "Voice"), systemImage: "waveform.circle.fill")
                }
            }
            .accessibilityHint(tr(ar: "يفتح قائمة اختيار صوت Voca", en: "Opens the Voca voice picker"))
        } header: {
            Text(tr(ar: "الصوت والشخصية", en: "Voice & personality"))
        } footer: {
            Text(genderFooter)
        }
    }

    private var genderFooter: String {
        switch store.voice.gender {
        case .feminine:
            return tr(
                ar: "Voca راح تتكلم بصيغة المؤنّث، حسب الصوت المختار.",
                en: "Voca will speak with feminine forms, based on the selected voice."
            )
        case .masculine:
            return tr(
                ar: "Voca راح يتكلم بصيغة المذكّر، حسب الصوت المختار.",
                en: "Voca will speak with masculine forms, based on the selected voice."
            )
        case .unspecified:
            return tr(
                ar: "Google ما حدّدت جنس هذا الصوت؛ Voca راح تختار الصيغة الأنسب لصوته.",
                en: "Google hasn't specified this voice's gender; Voca will pick the forms that fit its voice."
            )
        }
    }

    private var languageSection: some View {
        Section {
            NavigationLink {
                LanguagePickerView()
            } label: {
                LabeledContent {
                    Text("\(store.language.displayName) — \(store.dialect.displayName)")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } label: {
                    Label(tr(ar: "لغة Voca ولهجتها", en: "Voca's language & dialect"), systemImage: "globe")
                }
            }
            .accessibilityHint(tr(
                ar: "يفتح قائمة اختيار لغة Voca ولهجتها",
                en: "Opens the Voca language and dialect picker"
            ))
        } header: {
            Text(tr(ar: "اللغة", en: "Language"))
        } footer: {
            Text(tr(
                ar: "اختر اللغة اللي تتكلم بها Voca، ثم اللهجة. النموذج يلتزم باللهجة المختارة بدقّة.",
                en: "Pick the language Voca speaks, then the dialect. The model follows the chosen dialect strictly."
            ))
        }
    }

    private var behaviourSection: some View {
        Section {
            NavigationLink {
                PresetPickerView()
            } label: {
                LabeledContent {
                    Text(store.preset.displayTitle)
                        .foregroundStyle(.secondary)
                } label: {
                    Label(tr(ar: "وضع التشغيل", en: "Operating mode"), systemImage: "wand.and.stars")
                }
            }
            .accessibilityHint(tr(
                ar: "يفتح قائمة أوضاع التشغيل الجاهزة + خيار التخصيص",
                en: "Opens the list of preset operating modes plus the custom option"
            ))

            if store.preset == .custom {
                NavigationLink {
                    CustomPromptEditorView()
                } label: {
                    Label(
                        tr(ar: "تعديل التعليمات الخاصّة", en: "Edit custom instructions"),
                        systemImage: "square.and.pencil"
                    )
                }
                .accessibilityHint(tr(
                    ar: "يفتح محرّر التعليمات الخاصّة",
                    en: "Opens the custom-instructions editor"
                ))
            }
        } header: {
            Text(tr(ar: "طريقة شغل Voca", en: "How Voca operates"))
        } footer: {
            Text(store.preset.displaySummary)
        }
    }

    private var callSection: some View {
        @Bindable var store = store
        return Section {
            Toggle(isOn: $store.bargeInEnabled) {
                Label(tr(ar: "المقاطعة بالصوت", en: "Interrupt by voice"), systemImage: "hand.raised.fill")
            }
            .accessibilityHint(tr(
                ar: "لما يكون شغّال تقدر تقاطع Voca بصوتك وهي تتكلم. لما يكون مقفول، Voca تكمّل كلامها ثم تسمعك",
                en: "When on, you can interrupt Voca by speaking while she talks. When off, Voca finishes speaking before listening"
            ))
        } header: {
            Text(tr(ar: "المكالمة", en: "Call"))
        } footer: {
            Text(tr(
                ar: "الميكروفون يستخدم إلغاء الصدى من النظام. لو لاحظت أن Voca تقطع كلامها من صوتها نفسه على السماعة، اقفل هالخيار.",
                en: "The microphone uses the system's echo cancellation. If Voca keeps cutting herself off from her own voice on the speaker, turn this off."
            ))
        }
    }

    private var footerSection: some View {
        Section {
            EmptyView()
        } footer: {
            Text(tr(
                ar: "Voca تطبيق سعودي ١٠٠٪. الواجهة عربية بشكل افتراضي، وتدعم الإنجليزية تلقائيّاً لو غيّرت لغة جهازك من إعدادات iOS.",
                en: "Voca is a 100% Saudi-made app. The interface is Arabic by default and supports English automatically if you change your device language in iOS Settings."
            ))
        }
    }
}

// MARK: - Voice picker

struct VoicePickerView: View {
    @Environment(CustomizationStore.self) private var store
    @Environment(APIKeyStore.self) private var apiKeyStore
    @State private var samplePlayer = VoiceSamplePlayer()
    @State private var infoVoice: VoiceCatalog.Voice?
    @State private var sampleErrorMessage: String?

    private var directory: VoiceDirectory { VoiceDirectory.shared }

    var body: some View {
        List {
            Section {
                ForEach(VoiceCatalog.voices) { voice in
                    VoiceRow(
                        voice: voice,
                        isSelected: voice.id == store.voiceID,
                        isPlaying: samplePlayer.playingVoiceID == voice.id,
                        isLoading: samplePlayer.loadingVoiceID == voice.id,
                        onSelect: { store.voiceID = voice.id },
                        onPlaySample: {
                            if samplePlayer.playingVoiceID == voice.id || samplePlayer.loadingVoiceID == voice.id {
                                samplePlayer.stop()
                                return
                            }
                            samplePlayer.playOfficialSample(voice: voice)
                        },
                        onShowInfo: { infoVoice = voice }
                    )
                }
            } footer: {
                directoryFooter
            }
        }
        .navigationTitle(tr(ar: "اختر الصوت", en: "Choose voice"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await directory.refresh() }
                } label: {
                    if directory.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(directory.isRefreshing)
                .accessibilityLabel(tr(ar: "تحديث قائمة الأصوات من خادم Google", en: "Refresh the voice list from Google's server"))
            }
        }
        .sheet(item: $infoVoice) { voice in
            VoiceInfoSheet(
                voice: voice,
                isPlaying: samplePlayer.playingVoiceID == voice.id,
                isLoading: samplePlayer.loadingVoiceID == voice.id,
                onPlayOfficial: { samplePlayer.playOfficialSample(voice: voice) },
                onPlayDialect: {
                    guard let key = apiKeyStore.currentKey() else {
                        sampleErrorMessage = tr(
                            ar: "أضف مفتاح Gemini من الإعدادات الرئيسية أولاً عشان تسمع الصوت بلهجتك.",
                            en: "Add a Gemini key in the main Settings first to hear the voice in your dialect."
                        )
                        return
                    }
                    samplePlayer.playDialectSample(voice: voice, dialect: store.dialect, apiKey: key)
                },
                onStop: { samplePlayer.stop() }
            )
        }
        .alert(
            tr(ar: "ما قدرت أشغّل العينة", en: "Couldn't play the preview"),
            isPresented: Binding(
                get: { sampleErrorMessage != nil || samplePlayer.lastError != nil },
                set: { if !$0 { sampleErrorMessage = nil; samplePlayer.clearError() } }
            )
        ) {
            Button(tr(ar: "تمام", en: "OK"), role: .cancel) {}
        } message: {
            Text(sampleErrorMessage ?? samplePlayer.lastError ?? "")
        }
        .task { await directory.refreshIfStale() }
        .onDisappear { samplePlayer.stop() }
    }

    @ViewBuilder private var directoryFooter: some View {
        if let fetchedAt = directory.fetchedAt, !directory.entries.isEmpty {
            Text(tr(ar: "القائمة والأوصاف والعينات من خادم Google. آخر تحديث: \(fetchedAt.formatted(date: .abbreviated, time: .shortened)).",
                    en: "List, descriptions and samples come from Google's server. Last updated \(fetchedAt.formatted(date: .abbreviated, time: .shortened))."))
        } else if directory.isRefreshing {
            Text(tr(ar: "جاري تحميل قائمة الأصوات من خادم Google…", en: "Loading the voice list from Google's server…"))
        } else {
            Text(tr(ar: "تعذّر الوصول لخادم Google الآن؛ هذه القائمة المحفوظة في التطبيق.",
                    en: "Google's server couldn't be reached; this is the list bundled with the app."))
        }
    }
}

private struct VoiceRow: View {
    let voice: VoiceCatalog.Voice
    let isSelected: Bool
    let isPlaying: Bool
    let isLoading: Bool
    let onSelect: () -> Void
    let onPlaySample: () -> Void
    let onShowInfo: () -> Void

    var body: some View {
        HStack(spacing: AppTheme.Spacing.md) {
            Button(action: onSelect) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "person.fill")
                        .foregroundStyle(voice.gender == .feminine ? Color.pink : (voice.gender == .masculine ? Color.blue : Color.secondary))
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.displayName)
                            .font(.body.weight(.medium))
                        HStack(spacing: 6) {
                            Text(voice.genderLabel)
                            Text("•")
                                .accessibilityHidden(true)
                            Text(voice.displayStyle)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            // Both extra controls (play sample + info) live as VoiceOver
            // rotor actions on the row itself, so a screen-reader user
            // never needs to navigate to the small icons on the right.
            .accessibilityActions {
                Button(isPlaying
                       ? tr(ar: "إيقاف العينة", en: "Stop preview")
                       : tr(ar: "تشغيل عينة من الصوت", en: "Play voice preview"),
                       action: onPlaySample)
                Button(tr(ar: "عرض تفاصيل الصوت", en: "Show voice details"), action: onShowInfo)
            }

            // Visual-only sample button. Tap to start the preview, tap
            // again to stop. Hidden from VoiceOver because the rotor
            // action above does the same job in an a11y-friendly way.
            Button(action: onPlaySample) {
                Group {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                    }
                }
                .foregroundStyle(AppTheme.accent)
                .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)

            // Visual-only info button — same logic.
            Button(action: onShowInfo) {
                Image(systemName: "info.circle")
                    .font(.title3)
                    .foregroundStyle(AppTheme.accent)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }

    private var accessibilityLabelText: String {
        let gender = voice.genderLabel
        let style = voice.displayStyle
        let state = isSelected
            ? tr(ar: "، مُختار حاليّاً", en: ", currently selected")
            : ""
        let playState: String
        if isPlaying {
            playState = tr(ar: "، جاري تشغيل العينة", en: ", preview playing")
        } else if isLoading {
            playState = tr(ar: "، جاري تحميل العينة", en: ", loading preview")
        } else {
            playState = ""
        }
        return "\(voice.displayName)، \(gender)، \(style)\(state)\(playState)"
    }
}

private struct VoiceInfoSheet: View {
    let voice: VoiceCatalog.Voice
    let isPlaying: Bool
    let isLoading: Bool
    let onPlayOfficial: () -> Void
    let onPlayDialect: () -> Void
    let onStop: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                HStack(spacing: AppTheme.Spacing.md) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(AppTheme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(voice.displayName)
                            .font(.title2.bold())
                        Text(voice.genderNoun)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Text(voice.description)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(tr(ar: "الوصف والتصنيف كما تنشرهما Google.", en: "Description and classification as published by Google."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: isPlaying || isLoading ? onStop : onPlayOfficial) {
                        Label(isPlaying || isLoading
                              ? tr(ar: "إيقاف", en: "Stop")
                              : tr(ar: "عينة Google الرسمية", en: "Google's official sample"),
                              systemImage: isPlaying || isLoading ? "stop.fill" : "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)

                    Button(action: onPlayDialect) {
                        Label(tr(ar: "اسمعه بلهجتك (يستخدم مفتاحك)", en: "Hear it in your dialect (uses your key)"),
                              systemImage: "globe")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .disabled(isLoading)
                }

                Spacer()
            }
            .padding(AppTheme.Spacing.lg)
            .navigationTitle(tr(ar: "عن الصوت", en: "About this voice"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(tr(ar: "إغلاق", en: "Close")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Language + dialect picker

struct LanguagePickerView: View {
    @Environment(CustomizationStore.self) private var store

    var body: some View {
        List(LanguageCatalog.languages) { language in
            NavigationLink {
                DialectPickerView(language: language)
            } label: {
                LabeledContent {
                    if language.dialects.contains(where: { $0.id == store.dialectID }) {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                    } else {
                        EmptyView()
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(language.nativeName)
                            .font(.body)
                        if language.englishName != language.nativeName {
                            Text(language.englishName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .accessibilityHint(tr(
                ar: "يفتح قائمة لهجات \(language.displayName)",
                en: "Opens the list of \(language.displayName) dialects"
            ))
        }
        .navigationTitle(tr(ar: "اختر اللغة", en: "Choose language"))
        .toolbarTitleDisplayMode(.inline)
    }
}

struct DialectPickerView: View {
    let language: LanguageCatalog.Language
    @Environment(CustomizationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List(language.dialects) { dialect in
            Button {
                store.dialectID = dialect.id
                dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(dialect.nativeName)
                            .font(.body)
                            .foregroundStyle(.primary)
                        if dialect.englishName != dialect.nativeName {
                            Text(dialect.englishName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if dialect.id == store.dialectID {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(dialect.id == store.dialectID ? [.isButton, .isSelected] : .isButton)
        }
        .navigationTitle(language.nativeName)
        .toolbarTitleDisplayMode(.inline)
    }
}

// MARK: - Preset picker

struct PresetPickerView: View {
    @Environment(CustomizationStore.self) private var store

    var body: some View {
        List(PromptPreset.allCases) { preset in
            Button {
                store.presetID = preset.id
            } label: {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    Image(systemName: iconName(for: preset))
                        .font(.title3)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 28)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(preset.displayTitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text(preset.displaySummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer(minLength: 0)

                    if preset.id == store.presetID {
                        Image(systemName: "checkmark")
                            .foregroundStyle(AppTheme.accent)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(presetA11yLabel(for: preset))
            .accessibilityAddTraits(preset.id == store.presetID ? [.isButton, .isSelected] : .isButton)
        }
        .navigationTitle(tr(ar: "وضع التشغيل", en: "Operating mode"))
        .toolbarTitleDisplayMode(.inline)
    }

    private func presetA11yLabel(for preset: PromptPreset) -> String {
        let suffix = preset.id == store.presetID
            ? tr(ar: "، مُختار حاليّاً.", en: ", currently selected.")
            : ""
        return "\(preset.displayTitle). \(preset.displaySummary)\(suffix)"
    }

    private func iconName(for preset: PromptPreset) -> String {
        switch preset {
        case .defaultNarrator:  return "eye.circle.fill"
        case .biosNavigator:    return "list.bullet.rectangle.fill"
        case .documentReader:   return "text.document.fill"
        case .objectIdentifier: return "cube.transparent.fill"
        case .custom:           return "square.and.pencil"
        }
    }
}

// MARK: - Custom prompt editor

// MARK: - User profile editor

/// Two-state profile screen.
///
///  * **Display mode** (when there's saved data): shows the stored name
///    and gender as read-only rows, plus an "Edit" button and a
///    "Delete" button that asks for confirmation before clearing.
///  * **Edit mode** (when there's no data yet, or after the user taps
///    Edit): shows a form with a name field, gender picker, and a
///    "Save" button that flips the screen back to display mode.
///
/// Tapping "Delete" → confirmation alert → on confirm, clears the
/// stored profile and pops back to the customisation screen.
struct UserProfileEditorView: View {
    @Environment(CustomizationStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private enum Mode { case display, edit }

    @State private var mode: Mode = .display
    @State private var nameDraft: String = ""
    @State private var genderDraft: UserProfile.Gender = .male
    @State private var showDeleteConfirm: Bool = false
    @FocusState private var isNameFocused: Bool

    /// True when at least one field has been filled — used to choose
    /// the initial mode and to gate the "Delete" affordance.
    private var hasSavedData: Bool {
        !store.userName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || store.userGender != .unspecified
    }

    var body: some View {
        Group {
            switch mode {
            case .display: displayMode
            case .edit:    editingForm
            }
        }
        .navigationTitle(tr(ar: "الملف الشخصي", en: "Profile"))
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            nameDraft = store.userName
            // .unspecified isn't a user-facing option anymore — fall back
            // to .male so the segmented picker always has a real value.
            genderDraft = (store.userGender == .unspecified) ? .male : store.userGender
            // First time on this screen: jump straight into the form
            // when there's nothing saved yet, otherwise show the
            // saved-summary view.
            mode = hasSavedData ? .display : .edit
            if mode == .edit {
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    isNameFocused = true
                }
            }
        }
        .alert(
            tr(ar: "تبي تحذف ملفّك الشخصي؟", en: "Delete your profile?"),
            isPresented: $showDeleteConfirm
        ) {
            Button(tr(ar: "حذف", en: "Delete"), role: .destructive) {
                store.userName = ""
                store.userGender = .unspecified
                announce(tr(ar: "تمّ حذف الملف الشخصي", en: "Profile deleted"))
                dismiss()
            }
            Button(tr(ar: "إلغاء", en: "Cancel"), role: .cancel) {}
        } message: {
            Text(tr(
                ar: "راح ينمسح اسمك وجنسك من جهازك. تقدر تضيفهم مرة ثانية في أي وقت.",
                en: "Your name and gender will be removed from this device. You can add them again any time."
            ))
        }
    }

    // MARK: Edit (form) mode

    private var editingForm: some View {
        Form {
            Section {
                TextField(tr(ar: "الاسم (اختياري)", en: "Name (optional)"), text: $nameDraft)
                    .focused($isNameFocused)
                    .submitLabel(.done)
                    .accessibilityLabel(tr(ar: "اسمك", en: "Your name"))
                    .accessibilityHint(tr(
                        ar: "اختياري. Voca تنادك فيه أحياناً",
                        en: "Optional. Voca will call you by it sometimes"
                    ))
            } header: {
                Text(tr(ar: "اسمك", en: "Your name"))
            } footer: {
                Text(tr(
                    ar: "خلّه فاضي لو ما تبي Voca تنادك باسمك.",
                    en: "Leave it blank if you don't want Voca to call you by name."
                ))
            }

            Section {
                // Segmented picker with explicit two options. We avoid
                // an outer .accessibilityLabel here — VoiceOver already
                // announces the selected segment ("ذكر" / "أنثى") on
                // its own, plus the section header ("الجنس") gives the
                // category. A wrapping label caused VoiceOver to read
                // "جنسك جنسك" with no value.
                Picker(selection: $genderDraft) {
                    Text(tr(ar: "ذكر", en: "Male")).tag(UserProfile.Gender.male)
                    Text(tr(ar: "أنثى", en: "Female")).tag(UserProfile.Gender.female)
                } label: {
                    Text(tr(ar: "الجنس", en: "Gender"))
                }
                .pickerStyle(.segmented)
            } header: {
                Text(tr(ar: "الجنس", en: "Gender"))
            } footer: {
                Text(tr(
                    ar: "يستخدم عشان تختار Voca صيغة الخطاب المناسبة. محفوظ على جهازك بس وما يطلع لأي خادم.",
                    en: "Used so Voca picks the right form when speaking to you. Stored on your device only — never sent to any server."
                ))
            }

            Section {
                Button {
                    store.userName = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.userGender = genderDraft
                    announce(tr(ar: "تمّ الحفظ", en: "Saved"))
                    withAnimation { mode = .display }
                } label: {
                    Label(tr(ar: "حفظ", en: "Save"), systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityHint(tr(
                    ar: "يحفظ بياناتك وينقلك لشاشة العرض",
                    en: "Saves your info and switches to the summary view"
                ))
            }
        }
    }

    // MARK: Display mode

    private var displayMode: some View {
        Form {
            Section {
                LabeledContent(tr(ar: "الاسم", en: "Name")) {
                    Text(store.userName.isEmpty
                         ? tr(ar: "غير محدّد", en: "Not set")
                         : store.userName)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)

                LabeledContent(tr(ar: "الجنس", en: "Gender")) {
                    Text(store.userGender.displayLocalised)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            } header: {
                Text(tr(ar: "بياناتك المحفوظة", en: "Saved info"))
            } footer: {
                Text(tr(
                    ar: "هالبيانات محفوظة محلّيّاً على جهازك فقط، وتستخدم لمخاطبتك بالشكل الصحيح.",
                    en: "This info is stored locally on your device only, and is used to address you correctly."
                ))
            }

            Section {
                Button {
                    nameDraft = store.userName
                    genderDraft = (store.userGender == .unspecified) ? .male : store.userGender
                    withAnimation { mode = .edit }
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        isNameFocused = true
                    }
                } label: {
                    Label(tr(ar: "تعديل البيانات", en: "Edit info"), systemImage: "pencil")
                }
                .accessibilityHint(tr(
                    ar: "يفتح شاشة التعديل عشان تغيّر اسمك أو جنسك",
                    en: "Opens the edit screen so you can change your name or gender"
                ))

                // Delete only appears when there is something to delete.
                if hasSavedData {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label(tr(ar: "حذف الملف الشخصي", en: "Delete profile"), systemImage: "trash")
                    }
                    .accessibilityHint(tr(
                        ar: "يطلب تأكيد ثم يمسح اسمك وجنسك ويرجعك للإعدادات",
                        en: "Asks for confirmation, then clears your name and gender and returns to Settings"
                    ))
                }
            }
        }
    }
}

struct CustomPromptEditorView: View {
    @Environment(CustomizationStore.self) private var store
    @State private var draft: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        Form {
            Section {
                TextEditor(text: $draft)
                    .focused($isFocused)
                    .frame(minHeight: 220)
                    .accessibilityLabel(tr(ar: "التعليمات الخاصّة", en: "Custom instructions"))
            } header: {
                Text(tr(ar: "اكتب قواعدك", en: "Write your rules"))
            } footer: {
                Text(tr(
                    ar: "هالتعليمات راح تتمرر لـ Voca وتلتزم فيها بالحرف. مثال: «أنا في شاشة BIOS، اقرأ لي فقط الخيار اللي عليه التحديد لما أتحرك بالأسهم».",
                    en: "These instructions are passed to Voca and followed to the letter. Example: \"I'm on a BIOS screen — only read the highlighted option as I move through it with the arrow keys.\""
                ))
            }

            Section {
                Button(tr(ar: "حفظ التعليمات", en: "Save instructions")) {
                    store.customPrompt = draft
                    announce(tr(ar: "تمّ الحفظ", en: "Saved"))
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button(role: .destructive) {
                    draft = ""
                    store.customPrompt = ""
                } label: {
                    Text(tr(ar: "مسح التعليمات", en: "Clear instructions"))
                }
            }
        }
        .navigationTitle(tr(ar: "التعليمات الخاصّة", en: "Custom instructions"))
        .toolbarTitleDisplayMode(.inline)
        .onAppear {
            draft = store.customPrompt
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                isFocused = true
            }
        }
    }
}
