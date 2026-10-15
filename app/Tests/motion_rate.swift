import Foundation

@main enum MotionRateTests {
    static func main() {
        for delivery in [30.0, 60, 120] {
            var filter = MotionRateFilter()
            var last = SIMD2<Double>.zero
            for i in 0...Int(delivery) {
                let now = 1 + Double(i) / delivery
                let sampleTime = 1 + floor((now - 1) * 100 + 1e-6) / 100
                last = filter.sample(SIMD2(0.8, -0.4), timestamp: sampleTime, now: now, active: true)
                let duplicate = filter.sample(SIMD2(0.8, -0.4), timestamp: sampleTime, now: now + 0.0001, active: true)
                assert(last == duplicate)
            }
            assert(abs(last.x - 0.8) < 0.001 && abs(last.y + 0.4) < 0.001)
            assert(filter.sample(SIMD2(8, 8), timestamp: 2, now: 2.2, active: true) == .zero)
            assert(filter.sample(SIMD2(8, 8), timestamp: 2.2, now: 2.2, active: false) == .zero)
            assert(filter.sample(SIMD2(0.1, 0.1), timestamp: 2.21, now: 2.21, active: true) == .zero)
            assert(filter.sample(SIMD2(0.1, 0.1), timestamp: 2.22, now: 2.22, active: true).x < 0.1)
            filter.reset()
            assert(filter.sample(SIMD2(8, 8), timestamp: 3, now: 3, active: true) == .zero)
        }
        var filter = MotionRateFilter()
        _ = filter.sample(SIMD2(0.2, 0.1), timestamp: 10, now: 10, active: true)
        _ = filter.sample(SIMD2(0.2, 0.1), timestamp: 10.01, now: 10.01, active: true)
        assert(filter.sample(SIMD2(0.2, 0.1), timestamp: 9, now: 10.02, active: true) == .zero)
        assert(filter.sample(SIMD2(.nan, 0), timestamp: 10.03, now: 10.03, active: true) == .zero)
        assert(MotionRateFilter.axis(0, sensitivity: 1) == 0)
        assert(MotionRateFilter.axis(2, sensitivity: 1) == 1)
        assert(MotionRateFilter.axis(-2, sensitivity: 1) == -1)
        var previous: Float = 0
        for i in 0...10000 {
            let rate = Double(i) / 10000
            let current = MotionRateFilter.axis(rate, sensitivity: 1)
            assert(current >= previous && current - previous < 0.002)
            assert(current == -MotionRateFilter.axis(-rate, sensitivity: 1))
            previous = current
        }
        print("PASS: sensor-clock rate filtering across delivery rates, duplicate/stale/inactive samples, resets and continuous gyro stick mapping.")
    }
}
