import Foundation

/// Consumes the sensor's clock, not the number or timing of UI/touch polls.
struct MotionRateFilter {
    private var lastTimestamp: Double?
    private var filtered = SIMD2<Double>.zero

    mutating func reset() { lastTimestamp = nil; filtered = .zero }

    mutating func sample(_ rate: SIMD2<Double>, timestamp: Double, now: Double, active: Bool) -> SIMD2<Double> {
        guard active, timestamp.isFinite, now.isFinite, rate.x.isFinite, rate.y.isFinite,
              now - timestamp >= -0.005, now - timestamp <= 0.1 else {
            reset(); return .zero
        }
        guard let last = lastTimestamp else { lastTimestamp = timestamp; return .zero }
        guard timestamp >= last else { reset(); return .zero }
        if timestamp == last { return filtered }
        let dt = min(timestamp - last, 0.05)
        lastTimestamp = timestamp
        // Fast turns remain responsive; slow corrections receive a little more
        // filtering. Exponential smoothing has the same time constant at 30/120 Hz.
        let speed = hypot(rate.x, rate.y)
        let blend = min(1, max(0, (speed - 0.035) / 0.105))
        let tau = 0.020 - 0.012 * blend
        let alpha = 1 - exp(-dt / tau)
        filtered += (rate - filtered) * alpha
        return filtered
    }

    /// Gyro-specific curve, continuous through zero. The short ramp compensates
    /// the game's stick dead zone without the touch drag's hard velocity cutoff.
    /// The engine still quantizes its virtual stick to eight bits.
    static func axis(_ rate: Double, sensitivity: Double) -> Float {
        guard rate.isFinite, sensitivity.isFinite else { return 0 }
        let magnitude = min(1, abs(rate) * max(0, sensitivity) / 2)
        let result = 0.24 * min(1, magnitude / 0.008) + 0.76 * magnitude
        return Float(copysign(min(1, result), rate))
    }
}
