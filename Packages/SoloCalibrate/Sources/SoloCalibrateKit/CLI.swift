import Foundation
import SoloEngine

/// Entry point logic, separated from `main.swift` so it can be tested.
public enum CLI {
    public static let usage = """
        usage: solo-calibrate validate <dir>
               solo-calibrate report --files <dir> [--rules <dir>] [--exercise <id>] [--sweep <path>=<v1>,<v2>,...]
               solo-calibrate suggest --files <dir> --rules <dir> --exercise <id> [--out <file>]
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
                output(try Report.run(reportOptions(Array(arguments.dropFirst()))))
                return 0
            case "suggest":
                let o = try options(Array(arguments.dropFirst()), allowed: ["--files", "--rules", "--exercise", "--out"])
                guard let files = o["--files"], let rules = o["--rules"], let exercise = o["--exercise"] else { throw CalibrateError.usage(usage) }
                output(try Suggest.run(files: URL(fileURLWithPath: files, isDirectory: true), rules: URL(fileURLWithPath: rules, isDirectory: true),
                                       exercise: exercise, out: o["--out"].map { URL(fileURLWithPath: $0) }))
                return 0
            case "--version":
                output(SoloEngine.generatedBy)
                return 0
            default:
                throw CalibrateError.usage(usage)
            }
        } catch let error as CalibrationError {
            output("error: \(error.description)")
            return 1
        } catch let error as ReportError {
            output("error: \(error.description)")
            return 1
        } catch let error as SuggestError {
            output("error: \(error.description)")
            return 1
        } catch let error as CalibrateError {
            output("error: \(error.description)")
            return 2
        } catch {
            output("error: \(error.localizedDescription)")
            return 2
        }
    }

    /// `--key value` pairs, each key once and only from `allowed`.
    static func options(_ args: [String], allowed: [String]) throws -> [String: String] {
        var values: [String: String] = [:]
        var i = 0
        while i < args.count {
            let key = args[i]
            guard allowed.contains(key), i + 1 < args.count, values[key] == nil else { throw CalibrateError.usage(usage) }
            values[key] = args[i + 1]
            i += 2
        }
        return values
    }

    /// `--files <dir> [--rules <dir>] [--exercise <id>] [--sweep <spec>]`; rules default to `exercises`.
    static func reportOptions(_ args: [String]) throws -> ReportOptions {
        let values = try options(args, allowed: ["--files", "--rules", "--exercise", "--sweep"])
        guard let files = values["--files"] else { throw CalibrateError.usage(usage) }
        return ReportOptions(files: URL(fileURLWithPath: files, isDirectory: true),
                             rules: URL(fileURLWithPath: values["--rules"] ?? "exercises", isDirectory: true),
                             exercise: values["--exercise"], sweep: values["--sweep"])
    }
}
