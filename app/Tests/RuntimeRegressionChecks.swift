// Compiled only by verify_ui_launch.sh, never linked into a shipping IPA.
import UIKit
import QuartzCore

enum RuntimeRegressionChecks {
    static var scenario: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--verify-runtime-regressions"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }
    static func prepare() {
        guard let scenario else { return }
        GameSettings.shared.frameRateCap = scenario == "unlocked" ? 60 : 0
        GameSettings.shared.gameMode = .sandbox
        PGUISmokeRuntimeState(0, true)
    }
    static func schedule(on root: UIViewController) {
        guard let scenario else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            // Read private storage without introducing production test accessors.
            let fields = Dictionary(uniqueKeysWithValues: Mirror(reflecting: root).children.compactMap { child in
                child.label.map { ($0, child.value) }
            })
            var failures: [String] = []
            func check(_ condition: Bool, _ name: String) { if !condition { failures.append(name) } }
            let touch = fields["touchControls"] as! UIView
            let output = fields["output"] as! UITextView
            let display = fields["displayLink"] as! CADisplayLink?
            check(output.isHidden, "Release startup console is visible")
            GameSettings.shared.frameRateCap = scenario == "unlocked" ? 0 : 30
            root.perform(NSSelectorFromString("startEngine"))
            let top = Float(root.view.window!.windowScene!.screen.maximumFramesPerSecond)
            let target = scenario == "unlocked" ? top : min(30, top)
            check(display?.preferredFrameRateRange.preferred == target, "Home frame cap was not applied at Play")
            check(PGUISmokeFrameLimit() == (scenario == "unlocked" ? 0 : 2), "Engine frame cap differs from selection")
            func poll(_ status: UInt32, _ loading: Bool) {
                PGUISmokeRuntimeState(status, loading)
                root.perform(NSSelectorFromString("pollController"))
            }
            poll(0, true)
            check(touch.isHidden, "Transient player during loading exposed controls")
            poll(16, false)
            check(touch.isHidden, "Missing player exposed controls")
            poll(0, false) // Deliberately never emit WORLD_READY.
            check(!touch.isHidden, "Playable player still waits for pipeline quiescence")
            poll(2, false)
            check(!touch.isHidden, "Phone navigation disappeared")
            poll(4, false)
            check(touch.isHidden, "Cutscene kept controls visible")
            poll(0, false)
            check(!touch.isHidden, "Controls did not return after cutscene")
            poll(0, true)
            check(touch.isHidden, "Later loading kept controls visible")
            let result = failures.isEmpty ? "UIKit runtime regressions passed." : "UIKit runtime regressions FAILED: " + failures.joined(separator: "; ")
            NativeLog.shared.append(result)
            NativeLog.shared.flush()
        }
    }
}
