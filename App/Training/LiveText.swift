import SwiftUI
import UIKit

/// The T2 counter and the R2 strike name (specs/12 "Sayaç ve saldırı adının boyutu", AC-12.1, AC-12.2): the system
/// font's compressed width, sized by line height against the full screen height, laid out so that it never overflows.
enum LiveText {
    /// Line height / full screen height (AC-12.2).
    static let counterRatio: CGFloat = 0.25
    static let strikeRatio: CGFloat = 0.20
    /// The "/target" under the count when both do not fit on one line.
    static let targetRatio: CGFloat = 0.08
    static let margin: CGFloat = 24
    /// The safe area at each side of a landscape iPhone (the largest, Dynamic Island).
    static let landscapeSideInset: CGFloat = 62

    /// The font whose line height is at least `lineHeight`.
    static func font(lineHeight: CGFloat) -> UIFont {
        let probe = UIFont.systemFont(ofSize: 100, weight: .heavy, width: .compressed)
        return UIFont.systemFont(ofSize: (lineHeight / probe.lineHeight * 100).rounded(.up), weight: .heavy, width: .compressed)
    }

    static func width(_ s: String, _ f: UIFont) -> CGFloat { (s as NSString).size(withAttributes: [.font: f]).width.rounded(.up) }

    /// The width text can use: the screen less the side safe areas (landscape) and the margins.
    static func usableWidth(screen: CGSize) -> CGFloat {
        screen.width - (screen.width > screen.height ? 2 * landscapeSideInset : 0) - 2 * margin
    }

    struct Counter {
        var main: String
        /// "/target" on its own line, or nil when "x/target" fits on one.
        var target: String?
        var font: UIFont
        var targetFont: UIFont
    }

    static func counter(counted: Int, target: Int?, screen: CGSize) -> Counter {
        let f = font(lineHeight: screen.height * counterRatio), small = font(lineHeight: screen.height * targetRatio)
        guard let target else { return Counter(main: "\(counted)", target: nil, font: f, targetFont: small) }
        let full = "\(counted)/\(target)"
        if width(full, f) <= usableWidth(screen: screen) { return Counter(main: full, target: nil, font: f, targetFont: small) }
        return Counter(main: "\(counted)", target: "/\(target)", font: f, targetFont: small)
    }

    /// One line when it fits, else two lines split at the word boundary that keeps the wider line narrowest.
    static func strike(_ text: String, screen: CGSize) -> (lines: [String], font: UIFont) {
        let f = font(lineHeight: screen.height * strikeRatio)
        let words = text.split(separator: " ").map(String.init)
        guard width(text, f) > usableWidth(screen: screen), words.count > 1 else { return ([text], f) }
        let splits = (1..<words.count).map { i in [words[..<i].joined(separator: " "), words[i...].joined(separator: " ")] }
        return (splits.min { $0.map { width($0, f) }.max()! < $1.map { width($0, f) }.max()! }!, f)
    }
}

/// T2's large counter (x / target).
struct CounterText: SwiftUI.View {
    let counted: Int
    let target: Int?
    let screen: CGSize

    var body: some SwiftUI.View {
        let l = LiveText.counter(counted: counted, target: target, screen: screen)
        VStack(alignment: .trailing, spacing: 0) {
            Text(verbatim: l.main).font(Font(l.font))
            if let t = l.target { Text(verbatim: t).font(Font(l.targetFont)) }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// R2's strike name at the cue.
struct StrikeText: SwiftUI.View {
    let text: String
    let screen: CGSize

    var body: some SwiftUI.View {
        let l = LiveText.strike(text, screen: screen)
        VStack(spacing: 0) {
            ForEach(Array(l.lines.enumerated()), id: \.offset) { _, line in Text(verbatim: line).font(Font(l.font)) }
        }
        .lineLimit(1)
        .fixedSize()
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}
