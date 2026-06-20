import Foundation

enum Codesign {
    struct Info {
        let teamID: String?
        let identifier: String?
        let isValid: Bool
    }

    static func verify(path: String) -> Info {
        let result = Shell.run("/usr/bin/codesign", args: ["--verify", "--deep", "--strict", path])
        guard result.succeeded else {
            return Info(teamID: nil, identifier: nil, isValid: false)
        }
        let teamID = extractTeamID(path: path)
        let identifier = extractIdentifier(path: path)
        return Info(teamID: teamID, identifier: identifier, isValid: true)
    }

    private static func extractTeamID(path: String) -> String? {
        let result = Shell.run("/usr/bin/codesign", args: ["-dv", "--verbose=4", path])
        // Team ID appears in stderr as "TeamIdentifier=XXXXXXXXXX"
        let output = result.stderr + result.stdout
        return output.components(separatedBy: "\n")
            .first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
    }

    private static func extractIdentifier(path: String) -> String? {
        let result = Shell.run("/usr/bin/codesign", args: ["-dv", path])
        let output = result.stderr + result.stdout
        return output.components(separatedBy: "\n")
            .first { $0.hasPrefix("Identifier=") }
            .map { String($0.dropFirst("Identifier=".count)) }
    }
}
