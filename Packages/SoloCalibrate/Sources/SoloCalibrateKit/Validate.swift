import Foundation
import SoloEngine

/// `solo-calibrate validate <exercises-dir>` (specs/02 CI, specs/04 AC-4.1).
///
/// - `<dir>/*.json`: this project's templates. Rule pack schema, every
///   expression, file name = `id`, and `howTo` is required (AC-4.8).
/// - `<dir>/source/*.json`: verbatim source templates (c2fe3fd). Same checks
///   except `howTo`, which the source format leaves optional.
/// - Any other JSON (e.g. `reflex/`, `workouts/`) is an error until its
///   validator exists, so a new file kind cannot slip through unchecked.
public struct ValidationReport: Sendable, Equatable {
    public var checkedFiles: [String] = []
    public var errors: [String] = []

    public var isValid: Bool { errors.isEmpty }
}

public enum Validator {
    public static func validate(directory: URL) throws -> ValidationReport {
        var report = ValidationReport()
        let root = directory.standardizedFileURL
        for file in try jsonFiles(in: root) {
            let relative = String(file.path.dropFirst(root.path.count + 1))
            report.checkedFiles.append(relative)
            let parts = relative.split(separator: "/")
            switch parts.count {
            case 1:
                report.errors += validateRulePack(file, relative: relative, requireHowTo: true)
            case 2 where parts[0] == "source":
                report.errors += validateRulePack(file, relative: relative, requireHowTo: false)
            default:
                report.errors.append("\(relative): no validator for this file kind yet")
            }
        }
        return report
    }

    static func validateRulePack(_ file: URL, relative: String, requireHowTo: Bool) -> [String] {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch {
            return ["\(relative): cannot read (\(error.localizedDescription))"]
        }
        switch RulePackLoader.load(data: data) {
        case .failure(let e):
            return e.issues.map { "\(relative): \($0)" }
        case .success(let loaded):
            var errors: [String] = []
            let stem = file.deletingPathExtension().lastPathComponent
            if loaded.pack.id != stem {
                errors.append("\(relative): id '\(loaded.pack.id)' does not match the file name")
            }
            if requireHowTo, loaded.pack.howTo == nil {
                errors.append("\(relative): howTo: required for this project's templates (specs/04 AC-4.8)")
            }
            return errors
        }
    }

    static func jsonFiles(in directory: URL) throws -> [URL] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw CalibrateError.notADirectory(directory.path)
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            throw CalibrateError.notADirectory(directory.path)
        }
        var result: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            result.append(url.standardizedFileURL)
        }
        return result.sorted { $0.path < $1.path }
    }
}

public enum CalibrateError: Error, Equatable, CustomStringConvertible {
    case notADirectory(String)
    case usage(String)

    public var description: String {
        switch self {
        case .notADirectory(let path): "not a directory: \(path)"
        case .usage(let message): message
        }
    }
}
