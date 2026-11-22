import Foundation

public struct CompiledFault: Sendable, Equatable {
    public var fault: Fault
    public var position: CheckPosition
    public var expr: Expr
}

public struct ReadyPose: Sendable, Equatable {
    public var expr: Expr
    public var durationMs: Int
}

/// A validated rule pack with every expression parsed against its metrics.
public struct LoadedRulePack: Sendable, Equatable {
    public var pack: RulePack
    public var faults: [CompiledFault]
    public var readyPose: ReadyPose
}

/// What the running pose pipeline can provide (specs/03). Without
/// capabilities only the schema and expressions are checked (as the source).
public struct PoseCapabilities: Sendable, Equatable {
    public var skeleton: Skeleton
    /// World (3D) landmarks are available (H1, specs/03).
    public var worldAvailable: Bool

    public init(skeleton: Skeleton, worldAvailable: Bool) {
        self.skeleton = skeleton
        self.worldAvailable = worldAvailable
    }

    public static let mediapipe33 = PoseCapabilities(skeleton: .mediapipe33, worldAvailable: true)
    /// Default plan H2: Vision 2D only.
    public static let vision19TwoD = PoseCapabilities(skeleton: .vision19, worldAvailable: false)
}

public enum RulePackLoader {
    /// Validates a rule pack and parses every expression (source
    /// `safeLoadRulePack`, ref AC-4.1). With `capabilities`, also rejects
    /// templates the skeleton cannot serve: `unsupported_landmark` (AC-3.5) and
    /// `world_unavailable` (specs/03 "Koordinat dönüşümü").
    public static func load(_ json: JSONValue, capabilities: PoseCapabilities? = nil) -> Result<LoadedRulePack, RulePackIssues> {
        let pack: RulePack
        switch RulePackParser.parse(json) {
        case .failure(let issues): return .failure(issues)
        case .success(let p): pack = p
        }

        let metrics = Set(pack.metricNames)
        var issues: [SchemaIssue] = []
        var faults: [CompiledFault] = []
        for (i, fault) in pack.faults.enumerated() {
            do {
                let check = try ExpressionParser.parseCheck(fault.check, metrics: metrics)
                faults.append(CompiledFault(fault: fault, position: check.position, expr: check.expr))
            } catch {
                issues.append(SchemaIssue(path: "faults.\(i).check", message: error.description, code: .expression))
            }
        }
        var readyPose: ReadyPose?
        do {
            let r = try ExpressionParser.parseReadyPose(pack.readyPose, metrics: metrics)
            readyPose = ReadyPose(expr: r.expr, durationMs: r.durationMs)
        } catch {
            issues.append(SchemaIssue(path: "readyPose", message: error.description, code: .expression))
        }

        if let capabilities {
            issues += capabilityIssues(pack, capabilities)
        }

        guard issues.isEmpty, let readyPose else { return .failure(RulePackIssues(issues: issues)) }
        return .success(LoadedRulePack(pack: pack, faults: faults, readyPose: readyPose))
    }

    public static func load(data: Data, capabilities: PoseCapabilities? = nil) -> Result<LoadedRulePack, RulePackIssues> {
        do {
            return load(try JSONValue.parse(data), capabilities: capabilities)
        } catch {
            return .failure(RulePackIssues(issues: [SchemaIssue(path: "", message: error.description)]))
        }
    }

    /// Landmarks are checked after near_/far_ resolution: either side may be
    /// near, so both must exist.
    static func capabilityIssues(_ pack: RulePack, _ capabilities: PoseCapabilities) -> [SchemaIssue] {
        var issues: [SchemaIssue] = []
        let available = capabilities.skeleton.landmarks
        func missing(_ refs: [LandmarkRef]) -> [String] {
            var seen = Set<LandmarkName>()
            return refs.flatMap(\.possibleLandmarks)
                .filter { !available.contains($0) && seen.insert($0).inserted }
                .map(\.rawValue)
        }
        let skeleton = capabilities.skeleton.rawValue
        for metric in pack.metrics {
            let absent = missing(metric.definition.landmarks)
            if !absent.isEmpty {
                issues.append(SchemaIssue(
                    path: "metrics.\(metric.name)",
                    message: "unsupported_landmark: \(absent.joined(separator: ", ")) not in skeleton \(skeleton)",
                    code: .unsupportedLandmark))
            }
            if metric.definition.usesWorld, !capabilities.worldAvailable {
                issues.append(SchemaIssue(
                    path: "metrics.\(metric.name)",
                    message: "world_unavailable: \(metric.definition.functionName) needs world (3D) landmarks",
                    code: .worldUnavailable))
            }
        }
        let absent = missing(pack.camera.minVisibleLandmarks)
        if !absent.isEmpty {
            issues.append(SchemaIssue(
                path: "camera.minVisibleLandmarks",
                message: "unsupported_landmark: \(absent.joined(separator: ", ")) not in skeleton \(skeleton)",
                code: .unsupportedLandmark))
        }
        return issues
    }
}
