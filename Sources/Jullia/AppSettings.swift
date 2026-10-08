import AppKit
import JulliaCore
import Observation
import SwiftUI

/// One glass surface: on/off and how see-through it is. `percent` 0 is solid; the ceiling keeps text readable.
struct GlassSetting: Codable, Equatable {
    static let maxPercent: Double = 85

    var enabled: Bool
    var percent: Double

    /// How opaque the theme colour laid over the glass is, honouring the system's Reduce Transparency.
    func fillOpacity(reduceTransparency: Bool) -> Double {
        guard enabled, !reduceTransparency else { return 1 }
        return 1 - min(max(percent, 0), Self.maxPercent) / 100
    }

    var isOn: Bool { enabled && percent > 0 }

    func isGlassy(reduceTransparency: Bool) -> Bool {
        fillOpacity(reduceTransparency: reduceTransparency) < 1
    }
}

/// Preferences, kept in `UserDefaults` and changed live from the Settings window and the menus.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var appearanceObserver: (any NSObjectProtocol)?

    var followSystem: Bool { didSet { defaults.set(followSystem, forKey: "followSystem") } }
    var darkTheme: ThemeID { didSet { defaults.set(darkTheme.rawValue, forKey: "darkTheme") } }
    var lightTheme: ThemeID { didSet { defaults.set(lightTheme.rawValue, forKey: "lightTheme") } }
    /// The theme used when not following the system.
    var fixedTheme: ThemeID { didSet { defaults.set(fixedTheme.rawValue, forKey: "fixedTheme") } }

    var windowGlass: GlassSetting { didSet { save(windowGlass, "windowGlass") } }
    var filesGlass: GlassSetting { didSet { save(filesGlass, "filesGlass") } }
    var commentsGlass: GlassSetting { didSet { save(commentsGlass, "commentsGlass") } }

    var reopenFolders: Bool { didSet { defaults.set(reopenFolders, forKey: "reopenFolders") } }
    var liveReload: Bool { didSet { defaults.set(liveReload, forKey: "liveReload") } }
    var fontSize: Double { didSet { defaults.set(fontSize, forKey: "fontSize") } }
    var readingWidth: Double { didSet { defaults.set(readingWidth, forKey: "readingWidth") } }
    /// The colour ⌘⇧H highlights with: the last one picked.
    var lastColor: MarkColor { didSet { defaults.set(lastColor.rawValue, forKey: "lastColor") } }

    /// Whether macOS itself is in Dark Mode, independent of the appearance this app forces on its windows.
    private(set) var systemIsDark: Bool

    static let fontSizes: ClosedRange<Double> = 12...26
    static let readingWidths: ClosedRange<Double> = 520...1100

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            "followSystem": true, "reopenFolders": true, "liveReload": true,
            "fontSize": 16.0, "readingWidth": 760.0,
        ])
        followSystem = defaults.bool(forKey: "followSystem")
        darkTheme = ThemeID(rawValue: defaults.string(forKey: "darkTheme") ?? "") ?? .polar
        lightTheme = ThemeID(rawValue: defaults.string(forKey: "lightTheme") ?? "") ?? .snow
        fixedTheme = ThemeID(rawValue: defaults.string(forKey: "fixedTheme") ?? "") ?? .polar
        windowGlass = Self.load(defaults, "windowGlass") ?? GlassSetting(enabled: true, percent: 30)
        filesGlass = Self.load(defaults, "filesGlass") ?? GlassSetting(enabled: true, percent: 45)
        commentsGlass = Self.load(defaults, "commentsGlass") ?? GlassSetting(enabled: true, percent: 45)
        reopenFolders = defaults.bool(forKey: "reopenFolders")
        liveReload = defaults.bool(forKey: "liveReload")
        fontSize = defaults.double(forKey: "fontSize")
        readingWidth = defaults.double(forKey: "readingWidth")
        lastColor = MarkColor(rawValue: defaults.string(forKey: "lastColor") ?? "") ?? .yellow
        systemIsDark = Self.readSystemIsDark()

        appearanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemIsDark = Self.readSystemIsDark() }
        }
    }

    isolated deinit {
        if let appearanceObserver {
            DistributedNotificationCenter.default().removeObserver(appearanceObserver)
        }
    }

    var theme: Theme {
        (followSystem ? (systemIsDark ? darkTheme : lightTheme) : fixedTheme).theme
    }

    /// Picks a theme from the View menu or a theme card: it becomes the theme in use.
    func choose(_ id: ThemeID) {
        if followSystem {
            if id.theme.isDark == systemIsDark {
                if id.theme.isDark { darkTheme = id } else { lightTheme = id }
                return
            }
            followSystem = false
        }
        fixedTheme = id
    }

    func adjustFontSize(by delta: Double) {
        fontSize = min(max(fontSize + delta, Self.fontSizes.lowerBound), Self.fontSizes.upperBound)
    }

    private static func readSystemIsDark() -> Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle")?.lowercased() == "dark"
    }

    private func save(_ value: GlassSetting, _ key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> GlassSetting? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(GlassSetting.self, from: $0) }
    }
}

extension RGBA {
    var color: Color { Color(nsColor: ns) }
}
