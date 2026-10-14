import Foundation

@main
struct NativeLogTests {
    static func main() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let log = NativeLog(directory: folder)
        // A burst from engine workers must retain every record while the main
        // thread never drains a UI callback or performs a per-line disk write.
        DispatchQueue.concurrentPerform(iterations: 12_000) { i in
            log.append("worker line \(i)")
        }
        log.append("Health: complete")
        log.flush()
        let contents = try String(contentsOf: folder.appendingPathComponent("native-port.log"), encoding: .utf8)
        let lines = contents.split(separator: "\n").map(String.init)
        precondition(lines.count == 12_001)
        precondition(Set(lines).count == 12_001)
        precondition(lines.last == "Health: complete")
        precondition(log.snapshot().lines == Array(lines.suffix(500)))
        let metrics = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("native-metrics.json"))) as! [String: String]
        precondition(metrics["Health:"] == "Health: complete")

        // Preserve the last played run across repeated shell-only launches.
        let next = NativeLog(directory: folder)
        next.append("shell only")
        next.flush()
        let previous = folder.appendingPathComponent("native-port-previous.log")
        let saved = try String(contentsOf: previous, encoding: .utf8)
        precondition(saved == contents)
        let third = NativeLog(directory: folder)
        third.append("another shell launch")
        third.flush()
        let retained = try String(contentsOf: previous, encoding: .utf8)
        precondition(retained == contents)
        print("PASS: concurrent log bursts, ordered flush, bounded UI tail, metrics and played-run rotation")
    }
}
