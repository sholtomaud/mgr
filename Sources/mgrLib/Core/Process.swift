import Foundation

public enum Shell {
    public struct Result {
        public let exitCode: Int32
        public let stdout: String
        public let stderr: String
        public var succeeded: Bool { exitCode == 0 }
    }

    @discardableResult
    public static func run(_ executable: String, args: [String] = [], env: [String: String]? = nil) -> Result {
        let process = Foundation.Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args

        if let env {
            var merged = ProcessInfo.processInfo.environment
            merged.merge(env) { _, new in new }
            process.environment = merged
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(exitCode: 1, stdout: "", stderr: error.localizedDescription)
        }

        process.waitUntilExit()

        let out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(exitCode: process.terminationStatus, stdout: out, stderr: err)
    }
}
