import UIKit

typealias CheatApplyHandler = (String, [UInt16], CheatInputMode) -> Void

/// GTA V's cheat inputs, delivered through its console or virtual controller.
/// Codes are game protocol values; translating them would make them invalid.
final class CheatsViewController: UITableViewController, UISearchResultsUpdating {
    private struct Cheat {
        let title: String
        let detail: String
        let code: String
        let phone: String?
        var buttons: [UInt16] { CheatsViewController.gamepadSequences[code] ?? [] }
    }

    private let search = UISearchController(searchResultsController: nil)
    private let engineRunning: Bool
    var onApply: CheatApplyHandler?
    private var inputMode = CheatInputMode(rawValue: UserDefaults.standard.integer(forKey: "cheatInputMode")) ?? .automatic
    private lazy var method = UISegmentedControl(items: CheatInputMode.allCases.map { $0.title })
    private let cheats: [Cheat] = [
        Cheat(title: String(localized: "Invincibility", table: "Cheats"), detail: String(localized: "Invincibility for five minutes.", table: "Cheats"), code: "PAINKILLER", phone: "1-999-724-654-5537"),
        Cheat(title: String(localized: "Full health and armor", table: "Cheats"), detail: String(localized: "Restore your health and armor.", table: "Cheats"), code: "TURTLE", phone: "1-999-887-853"),
        Cheat(title: String(localized: "Weapons and ammunition", table: "Cheats"), detail: String(localized: "Receive a selection of weapons and ammunition.", table: "Cheats"), code: "TOOLUP", phone: "1-999-866-587"),
        Cheat(title: String(localized: "Lower wanted level", table: "Cheats"), detail: String(localized: "Remove one wanted star per use.", table: "Cheats"), code: "LAWYERUP", phone: "1-999-529-93787"),
        Cheat(title: String(localized: "Raise wanted level", table: "Cheats"), detail: String(localized: "Add one wanted star per use.", table: "Cheats"), code: "FUGITIVE", phone: "1-999-3844-8483"),
        Cheat(title: String(localized: "Recharge special ability", table: "Cheats"), detail: String(localized: "Refill the character's special ability meter.", table: "Cheats"), code: "POWERUP", phone: "1-999-769-3787"),
        Cheat(title: String(localized: "Fast running", table: "Cheats"), detail: String(localized: "Run faster on foot.", table: "Cheats"), code: "CATCHME", phone: "1-999-228-2463"),
        Cheat(title: String(localized: "Fast swimming", table: "Cheats"), detail: String(localized: "Swim faster in the water.", table: "Cheats"), code: "GOTGILLS", phone: "1-999-468-44557"),
        Cheat(title: String(localized: "Super jump", table: "Cheats"), detail: String(localized: "Jump higher; hold the jump button for more height.", table: "Cheats"), code: "HOPTOIT", phone: "1-999-467-8648"),
        Cheat(title: String(localized: "Parachute", table: "Cheats"), detail: String(localized: "Equip a parachute.", table: "Cheats"), code: "SKYDIVE", phone: "1-999-759-3483"),
        Cheat(title: String(localized: "Explosive ammunition", table: "Cheats"), detail: String(localized: "Bullets explode on impact.", table: "Cheats"), code: "HIGHEX", phone: "1-999-444-439"),
        Cheat(title: String(localized: "Explosive melee attacks", table: "Cheats"), detail: String(localized: "Melee strikes cause explosions.", table: "Cheats"), code: "HOTHANDS", phone: "1-999-4684-2637"),
        Cheat(title: String(localized: "Flaming ammunition", table: "Cheats"), detail: String(localized: "Bullets set targets on fire.", table: "Cheats"), code: "INCENDIARY", phone: "1-999-462-363-4279"),
        Cheat(title: String(localized: "Slow-motion aiming", table: "Cheats"), detail: String(localized: "Cycle through slow-motion aiming levels.", table: "Cheats"), code: "DEADEYE", phone: "1-999-332-3393"),
        Cheat(title: String(localized: "Change weather", table: "Cheats"), detail: String(localized: "Cycle through the weather conditions.", table: "Cheats"), code: "MAKEITRAIN", phone: "1-999-625-348-7246"),
        Cheat(title: String(localized: "Slippery vehicles", table: "Cheats"), detail: String(localized: "Reduce vehicle traction.", table: "Cheats"), code: "SNOWDAY", phone: "1-999-766-9329"),
        Cheat(title: String(localized: "Moon gravity", table: "Cheats"), detail: String(localized: "Reduce gravity in the game world.", table: "Cheats"), code: "FLOATER", phone: "1-999-356-2837"),
        Cheat(title: String(localized: "Slow motion", table: "Cheats"), detail: String(localized: "Cycle through slow-motion gameplay levels.", table: "Cheats"), code: "SLOWMO", phone: "1-999-756-966"),
        Cheat(title: String(localized: "Spawn Buzzard helicopter", table: "Cheats"), detail: String(localized: "Spawn a Buzzard attack helicopter where space allows.", table: "Cheats"), code: "BUZZOFF", phone: "1-999-289-9633"),
        Cheat(title: String(localized: "Spawn Comet", table: "Cheats"), detail: String(localized: "Spawn a Comet sports car where space allows.", table: "Cheats"), code: "COMET", phone: "1-999-266-38"),
        Cheat(title: String(localized: "Spawn Rapid GT", table: "Cheats"), detail: String(localized: "Spawn a Rapid GT sports car where space allows.", table: "Cheats"), code: "RAPIDGT", phone: "1-999-727-4348"),
        Cheat(title: String(localized: "Spawn Sanchez", table: "Cheats"), detail: String(localized: "Spawn a Sanchez dirt bike where space allows.", table: "Cheats"), code: "OFFROAD", phone: "1-999-633-7623"),
        Cheat(title: String(localized: "Spawn PCJ-600", table: "Cheats"), detail: String(localized: "Spawn a PCJ-600 motorcycle where space allows.", table: "Cheats"), code: "ROCKET", phone: "1-999-762-538"),
        Cheat(title: String(localized: "Spawn BMX", table: "Cheats"), detail: String(localized: "Spawn a BMX bicycle where space allows.", table: "Cheats"), code: "BANDIT", phone: "1-999-226-348"),
        Cheat(title: String(localized: "Skyfall", table: "Cheats"), detail: String(localized: "Fall from the sky without a parachute.", table: "Cheats"), code: "SKYFALL", phone: nil),
        Cheat(title: String(localized: "Drunk mode", table: "Cheats"), detail: String(localized: "Make the character move as if drunk.", table: "Cheats"), code: "LIQUOR", phone: nil),
        Cheat(title: String(localized: "Spawn limousine", table: "Cheats"), detail: String(localized: "Spawn a stretch limousine where space allows.", table: "Cheats"), code: "VINEWOOD", phone: nil),
        Cheat(title: String(localized: "Spawn garbage truck", table: "Cheats"), detail: String(localized: "Spawn a Trashmaster garbage truck where space allows.", table: "Cheats"), code: "TRASHED", phone: nil),
        Cheat(title: String(localized: "Spawn stunt plane", table: "Cheats"), detail: String(localized: "Spawn a stunt plane where space allows.", table: "Cheats"), code: "BARNSTORM", phone: nil),
        Cheat(title: String(localized: "Spawn crop duster", table: "Cheats"), detail: String(localized: "Spawn a Duster aircraft where space allows.", table: "Cheats"), code: "FLYSPRAY", phone: nil),
        Cheat(title: String(localized: "Spawn Duke O'Death", table: "Cheats"), detail: String(localized: "Requires the vehicle to be unlocked in your game progress.", table: "Cheats"), code: "DEATHCAR", phone: nil),
        Cheat(title: String(localized: "Spawn Kraken submarine", table: "Cheats"), detail: String(localized: "Requires the vehicle to be unlocked in your game progress.", table: "Cheats"), code: "BUBBLES", phone: nil),
        Cheat(title: String(localized: "Spawn Dodo seaplane", table: "Cheats"), detail: String(localized: "Requires the vehicle to be unlocked in your game progress.", table: "Cheats"), code: "EXTINCT", phone: nil)
    ]
    private var visible: [Cheat] = []

    init(engineRunning: Bool = false) {
        self.engineRunning = engineRunning
        super.init(style: .insetGrouped)
        title = String(localized: "Cheat codes", table: "Cheats")
        overrideUserInterfaceStyle = .dark
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.backgroundView = Theme.dimmedBackdrop(image: "SettingsBackground")
        visible = cheats
        search.searchResultsUpdater = self
        search.obscuresBackgroundDuringPresentation = false
        search.searchBar.placeholder = String(localized: "Search names or codes", table: "Cheats")
        navigationItem.searchController = search
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
        method.selectedSegmentIndex = inputMode.rawValue
        method.addAction(UIAction { [weak self] _ in
            guard let self, let mode = CheatInputMode(rawValue: self.method.selectedSegmentIndex) else { return }
            self.inputMode = mode
            UserDefaults.standard.set(mode.rawValue, forKey: "cheatInputMode")
        }, for: .valueChanged)
        method.accessibilityLabel = String(localized: "Activation method", table: "Cheats")
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 3 : visible.count }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? String(localized: "How to use", table: "Cheats") : String(localized: "Story mode codes", table: "Cheats")
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        guard section == 1 else { return nil }
        return String(localized: "Cheats may be unavailable during missions. They temporarily disable achievements; reload a save or restart the game to reset them.", table: "Cheats")
    }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = Theme.rowBackground
        var content = cell.defaultContentConfiguration()
        content.textProperties.numberOfLines = 0
        content.secondaryTextProperties.numberOfLines = 0
        content.secondaryTextProperties.color = Theme.secondaryText
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                content.text = String(localized: "Names and instructions follow the app language. Codes stay unchanged.", table: "Cheats")
                content.secondaryText = engineRunning
                    ? String(localized: "Close the game's pause menu and wait until you can control the character. Auto uses the console to avoid triggering vehicle-exit or attack buttons. Gamepad sends normal controller buttons. Check the game's own message for the result.", table: "Cheats")
                    : String(localized: "Start the game before applying a cheat. You can browse and copy codes here while it loads.", table: "Cheats")
                cell.selectionStyle = .none
            case 1:
                content.text = String(localized: "Activation method", table: "Cheats")
                cell.accessoryView = method
                cell.selectionStyle = .none
            default:
                content.text = String(localized: "Custom code", table: "Cheats")
                content.secondaryText = String(localized: "Send an A–Z cheat code through the in-game console.", table: "Cheats")
                cell.accessoryType = .disclosureIndicator
            }
        } else {
            let cheat = visible[indexPath.row]
            content.text = cheat.title
            content.secondaryText = "\(cheat.detail)\n\(cheat.code)" + (cheat.phone.map { " · \($0)" } ?? "")
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityHint = String(localized: "Show activation and copy options", table: "Cheats")
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            if indexPath.row == 2 { showCustomCode() }
            return
        }
        let cheat = visible[indexPath.row]
        let message = cheat.detail + "\n\n" + String(localized: "PC code: \(cheat.code)", table: "Cheats")
            + (cheat.phone.map { "\n" + String(localized: "In-game phone: \($0)", table: "Cheats") } ?? "")
        let alert = UIAlertController(title: cheat.title, message: message, preferredStyle: .alert)
        let apply = UIAlertAction(title: String(localized: "Apply to game", table: "Cheats"), style: .default) { [weak self] _ in
            guard let self else { return }
            if self.inputMode == .gamepad && cheat.buttons.isEmpty {
                self.explain(String(localized: "This code uses the console. Select Auto or Console.", table: "Cheats"))
                return
            }
            self.onApply?(cheat.code, cheat.buttons, self.inputMode)
        }
        apply.isEnabled = engineRunning && onApply != nil
        alert.addAction(apply)
        alert.addAction(UIAlertAction(title: String(localized: "Copy PC code", table: "Cheats"), style: .default) { _ in UIPasteboard.general.string = cheat.code })
        if let phone = cheat.phone {
            alert.addAction(UIAlertAction(title: String(localized: "Copy in-game phone number", table: "Cheats"), style: .default) { _ in UIPasteboard.general.string = phone })
        }
        alert.addAction(UIAlertAction(title: String(localized: "Done", table: "Cheats"), style: .cancel))
        present(alert, animated: true)
    }
    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        visible = query.isEmpty ? cheats : cheats.filter {
            [$0.title, $0.detail, $0.code, $0.phone ?? ""].contains { $0.localizedStandardContains(query) }
        }
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }

    private func showCustomCode() {
        guard engineRunning, onApply != nil else {
            explain(String(localized: "Start the game before applying a cheat.", table: "Cheats"))
            return
        }
        let alert = UIAlertController(title: String(localized: "Custom code", table: "Cheats"),
                                      message: String(localized: "Send an A–Z cheat code through the in-game console.", table: "Cheats"), preferredStyle: .alert)
        alert.addTextField {
            $0.placeholder = "PAINKILLER"
            $0.keyboardType = .asciiCapable
            $0.autocapitalizationType = .allCharacters
            $0.autocorrectionType = .no
            $0.spellCheckingType = .no
        }
        alert.addAction(UIAlertAction(title: String(localized: "Send through console", table: "Cheats"), style: .default) { [weak self, weak alert] _ in
            let code = (alert?.textFields?.first?.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased(with: Locale(identifier: "en_US_POSIX"))
            guard !code.isEmpty, code.utf8.count <= 32,
                  code.utf8.allSatisfy({ (65...90).contains($0) }) else {
                self?.explain(String(localized: "Use 1–32 letters A–Z. Spaces, numbers and punctuation are not accepted.", table: "Cheats"))
                return
            }
            self?.onApply?(code, [], .console)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Cancel", table: "Cheats"), style: .cancel))
        present(alert, animated: true)
    }

    private func explain(_ message: String) {
        let alert = UIAlertController(title: String(localized: "Cheat codes", table: "Cheats"), message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK", table: "Cheats"), style: .default))
        present(alert, animated: true)
    }

    // Button sequences recovered from the supplied GTA5Port.ipa. SNOW was a
    // duplicate weather sequence, so SNOWDAY correctly falls back to console.
    // The limousine sequence excludes the reference's trailing zero padding.
    private static let gamepadSequences: [String: [UInt16]] = [
        "PAINKILLER": [8192, 64, 8192, 32768, 8192, 8, 8192, 32768, 64, 16],
        "TURTLE": [32, 4, 16, 2, 64, 128, 32, 8192, 128, 4, 4, 4],
        "TOOLUP": [16, 2, 32768, 4, 64, 8192, 16, 16384, 128, 4, 4, 4],
        "FUGITIVE": [8, 8, 32, 2, 32768, 8192, 32768, 8192, 32768, 8192],
        "LAWYERUP": [8, 8, 32, 2, 8192, 32768, 8192, 32768, 8192, 32768],
        "POWERUP": [64, 64, 128, 8, 4, 64, 8192, 32768, 64],
        "CATCHME": [16, 32768, 8192, 8192, 1, 4, 128],
        "GOTGILLS": [32768, 32768, 4, 8192, 8192, 2, 32768, 1, 8192],
        "HOPTOIT": [32768, 32768, 16, 16, 8192, 8192, 32768, 8192, 128, 8, 2],
        "SKYFALL": [4, 1, 8, 2, 32768, 8192, 32768, 8192, 4, 1, 8, 2, 32768, 8192, 32768, 8192],
        "FLOATER": [32768, 32768, 4, 8, 4, 8192, 32768, 4, 32768],
        "SLOWMO": [16, 32768, 8192, 8192, 128, 2, 8],
        "DEADEYE": [128, 1, 8, 16, 32768, 128, 1, 8192, 64],
        "MAKEITRAIN": [2, 64, 4, 4, 1, 1, 1, 128],
        "HOTHANDS": [8192, 32768, 64, 16, 8, 32, 32, 32, 1],
        "INCENDIARY": [4, 8, 128, 8, 32768, 2, 8, 32768, 128, 8192, 4, 4],
        "HIGHEX": [8192, 128, 64, 32768, 8, 2, 32768, 8192, 8192, 4, 4, 4],
        "LIQUOR": [16, 8192, 8192, 32768, 8192, 128, 32, 32768],
        "SKYDIVE": [32768, 8192, 4, 1, 8, 2, 2, 32768, 32768, 8192, 4],
        "COMET": [8, 32, 2, 8192, 4, 1, 64, 64, 128, 8],
        "RAPIDGT": [2, 4, 32, 8192, 4, 8, 8192, 32768, 32, 2],
        "VINEWOOD": [2, 8192, 1, 32768, 32768, 8, 4, 32, 8192],
        "TRASHED": [32, 8, 32, 8, 32768, 32768, 8, 4, 32, 8192],
        "BARNSTORM": [32, 8192, 4, 1, 32768, 8, 4, 4, 32768, 32768, 64, 16],
        "BUZZOFF": [32, 32, 4, 32, 32, 32, 4, 1, 8, 16, 32, 16],
        "FLYSPRAY": [8192, 32768, 8, 8, 8, 32768, 16, 16, 64, 32, 4, 4],
        "BANDIT": [32768, 32768, 8192, 8192, 32768, 8192, 128, 32, 16, 8, 2],
        "ROCKET": [8, 8192, 32768, 8192, 2, 32768, 8192, 128, 8192, 1, 4, 4],
        "OFFROAD": [32, 64, 4, 32, 32, 4, 32, 8, 2, 1, 4, 4],
    ]
}
