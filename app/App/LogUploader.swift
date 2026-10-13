import Foundation
import UIKit

/// Sends the app's logs to the developer (5★ Port Builder site, which forwards them on Telegram).
enum LogUploader {
    static let endpoint = URL(string: "https://fivestarport.vercel.app/api/log")!
    /// The site accepts up to 4 MB, so each log is trimmed to its last 1.8 MB.
    private static let perLog = 1_800_000

    static func send(note: String, done: @escaping ((String, String)) -> Void) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var body = Data()
        for (title, name) in [("PREVIOUS RUN", "native-port-previous.log"), ("THIS RUN", "native-port.log")] {
            guard let data = try? Data(contentsOf: documents.appendingPathComponent(name)), !data.isEmpty else { continue }
            body.append("===== \(title) (\(name)) =====\n".data(using: .utf8)!)
            body.append(data.count > perLog ? data.suffix(perLog) : data)
            body.append("\n".data(using: .utf8)!)
        }
        guard !body.isEmpty else { DispatchQueue.main.async { done((String(localized: "No log yet", table: "Files"), String(localized: "Start the game once, then try again.", table: "Files"))) }; return }
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("\(GameSettings.shared.tier.model) · iOS \(UIDevice.current.systemVersion) · \(GameSettings.shared.tier.memoryLimitMB) MB limit", forHTTPHeaderField: "X-Device")
        request.setValue(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?", forHTTPHeaderField: "X-App-Version")
        request.setValue(String(note.prefix(400)).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "", forHTTPHeaderField: "X-Note")
        URLSession.shared.uploadTask(with: request, from: body) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let reply = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let result: (String, String)
            if status == 200 {
                result = (String(localized: "Log sent, thank you!", table: "Files"), String(localized: "Reference: \(reply?["id"] as? String ?? "-"). Mention it if you also ask for help in the community.", table: "Files"))
            } else if error != nil {
                result = (String(localized: "Couldn't send the log", table: "Files"), String(localized: "No internet connection? Try again, or use Share log instead.", table: "Files"))
            } else {
                result = (String(localized: "Couldn't send the log", table: "Files"), (reply?["error"] as? String).map { String(localized: "The server could not accept the log: \($0)", table: "Files") } ?? String(localized: "Try again later, or use Share log instead.", table: "Files"))
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }
}

/// "Send log to the developer": its own screen so the buttons stay visible above the keyboard in landscape.
final class SendLogViewController: UIViewController {
    private let note = UITextView()
    private let status = UILabel()
    var finished: ((String, String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Send log to the developer", table: "Files")
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: String(localized: "Cancel", table: "Files"), primaryAction: UIAction(title: String(localized: "Cancel", table: "Files")) { [weak self] _ in self?.dismiss(animated: true) })
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: String(localized: "Send", table: "Files"), primaryAction: UIAction(title: String(localized: "Send", table: "Files")) { [weak self] _ in self?.send() })
        navigationItem.rightBarButtonItem?.style = .done

        let info = UILabel()
        info.text = String(localized: "Sends this run's game log and the previous one: your iPhone model, iOS version, app settings and what the game printed. No personal data, photos or contacts.", table: "Files")
        info.numberOfLines = 0
        info.font = .preferredFont(forTextStyle: .footnote)
        info.textColor = .secondaryLabel
        note.font = .preferredFont(forTextStyle: .body)
        note.layer.cornerRadius = 10
        note.backgroundColor = .secondarySystemGroupedBackground
        note.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        note.accessibilityLabel = String(localized: "What happened? (optional)", table: "Files")
        let placeholder = UILabel()
        placeholder.text = String(localized: "What happened? (optional)", table: "Files")
        placeholder.textColor = .placeholderText
        placeholder.font = note.font
        placeholder.tag = 7
        note.addSubview(placeholder)
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([placeholder.topAnchor.constraint(equalTo: note.topAnchor, constant: 10),
                                     placeholder.leadingAnchor.constraint(equalTo: note.leadingAnchor, constant: 13)])
        NotificationCenter.default.addObserver(forName: UITextView.textDidChangeNotification, object: note, queue: .main) { [weak self] _ in
            self?.note.viewWithTag(7)?.isHidden = !(self?.note.text.isEmpty ?? true)
        }
        status.font = .preferredFont(forTextStyle: .footnote)
        status.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [info, note, status])
        stack.axis = .vertical
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            // The note shrinks to stay above the keyboard.
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.keyboardLayoutGuide.topAnchor, constant: -8),
            note.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        let preferred = note.heightAnchor.constraint(equalToConstant: 140)
        preferred.priority = .defaultLow
        preferred.isActive = true
    }

    private func send() {
        navigationItem.rightBarButtonItem?.isEnabled = false
        note.resignFirstResponder()
        status.text = String(localized: "Sending…", table: "Files")
        LogUploader.send(note: note.text ?? "") { [weak self] result in
            guard let self else { return }
            let done = self.finished
            self.dismiss(animated: true) { done?(result.0, result.1) }
        }
    }
}
