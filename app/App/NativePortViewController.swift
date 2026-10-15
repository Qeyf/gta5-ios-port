import UIKit
import MetalKit
import GameController
import AVFAudio
import UniformTypeIdentifiers
import os

private func engineLog(_ message: UnsafePointer<CChar>?, _ context: UnsafeMutableRawPointer?) {
    guard let message, let context else { return }
    let line = String(cString: message)
    let controller = Unmanaged<NativePortViewController>.fromOpaque(context).takeUnretainedValue()
    NativeLog.shared.append(line)
    if isEngineUIEvent(line) { DispatchQueue.main.async { controller.handleLogEvent(line) } }
}

private func isEngineUIEvent(_ line: String) -> Bool {
    line.hasPrefix("ASSET_WARM_PROGRESS ") || line == "ASSET_WARM_COMPLETE" || line == "WORLD_READY" ||
        line.contains("\"label\":\"First frame\"") || line.hasPrefix("Native boot stopped:") ||
        line == "iOS could not reserve the engine memory."
}

final class NativePortViewController: UIViewController, MTKViewDelegate {
    private var metalView: MTKView!
    private var queue: MTLCommandQueue?
    private var lastShellCommand: MTLCommandBuffer?
    private let output = UITextView()
    private let fpsLabel = UILabel()
    private var lastFPSLabelUpdate: CFTimeInterval = 0
    /// The start screen; it hides once the game's world is up.
    private lazy var home = HomeView(modes: GameMode.allCases.map { ($0.title, $0 == .story ? "book.fill" : "map.fill") }, log: output)
    private var launchButton: UIButton { home.playButton }
    private var preloadLabel: UILabel { home.preloadLabel }
    private var controllerLabel: UILabel { home.controllerLabel }
    private var diagnosticsOverlay: UIView? { home }
    private let audioEngine = AVAudioEngine()
    private var audioSource: AVAudioSourceNode?
    private var displayLink: CADisplayLink?
    private var lastControllerPoll: CFTimeInterval?
    private let nativeLog = NativeLog.shared
    private var logRefreshTimer: Timer?
    private var logRevision: UInt64 = 0
    private let touchControls = TouchControlsView(frame: .zero)
    private let gyro = GyroInput()
    private var engineStarted = false
    private var pendingCheatCode: String?
    private var cheatBanner: UILabel?
    private var bootedPreset = GameSettings.shared.graphicsPreset
    private var bootedMode: GameMode?
    private var stableTimer: Timer?
    private var healthTimer: Timer?
    private var lastHealth: [UInt64] = [0, 0, 0, 0, 0, 0, 0]
    private var padProof: PGPadState?
    private var lastGameStatus: UInt32 = 999
    private var worldReadyAt: CFTimeInterval?
    private var tiltNeutral: Double?
    private var tiltSince: CFTimeInterval?
    private var tiltSmoothed: Double = 0
    private var motionOrientation: UIInterfaceOrientation?
    private var touchControlsAvailable = false
    private var gameplayReadiness = GameplayReadiness()
    private var lastTouchInputTrace = ""
    private var movementProofStarted = false
    private var proofController: GCController?
    private var proofInputSamples = 0
    private var proofInputActive = false
    #if targetEnvironment(simulator)
    private var simulatorKeys = Set<UIKeyboardHIDUsage>()
    override var canBecomeFirstResponder: Bool { true }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // With keyboard and mouse on, keys reach the game as PC keys instead (KeyboardMouse).
        let pcKeys = GameSettings.shared.keyboardMouse && KeyboardMouse.shared.hasKeyboard
        for press in presses { if let key = press.key, !pcKeys { simulatorKeys.insert(key.keyCode) } }
        super.pressesBegan(presses, with: event)
    }
    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses { if let key = press.key { simulatorKeys.remove(key.keyCode) } }
        super.pressesEnded(presses, with: event)
    }
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        simulatorKeys.removeAll()
        super.pressesCancelled(presses, with: event)
    }
    #endif

    override var prefersStatusBarHidden: Bool { true }
    /// While playing with a mouse (iPad), the pointer is captured so moving it looks around.
    override var prefersPointerLocked: Bool { engineStarted && GameSettings.shared.keyboardMouse && KeyboardMouse.shared.hasMouse }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }

    override func viewDidLoad() {
        super.viewDidLoad()
        UIApplication.shared.isIdleTimerDisabled = true
        let device = MTLCreateSystemDefaultDevice()
        metalView = MTKView(frame: .zero, device: device)
        queue = device?.makeCommandQueue()
        metalView.delegate = self
        metalView.clearColor = MTLClearColorMake(0.025, 0.025, 0.035, 1)
        metalView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(metalView)

        controllerLabel.text = String(localized: "Controller: none connected", table: "Main")
        // Progress text (preparing assets, loading) shows on the disabled Play button.
        let playStyle = launchButton.configurationUpdateHandler
        launchButton.configurationUpdateHandler = { [weak self] button in
            playStyle?(button)
            // Before Play is pressed a disabled button still says Play (files or mode missing).
            let playTitle = String(localized: "Play", table: "Main")
            let title = button.isEnabled || !(self?.engineStarted ?? false) ? playTitle : button.title(for: .disabled) ?? String(localized: "Loading…", table: "Main")
            var text = AttributedString(title)
            text.font = Theme.display(20, .heavy)
            text.foregroundColor = button.isEnabled ? UIColor(red: 0.16, green: 0.07, blue: 0.02, alpha: 1) : UIColor(white: 1, alpha: 0.7)
            button.configuration?.attributedTitle = text
            button.configuration?.image = title == playTitle ? UIImage(systemName: "play.fill", withConfiguration: UIImage.SymbolConfiguration(weight: .heavy)) : nil
        }
        launchButton.addTarget(self, action: #selector(startEngine), for: .touchUpInside)
        output.isEditable = false
        #if DEBUG
        output.isHidden = !ProcessInfo.processInfo.arguments.contains("--show-log")
        #else
        output.isHidden = true
        #endif
        output.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        output.textColor = .white
        output.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        output.layer.cornerRadius = 12
        home.settingsButton.addAction(UIAction { [weak self] _ in self?.showSettings() }, for: .touchUpInside)
        home.cheatsButton.addAction(UIAction { [weak self] _ in self?.showCheats() }, for: .touchUpInside)
        home.layoutButton.addAction(UIAction { [weak self] _ in self?.showLayoutEditor() }, for: .touchUpInside)
        home.onFiles = { [weak self] in self?.showGameFiles() }
        home.onMap = { [weak self] index in
            guard let self, !self.engineStarted else { return }
            GameSettings.shared.sandboxMap = index
            self.refreshModeChoice()
        }
        home.onMode = { [weak self] index in
            guard let self, !self.engineStarted else { return }
            GameSettings.shared.gameMode = GameMode.allCases[index]
            self.refreshModeChoice()
        }
        updateServerStatus()
        // Debug/automation: --local-game-folder /path (a folder the app can already read) skips the picker.
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--local-game-folder"), index + 1 < ProcessInfo.processInfo.arguments.count {
            let folder = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[index + 1])
            if case let .refused(problem) = GameFolder.choose(folder) { appendLog("Game folder refused: " + problem) }
        }
        if GameFolder.isChosen { updateServerStatus() }
        else if !GameSettings.shared.assetServer.isEmpty { testAssetServer() }
        // Debug/automation: --game-mode story|sandbox picks the mode before Play.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--game-mode"), index + 1 < arguments.count {
            GameSettings.shared.gameMode = arguments[index + 1] == "story" ? .story : .sandbox
        }
        refreshModeChoice()
        home.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(home)
        fpsLabel.text = String(localized: "— FPS", table: "Main")
        fpsLabel.isHidden = true
        fpsLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        fpsLabel.textColor = .white
        fpsLabel.textAlignment = .center
        fpsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.5)
        fpsLabel.layer.cornerRadius = 6
        fpsLabel.clipsToBounds = true
        fpsLabel.isUserInteractionEnabled = false
        fpsLabel.accessibilityLabel = String(localized: "Game frame rate", table: "Main")
        fpsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(fpsLabel)
        touchControls.translatesAutoresizingMaskIntoConstraints = false
        touchControls.isHidden = true
        touchControls.inputChanged = { [weak self] in self?.pollController() }
        touchControls.openSettings = { [weak self] in self?.showSettings() }
        touchControls.openCheats = { [weak self] in self?.showCheats() }
        touchControls.hintsChanged = { [weak self] line in self?.appendLog(line) }
        KeyboardMouse.shared.start()
        KeyboardMouse.shared.changed = { [weak self] in
            guard let self else { return }
            self.appendLog("Keyboard: \(KeyboardMouse.shared.hasKeyboard ? "connected" : "none"), mouse: \(KeyboardMouse.shared.hasMouse ? "connected" : "none")")
            self.setNeedsUpdateOfPrefersPointerLocked()
        }
        view.addSubview(touchControls)
        #if PG_UI_SMOKE_TEST
        if arguments.contains("--verify-input-reset") {
            touchControls.verifyInputReset()
            KeyboardMouse.shared.verifyFocusReset()
            appendLog("UIKit input reset regression passed.")
        }
        #endif
        NSLayoutConstraint.activate([
            touchControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            touchControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            touchControls.topAnchor.constraint(equalTo: view.topAnchor),
            touchControls.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        NSLayoutConstraint.activate([
            fpsLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            fpsLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            fpsLabel.widthAnchor.constraint(equalToConstant: 68),
            fpsLabel.heightAnchor.constraint(equalToConstant: 24)
        ])
        NSLayoutConstraint.activate([
            metalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            metalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            metalView.topAnchor.constraint(equalTo: view.topAnchor),
            metalView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            home.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            home.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            home.topAnchor.constraint(equalTo: view.topAnchor),
            home.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        if !output.isHidden {
            logRefreshTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.refreshLogView() }
        }
        appendLog("GtaV Mobile \(Theme.appVersion) on iOS \(UIDevice.current.systemVersion)")
        appendLog("Native UIKit + Metal host. Engine compiled into the app; no WebView or JIT.")
        appendLog("Metal device: \(device?.name ?? "unavailable")")
        GameFolder.log = { [weak self] line in self?.appendLog(line) }
        // A game folder moved into Files › On My iPhone › GtaV Mobile is found without any picking.
        lookForGameFiles()
        NotificationCenter.default.addObserver(self, selector: #selector(lookForGameFiles), name: UIScene.didActivateNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(installChanged), name: .gameInstallChanged, object: nil)
        displayLink = CADisplayLink(target: self, selector: #selector(pollController))
        configureDisplayLink(frameRateCap: GameSettings.shared.frameRateCap)
        displayLink?.add(to: .main, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerChanged), name: .GCControllerDidDisconnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(controllerChanged), name: .GCControllerDidConnect, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(leftApp), name: UIScene.didEnterBackgroundNotification, object: nil)
        if let recovery = GameSettings.shared.recoverFromFailedBoot() {
            appendLog("Previous launch on \(recovery.failed.title) did not finish; lowered to \(recovery.fallback.title)\(recovery.resetHeight.map { ", resolution \($0)p back to Auto" } ?? "").")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { self.explainRecovery(recovery) }
        }
        if ProcessInfo.processInfo.arguments.contains("--touch-controls-preview") {
            diagnosticsOverlay?.isHidden = true
            touchControlsAvailable = true
            fpsLabel.isHidden = false
            touchControls.isHidden = false
        }
        NotificationCenter.default.addObserver(self, selector: #selector(preloadChanged), name: .assetPreloadChanged, object: nil)
        // Continue an unfinished "Download all game files" after a relaunch.
        AssetPreloader.shared.resumeIfNeeded()
        if ProcessInfo.processInfo.arguments.contains("--preload-autostart") {
            // Debug: start the download without tapping (simulator checks).
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let message = AssetPreloader.shared.start() { self.appendLog("Preload refused: " + message) }
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--open-layout-editor") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showLayoutEditor() }
        }
        if ProcessInfo.processInfo.arguments.contains("--open-game-files") || ProcessInfo.processInfo.arguments.contains("--install-link") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showGameFiles() }
        }
        if ProcessInfo.processInfo.arguments.contains("--open-settings") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showSettings() }
        }
        if ProcessInfo.processInfo.arguments.contains("--open-cheats") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.showCheats() }
        }
        if ProcessInfo.processInfo.arguments.contains("--boot-engine") {
            DispatchQueue.main.async { self.startEngine() }
        }
    }

    @objc private func preloadChanged() {
        let summary = AssetPreloader.shared.launchSummary
        preloadLabel.text = summary
        preloadLabel.isHidden = summary == nil
    }

    func appendLog(_ line: String) {
        nativeLog.append(line)
        // Ordinary engine diagnostics never enqueue work on the input/UI thread.
        guard isEngineUIEvent(line) else { return }
        if Thread.isMainThread { handleLogEvent(line) }
        else { DispatchQueue.main.async { [weak self] in self?.handleLogEvent(line) } }
    }

    private func refreshLogView() {
        guard !output.isHidden, diagnosticsOverlay?.isHidden != true else { return }
        let snapshot = nativeLog.snapshot()
        guard snapshot.revision != logRevision else { return }
        logRevision = snapshot.revision
        output.text = snapshot.lines.joined(separator: "\n")
        if !output.text.isEmpty { output.scrollRangeToVisible(NSRange(location: output.text.utf16.count - 1, length: 1)) }
    }

    fileprivate func handleLogEvent(_ line: String) {
        if line.hasPrefix("ASSET_WARM_PROGRESS ") {
            let parts = line.split(separator: " ")
            if parts.count >= 3 {
                let size = Double(parts[2]).map { amount in
                    let gigabytes = (amount * 1048576 / 1_000_000_000).formatted(.number.precision(.fractionLength(1)))
                    return String(localized: "\(gigabytes) GB", table: "Main")
                } ?? ""
                let percent = Int(parts[1]) ?? 0
                launchButton.setTitle(String(localized: "Preparing assets… \(percent)% · \(size)", table: "Main"), for: .disabled); launchButton.setNeedsUpdateConfiguration()
            }
        }
        if line == "ASSET_WARM_COMPLETE" { launchButton.setTitle(String(localized: "Loading…", table: "Main"), for: .disabled); launchButton.setNeedsUpdateConfiguration() }
        if line == "WORLD_READY", ProcessInfo.processInfo.arguments.contains("--capture-world") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 35) { PGCaptureNativeFrame("optimized-world") }
        }
        if line == "WORLD_READY", let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--pad-script"), i + 1 < ProcessInfo.processInfo.arguments.count, !movementProofStarted {
            movementProofStarted = true
            runPadScript(ProcessInfo.processInfo.arguments[i + 1])
        }
        if line == "WORLD_READY", ProcessInfo.processInfo.arguments.contains("--verify-pad"), !movementProofStarted {
            movementProofStarted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.verifyVirtualPad() }
        }
        if line == "WORLD_READY", ProcessInfo.processInfo.arguments.contains("--verify-movement"), !movementProofStarted {
            movementProofStarted = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.verifyMovement() }
        }
        if line == "WORLD_READY", worldReadyAt == nil { worldReadyAt = CACurrentMediaTime() }
        if line == "WORLD_READY", healthTimer == nil {
            // Every 10 s: memory, how often the memory guard held streaming back, and game-file reads.
            healthTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in self?.logHealth() }
        }
        if line == "WORLD_READY", stableTimer == nil {
            // Three minutes in the world counts as a launch that fits in memory.
            stableTimer = Timer.scheduledTimer(withTimeInterval: 180, repeats: false) { _ in GameSettings.shared.markBootStable() }
        }
        if line == "WORLD_READY" || line.contains("\"label\":\"First frame\"") {
            diagnosticsOverlay?.isHidden = true
            fpsLabel.isHidden = false
        }
        if line.hasPrefix("Native boot stopped:") || line == "iOS could not reserve the engine memory." {
            audioEngine.stop()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            metalView.isPaused = true
        }
    }

    /// The launch screen asks for a mode once; after that it remembers it.
    private func refreshModeChoice() {
        let choice = GameSettings.shared.gameModeChoice
        home.setMode(choice.flatMap { GameMode.allCases.firstIndex(of: $0) }, detail: choice?.detail ?? String(localized: "Choose Story mode or Sandbox to play.", table: "Main"), enabled: !engineStarted)
        home.setMap(GameSettings.shared.sandboxMap, visible: choice == .sandbox, enabled: !engineStarted)
        updatePlayEnabled()
    }

    private func configureDisplayLink(frameRateCap: Int) {
        let top = Float(view.window?.windowScene?.screen.maximumFramesPerSecond ?? 60)
        let target = frameRateCap == 0 ? top : min(Float(frameRateCap == 30 ? 30 : 60), top)
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: frameRateCap == 0 ? min(80, top) : target, maximum: target, preferred: target)
        appendLog("Display cadence: screen maximum=\(Int(top)) Hz, requested=\(Int(target)) Hz, engine cap=\(frameRateCap).")
    }

    @objc private func startEngine() {
        if GameSettings.shared.gameModeChoice == nil {
            // Automated launches without a choice keep the old sandbox start.
            guard ProcessInfo.processInfo.arguments.contains("--boot-engine") else { return }
        }
        guard let path = EnginePaths.manifest else {
            appendLog("Asset manifest is missing from the app bundle.")
            return
        }
        metalView.isPaused = true
        metalView.delegate = nil
        // Dawn owns the drawable size from here; MTKView must not reset it on layout.
        metalView.autoResizeDrawable = false
        PGAttachMetalLayer(Unmanaged.passUnretained(metalView.layer).toOpaque())
        launchButton.isEnabled = false
        home.settingsButton.isHidden = true
        home.layoutButton.isHidden = true
        engineStarted = true
        refreshModeChoice()
        let mode = GameSettings.shared.gameMode
        bootedMode = mode
        let testMap = mode == .sandbox && GameSettings.shared.sandboxMap == 1
        PGSetStartMode(testMap ? 3 : Int32(mode.rawValue))
        appendLog("Game mode: \(mode.title)\(mode == .sandbox ? " on " + GameSettings.sandboxMapTitles[GameSettings.shared.sandboxMap] : "")")
        bootedPreset = GameSettings.shared.graphicsPreset
        // Home settings can change after viewDidLoad. Use the cap passed to the
        // engine now, including resetting an earlier Unlocked preference.
        let frameRateCap = GameSettings.shared.frameRateCap
        configureDisplayLink(frameRateCap: frameRateCap)
        appendLog("Graphics: " + GraphicsConfiguration.apply(GameSettings.shared, screen: view.bounds.size, frameRateCap: frameRateCap))
        appendLog("Device: " + GameSettings.shared.tier.summary)
        GameSettings.shared.markBootStarted()
        launchButton.setTitle(String(localized: "Loading…", table: "Main"), for: .disabled); launchButton.setNeedsUpdateConfiguration()
        appendLog("Native touch controls support held buttons, sprint and weapon selection.")
        startAudio()
        let (root, rootNote) = EnginePaths.filesRoot()
        if let rootNote { appendLog(rootNote) }
        // The game's own settings.xml only holds graphics and display options, which the app sets on
        // every launch. Some choices in the game's pause menu (MSAA, DirectX version, resolution)
        // stopped it from starting at all, so the file is reset before each launch.
        for mode in ["userdata", "sandbox"] {
            let settings = "\(root)/\(mode)/Documents/Rockstar Games/GTA V/settings.xml"
            if (try? FileManager.default.removeItem(atPath: settings)) != nil { appendLog("Reset the game's own graphics settings (\(mode)); use the app's Settings for graphics.") }
        }
        if GameFolder.isChosen {
            guard let data = GameFolder.open() else {
                appendLog("The game folder on this iPhone can't be opened any more. Choose it again.")
                showWhenFree(title: String(localized: "Game files not found", table: "Main"), message: String(localized: "The game folder was moved or deleted. Put it back in Files › On My iPhone › GtaV Mobile, or pick it again.", table: "Main"))
                GameFolder.clear(); updateServerStatus(); launchButton.isEnabled = true; launchButton.setTitle(String(localized: "Play", table: "Main"), for: .normal)
                return
            }
            PGSetLocalGameFolder(data.path)
        } else {
            PGSetAssetServer(GameSettings.shared.assetServer)
        }
        AssetPreloader.shared.engineRunning = true
        path.withCString { manifest in
            root.withCString { PGStartEngine(manifest, $0, engineLog, Unmanaged.passUnretained(self).toOpaque()) }
        }
    }

    private func verifyMovement() {
        let testController = GCController.withExtendedGamepad()
        guard let pad = testController.extendedGamepad else {
            appendLog("Movement proof needs the native touch controller.")
            return
        }
        appendLog("Movement proof: capturing the world before native controller input.")
        PGCaptureNativeFrame("movement-before")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            self.proofController = testController
            self.proofInputActive = true
            self.proofInputSamples = 0
            pad.leftThumbstick.setValueForXAxis(0, yAxis: 0.8)
            pad.rightThumbstick.setValueForXAxis(0.25, yAxis: 0)
            self.appendLog("Movement proof: native controller sticks active.")
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                self.proofInputActive = false
                self.appendLog("Movement proof: \(self.proofInputSamples) controller samples delivered to the engine.")
                pad.leftThumbstick.setValueForXAxis(0, yAxis: 0)
                pad.rightThumbstick.setValueForXAxis(0, yAxis: 0)
                self.proofController = nil
                PGCaptureNativeFrame("movement-after")
                self.appendLog("Movement proof: native controller sticks released.")
            }
        }
    }

    /// Debug: scripted controller input, "step;step;..." with steps "wait:<s>", "hold:<buttons>:<s>"
    /// (buttons: a b x y l1 r1 lt rt down up left right start rx+ rx- ry+ ry-, joined with +), "frame:<name>".
    /// Debug: --watch-memory <address> <length> logs which bytes change between pad-script frames.
    private var watchSnapshot: [UInt8]?
    private func watchMemory(_ label: String) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "--watch-memory"), i + 2 < args.count,
              let start = UInt64(args[i + 1]), let length = Int(args[i + 2]) else { return }
        var now = [UInt8](repeating: 0, count: length)
        guard now.withUnsafeMutableBytes({ PGDebugReadMemory(start, $0.baseAddress, UInt64(length)) }) else { return }
        if let before = watchSnapshot {
            var changes: [String] = []
            for k in 0..<length where before[k] != now[k] { changes.append("\(start + UInt64(k)):\(before[k])>\(now[k])") }
            appendLog("Memory watch \(label): \(changes.count) changed " + changes.prefix(400).joined(separator: " "))
        }
        watchSnapshot = now
    }
    private func runPadScript(_ script: String) {
        var at = 0.0
        for step in script.split(separator: ";") {
            let parts = step.split(separator: ":").map(String.init)
            switch parts.first {
            case "wait": at += Double(parts.count > 1 ? parts[1] : "1") ?? 1
            case "frame":
                let name = parts.count > 1 ? parts[1] : "script"
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { PGCaptureNativeFrame(name); self.appendLog("Pad script: frame \(name)"); self.watchMemory(name) }
            case "hold":
                var state = PGPadState(); var held = PadButtons()
                for name in (parts.count > 1 ? parts[1] : "").split(separator: "+") {
                    switch name {
                    case "a": held.insert(.a); case "b": held.insert(.b); case "x": held.insert(.x); case "y": held.insert(.y)
                    case "l1": held.insert(.l1); case "r1": held.insert(.r1); case "down": held.insert(.down); case "up": held.insert(.up)
                    case "left": held.insert(.left); case "right": held.insert(.right); case "start": held.insert(.start)
                    case "lt": state.leftTrigger = 1; case "rt": state.rightTrigger = 1
                    case "rx+": state.rightX = 1; case "rx-": state.rightX = -1; case "ry+": state.rightY = 1; case "ry-": state.rightY = -1
                    default: break
                    }
                }
                state.padButtons = held
                let duration = Double(parts.count > 2 ? parts[2] : "0.3") ?? 0.3
                let label = String(step)
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { self.padProof = state; self.appendLog("Pad script: \(label)") }
                at += duration
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { self.padProof = PGPadState() }
            default: break
            }
        }
        // Hand input back to the touch controls (and controller) when the script ends.
        DispatchQueue.main.asyncAfter(deadline: .now() + at + 0.5) { self.padProof = nil; self.appendLog("Pad script: done") }
    }

    /// Simulator proof that the engine accepts the virtual controller and
    /// that controller aiming locks on: walk, pick a gun from the wheel, aim.
    private func verifyVirtualPad() {
        func log(_ step: String) { appendLog("Pad proof: \(step); input device \(PGLastInputDevice()), targeting mode \(PGTargetingMode())") }
        func pad(_ build: (inout PGPadState) -> Void) -> PGPadState { var s = PGPadState(); build(&s); return s }
        let steps: [(Double, PGPadState?, String?, String?)] = [
            (0, PGPadState(), "before input", "pad-before"),
            (0.5, pad { $0.leftY = 0.8 }, nil, nil),
            (3.5, PGPadState(), "walked forward", "pad-moved"),
            // Weapon wheel: hold L1 and point the right stick at a slot.
            (4.5, pad { $0.padButtons = .l1 }, nil, nil),
            (5.3, pad { $0.padButtons = .l1; $0.rightX = 1 }, "wheel open, pointing right", "pad-wheel"),
            (6.3, PGPadState(), "wheel released", nil),
            (8.0, pad { $0.leftTrigger = 1 }, nil, nil),
            (9.2, pad { $0.leftTrigger = 1 }, "aim held", "pad-aim"),
            (9.4, pad { $0.leftTrigger = 1; $0.rightX = 0.35 }, nil, nil),
            (10.0, pad { $0.leftTrigger = 1; $0.rightTrigger = 1 }, nil, nil),
            (10.6, pad { $0.leftTrigger = 1; $0.rightTrigger = 1 }, "aim and fire", "pad-fire"),
            (11.5, PGPadState(), "released", nil)]
        for (time, state, message, frame) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                if let state { self.padProof = state }
                if let message { log(message) }
                if let frame { PGCaptureNativeFrame(frame) }
            }
        }
    }

    private func startAudio() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setPreferredSampleRate(48000)
            try session.setActive(true)
            let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
            let source = AVAudioSourceNode(format: format) { _, _, count, audioBufferList in
                let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
                guard buffers.count >= 2, let left = buffers[0].mData, let right = buffers[1].mData else { return noErr }
                PGFillAudio(left.assumingMemoryBound(to: Float.self), right.assumingMemoryBound(to: Float.self), count)
                return noErr
            }
            audioSource = source
            audioEngine.attach(source)
            audioEngine.connect(source, to: audioEngine.mainMixerNode, format: format)
            #if targetEnvironment(simulator)
            // Simulator runs are silent unless --sound is passed (test runs play through the Mac's speakers).
            if !ProcessInfo.processInfo.arguments.contains("--sound") { audioEngine.mainMixerNode.outputVolume = 0 }
            #endif
            // Silent test runs on a phone.
            if ProcessInfo.processInfo.arguments.contains("--mute") { audioEngine.mainMixerNode.outputVolume = 0 }
            try audioEngine.start()
        } catch { appendLog("Native audio setup failed: \(error.localizedDescription)") }
    }

    @objc private func controllerChanged() { pollController() }

    // MARK: Game file server

    /// Back in the app (for example after moving the game folder in Files): look again. Checking every
    /// file takes about a second, so it runs off the main thread.
    @objc private func lookForGameFiles() {
        guard !engineStarted, !GameFolder.isChosen || GameFolder.inAppFolder, !lookingForGameFiles, !GameInstallManager.shared.isRunning else { return }
        lookingForGameFiles = true
        if !GameFolder.isChosen { home.setFiles(.busy, title: String(localized: "Looking for your game files…", table: "Main"), detail: "") }
        DispatchQueue.global(qos: .userInitiated).async {
            GameFolder.findInAppFolder()
            DispatchQueue.main.async {
                self.lookingForGameFiles = false
                self.updateServerStatus()
            }
        }
    }
    private var lookingForGameFiles = false
    @objc private func installChanged() {
        guard !engineStarted else { return }
        updateServerStatus()
        // Finished while the game files screen was closed: say how it went here.
        guard presentedViewController == nil, case let .finished(result) = GameInstallManager.shared.state else { return }
        GameInstallManager.shared.acknowledge()
        switch result {
        case .success: appendLog("Game files installed and checked.")
        case let .failure(message): showWhenFree(title: String(localized: "Couldn't get the game files", table: "Main"), message: message)
        case .webPage: showGameFiles()
        }
    }
    /// Shows where the game files come from, and whether Play can start.
    private func updateServerStatus(_ status: String? = nil) {
        // A download running in the background shows on the card (tap it for the full progress).
        if case let .running(update) = GameInstallManager.shared.state {
            home.setFiles(.busy, title: update.title, detail: update.detail.split(separator: "\n").first.map(String.init) ?? String(localized: "Tap to see the progress.", table: "Main"))
            updatePlayEnabled()
            return
        }
        // A server address that isn't a web address would boot the game with no files at all.
        let raw = GameSettings.shared.assetServer
        let server = Self.isServerAddress(raw) ? raw : ""
        if GameFolder.isChosen {
            let place = GameFolder.inAppFolder ? String(localized: "In the GtaV Mobile folder", table: "Main") : String(localized: "On this iPhone", table: "Main")
            let problems = GameFolder.acceptedProblemCount
            let problemDetail = String(localized: "\(problems) problem files, playing anyway", table: "Main")
            home.setFiles(problems > 0 ? .attention : .ready, title: "\"\(GameFolder.name)\"",
                          detail: problems > 0 ? String(localized: "\(place) · \(problemDetail)", table: "Main") : String(localized: "\(place) · every file checked", table: "Main"))
        } else if server.isEmpty, let report = GameFolder.appFolderReport {
            home.setFiles(.problem, title: report.explanation.title, detail: String(localized: "Found your game folder, but it can't be used yet. Tap to see why and how to fix it.", table: "Main"))
        } else if server.isEmpty, !raw.isEmpty {
            home.setFiles(.problem, title: String(localized: "Server address isn't a web address", table: "Main"), detail: String(localized: "Tap to change it.", table: "Main"))
        } else if server.isEmpty {
            home.setFiles(.attention, title: String(localized: "Add your game files", table: "Main"), detail: GameFolder.archivesFound.isEmpty ? String(localized: "Tap to find them on this iPhone, or get them from a link or an archive.", table: "Main") : String(localized: "Found a game archive. Tap to unpack it.", table: "Main"))
        } else if status == String(localized: "checking…", table: "Main") {
            home.setFiles(.busy, title: String(localized: "Streaming from your server", table: "Main"), detail: server)
        } else {
            let ok = status == nil || status == String(localized: "connected ✓", table: "Main")
            let detail = status.map { String(localized: "\(server) · \($0)", table: "Main") } ?? server
            home.setFiles(ok ? .ready : .problem, title: String(localized: "Streaming from your server", table: "Main"), detail: detail)
        }
        updatePlayEnabled()
    }
    /// Play needs game files and a chosen mode.
    private func updatePlayEnabled() {
        let server = Self.isServerAddress(GameSettings.shared.assetServer)
        launchButton.isEnabled = !engineStarted && !GameInstallManager.shared.isRunning && (GameFolder.isChosen || server) && GameSettings.shared.gameModeChoice != nil
    }
    static func isServerAddress(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(), let host = url.host else { return false }
        return (scheme == "http" || scheme == "https") && !host.isEmpty
    }
    /// The game files screen: checking, finding, downloading and unpacking.
    private func showGameFiles() {
        guard !engineStarted, presentedViewController == nil else { return }
        let controller = GameFilesViewController()
        controller.onChange = { [weak self] in self?.updateServerStatus() }
        controller.onServer = { [weak self] server in
            GameFolder.clear()
            GameSettings.shared.assetServer = server
            self?.appendLog("Game files: streaming from \(server)")
            self?.testAssetServer()
        }
        let navigation = UINavigationController(rootViewController: controller)
        Theme.styleNavigation(navigation)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }
    /// Shows a message once nothing else (like the closing folder picker) is on screen; iOS drops
    /// alerts presented during another presentation.
    private func showWhenFree(title: String, message: String, attempt: Int = 0) {
        if (presentedViewController != nil || transitionCoordinator != nil) && attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.showWhenFree(title: title, message: message, attempt: attempt + 1) }
            return
        }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK", table: "Main"), style: .default))
        present(alert, animated: true)
    }
    /// Checks that the server answers with the game's file list.
    private func testAssetServer() {
        var server = GameSettings.shared.assetServer
        while server.hasSuffix("/") { server.removeLast() }
        guard let url = URL(string: server + "/data/manifest.json"), url.scheme?.hasPrefix("http") == true else {
            updateServerStatus(String(localized: "not a valid address", table: "Main")); return
        }
        updateServerStatus(String(localized: "checking…", table: "Main"))
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "HEAD"
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                if code == 200 { self?.updateServerStatus(String(localized: "connected ✓", table: "Main")) }
                else if let error { self?.updateServerStatus(String(localized: "can't connect (\(error.localizedDescription))", table: "Main")) }
                else { self?.updateServerStatus(String(localized: "answered \(code); is the address the folder with data/ and b/?", table: "Main")) }
            }
        }.resume()
    }
    /// An unfinished launch is not proof of an out-of-memory termination.
    private func explainRecovery(_ recovery: GameSettings.BootRecovery) {
        let title = String(localized: "Ready to try again", table: "Main")
        let message = recovery.resetHeight != nil
            ? String(localized: "The previous game launch didn't finish. Graphics are now set to \(recovery.fallback.title) with Auto resolution. You can adjust them in Settings or share the log to help investigate.", table: "Main")
            : String(localized: "The previous game launch didn't finish. Graphics are now set to \(recovery.fallback.title). You can adjust them in Settings or share the log to help investigate.", table: "Main")
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK", table: "Main"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Share log", table: "Main"), style: .default) { [weak self] _ in
            guard let self else { return }
            self.nativeLog.flush()
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let logs = ["native-port-previous.log", "native-port.log"].map { documents.appendingPathComponent($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
            let sheet = UIActivityViewController(activityItems: logs, applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = self.view
            self.present(sheet, animated: true)
        })
        alert.addAction(UIAlertAction(title: String(localized: "Try \(recovery.failed.title) again", table: "Main"), style: .destructive) { [weak self] _ in
            GameSettings.shared.undoRecovery(recovery)
            self?.appendLog("Kept \(recovery.failed.title) after the warning.")
        })
        presentRecoveryWhenFree(alert)
    }

    private func presentRecoveryWhenFree(_ alert: UIAlertController) {
        guard presentedViewController == nil, transitionCoordinator == nil,
              view.window?.windowScene?.activationState == .foregroundActive else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.presentRecoveryWhenFree(alert) }
            return
        }
        present(alert, animated: true)
    }

    private func logHealth() {
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let ok = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
        } == KERN_SUCCESS
        let used = ok ? Int(vm.phys_footprint / 1_048_576) : -1
        let free = Int(os_proc_available_memory() / 1_048_576)
        var reads = [UInt64](repeating: 0, count: 6)
        reads.withUnsafeMutableBufferPointer { PGAssetHealth($0.baseAddress) }
        let now = [PGMemoryBudgetClamps()] + reads
        let d = zip(now, lastHealth).map { $0 &- $1 }
        lastHealth = now
        let avgMS = d[1] > 0 ? Double(d[6]) / Double(d[1]) / 1000 : 0
        appendLog(String(format: "Health: memory %d MB used, %d MB free · guard held back streaming %llu× · reads %llu (%.1f MB, avg %.1f ms, slow %llu, errors %llu) · %.0f FPS",
                         used, free, d[0], d[1], Double(d[2]) / 1_048_576, avgMS, d[5], d[3], PGRenderedFramesPerSecond()))
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "nominal"
        case .fair: thermal = "fair"
        case .serious: thermal = "serious"
        case .critical: thermal = "critical"
        @unknown default: thermal = "unknown"
        }
        let metalMB = (metalView.device?.currentAllocatedSize ?? 0) / 1_048_576
        appendLog("Resources: Metal \(metalMB) MB · unified memory \(metalView.device?.hasUnifiedMemory == true) · thermal \(thermal) · low power \(ProcessInfo.processInfo.isLowPowerModeEnabled)")
    }

    @objc private func leftApp() {
        nativeLog.flush()
        if stableTimer?.isValid != false { GameSettings.shared.markBootInterrupted() }
    }

    /// The touch-controls layout editor (pre-game, or from Settings).
    private func showLayoutEditor() {
        releaseTouchControls()
        let editor = ControlsLayoutEditorController()
        editor.modalPresentationStyle = .fullScreen
        editor.onDone = { [weak self] in
            self?.touchControls.updateVisibility()
            self?.appendLog("Controls layout saved (\(ControlsLayout.entries.count) customized controls).")
        }
        (presentedViewController ?? self).present(editor, animated: true)
    }
    private func showSettings() {
        guard presentedViewController == nil else { return }
        releaseTouchControls()
        let controller = SettingsViewController(engineRunning: engineStarted, runningMode: bootedMode)
        controller.gameModeChanged = { [weak self] in self?.refreshModeChoice() }
        controller.resolutionChanged = { [weak self] in self?.applyLiveResolution() }
        controller.controlsChanged = { [weak self] in self?.touchControls.updateVisibility() }
        controller.editLayout = { [weak self] in self?.showLayoutEditor() }
        controller.targetingChanged = { PGSetTargetingMode(Int32(GameSettings.shared.targetingMode)) }
        controller.applyCheat = { [weak self] code, buttons, mode in
            self?.dismiss(animated: true) { self?.applyCheat(code, buttons: buttons, mode: mode) }
        }
        let navigation = UINavigationController(rootViewController: controller)
        Theme.styleNavigation(navigation)
        present(navigation, animated: true)
    }

    private func showCheats() {
        guard presentedViewController == nil else { return }
        releaseTouchControls()
        let controller = CheatsViewController(engineRunning: engineStarted)
        controller.onApply = { [weak self] code, buttons, mode in
            self?.dismiss(animated: true) { self?.applyCheat(code, buttons: buttons, mode: mode) }
        }
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            title: String(localized: "Done", table: "Cheats"), primaryAction: UIAction { [weak controller] _ in
                controller?.dismiss(animated: true)
            })
        let navigation = UINavigationController(rootViewController: controller)
        Theme.styleNavigation(navigation)
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    private func applyCheat(_ code: String, buttons: [UInt16], mode: CheatInputMode) {
        let title = String(localized: "Cheat codes", table: "Cheats")
        appendLog("Cheat requested: \(code), mode \(mode.rawValue), engine \(engineStarted), status \(PGGameStatus()), pause \(PGPauseMenuActive())")
        guard engineStarted, !PGLoadingScreenActive(), PGGameStatus() == 0, !PGPauseMenuActive() else {
            showWhenFree(title: title, message: String(localized: "Wait until the game has loaded, close its pause menu and phone, and return to controlling the character.", table: "Cheats"))
            return
        }
        guard !PGIsCheatInProgress() else {
            showWhenFree(title: title, message: String(localized: "Another cheat input is still being sent. Wait a moment and try again.", table: "Cheats"))
            return
        }
        touchControls.reset(publish: false)
        KeyboardMouse.shared.setFocused(false)
        KeyboardMouse.shared.releaseAll()
        stopMotionInput()
        PGUpdateVirtualPad(PGPadState())
        let useGamepad = mode.usesGamepad
        let sent = useGamepad
            ? buttons.withUnsafeBufferPointer { PGApplyCheatGamepad($0.baseAddress, UInt32($0.count)) }
            : code.withCString { PGApplyCheatConsole($0) }
        guard sent else {
            showWhenFree(title: title, message: String(localized: "The cheat input could not start. Return to the game and try again.", table: "Cheats"))
            return
        }
        pendingCheatCode = code
        showCheatBanner(String(localized: "Sending cheat input: \(code)", table: "Cheats"))
    }

    private func showCheatBanner(_ text: String) {
        cheatBanner?.removeFromSuperview()
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .preferredFont(forTextStyle: .callout)
        label.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 60),
            label.widthAnchor.constraint(equalTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.75),
            label.heightAnchor.constraint(greaterThanOrEqualToConstant: 50)
        ])
        cheatBanner = label
        UIAccessibility.post(notification: .announcement, argument: text)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak label] in
            label?.removeFromSuperview()
            if self?.cheatBanner === label { self?.cheatBanner = nil }
        }
    }
    /// The engine follows back-buffer size changes while running.
    private func applyLiveResolution() {
        guard engineStarted else { return }
        let settings = GameSettings.shared
        let (width, height) = GraphicsConfiguration.size(for: bootedPreset, renderHeight: settings.renderHeight, screen: view.bounds.size, matchScreenShape: settings.matchScreenShape)
        PGSetBackBufferSize(Int32(width), Int32(height))
        appendLog("Graphics: live resize to \(width)×\(height)")
    }
    private func stopMotionInput() {
        gyro.setRunning(false, orientation: .landscapeRight)
        tiltNeutral = nil; tiltSince = nil; tiltSmoothed = 0
        motionOrientation = nil
    }

    @objc private func releaseTouchControls() {
        PGCancelCheat()
        touchControls.reset(publish: false)
        stopMotionInput()
        lastControllerPoll = nil
        #if targetEnvironment(simulator)
        simulatorKeys.removeAll()
        #endif
        KeyboardMouse.shared.setFocused(false)
        KeyboardMouse.shared.releaseAll()
        PGUpdateVirtualPad(PGPadState())
    }

    func sceneDeactivated() {
        metalView.isPaused = true
        releaseTouchControls()
        PGSetGraphicsActive(false)
        lastShellCommand?.waitUntilScheduled()
        appendLog("Scene inactive: Metal submissions suspended and queued work scheduled.")
        nativeLog.flush()
    }

    func sceneActivated() {
        PGSetGraphicsActive(true)
        appendLog("Scene active: Metal submissions resumed.")
        metalView.isPaused = engineStarted
        lastControllerPoll = nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        PGTrimGraphicsMemory()
        appendLog("Memory warning: reclaiming completed, unused Metal upload buffers.")
    }
    private var injectedKey = false, releasedKey = false, injectedMouse = false
    private func injectTestInput(sinceWorld: Double) {
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--inject-key"), i + 3 < arguments.count,
           let key = UInt8(arguments[i + 1], radix: 16), let after = Double(arguments[i + 2]), let hold = Double(arguments[i + 3]) {
            if !injectedKey && sinceWorld > after { injectedKey = true; KeyboardMouse.shared.inject(key: key, down: true); appendLog("Test: key 0x\(arguments[i + 1]) down") }
            if injectedKey && !releasedKey && sinceWorld > after + hold { releasedKey = true; KeyboardMouse.shared.inject(key: key, down: false); appendLog("Test: key 0x\(arguments[i + 1]) up") }
        }
        if let i = arguments.firstIndex(of: "--inject-mouse"), i + 3 < arguments.count,
           let dx = Double(arguments[i + 1]), let dy = Double(arguments[i + 2]), let after = Double(arguments[i + 3]),
           !injectedMouse, sinceWorld > after {
            injectedMouse = true
            KeyboardMouse.shared.inject(dx: dx, dy: dy)
            appendLog("Test: mouse moved \(dx), \(dy)")
        }
    }
    @objc private func pollController() {
        guard view.window?.windowScene?.activationState == .foregroundActive,
              presentedViewController == nil else {
            KeyboardMouse.shared.setFocused(false)
            touchControls.reset(publish: false)
            stopMotionInput()
            lastControllerPoll = nil
            PGUpdateVirtualPad(PGPadState())
            return
        }
        if let code = pendingCheatCode, !PGIsCheatInProgress() {
            pendingCheatCode = nil
            switch PGCheatResult() {
            case 2:
                showCheatBanner(String(localized: "Cheat input sent: \(code)\nCheck the game's confirmation message.", table: "Cheats"))
            case 3:
                showCheatBanner(String(localized: "Cheat input cancelled.", table: "Cheats"))
            default:
                showCheatBanner(String(localized: "Cheat input failed. Return to the game and try again.", table: "Cheats"))
            }
        }
        // The injector owns input until its sequence finishes. Hardware/touch
        // polling must not erase its pressed keys or virtual-pad sample.
        guard !PGIsCheatInProgress() else {
            stopMotionInput()
            lastControllerPoll = nil
            return
        }
        let now = CACurrentMediaTime()
        if now - lastFPSLabelUpdate >= 0.25 {
            let fps = PGRenderedFramesPerSecond()
            fpsLabel.text = fps > 0 ? String(localized: "\(Int(fps.rounded())) FPS", table: "Main") : String(localized: "— FPS", table: "Main")
            lastFPSLabelUpdate = now
        }
        let elapsed = lastControllerPoll.map { now - $0 } ?? (1.0 / 60.0)
        lastControllerPoll = now
        let gameStatus = PGGameStatus()
        if gameStatus != lastGameStatus {
            lastGameStatus = gameStatus
            appendLog("Game state: control \(gameStatus & 1 != 0 ? "off" : "on")\(gameStatus & 2 != 0 ? ", phone out" : "")\(gameStatus & 4 != 0 ? ", cutscene" : "")\(gameStatus & 8 != 0 ? ", warning screen" : "")\(gameStatus & 16 != 0 ? ", no player" : "")")
            if ProcessInfo.processInfo.arguments.contains("--capture-state") { PGCaptureNativeFrame("state-\(gameStatus)-\(Int(now))") }
        }
        if let padProof { PGUpdateVirtualPad(padProof); return }
        // Everything reaches the engine as its own controller, so controller
        // features (assisted aim, analog steering and throttle) apply.
        var state = PGPadState()
        var hasController = false
        if let controller = GCController.controllers().first(where: { $0.extendedGamepad != nil }), let pad = controller.extendedGamepad {
            state = PGPadState(gamepad: pad)
            hasController = true
            if diagnosticsOverlay?.isHidden != true {
                let name = controller.vendorName ?? String(localized: "Gamepad", table: "Main")
                controllerLabel.text = String(localized: "Controller: \(name)", table: "Main")
            }
        } else if diagnosticsOverlay?.isHidden != true {
            controllerLabel.text = String(localized: "Touch controls ready", table: "Main")
        }
        // With a controller connected the touch controls step aside (Settings › Touch controls).
        // Keyboard and mouse: every frame while the game runs (keys go straight to the game as they change).
        let keyboardMouse = GameSettings.shared.keyboardMouse
        if engineStarted && keyboardMouse { KeyboardMouse.shared.send(focused: true) }
        // Automation: --inject-key <vk> <seconds after WORLD_READY> <hold seconds>, --inject-mouse <dx> <dy> <seconds after>.
        if let ready = worldReadyAt { injectTestInput(sinceWorld: now - ready) }
        let pcControls = keyboardMouse && KeyboardMouse.shared.hasKeyboard && KeyboardMouse.shared.hasMouse
        let previewing = ProcessInfo.processInfo.arguments.contains("--touch-controls-preview")
        var pauseMenu = PGPauseMenuActive()
        let hadEnteredGameplay = gameplayReadiness.enteredGameplay
        let controlsReady = gameplayReadiness.allowsControls(engineStarted: engineStarted, loading: PGLoadingScreenActive(), status: gameStatus, paused: pauseMenu, preview: previewing)
        if !hadEnteredGameplay && gameplayReadiness.enteredGameplay {
            PGSetTargetingMode(Int32(GameSettings.shared.targetingMode))
            appendLog("Gameplay controls ready: loading screens inactive, local player controllable; pipeline quiescence not required.")
        }
        if touchControlsAvailable && !controlsReady { touchControls.reset(publish: false) }
        touchControlsAvailable = controlsReady
        let touchActive = touchControlsAvailable && (previewing || !((hasController || pcControls) && GameSettings.shared.hideTouchWithController))
        touchControls.isHidden = !touchActive
        var vehicle = touchActive ? PGCurrentTouchContext() : 0
        // Debug: --preview-context <vehicle type + 1 | menu> to review a layout.
        let arguments = ProcessInfo.processInfo.arguments
        if let i = arguments.firstIndex(of: "--preview-context"), i + 1 < arguments.count {
            if arguments[i + 1] == "menu" { pauseMenu = true } else { vehicle = UInt32(arguments[i + 1]) ?? 0 }
        }
        // Debug: --context-after <seconds after WORLD_READY> <vehicle type + 1> simulates entering a vehicle.
        if let i = arguments.firstIndex(of: "--context-after"), i + 2 < arguments.count, let ready = worldReadyAt,
           let after = Double(arguments[i + 1]), now - ready > after { vehicle = UInt32(arguments[i + 2]) ?? vehicle }
        if touchActive {
            // Debug: --preview-prompt shows the Accept/Back prompt layout, --preview-phone the phone dock.
            var status = gameStatus
            if arguments.contains("--preview-prompt") { status |= 1 }
            if arguments.contains("--preview-phone") { status |= 2 }
            touchControls.characterSwitchEnabled = bootedMode == .story || arguments.contains("--preview-switch")
            touchControls.updateGameState(status)
            touchControls.updateContext(vehicle: vehicle, pauseMenu: pauseMenu)
            var hints = PGReadControlHints(vehicle)
            // Debug: --preview-hints special,detonate,help shows the situational buttons.
            if let i = arguments.firstIndex(of: "--preview-hints"), i + 1 < arguments.count {
                let wanted = arguments[i + 1]
                if wanted.contains("special") { hints.specialShown = true; hints.specialReady = true; hints.specialFill = 0.7 }
                if wanted.contains("detonate") { hints.canDetonate = true }
                if wanted.contains("help") { hints.helpShown = true; hints.helpContext = true }
            }
            touchControls.updateHints(hints)
            let touch = touchControls.padState(elapsed: elapsed)
            if ProcessInfo.processInfo.arguments.contains("--trace-touch-controls") {
                let sample = String(format: "Touch pad: buttons=%u move=%.2f,%.2f look=%.2f,%.2f triggers=%.2f,%.2f device=%d", touch.buttons, touch.leftX, touch.leftY, touch.rightX, touch.rightY, touch.leftTrigger, touch.rightTrigger, PGLastInputDevice())
                if sample != lastTouchInputTrace { lastTouchInputTrace = sample; appendLog(sample) }
            }
            state.merge(touch)
        }
        #if targetEnvironment(simulator)
        var keys = PGPadState()
        func held(_ key: UIKeyboardHIDUsage) -> Float { simulatorKeys.contains(key) ? 1 : 0 }
        keys.leftX = held(.keyboardD) - held(.keyboardA)
        keys.leftY = held(.keyboardW) - held(.keyboardS)
        keys.rightX = held(.keyboardRightArrow) - held(.keyboardLeftArrow)
        keys.rightY = held(.keyboardUpArrow) - held(.keyboardDownArrow)
        keys.leftTrigger = held(.keyboardZ); keys.rightTrigger = held(.keyboardX)
        let map: [(UIKeyboardHIDUsage, PadButtons)] = [(.keyboardSpacebar, .x), (.keyboardLeftShift, .a), (.keyboardF, .y), (.keyboardR, .b),
            (.keyboardQ, .r1), (.keyboardTab, .l1), (.keyboardV, .select), (.keyboardEscape, .start), (.keyboardE, .l3),
            (.keyboardReturnOrEnter, .a), (.keyboardDeleteOrBackspace, .b), (.keyboardI, .up), (.keyboardK, .down), (.keyboardJ, .left), (.keyboardL, .right)]
        var keyButtons = PadButtons()
        for (key, bit) in map where simulatorKeys.contains(key) { keyButtons.insert(bit) }
        keys.padButtons = keyButtons
        state.merge(keys)
        #endif
        // Optional gyro: phone rotation adds to the right stick.
        let settings = GameSettings.shared
        let onFoot = vehicle == 0
        let driving = touchControls.context.driving
        let tiltWanted = touchActive && driving && settings.tiltSteer != .off
        let gyroWanted = touchActive && gameStatus == 0 && !pauseMenu && ((settings.gyroAim != .off && !touchControls.flyingWithRightStick && touchControls.context != .menu) || tiltWanted)
        let orientation = view.window?.windowScene?.interfaceOrientation ?? .landscapeRight
        if motionOrientation != orientation || !gyroWanted {
            tiltNeutral = nil; tiltSince = nil; tiltSmoothed = 0
        }
        motionOrientation = gyroWanted ? orientation : nil
        gyro.setRunning(gyroWanted, orientation: orientation)
        if tiltWanted, let angle = gyro.steeringAngle() {
            // The neutral angle is however the phone is held on entering.
            if tiltSince == nil { tiltSince = now }
            if tiltNeutral == nil, now - (tiltSince ?? now) > 0.15 { tiltNeutral = angle }
            if let neutral = tiltNeutral {
                var degrees = (angle - neutral) * 180 / .pi
                degrees = abs(degrees) < 1.5 ? 0 : degrees - copysign(1.5, degrees)
                let raw = max(-1, min(1, degrees / settings.tiltFullLock))
                let curved = copysign(pow(abs(raw), 1.4), raw)
                tiltSmoothed += (curved - tiltSmoothed) * min(1, elapsed / 0.06)
                let fadeIn = min(1, (now - (tiltSince ?? now) - 0.15) / 0.3)
                let tilt = Float(tiltSmoothed * max(0, fadeIn))
                if settings.tiltSteer == .full && abs(state.leftX) < 0.05 { state.leftX = tilt }
                else if settings.tiltSteer == .assist { state.leftX = max(-1, min(1, state.leftX + tilt * 0.6)) }
            }
        } else if !driving {
            tiltNeutral = nil; tiltSince = nil; tiltSmoothed = 0
        }
        if gyroWanted && settings.gyroAim != .off {
            let aiming = touchControls.aiming || state.leftTrigger > 0.1
            let active = aiming || (settings.gyroAim == .always && onFoot)
            let rate = gyro.rate(active: active, elapsed: elapsed)
            let invert: Double = settings.gyroInvertY ? -1 : 1
            state.rightX = max(-1, min(1, state.rightX + MotionRateFilter.axis(Double(rate.dx), sensitivity: settings.gyroSensitivity)))
            state.rightY = max(-1, min(1, state.rightY - MotionRateFilter.axis(Double(rate.dy) * invert, sensitivity: settings.gyroSensitivity)))
        }
        // A controller's right stick picks on the radio wheel (its own inputs have no controller
        // binding in this build; see PGSetRadioWheelDirection). The camera ignores the stick meanwhile.
        if hasController, engineStarted, let pad = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad,
           PGReadControlHints(PGCurrentTouchContext()).radioWheelOpen {
            let x = pad.rightThumbstick.xAxis.value, y = pad.rightThumbstick.yAxis.value, length = hypotf(x, y)
            PGSetRadioWheelDirection(length > 0.3 ? x / length : 0, length > 0.3 ? y / length : 0, true)
            state.rightX = 0; state.rightY = 0
            controllerRadioWheel = true
        } else if controllerRadioWheel {
            controllerRadioWheel = false
            PGSetRadioWheelDirection(0, 0, false)
        }
        PGUpdateVirtualPad(state)
    }
    private var controllerRadioWheel = false

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        guard view.window?.windowScene?.activationState == .foregroundActive,
              let descriptor = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let command = queue?.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.endEncoding()
        command.present(drawable)
        command.commit()
        lastShellCommand = command
    }
}
