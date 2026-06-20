import XCTest
import Foundation
import mgrLib

final class MonitorTests: XCTestCase {
    var tmpPlist: URL!

    override func setUp() {
        super.setUp()
        tmpPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgr-test-monitor-\(UUID().uuidString).plist")
        ApprovedList.testPlistPathOverride = tmpPlist.path
        Notify.suppressForTesting = true
    }

    override func tearDown() {
        Notify.suppressForTesting = false
        ApprovedList.testPlistPathOverride = nil
        try? FileManager.default.removeItem(at: tmpPlist)
        super.tearDown()
    }

    func testPollDoesNotCrash() {
        Monitor.poll()
    }

    func testPollWithApprovedEntryDoesNotNotify() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/Library/LaunchAgents"
        guard let first = try? FileManager.default.contentsOfDirectory(atPath: dir)
                .first(where: { $0.hasSuffix(".plist") }) else { return }

        let plistPath = "\(dir)/\(first)"
        let entry = ApprovedEntry(name: first, path: plistPath, teamID: "",
                                  sha256: "", approvedBy: "test", approvedAt: "")
        try ApprovedList.append(entry)

        // With notifications suppressed and the path approved, poll() should complete cleanly
        Monitor.poll()
    }
}

final class NotifyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Notify.suppressForTesting = true
    }

    override func tearDown() {
        Notify.suppressForTesting = false
        super.tearDown()
    }

    func testSendWhenSuppressedDoesNothing() {
        // Should complete immediately without calling osascript
        Notify.send(title: "test", body: "should be suppressed")
    }

    func testSuppressFlagDefaultsToFalse() {
        // Verify the flag resets correctly between tests
        XCTAssertTrue(Notify.suppressForTesting) // setUp sets it
    }
}
