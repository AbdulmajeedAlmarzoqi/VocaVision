import SwiftUI

@main
struct VocaVisionApp: App {
    @AppStorage(AppStorageKey.hasCompletedOnboarding) private var hasCompletedOnboarding: Bool = false

    @State private var apiKeyStore = APIKeyStore()
    @State private var customizationStore = CustomizationStore()

    var body: some Scene {
        WindowGroup {
            RootView(hasCompletedOnboarding: $hasCompletedOnboarding)
                .environment(apiKeyStore)
                .environment(customizationStore)
                .tint(AppTheme.accent)
                // Google's voice table (names, styles, gender, samples) is
                // refreshed from Google's server at most once a day.
                .task { await VoiceDirectory.shared.refreshIfStale() }
        }
    }
}

enum AppStorageKey {
    static let hasCompletedOnboarding = "hasCompletedOnboarding.v2"
}
