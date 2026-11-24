import SwiftData
import SwiftUI

@main
struct GymSpotSoloApp: App {
    /// The local store (specs/11). If it cannot be opened the app still runs, without history.
    let store: ModelContainer = {
        do {
            return try SoloStore.container()
        } catch {
            assertionFailure("store: \(error)")
            return try! SoloStore.container(inMemory: true)
        }
    }()

    init() {
        #if RECORDING_MODE
        RecordingFeature.link()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(store)
    }
}
