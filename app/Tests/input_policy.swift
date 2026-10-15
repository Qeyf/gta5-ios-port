import Foundation

@main enum InputPolicyTests {
    static func main() {
        assert(!CheatInputMode.automatic.usesGamepad && !CheatInputMode.console.usesGamepad)
        assert(CheatInputMode.gamepad.usesGamepad)
        var policy = GameplayReadiness()
        func allowed(_ world: Bool, _ status: UInt32, _ paused: Bool = false, _ preview: Bool = false) -> Bool {
            policy.allowsControls(engineStarted: world, loading: false, status: status, paused: paused, preview: preview)
        }
        assert(!policy.allowsControls(engineStarted: true, loading: true, status: 0, paused: false, preview: false))
        assert(!policy.enteredGameplay)
        assert(!allowed(false, 16) && !allowed(false, 0))
        assert(!allowed(true, 16) && !allowed(true, 4) && !allowed(true, 1) && !allowed(true, 1, true))
        assert(allowed(true, 0) && policy.enteredGameplay)
        assert(allowed(true, 2) && allowed(true, 1) && allowed(true, 8))
        assert(!allowed(true, 4) && !allowed(true, 16))
        assert(allowed(true, 4, true) && allowed(true, 16, true))
        assert(!policy.allowsControls(engineStarted: true, loading: true, status: 0, paused: false, preview: false))
        assert(allowed(true, 0))
        var preview = GameplayReadiness()
        assert(preview.allowsControls(engineStarted: false, loading: true, status: 16, paused: false, preview: true))
        assert(!preview.enteredGameplay)
        print("PASS: automatic cheats use console; initial loading/cutscenes hide controls, gameplay and later menus/phone/prompts remain available.")
    }
}
