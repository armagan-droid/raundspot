import SwiftUI
import Testing
import UIKit
@testable import GymSpotSolo

/// AC-12.1, AC-12.2 (specs/12 "Sayaç ve saldırı adının boyutu"): on the smallest and the largest iPhone, in both
/// orientations, the T2 counter's line is ≥ 25 % of the screen height and the R2 strike name's ≥ 20 %, and neither
/// overflows. With `SNAPSHOT_DIR` set the screens are also written as PNGs to look at.
@MainActor @Suite struct LiveLayoutTests {
    /// iPhone SE (375×667) and the largest iPhone (440×956), portrait and landscape.
    static let screens: [CGSize] = [CGSize(width: 375, height: 667), CGSize(width: 440, height: 956)]
        .flatMap { [$0, CGSize(width: $0.height, height: $0.width)] }

    static func idealSize<V: SwiftUI.View>(_ v: V) -> CGSize {
        UIHostingController(rootView: v).sizeThatFits(in: CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
    }

    /// Every strike text the cue can show, in both languages.
    static func strikeTexts() throws -> [String] {
        var out: Set<String> = []
        for lang in ["en", "tr"] {
            for (k, v) in try StringCatalogTests.compiledStrings(table: "Localizable", language: lang)
            where k.hasPrefix("strike.") && !k.hasPrefix("strike.name.") { out.insert(v) }
        }
        return out.sorted()
    }

    @Test func counterIsAQuarterOfTheHeightAndFits() {
        for screen in Self.screens {
            for target in [nil, 5, 8, 10, 12, 20, 30] as [Int?] {
                for counted in 0...(target ?? 120) {
                    let l = LiveText.counter(counted: counted, target: target, screen: screen)
                    let line = Self.idealSize(Text(verbatim: l.main).font(Font(l.font)).fixedSize())
                    #expect(line.height >= screen.height * LiveText.counterRatio - 0.5, "\(screen) \(counted)/\(target ?? 0): \(line)")
                    let all = Self.idealSize(CounterText(counted: counted, target: target, screen: screen))
                    #expect(all.width <= LiveText.usableWidth(screen: screen) && all.height <= screen.height,
                            "\(screen) \(counted)/\(target ?? 0) overflows: \(all)")
                    // "x/target" is shown whole: on one line, or the target under the count
                    #expect(target == nil || l.main == "\(counted)/\(target!)" || l.target == "/\(target!)")
                }
            }
        }
    }

    @Test func strikeNameIsAFifthOfTheHeightAndFits() throws {
        let texts = try Self.strikeTexts()
        #expect(texts.contains("Sol kroşe!") && texts.contains("Right hook!"))
        for screen in Self.screens {
            for text in texts {
                let l = LiveText.strike(text, screen: screen)
                #expect(l.lines.count <= 2 && l.lines.joined(separator: " ") == text)
                for line in l.lines {
                    let size = Self.idealSize(Text(verbatim: line).font(Font(l.font)).fixedSize())
                    #expect(size.height >= screen.height * LiveText.strikeRatio - 0.5, "\(screen) \(line): \(size)")
                }
                let all = Self.idealSize(StrikeText(text: text, screen: screen))
                #expect(all.width <= LiveText.usableWidth(screen: screen) && all.height <= screen.height, "\(screen) \(text) overflows: \(all)")
            }
        }
    }

    /// PNGs of the counter and the longest strike name on every screen, for a human look (not compared).
    @Test func writesSnapshotsWhenAsked() throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"].map({ URL(fileURLWithPath: $0) }) else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let longest = try Self.strikeTexts().max { $0.count < $1.count } ?? ""
        for screen in Self.screens {
            let view = ZStack {
                Color.black
                VStack { HStack { Spacer(); CounterText(counted: 10, target: 10, screen: screen).padding(.trailing, LiveText.margin) }; Spacer() }
                StrikeText(text: longest, screen: screen)
            }
            .foregroundStyle(.white)
            .frame(width: screen.width, height: screen.height)
            let r = ImageRenderer(content: view)
            r.scale = 2
            let png = try #require(r.uiImage?.pngData())
            try png.write(to: dir.appendingPathComponent("live-\(Int(screen.width))x\(Int(screen.height)).png"))
        }
    }
}
