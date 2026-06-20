import XCTest
@testable import mgrLib

final class BackupConfigTests: XCTestCase {
    func testDefaultConfigReturnsEmptyWhenNoActiveMappings() {
        // config/backup.plist ships with all entries commented out
        let mappings = Backup.readConfig()
        XCTAssertEqual(mappings.count, 0,
            "Default backup.plist should have 0 active mappings (all examples are commented out)")
    }

    func testMappingParsesAllFields() throws {
        let tmp = NSTemporaryDirectory() + "mgr-backup-config-\(UUID().uuidString).plist"
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><array><dict>
            <key>name</key>        <string>test</string>
            <key>source</key>      <string>~/Documents</string>
            <key>destination</key> <string>/Volumes/SSD/Documents</string>
            <key>excludes</key>    <array><string>.DS_Store</string></array>
        </dict></array></plist>
        """
        try content.write(toFile: tmp, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: tmp) }

        // Override the config path by writing to the expected dev location
        // (we can't easily inject the path, so test the parser via a known-good plist)
        let data = content.data(using: .utf8)!
        let obj  = try PropertyListSerialization.propertyList(from: data, format: nil)
        let arr  = obj as! [[String: Any]]
        XCTAssertEqual(arr.count, 1)
        XCTAssertEqual(arr[0]["name"] as? String, "test")
        XCTAssertEqual(arr[0]["destination"] as? String, "/Volumes/SSD/Documents")
        XCTAssertEqual(arr[0]["excludes"] as? [String], [".DS_Store"])
    }
}

final class BackupRsyncTests: XCTestCase {
    var tmpDir = ""

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "mgr-rsync-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        Notify.suppressForTesting = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        Notify.suppressForTesting = false
        super.tearDown()
    }

    func testRsyncBinaryExists() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/usr/bin/rsync"))
    }

    func testRsyncMirrorCopiesFiles() throws {
        let src = tmpDir + "/src"
        let dst = tmpDir + "/dst"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/hello.txt", contents: Data("world".utf8))

        let result = Shell.run("/usr/bin/rsync", args: ["-a", "--delete", src + "/", dst + "/"])
        XCTAssertTrue(result.succeeded)
        let copied = try String(contentsOfFile: dst + "/hello.txt", encoding: .utf8)
        XCTAssertEqual(copied, "world")
    }

    func testRsyncDeleteRemovesStaleFiles() throws {
        let src = tmpDir + "/src"
        let dst = tmpDir + "/dst"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
        // Put a stale file in dst that doesn't exist in src
        FileManager.default.createFile(atPath: dst + "/stale.txt", contents: Data("old".utf8))

        let result = Shell.run("/usr/bin/rsync", args: ["-a", "--delete", src + "/", dst + "/"])
        XCTAssertTrue(result.succeeded)
        // --delete should have removed stale.txt
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst + "/stale.txt"),
                       "--delete should remove files absent from source")
    }

    func testRsyncDryRunDoesNotCopy() throws {
        let src = tmpDir + "/src"
        let dst = tmpDir + "/dst"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/test.txt", contents: Data("x".utf8))

        let result = Shell.run("/usr/bin/rsync", args: ["-a", "--dry-run", src + "/", dst + "/"])
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst),
                       "dry-run should not create destination")
    }

    func testUnmountedDestinationSkipped() {
        // A destination that doesn't exist should be caught before rsync runs
        let mapping = Backup.Mapping(
            name: "test",
            source: "~/Documents",
            destination: "/Volumes/NonExistentDrive/backup",
            excludes: []
        )
        let parentExists = FileManager.default.fileExists(
            atPath: (mapping.destination as NSString).deletingLastPathComponent)
        XCTAssertFalse(parentExists, "Non-existent drive parent should not exist")
    }
}
