import Foundation

/// Where an install of the game files comes from.
enum GameInstallSource {
    /// A direct link to an archive: downloaded, unpacked as it arrives, and never stored whole.
    case url(URL, headers: [String: String] = [:])
    /// An archive in Files (other parts of a multi-part set are found by name). When the app owns
    /// it (it's in the app's folder), the part already unpacked is freed as it goes, so the
    /// archive and the game don't both need room.
    case file(URL, ownedByApp: Bool)
    /// Every part of a multi-part archive, in order.
    case parts([URL])
}

/// One progress report for the screen.
struct GameInstallUpdate {
    var title: String
    var detail: String
    var fraction: Double
}

enum GameInstallResult {
    case success
    case failure(String)
    /// The link was a web page, not the file (a download portal): open it in the download browser.
    case webPage(URL)
}

/// A running install (GameInstaller does the work). Reports on the main queue.
final class GameInstallRun {
    private var task: InstallTask?
    private var scoped: [URL] = []

    /// Debug web pages whose size web downloads change slightly; the game never reads them.
    private static let tolerated: Set<String> = ["common/non_final/www/parser/psomismatch.html", "common/non_final/www/parser/schemas.html"]

    static func start(_ source: GameInstallSource, to destination: URL,
                      progress: @escaping (GameInstallUpdate) -> Void,
                      completion: @escaping (GameInstallResult) -> Void) -> GameInstallRun {
        let run = GameInstallRun()
        guard let manifest = EnginePaths.manifest else {
            DispatchQueue.main.async { completion(.failure(String(localized: "The app's game file list is missing.", table: "Files"))) }
            return run
        }
        var options = GameInstaller.Options()
        options.log = { GameFolder.log("Install: " + $0) }
        options.toleratedSizeMismatches = tolerated
        let installerSource: GameInstaller.Source
        switch source {
        case let .url(url, headers):
            options.httpHeaders = headers
            installerSource = .url(url)
        case let .file(url, owned):
            run.access(url)
            options.allowModifyingSource = owned
            installerSource = .file(url)
        case let .parts(urls):
            urls.forEach(run.access)
            installerSource = .files(urls)
        }
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // The real folder, so the space check measures the disk the files actually go to.
        let destination = destination.resolvingSymlinksInPath()
        GameFolder.log("Install started from \(Self.describe(source)) into \(destination.lastPathComponent)")
        run.task = GameInstaller.install(from: installerSource, to: destination, manifest: URL(fileURLWithPath: manifest), options: options,
            progress: { p in progress(Self.update(p)) },
            completion: { result in
                run.scoped.forEach { $0.stopAccessingSecurityScopedResource() }
                run.scoped = []
                switch result {
                case let .success(report):
                    GameFolder.log("Install finished: \(report.filesWritten) files, \(report.format), \(Int(report.duration)) s, peak extra disk \(report.peakDiskIncrease / 1_000_000) MB")
                    completion(.success)
                case let .failure(error):
                    GameFolder.log("Install failed: \(error)")
                    if error.kind == .webPageNotFile, case let .url(url, headers) = source, headers.isEmpty {
                        completion(.webPage(url))
                        return
                    }
                    var message = error.message
                    if error.kind == .cancelled { message = String(localized: "Cancelled. Files already unpacked are kept; starting again replaces them.", table: "Files") }
                    completion(.failure(message))
                }
            })
        return run
    }

    func cancel() { task?.cancel() }

    private func access(_ url: URL) {
        if url.startAccessingSecurityScopedResource() { scoped.append(url) }
    }

    private static func describe(_ source: GameInstallSource) -> String {
        switch source {
        case let .url(url, _): return "a link (\(url.host ?? "?"))"
        case let .file(url, owned): return "\(url.lastPathComponent)\(owned ? " (freed as it unpacks)" : "")"
        case let .parts(urls): return "\(urls.count) parts"
        }
    }

    private static func update(_ p: GameInstaller.Progress) -> GameInstallUpdate {
        let size = { (bytes: Int64) in ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        var detail: [String] = []
        switch p.phase {
        case .checking:
            return GameInstallUpdate(title: String(localized: "Checking space and the archive…", table: "Files"), detail: "", fraction: 0)
        case .verifying:
            return GameInstallUpdate(title: String(localized: "Checking every file…", table: "Files"), detail: "", fraction: 1)
        case .finished:
            return GameInstallUpdate(title: String(localized: "Done", table: "Files"), detail: "", fraction: 1)
        case .downloading, .unpacking:
            detail.append(String(localized: "\(size(p.extractedBytes)) of \(size(p.totalBytes)) unpacked · \(p.filesDone.formatted()) of \(p.filesTotal.formatted()) files", table: "Files"))
            if p.downloadedBytes > 0 {
                let downloaded = p.downloadTotalBytes.map {
                    String(localized: "Downloaded \(size(p.downloadedBytes)) of \(size($0))", table: "Files")
                } ?? String(localized: "Downloaded \(size(p.downloadedBytes))", table: "Files")
                detail.append(p.bytesPerSecond.map { String(localized: "\(downloaded) · \(size(Int64($0)))/s", table: "Files") } ?? downloaded)
            }
            if let seconds = p.secondsRemaining, seconds.isFinite {
                detail.append(seconds < 90 ? String(localized: "About a minute left", table: "Files") : Int(seconds / 60) == 1 ? String(localized: "About 1 minute left", table: "Files") : String(localized: "About \(Int(seconds / 60).formatted()) minutes left", table: "Files"))
            }
            if p.retries > 0 { detail.append(String(localized: "Connection dropped \(p.retries.formatted())× and resumed", table: "Files")) }
            if let file = p.currentFile { detail.append(file) }
            let percent = (Double(Int(p.fraction * 100)) / 100).formatted(.percent.precision(.fractionLength(0)))
            let title = p.phase == .downloading ? String(localized: "Downloading and unpacking… \(percent)", table: "Files") : String(localized: "Unpacking… \(percent)", table: "Files")
            return GameInstallUpdate(title: title, detail: detail.joined(separator: "\n"), fraction: p.fraction)
        }
    }
}

extension Notification.Name {
    /// The shared install (GameInstallManager) started, made progress or finished.
    static let gameInstallChanged = Notification.Name("GameInstallChanged")
}

/// The one install that may run at a time. It belongs to the app, not to a screen, so the player
/// can leave the game files screen (start screen, Settings, controls layout) while it runs. Every
/// change is posted as `.gameInstallChanged`; only starting the game waits for it.
final class GameInstallManager {
    static let shared = GameInstallManager()
    enum State {
        case idle
        case running(GameInstallUpdate)
        case finished(GameInstallResult)
    }
    private(set) var state = State.idle
    private var run: GameInstallRun?
    var isRunning: Bool { if case .running = state { return true }; return false }

    func start(_ source: GameInstallSource, to destination: URL) {
        guard !isRunning else { return }
        state = .running(GameInstallUpdate(title: String(localized: "Starting…", table: "Files"), detail: "", fraction: 0))
        post()
        run = GameInstallRun.start(source, to: destination, progress: { [weak self] update in
            self?.state = .running(update)
            self?.post()
        }, completion: { [weak self] result in
            guard let self else { return }
            self.run = nil
            if case .success = result {
                // The new game is picked up from the app's folder (and checked) before Play unlocks.
                GameFolder.clear()
                DispatchQueue.global(qos: .userInitiated).async {
                    GameFolder.findInAppFolder()
                    DispatchQueue.main.async { self.state = .finished(result); self.post() }
                }
            } else {
                self.state = .finished(result)
                self.post()
            }
        })
    }

    func cancel() { run?.cancel() }

    /// Forgets a finished result once a screen has shown it.
    func acknowledge() { if case .finished = state { state = .idle } }

    private func post() { NotificationCenter.default.post(name: .gameInstallChanged, object: self) }
}
