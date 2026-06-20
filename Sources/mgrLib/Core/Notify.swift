import Foundation

public enum Notify {
    // Set to true in tests to suppress osascript calls (which open UI in CI).
    nonisolated(unsafe) public static var suppressForTesting = false

    // Sends a macOS notification via osascript — works in user-session LaunchAgents
    // without requiring a bundle identifier or UNUserNotificationCenter authorization.
    public static func send(title: String, body: String,
                            identifier: String = UUID().uuidString) {
        guard !suppressForTesting else { return }
        let safeTitle = title.replacingOccurrences(of: "\"", with: "'")
        let safeBody  = body.replacingOccurrences(of: "\"", with: "'")
        let script = "display notification \"\(safeBody)\" with title \"\(safeTitle)\""
        Shell.run("/usr/bin/osascript", args: ["-e", script])
    }
}
