import Foundation

enum CheatInputMode: Int, CaseIterable {
    case automatic, console, gamepad
    // Controller cheat sequences are normal gameplay buttons too. Automatic
    // input uses the console so vehicle-exit/melee actions are not synthesized.
    var usesGamepad: Bool { self == .gamepad }
    var title: String {
        switch self {
        case .automatic: return String(localized: "Auto", table: "Cheats")
        case .console: return String(localized: "Console", table: "Cheats")
        case .gamepad: return String(localized: "Gamepad", table: "Cheats")
        }
    }
}

struct GameplayReadiness {
    private(set) var enteredGameplay = false

    mutating func allowsControls(worldReady: Bool, status: UInt32, paused: Bool, preview: Bool) -> Bool {
        if worldReady && status == 0 { enteredGameplay = true }
        if preview { return true }
        guard worldReady && enteredGameplay else { return false }
        // Menus still need navigation after entering gameplay. Ordinary controls
        // disappear while there is no local player or a cutscene is playing.
        return paused || status & (4 | 16) == 0
    }
}
