import Foundation

public enum Plist {
    public static func read(at path: String) -> [String: Any]? {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard let data = try? Data(contentsOf: url),
              let obj = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dict = obj as? [String: Any] else { return nil }
        return dict
    }

    public static func write(_ dict: [String: Any], to path: String) throws {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }
}
