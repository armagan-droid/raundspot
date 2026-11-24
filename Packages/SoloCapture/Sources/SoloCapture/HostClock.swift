import Foundation

/// The single clock (specs/02 "Saat tabanı"): mach host time in milliseconds.
public enum HostClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static func ms(fromHostTicks ticks: UInt64) -> Double {
        Double(ticks) * Double(timebase.numer) / Double(timebase.denom) / 1e6
    }

    public static var nowMs: Double { ms(fromHostTicks: mach_absolute_time()) }

    /// The inverse of `ms(fromHostTicks:)`: a host time for scheduling audio (`AVAudioTime(hostTime:)`, specs/02).
    public static func hostTicks(fromMs ms: Double) -> UInt64 {
        UInt64((ms * 1e6 * Double(timebase.denom) / Double(timebase.numer)).rounded())
    }
}

/// Frames per second over a sliding window, and dropped frames (specs/02 "Tanı paneli").
public struct FrameRateMeter: Sendable, Equatable {
    public var windowMs: Double
    private var times: [Double] = []

    public init(windowMs: Double = 1000) {
        self.windowMs = windowMs
    }

    public mutating func record(_ tMs: Double) {
        times.append(tMs)
        times.removeAll { $0 < tMs - windowMs }
    }

    public var fps: Double {
        guard let first = times.first, let last = times.last, times.count > 1, last > first else { return 0 }
        return Double(times.count - 1) / ((last - first) / 1000)
    }
}

/// The time source the app runs on (specs/02 "Saat tabanı", AC-2.2): the host
/// clock live, a manual clock in tests and the Debug fake camera.
public protocol SoloClock: AnyObject, Sendable {
    /// Host time, ms.
    var nowMs: Double { get }
}

public final class LiveClock: SoloClock {
    public static let shared = LiveClock()
    public init() {}
    public var nowMs: Double { HostClock.nowMs }
}

/// A clock that moves only when told to.
public final class ManualClock: SoloClock, @unchecked Sendable {
    private let lock = NSLock()
    private var t: Double

    public init(startMs: Double = 1_000_000) { t = startMs }

    public var nowMs: Double { lock.withLock { t } }

    public func advance(byMs ms: Double) {
        precondition(ms >= 0, "time does not go back")
        lock.withLock { t += ms }
    }
}
