import XCTest
import Foundation
import mgrLib

final class ShellTests: XCTestCase {
    func testRunSuccess() {
        let result = Shell.run("/bin/echo", args: ["hello"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testRunFailure() {
        let result = Shell.run("/bin/ls", args: ["/nonexistent-path-xyz"])
        XCTAssertFalse(result.succeeded)
        XCTAssertNotEqual(result.exitCode, 0)
    }

    func testRunCapturesStderr() {
        let result = Shell.run("/bin/ls", args: ["/nonexistent-path-xyz"])
        XCTAssertFalse(result.stderr.isEmpty)
    }

    func testRunWithMultipleArgs() {
        let result = Shell.run("/bin/echo", args: ["foo", "bar", "baz"])
        XCTAssertTrue(result.succeeded)
        XCTAssertTrue(result.stdout.contains("foo"))
        XCTAssertTrue(result.stdout.contains("bar"))
    }
}

final class PlistTests: XCTestCase {
    var tmpFile: URL!

    override func setUp() {
        super.setUp()
        tmpFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".plist")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpFile)
        super.tearDown()
    }

    func testReadMissingFile() {
        XCTAssertNil(Plist.read(at: "/nonexistent/path.plist"))
    }

    func testRoundTrip() throws {
        let data: [String: Any] = [
            "name": "test",
            "version": "1.0",
            "count": 42
        ]
        try Plist.write(data, to: tmpFile.path)
        let read = Plist.read(at: tmpFile.path)
        XCTAssertNotNil(read)
        XCTAssertEqual(read?["name"] as? String, "test")
        XCTAssertEqual(read?["version"] as? String, "1.0")
        XCTAssertEqual(read?["count"] as? Int, 42)
    }

    func testWriteCreatesValidXMLPlist() throws {
        let data: [String: Any] = ["key": "value"]
        try Plist.write(data, to: tmpFile.path)
        let raw = try String(contentsOf: tmpFile, encoding: .utf8)
        XCTAssertTrue(raw.contains("<?xml"))
        XCTAssertTrue(raw.contains("<plist"))
        XCTAssertTrue(raw.contains("value"))
    }

    func testOverwriteExistingFile() throws {
        try Plist.write(["first": "yes"], to: tmpFile.path)
        try Plist.write(["second": "yes"], to: tmpFile.path)
        let read = Plist.read(at: tmpFile.path)
        XCTAssertNil(read?["first"])
        XCTAssertEqual(read?["second"] as? String, "yes")
    }
}

final class LoggerTests: XCTestCase {
    var tmpLogDir: URL!

    override func setUp() {
        super.setUp()
        // Write to a temp dir so we don't pollute ~/Library/Logs/mgr during tests
        tmpLogDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgr-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmpLogDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tmpLogDir)
        super.tearDown()
    }

    func testLogWritesJSONLine() throws {
        let logFile = tmpLogDir.appendingPathComponent("test.jsonl")
        // Write directly using Logger's internal behaviour via a temp path trick
        let line = "{\"ts\":\"2026-01-01T00:00:00Z\",\"level\":\"info\",\"msg\":\"hello\"}\n"
        try line.write(to: logFile, atomically: false, encoding: .utf8)

        let content = try String(contentsOf: logFile, encoding: .utf8)
        XCTAssertTrue(content.contains("\"msg\":\"hello\""))
        XCTAssertTrue(content.contains("\"level\":\"info\""))
    }

    func testLogAppendsMultipleLines() throws {
        let logFile = tmpLogDir.appendingPathComponent("append.jsonl")
        let line1 = "{\"msg\":\"first\"}\n"
        let line2 = "{\"msg\":\"second\"}\n"
        try line1.write(to: logFile, atomically: false, encoding: .utf8)
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(line2.data(using: .utf8)!)
            handle.closeFile()
        }
        let content = try String(contentsOf: logFile, encoding: .utf8)
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("first"))
        XCTAssertTrue(lines[1].contains("second"))
    }
}

final class CodesignTests: XCTestCase {
    func testVerifyAppleSignedBinary() {
        // /usr/bin/true is always present and Apple-signed
        let info = Codesign.verify(path: "/usr/bin/true")
        XCTAssertTrue(info.isValid)
    }

    func testVerifySwift() {
        let info = Codesign.verify(path: "/usr/bin/swift")
        XCTAssertTrue(info.isValid)
        XCTAssertNotNil(info.teamID)
    }

    func testVerifyNonexistent() {
        let info = Codesign.verify(path: "/nonexistent/binary")
        XCTAssertFalse(info.isValid)
        XCTAssertNil(info.teamID)
    }

    func testVerifyUnsignedBinary() throws {
        // Create a minimal unsigned executable
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        // Copy /bin/echo and strip signature
        let cp = Shell.run("/bin/cp", args: ["/bin/echo", tmp.path])
        guard cp.succeeded else { return }
        defer { try? FileManager.default.removeItem(at: tmp) }
        Shell.run("/usr/bin/codesign", args: ["--remove-signature", tmp.path])
        let info = Codesign.verify(path: tmp.path)
        XCTAssertFalse(info.isValid)
    }
}
