import Foundation
import SoloEngine

/// Entry point logic, separated from `main.swift` so it can be tested.
public enum CLI {
    public static let usage = """
        usage: solo-calibrate validate <dir>
               solo-calibrate report --files <dir> [--sweep <path>=<v1>,<v2>,...]
               solo-calibrate --version
        """

    /// Runs the tool and returns the process exit code.
    public static func run(_ arguments: [String], output: (String) -> Void) -> Int32 {
        guard let command = arguments.first else {
            output(usage)
            return 2
        }
        do {
            switch command {
            case "validate":
                guard arguments.count == 2 else { throw CalibrateError.usage(usage) }
                let directory = URL(fileURLWithPath: arguments[1], isDirectory: true)
                let report = try Validator.validate(directory: directory)
                for error in report.errors { output("error: \(error)") }
                output("checked \(report.checkedFiles.count) JSON file(s): \(report.isValid ? "OK" : "\(report.errors.count) error(s)")")
                return report.isValid ? 0 : 1
            case "report":
                throw CalibrateError.notImplemented(command: "report", task: "T2.9")
            case "--version":
                output(SoloEngine.generatedBy)
                return 0
            default:
                throw CalibrateError.usage(usage)
            }
        } catch let error as CalibrateError {
            output("error: \(error.description)")
            return 2
        } catch {
            output("error: \(error.localizedDescription)")
            return 2
        }
    }
}
