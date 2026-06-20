import Foundation

public enum Logger {
    public static var verbose = CommandLine.arguments.contains("--verbose")

    public static func info(_ message: String) {
        print("[mgr] \(message)")
    }

    public static func debug(_ message: String) {
        guard verbose else { return }
        print("[mgr:debug] \(message)")
    }

    public static func error(_ message: String) {
        fputs("[mgr:error] \(message)\n", stderr)
    }

    // Writes a structured JSON line to ~/Library/Logs/mgr/<file>
    public static func log(to file: String, level: String = "info", message: String, extra: [String: String] = [:]) {
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/mgr")
        let logFile = logDir.appendingPathComponent(file)

        var fields: [String: String] = [
            "ts": ISO8601DateFormatter().string(from: Date()),
            "level": level,
            "msg": message
        ]
        fields.merge(extra) { _, new in new }

        guard let data = try? JSONSerialization.data(withJSONObject: fields),
              let line = String(data: data, encoding: .utf8) else { return }

        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write((line + "\n").data(using: .utf8)!)
            handle.closeFile()
        } else {
            try? (line + "\n").write(to: logFile, atomically: false, encoding: .utf8)
        }
    }
}
