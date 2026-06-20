import XCTest
import Foundation
import mgrLib

final class ApprovedListTests: XCTestCase {
    var tmpPlist: URL!

    override func setUp() {
        super.setUp()
        tmpPlist = FileManager.default.temporaryDirectory
            .appendingPathComponent("mgr-test-approved-\(UUID().uuidString).plist")
        ApprovedList.testPlistPathOverride = tmpPlist.path
    }

    override func tearDown() {
        ApprovedList.testPlistPathOverride = nil
        try? FileManager.default.removeItem(at: tmpPlist)
        super.tearDown()
    }

    func testLoadEmptyList() {
        let entries = ApprovedList.load()
        XCTAssertEqual(entries.count, 0)
    }

    func testAppendAndLoad() throws {
        let entry = ApprovedEntry(
            name: "test-binary", path: "/usr/bin/true", teamID: "TESTTEAMID",
            sha256: "sha256:abc123", approvedBy: "tester", approvedAt: "2026-01-01T00:00:00Z"
        )
        try ApprovedList.append(entry)

        let loaded = ApprovedList.load()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].name, "test-binary")
        XCTAssertEqual(loaded[0].path, "/usr/bin/true")
        XCTAssertEqual(loaded[0].teamID, "TESTTEAMID")
        XCTAssertEqual(loaded[0].approvedBy, "tester")
    }

    func testAppendMultipleEntries() throws {
        for i in 1...3 {
            let entry = ApprovedEntry(name: "tool-\(i)", path: "/usr/bin/tool\(i)",
                                      teamID: "TEAM\(i)", sha256: "", approvedBy: "t",
                                      approvedAt: "2026-01-0\(i)T00:00:00Z")
            try ApprovedList.append(entry)
        }
        XCTAssertEqual(ApprovedList.load().count, 3)
    }

    func testIsApprovedByPath() throws {
        let entry = ApprovedEntry(name: "echo", path: "/bin/echo",
                                  teamID: "", sha256: "", approvedBy: "t", approvedAt: "")
        try ApprovedList.append(entry)
        XCTAssertTrue(ApprovedList.isApproved(path: "/bin/echo", teamID: nil))
        XCTAssertFalse(ApprovedList.isApproved(path: "/bin/ls", teamID: nil))
    }

    func testIsApprovedByTeamID() throws {
        let entry = ApprovedEntry(name: "app", path: "/Applications/App.app",
                                  teamID: "MYTEAM123", sha256: "", approvedBy: "t", approvedAt: "")
        try ApprovedList.append(entry)
        // Different path but same teamID — should match
        XCTAssertTrue(ApprovedList.isApproved(path: "/Applications/OtherApp.app",
                                              teamID: "MYTEAM123"))
        // Different team — should not match
        XCTAssertFalse(ApprovedList.isApproved(path: "/Applications/Evil.app",
                                               teamID: "EVILTEAM"))
    }

    func testIsNotApprovedWithEmptyTeamID() throws {
        // An entry with empty teamID should NOT match other paths by teamID
        let entry = ApprovedEntry(name: "app", path: "/Applications/App.app",
                                  teamID: "", sha256: "", approvedBy: "t", approvedAt: "")
        try ApprovedList.append(entry)
        XCTAssertFalse(ApprovedList.isApproved(path: "/Applications/Other.app", teamID: ""))
    }

    func testSha256OfKnownBinary() {
        let hash = ApprovedList.sha256(of: "/usr/bin/true")
        XCTAssertNotNil(hash)
        XCTAssertTrue(hash!.hasPrefix("sha256:"))
        XCTAssertEqual(hash!.count, "sha256:".count + 64)
    }

    func testSha256MissingFile() {
        XCTAssertNil(ApprovedList.sha256(of: "/nonexistent/binary"))
    }

    func testSha256IsDeterministic() {
        let h1 = ApprovedList.sha256(of: "/usr/bin/true")
        let h2 = ApprovedList.sha256(of: "/usr/bin/true")
        XCTAssertEqual(h1, h2)
    }
}

final class DoctorScanTests: XCTestCase {
    func testScanMissingDirectoryReturnsEmpty() {
        let findings = Doctor.scanLaunchdDir("/nonexistent/dir",
                                             category: "test", approved: [])
        XCTAssertEqual(findings.count, 0)
    }

    func testScanUserLaunchAgentsHasValidStructure() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let dir = "\(home)/Library/LaunchAgents"
        guard FileManager.default.fileExists(atPath: dir) else { return }

        let findings = Doctor.scanLaunchdDir(dir, category: "LaunchAgents/user", approved: [])
        for f in findings {
            XCTAssertFalse(f.name.isEmpty, "name should not be empty")
            XCTAssertFalse(f.path.isEmpty, "path should not be empty")
            XCTAssertEqual(f.category, "LaunchAgents/user")
        }
    }

    func testFindingStatusValues() {
        // Verify all status raw values are stable strings (used in JSON output)
        XCTAssertEqual(Doctor.FindingStatus.approved.rawValue, "approved")
        XCTAssertEqual(Doctor.FindingStatus.unknown.rawValue, "unknown")
        XCTAssertEqual(Doctor.FindingStatus.invalidSignature.rawValue, "invalid-signature")
    }

    func testFindingIsJSONEncodable() throws {
        let finding = Doctor.Finding(category: "test", name: "foo",
                                     path: "/usr/bin/foo", teamID: "TEAM1",
                                     status: .unknown)
        let data = try JSONEncoder().encode(finding)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "unknown")
        XCTAssertEqual(json?["name"] as? String, "foo")
        XCTAssertEqual(json?["teamID"] as? String, "TEAM1")
    }
}
