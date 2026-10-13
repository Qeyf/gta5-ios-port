import UIKit

/// A localized reference to GTA V's existing Story mode codes.
/// Codes are game protocol values; translating them would make them invalid.
final class CheatsViewController: UITableViewController, UISearchResultsUpdating {
    private struct Cheat {
        let title: String
        let detail: String
        let code: String
        let phone: String
    }

    private let search = UISearchController(searchResultsController: nil)
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
        Cheat(title: String(localized: "Spawn BMX", table: "Cheats"), detail: String(localized: "Spawn a BMX bicycle where space allows.", table: "Cheats"), code: "BANDIT", phone: "1-999-226-348")
    ]
    private var visible: [Cheat] = []

    init() {
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
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { section == 0 ? 1 : visible.count }
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
            content.text = String(localized: "Names and instructions follow the app language. Codes stay unchanged.", table: "Cheats")
            content.secondaryText = String(localized: "This is a reference, not an activation button. Enter the phone number on the character's in-game phone, or enter the PC code with a physical keyboard if this game build supports the cheat console. Copying a code does not activate it.", table: "Cheats")
            cell.selectionStyle = .none
        } else {
            let cheat = visible[indexPath.row]
            content.text = cheat.title
            content.secondaryText = "\(cheat.detail)\n\(cheat.code) · \(cheat.phone)"
            cell.accessoryType = .disclosureIndicator
            cell.accessibilityHint = String(localized: "Show code and copy options", table: "Cheats")
        }
        cell.contentConfiguration = content
        return cell
    }
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        let cheat = visible[indexPath.row]
        let message = String(localized: "\(cheat.detail)\n\nPC code: \(cheat.code)\nIn-game phone: \(cheat.phone)", table: "Cheats")
        let alert = UIAlertController(title: cheat.title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "Copy PC code", table: "Cheats"), style: .default) { _ in UIPasteboard.general.string = cheat.code })
        alert.addAction(UIAlertAction(title: String(localized: "Copy in-game phone number", table: "Cheats"), style: .default) { _ in UIPasteboard.general.string = cheat.phone })
        alert.addAction(UIAlertAction(title: String(localized: "Done", table: "Cheats"), style: .cancel))
        present(alert, animated: true)
    }
    func updateSearchResults(for searchController: UISearchController) {
        let query = (searchController.searchBar.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        visible = query.isEmpty ? cheats : cheats.filter {
            [$0.title, $0.detail, $0.code, $0.phone].contains { $0.localizedStandardContains(query) }
        }
        tableView.reloadSections(IndexSet(integer: 1), with: .none)
    }
}
