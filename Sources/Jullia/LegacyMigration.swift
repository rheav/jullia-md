import Foundation

/// The app was called Marknord (bundle `dev.rheav.marknord`) up to v0.2.0. On the first launch as Jullia.md, carry
/// its preferences and annotations over. The old copies are left where they are.
enum LegacyMigration {
    static let legacyBundleID = "dev.rheav.marknord"
    private static let doneKey = "migratedFromMarknord"

    static func run() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else { return }

        if let legacy = defaults.persistentDomain(forName: legacyBundleID) {
            for (key, value) in legacy where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }

        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacyFolder = support.appending(path: "Marknord", directoryHint: .isDirectory)
        let folder = support.appending(path: "Jullia", directoryHint: .isDirectory)
        if fileManager.fileExists(atPath: legacyFolder.path), !fileManager.fileExists(atPath: folder.path) {
            try? fileManager.copyItem(at: legacyFolder, to: folder)
        }

        defaults.set(true, forKey: doneKey)
    }
}
