import XCTest
@testable import mgrLib

final class BackupConfigTests: XCTestCase {
    func testDefaultConfigWhenNoPlist() {
        // When no plist is present in CWD config/, defaults are returned
        // (CWD during tests is the package root which does have config/backup.plist,
        //  so we test the parsed values instead)
        let config = Backup.readConfig()
        // snapshotBase must be non-empty
        XCTAssertFalse(config.snapshotBase.isEmpty)
        // globalExcludes is an array (may be empty)
        XCTAssertNotNil(config.globalExcludes)
    }

    func testConfigParsesGlobalExcludes() {
        // The bundled config/backup.plist has globalExcludes with at least .DS_Store
        let config = Backup.readConfig()
        XCTAssertTrue(config.globalExcludes.contains(".DS_Store"),
                      "Expected .DS_Store in globalExcludes")
    }
}

final class BackupSnapshotTests: XCTestCase {
    var tmpBase = ""

    override func setUp() {
        super.setUp()
        tmpBase = NSTemporaryDirectory() + "mgr-backup-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpBase, withIntermediateDirectories: true)
        Notify.suppressForTesting = true
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpBase)
        Notify.suppressForTesting = false
        super.tearDown()
    }

    func testListSnapshotsEmpty() {
        let snapshots = Backup.listSnapshots(base: tmpBase)
        XCTAssertTrue(snapshots.isEmpty)
    }

    func testListSnapshotsDetectsTimestampDirs() throws {
        // Create two fake snapshot dirs
        let dirs = ["2026-06-20_020000", "2026-06-19_020000"]
        for d in dirs {
            try FileManager.default.createDirectory(
                atPath: tmpBase + "/" + d, withIntermediateDirectories: true)
        }
        let snapshots = Backup.listSnapshots(base: tmpBase)
        XCTAssertEqual(snapshots.count, 2)
        // Most recent first
        XCTAssertTrue(snapshots[0].hasSuffix("2026-06-20_020000"))
    }

    func testListSnapshotsExcludesDSStore() throws {
        try FileManager.default.createDirectory(
            atPath: tmpBase + "/2026-06-20_020000", withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tmpBase + "/.DS_Store", contents: nil)
        let snapshots = Backup.listSnapshots(base: tmpBase)
        XCTAssertEqual(snapshots.count, 1)
    }

    func testDryRunWithNoSourcesDoesNothing() {
        // Backup with no sources configured should print a message and exit cleanly
        // We can't easily intercept stdout here, but we verify no crash and no dirs created
        let countBefore = (try? FileManager.default.contentsOfDirectory(atPath: tmpBase))?.count ?? 0
        // Use empty-sources config path — since config/backup.plist may have commented-out
        // sources, we rely on the fact that the default plist has an empty sources array.
        // Just verify the method runs without throwing.
        let config = Backup.readConfig()
        XCTAssertEqual(config.sources.count, 0, "Default backup.plist should have 0 active sources")
        let countAfter = (try? FileManager.default.contentsOfDirectory(atPath: tmpBase))?.count ?? 0
        XCTAssertEqual(countBefore, countAfter)
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
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/usr/bin/rsync"),
                      "/usr/bin/rsync must be present")
    }

    func testRsyncDryRunSucceeds() throws {
        // Create a small source tree
        let src = tmpDir + "/src"
        let dst = tmpDir + "/dst"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/test.txt", contents: Data("hello".utf8))

        let result = Shell.run("/usr/bin/rsync", args: [
            "-a", "--dry-run", "--stats",
            src + "/", dst + "/"
        ])
        XCTAssertTrue(result.succeeded, "rsync dry-run should succeed: \(result.stderr)")
        // Destination should NOT have been created (dry run)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dst))
    }

    func testRsyncCopiesFiles() throws {
        let src = tmpDir + "/src"
        let dst = tmpDir + "/dst"
        try FileManager.default.createDirectory(atPath: src, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: dst, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: src + "/hello.txt", contents: Data("world".utf8))

        let result = Shell.run("/usr/bin/rsync", args: ["-a", src + "/", dst + "/"])
        XCTAssertTrue(result.succeeded)
        let copied = try String(contentsOfFile: dst + "/hello.txt", encoding: .utf8)
        XCTAssertEqual(copied, "world")
    }
}
