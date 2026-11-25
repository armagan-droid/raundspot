import SoloCapture
import SoloEngine
import SwiftData
import SwiftUI
import Testing
import UIKit
import Vision
@testable import GymSpotSolo

/// Snapshot tests of what a screen shows: the screen is drawn in a window and its picture is read with Vision's
/// on-device text recognition (no network), in TR and EN.
/// - AC-10.6: the medical notice on the first launch (O2), at every workout's start (S2) and in Settings.
/// - AC-8.7: every calorie display (Y1's `EnergyEstimate`, the only one) says "estimate".
@MainActor @Suite(.serialized) struct ScreenTextTests {
    nonisolated static let languages = ["tr", "en"]

    /// The words a screen shows, lower-cased, read from its picture.
    static func shownText<V: SwiftUI.View>(_ view: V, language: String, size: CGSize = CGSize(width: 393, height: 852)) async throws -> String {
        let container = try SoloStore.container(inMemory: true)
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: language)).modelContainer(container))
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: size)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(400))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let cg = try #require(image.cgImage)
        if let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] {
            try? image.pngData()?.write(to: URL(fileURLWithPath: dir).appendingPathComponent("screen-\(V.self)-\(language).png".replacingOccurrences(of: "<", with: "_").replacingOccurrences(of: ">", with: "_").replacingOccurrences(of: " ", with: "")))
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = [language == "tr" ? "tr-TR" : "en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: " ").lowercased(with: Locale(identifier: language))
        // a key shown instead of its text (an interpolated `LocalizedStringKey` looks up the wrong key)
        #expect(text.range(of: #"\b[a-z]+\.[a-z_]+\.[a-z0-9_]+\b"#, options: .regularExpression) == nil, "raw key on screen [\(language)]: \(text)")
        return text
    }

    static func medical(_ language: String) -> String { language == "tr" ? "tıbbi tavsiye değildir" : "not medical advice" }

    @Test(arguments: languages) func firstLaunchShowsTheMedicalNotice(_ language: String) async throws {
        let text = try await Self.shownText(OnboardingView(step: .safety), language: language)
        #expect(text.contains(Self.medical(language)), "O2 [\(language)]: \(text)")
    }

    @Test(arguments: languages) func workoutStartShowsTheMedicalNotice(_ language: String) async throws {
        let clock = ManualClock()
        let source = SequenceFrameSource(sequence: try FakeCameraTests.slips(), clock: clock)
        let model = TrainingModel(single: try #require(ExerciseCatalog.pack("slip_left")), source: source, clock: clock)
        defer { model.close() }
        #expect(!model.spaceConfirmed)
        let text = try await Self.shownText(TrainingView(model), language: language)
        #expect(text.contains(Self.medical(language)), "S2 [\(language)]: \(text)")
    }

    @Test(arguments: languages) func settingsShowTheMedicalNotice(_ language: String) async throws {
        let text = try await Self.shownText(SettingsView(), language: language, size: CGSize(width: 393, height: 1600))
        #expect(text.contains(Self.medical(language)), "A [\(language)]: \(text)")
    }

    @Test(arguments: languages) func caloriesAreAlwaysAnEstimate(_ language: String) async throws {
        let text = try await Self.shownText(VStack { EnergyEstimate(kcal: 237) }.padding(), language: language)
        #expect(text.contains("kcal") && text.contains(language == "tr" ? "tahmin" : "estimate"), "Y1 [\(language)]: \(text)")
    }
}
