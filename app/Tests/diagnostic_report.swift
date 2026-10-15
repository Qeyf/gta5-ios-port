import Foundation

@main enum DiagnosticReportTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let empty = try DiagnosticReport.body(directory: directory)
        assert(empty.isEmpty)
        let text = "GtaV Mobile 1.3.5\nTürkçe: şğıİüöç\n"
        try Data(text.utf8).write(to: directory.appendingPathComponent("native-port.log"))
        var report = try DiagnosticReport.body(directory: directory)
        assert(String(data: report, encoding: .utf8)!.contains(text))
        let line = Data("Kare süresi: 16 ms; çatışma, jiroskop\n".utf8)
        var large = Data("Startup: build 14.1, A19 Pro\n".utf8)
        while large.count < DiagnosticReport.perLog + 200 { large.append(line) }
        large.append(Data("TAIL: last exception\n".utf8))
        try large.write(to: directory.appendingPathComponent("native-port-previous.log"))
        report = try DiagnosticReport.body(directory: directory)
        let decoded = String(data: report, encoding: .utf8)!
        assert(decoded.contains("Startup: build 14.1") && decoded.contains("TAIL: last exception"))
        assert(decoded.contains("Middle of log omitted") && decoded.contains(text))
        assert(report.count < DiagnosticReport.perLog + 2048)
        let id = UUID().uuidString
        let valid = Data("{\"accepted\":true,\"id\":\"\(id)\"}".utf8)
        assert(DiagnosticReport.acceptedID(status: 202, data: valid) == id)
        assert(DiagnosticReport.acceptedID(status: 200, data: valid) == nil)
        for value in ["{}", "{\"accepted\":false}", "{\"accepted\":true,\"id\":\"not an id\"}", "not json"] {
            assert(DiagnosticReport.acceptedID(status: 202, data: Data(value.utf8)) == nil)
        }
        print("PASS: bounded UTF-8 log snapshots preserve startup/tail, empty handling, strict accepted responses.")
    }
}
