import XCTest

final class mgrTests: XCTestCase {
    func testShellRun() {
        let result = Shell.run("/bin/echo", args: ["hello"])
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "hello")
    }

    func testPlistReadMissingFile() {
        let result = Plist.read(at: "/nonexistent/path.plist")
        XCTAssertNil(result)
    }

    func testCodesignVerifySystem() {
        // /usr/bin/swift should always be Apple-signed
        let info = Codesign.verify(path: "/usr/bin/swift")
        XCTAssertTrue(info.isValid)
        XCTAssertNotNil(info.teamID)
    }
}
