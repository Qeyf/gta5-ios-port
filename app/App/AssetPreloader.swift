import UIKit

extension Notification.Name {
    static let assetPreloadChanged = Notification.Name("AssetPreloadChanged")
}

/// Where the engine keeps its files. The asset cache sits next to this folder
/// (`AssetCache-<version>`), so the preloader and the engine must agree on it.
enum EnginePaths {
    static var manifest: String? { Bundle.main.path(forResource: "manifest", ofType: "json") }

    /// Returns the engine files root and, on the simulator, an optional note.
    static func filesRoot() -> (path: String, note: String?) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("EngineFiles").path
        #if targetEnvironment(simulator)
        // PG_SIMULATOR_ENGINE_ROOT (or PG_ENGINE_FILES_ROOT) keeps a test run's saves and cache apart.
        let environment = ProcessInfo.processInfo.environment
        guard let simulatorRoot = environment["PG_SIMULATOR_ENGINE_ROOT"] ?? environment["PG_ENGINE_FILES_ROOT"] else { return (documents, nil) }
        do {
            try FileManager.default.createDirectory(atPath: simulatorRoot, withIntermediateDirectories: true)
            return (simulatorRoot, nil)
        } catch {
            return (documents, String(localized: "Simulator uses its app container for engine files.", table: "Files"))
        }
        #else
        return (documents, nil)
        #endif
    }
}

/// "Download all game files": copies every archive into the same block cache
/// that streaming fills, so play no longer depends on the server. The native
/// side (Source/NativeAssetPreload.h) does the work; this class keeps the
/// player's choice, checks storage, estimates time and handles app lifecycle.
/// Progress is stored in the cache itself, so nothing is lost on relaunch.
final class AssetPreloader {
    static let shared = AssetPreloader()

    enum Phase: Equatable {
        case unavailable(String)
        case idle
        case downloading
        case paused
        case complete
    }

    /// Space left free on top of the download, for saves, shaders and iOS.
    static let reserveBytes: UInt64 = 1_000_000_000

    private let defaults = UserDefaults.standard
    private let arguments = ProcessInfo.processInfo.arguments
    /// Debug subset: comma-separated path prefixes (e.g. `common/,x64/data/`).
    let filter: String?
    private(set) var totalBytes: UInt64 = 0
    private(set) var cachedBytes: UInt64 = 0
    private(set) var fileCount: UInt32 = 0
    private(set) var measured = false
    private(set) var lastError: String?
    private var prepared = false
    private var running = false
    /// Removal in progress: no download may start until it is done.
    private(set) var removing = false
    private var timer: Timer?
    private var samples: [(time: CFTimeInterval, bytes: UInt64)] = []
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// The player asked for all files and has not cancelled.
    private(set) var wanted: Bool {
        get { defaults.bool(forKey: "assetPreloadWanted") }
        set { defaults.set(newValue, forKey: "assetPreloadWanted") }
    }
    /// Paused by the player (not by iOS or a network error).
    private(set) var userPaused: Bool {
        get { defaults.bool(forKey: "assetPreloadPaused") }
        set { defaults.set(newValue, forKey: "assetPreloadPaused") }
    }
    /// While the game runs, fewer download lanes leave bandwidth to demand reads.
    var engineRunning = false {
        didSet { PGAssetPreloadSetLanes(engineRunning ? 2 : 6) }
    }

    private init() {
        if let i = arguments.firstIndex(of: "--preload-filter"), i + 1 < arguments.count { filter = arguments[i + 1] } else { filter = nil }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    var phase: Phase {
        if GameFolder.isChosen {
            return .unavailable(String(localized: "The game files are already on this iPhone (folder \"\(GameFolder.name)\"), so nothing needs downloading.", table: "Files"))
        }
        if prepared && !PGAssetPreloadSupported() {
            return .unavailable(String(localized: "The simulator reads the Mac's game files directly. Launch with --stream-assets to test downloads.", table: "Files"))
        }
        if running { return .downloading }
        if measured && totalBytes > 0 && cachedBytes >= totalBytes { return .complete }
        if wanted { return .paused }
        return .idle
    }
    var fraction: Double { totalBytes > 0 ? min(1, Double(cachedBytes) / Double(totalBytes)) : 0 }
    var missingBytes: UInt64 { totalBytes > cachedBytes ? totalBytes - cachedBytes : 0 }

    /// Download speed over the last 20 seconds, once there are 3 seconds of data.
    var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last, last.time - first.time >= 3 else { return nil }
        return Double(last.bytes - first.bytes) / (last.time - first.time)
    }
    var secondsRemaining: Double? {
        guard let rate = bytesPerSecond, rate > 1024 else { return nil }
        return Double(missingBytes) / rate
    }

    /// Opens the cache the way the engine will. Cheap after the first call.
    func prepare() {
        guard !prepared, let manifest = EnginePaths.manifest else { return }
        let root = EnginePaths.filesRoot().path
        manifest.withCString { m in root.withCString { PGAssetCachePrepare(m, $0) } }
        prepared = true
    }

    /// Re-reads how much is on the device (presence maps only).
    func refresh(completion: (() -> Void)? = nil) {
        prepare()
        guard PGAssetPreloadSupported() else { measured = true; notify(); completion?(); return }
        let filter = self.filter
        DispatchQueue.global(qos: .utility).async {
            var total: UInt64 = 0, cached: UInt64 = 0, files: UInt32 = 0
            if let filter { filter.withCString { PGAssetPreloadMeasure($0, &total, &cached, &files) } }
            else { PGAssetPreloadMeasure(nil, &total, &cached, &files) }
            DispatchQueue.main.async {
                if !self.running { self.cachedBytes = cached }
                self.totalBytes = total; self.fileCount = files; self.measured = true
                self.notify(); completion?()
            }
        }
    }

    /// Free space for app data, as iOS reports it for important downloads.
    func availableBytes() -> UInt64 {
        if let i = arguments.firstIndex(of: "--preload-pretend-free-mb"), i + 1 < arguments.count, let mb = UInt64(arguments[i + 1]) {
            return mb * 1_000_000
        }
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return UInt64(max(0, values?.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    /// Starts or resumes. Returns a message when the download cannot start.
    @discardableResult
    func start() -> String? {
        prepare()
        guard !GameSettings.shared.assetServer.isEmpty else { return String(localized: "Set your game file server first (Play screen).", table: "Files") }
        PGSetAssetServer(GameSettings.shared.assetServer)
        guard PGAssetPreloadSupported() else { return String(localized: "Downloads are not available here.", table: "Files") }
        if running { return nil }
        if removing { return String(localized: "Still removing files. Try again in a moment.", table: "Files") }
        var total: UInt64 = 0, cached: UInt64 = 0, files: UInt32 = 0
        if let filter { filter.withCString { PGAssetPreloadMeasure($0, &total, &cached, &files) } }
        else { PGAssetPreloadMeasure(nil, &total, &cached, &files) }
        totalBytes = total; cachedBytes = cached; fileCount = files; measured = true
        if cached >= total { wanted = true; userPaused = false; lastError = nil; notify(); return nil }
        let needed = total - cached + Self.reserveBytes
        let free = availableBytes()
        if free < needed {
            let message = String(localized: "Not enough free space. The rest of the game needs \(Self.format(total - cached)) plus \(Self.format(Self.reserveBytes)) to spare, but only \(Self.format(free)) is free. Free up \(Self.format(needed - free)) and try again.", table: "Files")
            lastError = message
            notify()
            return message
        }
        wanted = true
        userPaused = false
        lastError = nil
        samples = []
        let lanes: UInt32 = engineRunning ? 2 : 6
        let started = filter.map { $0.withCString { PGAssetPreloadStart($0, lanes) } } ?? PGAssetPreloadStart(nil, lanes)
        guard started else { return String(localized: "The download could not start.", table: "Files") }
        running = true
        NSLog("[asset-preload] started: %llu of %llu bytes on device, %u files", cached, total, files)
        startTimer()
        notify()
        return nil
    }

    func pause() {
        userPaused = true
        PGAssetPreloadStop()
        notify()
    }

    /// Stops and forgets the request. Downloaded files stay until removed.
    func cancel() {
        wanted = false
        userPaused = false
        lastError = nil
        PGAssetPreloadStop()
        notify()
    }

    /// Deletes the whole asset cache (also the streamed startup set) on a
    /// background queue; thousands of files can take a few seconds.
    /// Returns a message when it cannot run now.
    func removeDownloads(completion: @escaping (String?) -> Void) {
        guard !running else { completion(String(localized: "Stop the download first.", table: "Files")); return }
        guard !engineRunning else { completion(String(localized: "Restart the app to remove files; the game is using them.", table: "Files")); return }
        guard !removing else { completion(nil); return }
        removing = true
        wanted = false
        userPaused = false
        lastError = nil
        notify()
        DispatchQueue.global(qos: .userInitiated).async {
            var freed: UInt64 = 0
            let removed = PGAssetCacheRemoveAll(&freed)
            DispatchQueue.main.async {
                self.removing = false
                if removed { self.cachedBytes = 0 }
                NSLog("[asset-preload] removed cache: %d, %llu bytes", removed ? 1 : 0, freed)
                self.refresh()
                completion(removed ? nil : String(localized: "The files could not be removed.", table: "Files"))
            }
        }
    }

    /// App launch and return to the foreground: continue an unfinished
    /// download unless the player paused it.
    func resumeIfNeeded() {
        prepare()
        refresh { [weak self] in
            guard let self, !self.removing, PGAssetPreloadSupported(), self.wanted, !self.userPaused, !self.running,
                  self.cachedBytes < self.totalBytes else { return }
            if self.start() != nil {
                NSLog("[asset-preload] resume refused: %llu free bytes, %llu bytes needed, server configured %d", self.availableBytes(), self.missingBytes + Self.reserveBytes, GameSettings.shared.assetServer.isEmpty ? 0 : 1)
            }
            else { NSLog("[asset-preload] resumed after relaunch or return") }
        }
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
    }

    private func tick() {
        let status = PGAssetPreloadGetStatus()
        let now = CACurrentMediaTime()
        samples.append((now, status.downloadedBytes))
        samples.removeAll { now - $0.time > 20 }
        if status.totalBytes > 0 { totalBytes = status.totalBytes; cachedBytes = status.cachedBytes }
        if status.running, availableBytes() < 300_000_000 {
            lastError = String(localized: "Paused because this iPhone is almost out of storage.", table: "Files")
            PGAssetPreloadStop()
        }
        if !status.running {
            running = false
            timer?.invalidate(); timer = nil
            switch status.error {
            case Int32(PGAssetPreloadErrorNetwork.rawValue):
                lastError = String(localized: "Could not reach the game server. Check that Tailscale is connected, then resume.", table: "Files")
            case Int32(PGAssetPreloadErrorStorage.rawValue):
                lastError = String(localized: "Stopped because files could not be saved. Free up storage, then resume.", table: "Files")
            default: break
            }
            NSLog("[asset-preload] stopped: %llu of %llu bytes on device, error %d", status.cachedBytes, status.totalBytes, status.error)
            endBackgroundTask()
            refresh()
        }
        notify()
    }

    @objc private func enteredBackground() {
        guard running, backgroundTask == .invalid else { return }
        // iOS allows a short time in the background; then the lanes stop after
        // their current 1 MB piece and continue when the app is opened again.
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Game file download") { [weak self] in
            PGAssetPreloadStop()
            self?.endBackgroundTask()
        }
    }
    @objc private func becameActive() {
        endBackgroundTask()
        resumeIfNeeded()
    }
    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private func notify() { NotificationCenter.default.post(name: .assetPreloadChanged, object: self) }

    static func format(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = bytes >= 1_000_000_000 ? [.useGB] : [.useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
    static func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 { return String(localized: "under a minute left", table: "Files") }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .short
        formatter.allowedUnits = seconds >= 3600 ? [.hour, .minute] : [.minute]
        formatter.maximumUnitCount = 2
        return String(localized: "about \(formatter.string(from: seconds) ?? "") left", table: "Files")
    }

    /// One-line summary for the launch screen; nil when there is nothing to say.
    var launchSummary: String? {
        let percent = (Double(Int((fraction * 100).rounded(.down))) / 100).formatted(.percent.precision(.fractionLength(0)))
        switch phase {
        case .downloading: return String(localized: "Downloading game files: \(percent) (\(Self.format(cachedBytes)) of \(Self.format(totalBytes)))", table: "Files")
        case .paused: return String(localized: "Game file download paused at \(percent)", table: "Files")
        case .complete: return wanted ? String(localized: "All game files on device", table: "Files") : nil
        case .idle, .unavailable: return nil
        }
    }
}
