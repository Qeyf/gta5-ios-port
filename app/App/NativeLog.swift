import Foundation

/// Engine workers record here without sending every diagnostic through UIKit.
/// A serial writer keeps one file open and coalesces bursts into disk writes.
final class NativeLog {
    static let shared = NativeLog(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
    private let queue = DispatchQueue(label: "io.github.qeyf.gtavmobile.log", qos: .utility)
    private let queueKey = DispatchSpecificKey<Bool>()
    private let lock = NSLock()
    private let file: URL
    private let handle: FileHandle?
    private var pending: [String] = []
    private var scheduled = false
    private var tail: [String] = []
    private var revision: UInt64 = 0
    // Accessed only on the writer queue.
    private var metrics: [String: String] = [:]

    init(directory: URL) {
        file = directory.appendingPathComponent("native-port.log")
        let previous = directory.appendingPathComponent("native-port-previous.log")
        let size = ((try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0)
        if size > 16_384 || !FileManager.default.fileExists(atPath: previous.path) {
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: file, to: previous)
        }
        try? Data().write(to: file)
        handle = try? FileHandle(forWritingTo: file)
        queue.setSpecific(key: queueKey, value: true)
    }

    func append(_ line: String) {
        lock.lock()
        pending.append(line)
        tail.append(line)
        if tail.count > 500 { tail.removeFirst(tail.count - 500) }
        revision &+= 1
        let needsSchedule = !scheduled
        scheduled = true
        lock.unlock()
        if needsSchedule {
            queue.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self] in self?.drain() }
        }
    }

    func snapshot() -> (lines: [String], revision: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        return (tail, revision)
    }

    /// Used before sharing diagnostics or entering the background. No fsync on
    /// the render/input path; all normal disk I/O stays on the serial writer.
    func flush() {
        if DispatchQueue.getSpecific(key: queueKey) == true { drain() }
        else { queue.sync { drain() } }
    }

    private func drain() {
        lock.lock()
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        scheduled = false
        lock.unlock()
        guard !batch.isEmpty else { return }
        if let data = (batch.joined(separator: "\n") + "\n").data(using: .utf8) {
            try? handle?.write(contentsOf: data)
        }
        var metricsChanged = false
        for line in batch {
            for key in ["[metal] fps:", "[metal] draw costs", "Native frame costs:", "Health:", "WORLD_READY"] where line.hasPrefix(key) {
                metrics[key] = line
                metricsChanged = true
            }
        }
        if metricsChanged, let data = try? JSONSerialization.data(withJSONObject: metrics, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: file.deletingLastPathComponent().appendingPathComponent("native-metrics.json"), options: .atomic)
        }
    }

    deinit {
        flush()
        try? handle?.close()
    }
}
