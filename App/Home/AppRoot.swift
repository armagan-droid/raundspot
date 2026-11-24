import SwiftData
import SwiftUI

enum AppStart {
    /// Onboarding until the adult confirmation is stored (specs/12 O2, specs/10 "Yaş").
    static func needsOnboarding(profiles: [Profile]) -> Bool { profiles.first?.adultConfirmedAt == nil }
}

/// The first launch (O1–O9), then the tabs: Antrenman · İlerleme · Ayarlar (specs/12 "Gezinme").
struct AppRoot: SwiftUI.View {
    @Query private var profiles: [Profile]

    var body: some SwiftUI.View {
        if AppStart.needsOnboarding(profiles: profiles) {
            OnboardingView()
        } else {
            TabView {
                RootView().tabItem { Label("tab.training", systemImage: "figure.boxing") }
                ProgressHome().tabItem { Label("tab.progress", systemImage: "chart.line.uptrend.xyaxis") }
                SettingsView().tabItem { Label("tab.settings", systemImage: "gearshape") }
            }
        }
    }
}
