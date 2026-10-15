import CoreMotion
import UIKit

/// Optional gyro look. Phone rotation adds camera movement on top of touch,
/// for the fine corrections a thumb cannot make.
enum GyroAimMode: Int, CaseIterable {
    case off, whileAiming, always
    var title: String {
        [String(localized: "Off", table: "Settings"),
         String(localized: "While aiming", table: "Settings"),
         String(localized: "Always on foot", table: "Settings")][rawValue]
    }
}

/// Optional tilt steering for ground vehicles.
enum TiltSteerMode: Int, CaseIterable {
    case off, assist, full
    var title: String {
        [String(localized: "Off", table: "Settings"),
         String(localized: "Assist", table: "Settings"),
         String(localized: "Tilt to steer", table: "Settings")][rawValue]
    }
}

/// Pull the latest processed motion sample on the display/input thread. There
/// is no operation-queue backlog and no accumulated turn to replay after a modal.
final class GyroInput {
    private let motion = CMMotionManager()
    private var filter = MotionRateFilter()
    private var orientation = UIInterfaceOrientation.landscapeRight
    private var startedAt: TimeInterval = 0

    var available: Bool { motion.isDeviceMotionAvailable }

    func setRunning(_ running: Bool, orientation: UIInterfaceOrientation) {
        if self.orientation != orientation {
            self.orientation = orientation
            filter.reset()
            startedAt = ProcessInfo.processInfo.systemUptime
        }
        guard available else { return }
        if running, !motion.isDeviceMotionActive {
            filter.reset()
            startedAt = ProcessInfo.processInfo.systemUptime
            motion.deviceMotionUpdateInterval = 1.0 / 120.0
            motion.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        } else if !running {
            if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
            filter.reset()
            startedAt = 0
        }
    }

    private var freshSample: CMDeviceMotion? {
        guard motion.isDeviceMotionActive, let sample = motion.deviceMotion,
              sample.timestamp >= startedAt,
              ProcessInfo.processInfo.systemUptime - sample.timestamp <= 0.1 else { return nil }
        return sample
    }

    func rate(active: Bool, elapsed: Double) -> CGVector {
        guard let sample = freshSample else { filter.reset(); return .zero }
        let rate = sample.rotationRate, gravity = sample.gravity
        let g = sqrt(gravity.x * gravity.x + gravity.y * gravity.y + gravity.z * gravity.z)
        let yaw = g > 0.1 ? (rate.x * gravity.x + rate.y * gravity.y + rate.z * gravity.z) / g : 0
        let pitch = orientation == .landscapeRight ? rate.y : -rate.y
        let value = filter.sample(SIMD2(yaw, pitch), timestamp: sample.timestamp,
                                  now: ProcessInfo.processInfo.systemUptime, active: active)
        return CGVector(dx: value.x, dy: value.y)
    }

    /// Steering-wheel angle, positive clockwise. Fresh gravity only; stopped
    /// sessions and orientation changes cannot reuse a previous neutral pose.
    func steeringAngle() -> Double? {
        guard let g = freshSample?.gravity else { return nil }
        let screenX = orientation == .landscapeRight ? -g.y : g.y
        let screenY = orientation == .landscapeRight ? g.x : -g.x
        guard hypot(screenX, screenY) > 0.3 else { return nil }
        return atan2(screenX, -screenY)
    }
}
