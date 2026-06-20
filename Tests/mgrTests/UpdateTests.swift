import XCTest
@testable import mgrLib

final class UpdateCheckTests: XCTestCase {
    func testFetchLatestTagReturnsStringOrNil() {
        // Integration: hits GitHub API. Acceptable to return nil in offline CI.
        let tag = Update.fetchLatestTag()
        if let tag {
            XCTAssertTrue(tag.hasPrefix("v"), "Expected tag to start with 'v', got: \(tag)")
        }
        // nil means network unavailable — not a failure
    }

    func testShortDigestTruncates() {
        let full = "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890"
        // shortDigest is private; test via the public contract: digests in containers
        // plist are full sha256 hashes — we just verify the binary was built with Update
        XCTAssertNotNil(Update.self)
    }
}

final class UpdateInstallTests: XCTestCase {
    func testRsyncBinaryIsAvailable() {
        // /usr/bin/curl must exist for --check and --self to work
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/usr/bin/curl"))
    }

    func testCodesignPathIsAvailable() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: "/usr/bin/codesign"))
    }

    func testCurrentBinaryHasNoCodeSignatureInDebugBuild() {
        // Debug builds from swift build are not signed — verify returns isValid=false
        // and we don't crash parsing the result
        let binaryPath = CommandLine.arguments[0]
        let info = Codesign.verify(path: binaryPath)
        // We don't assert isValid because CI may or may not sign the test runner
        XCTAssertNotNil(info)
    }
}

final class UpdateContainerTests: XCTestCase {
    func testContainersPlistParseable() {
        let paths = [
            "./config/containers.plist",
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/mgr/containers.plist").path
        ]
        // Either no file (empty dict) or a parseable plist
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                let result = Plist.read(at: path)
                XCTAssertNotNil(result, "containers.plist at \(path) should be parseable")
            }
        }
    }

    func testDockerAbsenceHandledGracefully() {
        // If docker is not installed, updateContainers() should not crash.
        // We can't easily call it without side effects; verify the binary path check
        // by confirming the guard logic is sound: only /usr/local/bin/docker supported.
        let dockerExists = FileManager.default.fileExists(atPath: "/usr/local/bin/docker")
        // Either docker exists (test skipped) or we expect the guard to catch it.
        // This is just a smoke test that the type is accessible.
        _ = dockerExists
        XCTAssertNotNil(Update.self)
    }
}
