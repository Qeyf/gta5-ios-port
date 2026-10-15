import Foundation

/// Bounded reads keep large logs off the UI thread and preserve startup metadata
/// as well as the recent failure. Only complete UTF-8 lines are spliced.
enum DiagnosticReport {
    static let perLog = 6 * 1024 * 1024
    private static let prefixBytes = 64 * 1024

    static func body(directory: URL) throws -> Data {
        var result = Data("GtaV Mobile diagnostics\n".utf8)
        var logs = 0
        for (title, name) in [("PREVIOUS RUN", "native-port-previous.log"), ("THIS RUN", "native-port.log")] {
            let file = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let size = try handle.seekToEnd()
            guard size > 0 else { continue }
            logs += 1
            result.append(Data("\n===== \(title) (\(name), \(size) bytes) =====\n".utf8))
            try handle.seek(toOffset: 0)
            if size <= UInt64(perLog) {
                result.append(try handle.read(upToCount: perLog) ?? Data())
            } else {
                let prefix = try handle.read(upToCount: prefixBytes) ?? Data()
                if let newline = prefix.lastIndex(of: 10) { result.append(prefix[...newline]) }
                result.append(Data("\n[Middle of log omitted: preserving startup and latest complete lines.]\n".utf8))
                try handle.seek(toOffset: size - UInt64(perLog - prefixBytes))
                let tail = try handle.read(upToCount: perLog - prefixBytes) ?? Data()
                if let newline = tail.firstIndex(of: 10) { result.append(tail.suffix(from: tail.index(after: newline))) }
            }
            result.append(10)
        }
        return logs > 0 ? result : Data()
    }

    static func acceptedID(status: Int, data: Data?) -> String? {
        guard status == 202, let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["accepted"] as? Bool == true, let id = json["id"] as? String,
              UUID(uuidString: id) != nil else { return nil }
        return id
    }
}
