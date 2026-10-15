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
            verifyReportSubmission { reportFailures in
                failures.append(contentsOf: reportFailures)
                let result = failures.isEmpty ? "UIKit runtime regressions passed." : "UIKit runtime regressions FAILED: " + failures.joined(separator: "; ")
                NativeLog.shared.append(result)
                NativeLog.shared.flush()
            }
        }
    }

    private static func verifyReportSubmission(done: @escaping ([String]) -> Void) {
        DiagnosticsMock.reset()
        LogUploader.testConfiguration = nil
        LogUploader.send(note: "Missing test transport must fail closed") { _ in
            guard DiagnosticsMock.requests == 0 else { done(["Unconfigured smoke build reached transport"]); return }
            verifyReportSubmissionWithMock(done: done)
        }
    }

    private static func verifyReportSubmissionWithMock(done: @escaping ([String]) -> Void) {
        LogUploader.testConfiguration = {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DiagnosticsMock.self]
            return configuration
        }
        var callbacks = 0
        func completed(_ result: (String, String)) {
            callbacks += 1
            guard callbacks == 2 else { return }
            var failures: [String] = []
            if DiagnosticsMock.requests != 1 { failures.append("Overlapping report uploads escaped the shared guard") }
            if DiagnosticsMock.notes != ["Tek rapor: çöktü"] { failures.append("Report note was lost or duplicated") }
            // A completed request must release the gate for the next report.
            LogUploader.send(note: "İkinci rapor") { _ in
                if DiagnosticsMock.requests != 2 { failures.append("Completed submission did not release its guard") }
                LogUploader.testConfiguration = nil
                done(failures)
            }
        }
        LogUploader.send(note: "Tek rapor: çöktü", done: completed)
        LogUploader.send(note: "This duplicate must never reach transport", done: completed)
    }
}

private final class DiagnosticsMock: URLProtocol {
    private static let lock = NSLock()
    private static var requestCount = 0
    private static var requestNotes: [String] = []
    static var requests: Int { lock.lock(); defer { lock.unlock() }; return requestCount }
    static var notes: [String] { lock.lock(); defer { lock.unlock() }; return requestNotes }
    static func reset() { lock.lock(); defer { lock.unlock() }; requestCount = 0; requestNotes = [] }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        Self.requestNotes.append(request.value(forHTTPHeaderField: "X-Note")?.removingPercentEncoding ?? "")
        Self.lock.unlock()
        let data = Data("{\"accepted\":true,\"id\":\"1f3053af-2230-4ae7-b0b3-8464a57b7e2f\"}".utf8)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 202, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
