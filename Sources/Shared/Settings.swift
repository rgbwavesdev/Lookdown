import Foundation

/// How previews look. The app writes these to settings.json; the Quick Look extension reads them
/// before every preview.
struct LookdownSettings: Codable, Equatable {
    enum Theme: String, Codable, CaseIterable, Identifiable {
        case warm, clean, github
        var id: String { rawValue }
        var title: String {
            switch self {
            case .warm: "Warm"
            case .clean: "Clean"
            case .github: "GitHub"
            }
        }
        var blurb: String {
            switch self {
            case .warm: "Serif on ivory, like the Claude app"
            case .clean: "Crisp sans, Obsidian style"
            case .github: "Familiar README look"
            }
        }
    }

    enum Appearance: String, Codable, CaseIterable, Identifiable {
        case system, light, dark
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    enum Width: String, Codable, CaseIterable, Identifiable {
        case narrow, medium, wide, full
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
        var css: String {
            switch self {
            case .narrow: "38rem"
            case .medium: "46rem"
            case .wide: "58rem"
            case .full: "300rem"
            }
        }
    }

    enum Properties: String, Codable, CaseIterable, Identifiable {
        case shown, collapsed, hidden
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var theme: Theme = .warm
    var appearance: Appearance = .system
    var fontSize: Double = 16
    var width: Width = .medium
    var softBreaks = false
    var properties: Properties = .shown
    var remoteImages = true

    init() {}

    // Each field falls back to its default on its own, so an old or hand-edited file still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = LookdownSettings()
        theme = (try? c.decode(Theme.self, forKey: .theme)) ?? d.theme
        appearance = (try? c.decode(Appearance.self, forKey: .appearance)) ?? d.appearance
        fontSize = (try? c.decode(Double.self, forKey: .fontSize)) ?? d.fontSize
        width = (try? c.decode(Width.self, forKey: .width)) ?? d.width
        softBreaks = (try? c.decode(Bool.self, forKey: .softBreaks)) ?? d.softBreaks
        properties = (try? c.decode(Properties.self, forKey: .properties)) ?? d.properties
        remoteImages = (try? c.decode(Bool.self, forKey: .remoteImages)) ?? d.remoteImages
    }

    var clampedFontSize: Double { min(max(fontSize, 11), 28) }

    /// The options object handed to lookdown.js.
    var rendererOptions: String {
        let options: [String: Any] = [
            "softBreaks": softBreaks,
            "properties": properties.rawValue,
            "remoteImages": remoteImages,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: options)) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

enum SettingsStore {
    /// The user's real home folder. Inside the sandboxed extension, NSHomeDirectory() points at
    /// the extension's container instead.
    static let realHome: URL = {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }()

    static var fileURL: URL {
        realHome.appendingPathComponent("Library/Application Support/Lookdown/settings.json")
    }

    static func load() -> LookdownSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(LookdownSettings.self, from: data)
        else { return LookdownSettings() }
        return settings
    }

    static func save(_ settings: LookdownSettings) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(settings)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
