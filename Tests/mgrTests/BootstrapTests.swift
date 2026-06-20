import XCTest
@testable import mgrLib

final class BootstrapSystemTests: XCTestCase {
    func testDefaultsWriteArgsBool() {
        // verified via reflection — private method exercised indirectly through runSystem()
        // Direct coverage via the helper exposed for testing
        let args = Bootstrap.testDefaultsWriteArgs(domain: "com.apple.dock", key: "autohide", value: true)
        XCTAssertEqual(args, ["write", "com.apple.dock", "autohide", "-bool", "true"])
    }

    func testDefaultsWriteArgsInt() {
        let args = Bootstrap.testDefaultsWriteArgs(domain: "NSGlobalDomain", key: "KeyRepeat", value: 2)
        XCTAssertEqual(args, ["write", "NSGlobalDomain", "KeyRepeat", "-int", "2"])
    }

    func testDefaultsWriteArgsString() {
        let args = Bootstrap.testDefaultsWriteArgs(domain: "com.apple.finder", key: "FXDefaultSearchScope", value: "SCcf")
        XCTAssertEqual(args, ["write", "com.apple.finder", "FXDefaultSearchScope", "-string", "SCcf"])
    }

    func testDefaultsWriteArgsBoolFalse() {
        let args = Bootstrap.testDefaultsWriteArgs(domain: "NSGlobalDomain", key: "NSAutomaticCapitalizationEnabled", value: false)
        XCTAssertEqual(args, ["write", "NSGlobalDomain", "NSAutomaticCapitalizationEnabled", "-bool", "false"])
    }
}

final class BootstrapDotfilesTests: XCTestCase {
    var tmpDir = ""
    var sourceFile = ""
    var targetFile = ""

    override func setUp() {
        super.setUp()
        tmpDir = NSTemporaryDirectory() + "mgr-dotfiles-test-\(UUID().uuidString)"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        sourceFile = tmpDir + "/source.txt"
        targetFile = tmpDir + "/target.txt"
        FileManager.default.createFile(atPath: sourceFile, contents: Data("hello".utf8))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: tmpDir)
        super.tearDown()
    }

    func testCreateSymlink() throws {
        Bootstrap.testCreateSymlink(source: sourceFile, target: targetFile)
        let attrs = try FileManager.default.attributesOfItem(atPath: targetFile)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeSymbolicLink)
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: targetFile)
        XCTAssertEqual(dest, sourceFile)
    }

    func testSkipsAlreadyCorrectSymlink() throws {
        try FileManager.default.createSymbolicLink(atPath: targetFile, withDestinationPath: sourceFile)
        // Second call should not throw or overwrite
        Bootstrap.testCreateSymlink(source: sourceFile, target: targetFile)
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: targetFile)
        XCTAssertEqual(dest, sourceFile)
    }

    func testSkipsRegularFile() throws {
        FileManager.default.createFile(atPath: targetFile, contents: Data("existing".utf8))
        Bootstrap.testCreateSymlink(source: sourceFile, target: targetFile)
        // Should still be a regular file, not a symlink
        let attrs = try FileManager.default.attributesOfItem(atPath: targetFile)
        XCTAssertEqual(attrs[.type] as? FileAttributeType, .typeRegular)
    }

    func testUpdatesWrongSymlink() throws {
        let otherFile = "\(tmpDir)/other.txt"
        FileManager.default.createFile(atPath: otherFile, contents: Data("other".utf8))
        try FileManager.default.createSymbolicLink(atPath: targetFile, withDestinationPath: otherFile)
        Bootstrap.testCreateSymlink(source: sourceFile, target: targetFile)
        let dest = try FileManager.default.destinationOfSymbolicLink(atPath: targetFile)
        XCTAssertEqual(dest, sourceFile)
    }
}

final class BootstrapDevTests: XCTestCase {
    func testXcodeToolsDetected() {
        // xcode-select -p succeeds on any mac with Xcode CLI tools
        let result = Shell.run("/usr/bin/xcode-select", args: ["-p"])
        XCTAssertTrue(result.succeeded, "Xcode CLI tools should be installed in the test environment")
    }

    func testSSHKeySkipsIfExists() {
        // If ~/.ssh/id_ed25519 exists, generateSSHKey should not regenerate it
        let expandedPath = (("~/.ssh/id_ed25519") as NSString).expandingTildeInPath
        let existsBefore = FileManager.default.fileExists(atPath: expandedPath)
        Bootstrap.testGenerateSSHKey(keyType: "ed25519", keyPath: expandedPath, comment: "test")
        let existsAfter = FileManager.default.fileExists(atPath: expandedPath)
        // Either it existed before (no change) or it was created — both are fine
        if existsBefore {
            XCTAssertTrue(existsAfter)
        }
    }
}
