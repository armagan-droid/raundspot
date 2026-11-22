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
