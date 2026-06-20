import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum Notify {
    public static func send(title: String, body: String, identifier: String = UUID().uuidString) {
        // UserNotifications requires a running app context — use osascript as fallback
        // for a CLI binary. Replace with UNUserNotificationCenter when running as a daemon.
        let script = """
        display notification "\(body.replacingOccurrences(of: "\"", with: "'"))" \
        with title "\(title.replacingOccurrences(of: "\"", with: "'"))"
        """
        Shell.run("/usr/bin/osascript", args: ["-e", script])
    }
}
