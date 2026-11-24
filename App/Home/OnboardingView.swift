import AVFoundation
import SoloCapture
import SwiftData
import SwiftUI

/// First launch (specs/12 O1–O7, O9; O8 is v1.0). The health questions' answers stay in this view
/// and are never stored (specs/10, AC-10.7); only that they were shown is.
struct OnboardingView: SwiftUI.View {
    enum Step: Int, CaseIterable { case welcome, safety, stance, level, weight, health, camera, first }

    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var step = Step.welcome
    @State private var adult = false
    @State private var answers: [Bool?] = [nil, nil, nil]
    @State private var stance = "orthodox"
    @State private var years = "beginner"
    @State private var goal = "balanced"
    @State private var weightText = ""
    @State private var cameraAsked = false

    var body: some SwiftUI.View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) { page }
                    .padding(24)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            .safeAreaInset(edge: .bottom) { footer.padding() }
        }
    }

    @ViewBuilder private var page: some SwiftUI.View {
        switch step {
        case .welcome:
            Text(AppBrand.name).font(.largeTitle.bold())
            Text("onboarding.welcome.line").font(.title3)
            Button("onboarding.language") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .safety:
            Text("onboarding.safety.title").font(.title.bold())
            Label("onboarding.safety.camera", systemImage: "lock.shield")
            Label("training.safety.medical", systemImage: "cross.case")
            Toggle("onboarding.safety.adult", isOn: $adult)
            Text("onboarding.health.title").font(.headline)
            ForEach(0..<3, id: \.self) { i in
                VStack(alignment: .leading) {
                    Text(LocalizedStringKey("onboarding.health.q\(i + 1)"))
                    Picker("", selection: $answers[i]) {
                        Text("onboarding.no").tag(Bool?.some(false))
                        Text("onboarding.yes").tag(Bool?.some(true))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel(Text(LocalizedStringKey("onboarding.health.q\(i + 1)")))
                }
            }
            if answers.contains(true) { Text("onboarding.health.advice").font(.callout.bold()).foregroundStyle(.orange) }
        case .stance:
            Text("onboarding.stance.title").font(.title.bold())
            Picker("onboarding.stance.title", selection: $stance) {
                Text("stance.orthodox").tag("orthodox")
                Text("stance.southpaw").tag("southpaw")
            }
            .pickerStyle(.inline)
            Button("onboarding.stance.unsure") { stance = "orthodox" }
            Text("onboarding.stance.later").font(.caption).foregroundStyle(.secondary)
        case .level:
            Text("onboarding.level.title").font(.title.bold())
            Picker("onboarding.level.title", selection: $years) {
                Text("level.beginner").tag("beginner")
                Text("level.intermediate").tag("intermediate")
                Text("level.advanced").tag("advanced")
            }
            .pickerStyle(.inline)
            Text("onboarding.goal.title").font(.headline)
            Picker("onboarding.goal.title", selection: $goal) {
                Text("goal.defense").tag("defense")
                Text("goal.conditioning").tag("conditioning")
                Text("goal.balanced").tag("balanced")
            }
            .pickerStyle(.inline)
        case .weight:
            Text("onboarding.weight.title").font(.title.bold())
            Text("onboarding.weight.why").font(.callout)
            TextField("onboarding.weight.placeholder", text: $weightText).keyboardType(.decimalPad).textFieldStyle(.roundedBorder)
        case .health:
            Text("onboarding.healthkit.title").font(.title.bold())
            Text("onboarding.healthkit.body").font(.callout)
            Text("onboarding.healthkit.later").font(.caption).foregroundStyle(.secondary)
        case .camera:
            Text("onboarding.camera.title").font(.title.bold())
            Text("onboarding.camera.body").font(.callout)
            Button("onboarding.camera.allow") {
                Task {
                    _ = await CameraSession.requestAccess()
                    cameraAsked = true
                }
            }
            .buttonStyle(.borderedProminent)
            if cameraAsked, AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
                Text("training.camera.denied").font(.callout).foregroundStyle(.orange)
            }
        case .first:
            Text("onboarding.first.title").font(.title.bold())
            Text("onboarding.first.body").font(.callout)
        }
    }

    private var canGoOn: Bool {
        switch step {
        case .safety: adult && !answers.contains(nil)
        case .weight: weightText.isEmpty || weight != nil
        default: true
        }
    }

    private var weight: Double? {
        Double(weightText.replacingOccurrences(of: ",", with: ".")).flatMap { (30...300).contains($0) ? $0 : nil }
    }

    private var footer: some SwiftUI.View {
        HStack {
            if step.rawValue > 0 { Button("onboarding.back") { step = Step(rawValue: step.rawValue - 1)! } }
            Spacer()
            if step == .weight || step == .health {
                Button("onboarding.not_now") { next() }
            }
            Button(step == .first ? "onboarding.finish" : "onboarding.next") { next() }
                .buttonStyle(.borderedProminent)
                .disabled(!canGoOn)
        }
        .frame(minHeight: 44)
    }

    private func next() {
        if let n = Step(rawValue: step.rawValue + 1) { step = n } else { finish() }
    }

    /// The profile, with what was confirmed; the health answers are not part of it (AC-10.7).
    private func finish() {
        let now = Date()
        let p = (try? context.fetch(FetchDescriptor<Profile>()).first) ?? {
            let p = Profile(createdAt: now)
            context.insert(p)
            return p
        }()
        p.stance = stance
        p.level = years
        p.goal = goal
        p.weightKg = weight
        p.adultConfirmedAt = now
        p.disclaimerShownVersion = 1
        p.healthScreeningShownAt = now
        try? context.save()
    }
}
