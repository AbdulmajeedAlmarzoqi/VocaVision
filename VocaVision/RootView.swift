import SwiftUI

struct RootView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var selectedTab: Tab = .home

    enum Tab: Hashable {
        case home, settings
    }

    var body: some View {
        if hasCompletedOnboarding {
            mainTabs
                .transition(.opacity)
        } else {
            OnboardingView {
                withAnimation(.easeInOut) {
                    hasCompletedOnboarding = true
                }
            }
            .transition(.opacity)
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            SwiftUI.Tab(tr(ar: "الرئيسية", en: "Home"), systemImage: "video.circle.fill", value: Tab.home) {
                HomeView()
            }
            SwiftUI.Tab(tr(ar: "الإعدادات", en: "Settings"), systemImage: "gearshape.fill", value: Tab.settings) {
                SettingsView()
            }
        }
    }
}
