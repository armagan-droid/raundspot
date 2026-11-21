import SwiftUI

@main
struct GymSpotSoloApp: App {
    init() {
        #if RECORDING_MODE
        RecordingFeature.link()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
