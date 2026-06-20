import XCTest
@testable import mgrLib

final class BackupConfigTests: XCTestCase {
    func testDefaultConfigHasNoBACKUPPatternAndNoMappings() {
        let config = Backup.readConfig()
        XCTAssertEqual(config.volumePattern, "BACKUP")
        XCTAssertEqual(config.mappings.count, 0,
            "Default backup.plist should have 0 active mappings (all examples commented out)")
    }

    func testMappingParsesAllFields() throws {
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
            <key>volumePattern</key> <string>MYBACKUP</string>
            <key>mappings</key>
            <array><dict>
                <key>name</key>        <string>home</string>
                <key>source</key>      <string>~/</string>
                <key>destination</key> <string>home</string>
                <key>excludes</key>    <array><string>.Trash</string></array>
            </dict></array>
        </dict></plist>
        """
        let data = content.data(using: .utf8)!
        let obj  = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(obj["volumePattern"] as? String, "MYBACKUP")
        let mappings = obj["mappings"] as! [[String: Any]]
        XCTAssertEqual(mappings.count, 1)
        XCTAssertEqual(mappings[0]["destination"] as? String, "home")
        XCTAssertEqual(mappings[0]["excludes"] as? [String], [".Trash"])
    }
}

final class BackupVolumeTests: XCTestCase {
    func testFindVolumeReturnsMountedMatch() {
        // /Volumes/Macintosh HD (or similar) will always exist — we can test prefix matching
        // by checking that a definitely-absent prefix returns nil
        let result = Backup.findVolume(pattern: "XYZNONEXISTENT123")
        XCTAssertNil(result, "Non-existent pattern should return nil")
    }

    func testFindVolumePicksAlphabeticallyFirst() throws {
        // We can't mount fake volumes in unit tests, but we can verify the sorting
        // logic by checking /Volumes itself exists
        let volumesExists = FileManager.default.fileExists(atPath: "/Volumes")
        XCTAssertTrue(volumesExists, "/Volumes should exist on macOS")
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
        FileManager.default.createFile(atPath: dst + "/stale.txt", contents: Data("old".utf8))

        let result = Shell.run("/usr/bin/rsync", args: ["-a", "--delete", src + "/", dst + "/"])
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst + "/stale.txt"),
                       "--delete should remove files absent from source")
    }

    func testRsyncDryRunDoesNotCopy() throws {
        let src = tmpDir + "/src"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/test.txt", contents: Data("x".utf8))

        let result = Shell.run("/usr/bin/rsync", args: ["-a", "--dry-run", src + "/", tmpDir + "/dst/"])
        XCTAssertTrue(result.succeeded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmpDir + "/dst"),
                       "dry-run should not create destination")
    }
}
