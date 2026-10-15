import Foundation
import UIKit

/// User-initiated diagnostics sent through our private-recipient Cloudflare relay.
enum LogUploader {
    static let endpoint = URL(string: "https://gtav-mobile-diagnostics.webusta.workers.dev/v1/logs")!
    private static let queue = DispatchQueue(label: "io.github.qeyf.gtavmobile.report", qos: .utility)
    private static let submission = DispatchSemaphore(value: 1)
    #if PG_UI_SMOKE_TEST
    static var testConfiguration: (() -> URLSessionConfiguration)?
    #endif

    static func send(note: String, done: @escaping ((String, String)) -> Void) {
        // Shared across screens: Cancel/reopen must not start a second request
        // while the first is still preparing, uploading or awaiting acceptance.
        guard submission.wait(timeout: .now()) == .success else {
            DispatchQueue.main.async {
                done((String(localized: "A report is already sending", table: "Files"), String(localized: "Please wait for the current report to finish. Your logs and note are sent together in one report.", table: "Files")))
            }
            return
        }
        // Capture UIKit/settings values here; file reads and uploads run off-main.
        let device = "\(GameSettings.shared.tier.model) · iOS \(UIDevice.current.systemVersion) · \(GameSettings.shared.tier.memoryLimitMB) MB limit"
        let version = Theme.appVersion
        let noteHeader = String(note.prefix(400)).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        func finish(_ title: String, _ message: String) {
            DispatchQueue.main.async {
                submission.signal()
                done((title, message))
            }
        }
        queue.async {
            NativeLog.shared.flush()
            guard let body = try? DiagnosticReport.body(directory: directory), !body.isEmpty else {
                finish(String(localized: "No log yet", table: "Files"), String(localized: "Start the game once, then try again.", table: "Files"))
                return
            }
            var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 120)
            request.httpMethod = "POST"
            request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("GtaVMobile/\(version) (iOS; diagnostics)", forHTTPHeaderField: "User-Agent")
            request.setValue(device.addingPercentEncoding(withAllowedCharacters: .alphanumerics), forHTTPHeaderField: "X-Device")
            request.setValue(version, forHTTPHeaderField: "X-App-Version")
            request.setValue(noteHeader, forHTTPHeaderField: "X-Note")
            let configuration = URLSessionConfiguration.ephemeral
            #if PG_UI_SMOKE_TEST
            let sessionConfiguration = testConfiguration?() ?? configuration
            #else
            let sessionConfiguration = configuration
            #endif
            sessionConfiguration.urlCache = nil
            sessionConfiguration.httpCookieStorage = nil
            sessionConfiguration.httpShouldSetCookies = false
            sessionConfiguration.timeoutIntervalForResource = 180
            let session = URLSession(configuration: sessionConfiguration)
            session.uploadTask(with: request, from: body) { data, response, error in
                defer { session.finishTasksAndInvalidate() }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if let id = DiagnosticReport.acceptedID(status: status, data: data) {
                    finish(String(localized: "Log sent, thank you!", table: "Files"), String(localized: "The developer's email service accepted your report. Reference: \(id)", table: "Files"))
                } else if status == 429 {
                    finish(String(localized: "Couldn't send the log", table: "Files"), String(localized: "Please wait one minute before sending another report.", table: "Files"))
                } else if error != nil {
                    finish(String(localized: "Couldn't send the log", table: "Files"), String(localized: "No internet connection? Try again, or use Share log instead.", table: "Files"))
                } else {
                    // Provider error text can contain private routing information.
                    finish(String(localized: "Couldn't send the log", table: "Files"), String(localized: "Try again later, or use Share log instead.", table: "Files"))
                }
            }.resume()
        }
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
        info.text = String(localized: "Sends the current and previous game logs and your optional note to the developer's email service through Cloudflare. Logs include device details, settings, file paths and game messages. Large logs keep startup details and recent lines. Use Share log to review them first. Photos and contacts are not accessed.", table: "Files")
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
