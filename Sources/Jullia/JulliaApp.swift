import AppKit
import JulliaCore
import SwiftUI

@main
struct JulliaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model: AppModel

    init() {
        LegacyMigration.run()
        _model = State(initialValue: AppModel.shared)
    }

    var body: some Scene {
        Window("Jullia.md", id: "main") {
            MainView()
                .environment(model)
                .environment(model.settings)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 860)
        .commands { JulliaCommands(model: model) }

        Settings {
            SettingsView()
                .environment(model.settings)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(AppModel.shared.open)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
