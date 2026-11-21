import Foundation

/// `solo-calibrate validate <dir>`.
///
/// T0.1 scope: every `*.json` file under the directory (recursively) must be
/// well-formed JSON. Full rule pack and catalog schema validation (unknown fields,
/// undefined or cyclic metrics, `unsupported_landmark`) is added in T2.1
/// (specs/03 AC-3.4, AC-3.5; specs/04 AC-4.1).
public struct ValidationReport: Sendable, Equatable {
    public var checkedFiles: [String] = []
    public var errors: [String] = []

    public var isValid: Bool { errors.isEmpty }
}

public enum Validator {
    public static func validate(directory: URL) throws -> ValidationReport {
        var report = ValidationReport()
        let files = try jsonFiles(in: directory)
        for file in files {
            let relative = file.path.replacingOccurrences(of: directory.path + "/", with: "")
            report.checkedFiles.append(relative)
            do {
                let data = try Data(contentsOf: file)
                _ = try JSONSerialization.jsonObject(with: data)
            } catch {
                report.errors.append("\(relative): invalid JSON (\(error.localizedDescription))")
            }
        }
        return report
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
    case notImplemented(command: String, task: String)

    public var description: String {
        switch self {
        case .notADirectory(let path): "not a directory: \(path)"
        case .usage(let message): message
        case .notImplemented(let command, let task): "'\(command)' is not implemented yet (specs/14 \(task))"
        }
    }
}
