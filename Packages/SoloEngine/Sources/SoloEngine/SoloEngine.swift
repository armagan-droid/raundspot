import Foundation

/// Namespace and version of the Swift rule engine (specs/03).
///
/// The engine is built up task by task (specs/14, T2.x). Snapshots written by the
/// engine record `generatedBy: "SoloEngine <version>"` (specs/03 "Yeni davranış").
public enum SoloEngine {
    public static let version = "0.0.1"

    /// Value written to the `generatedBy` field of snapshot fixtures.
    public static var generatedBy: String { "SoloEngine \(version)" }
}
