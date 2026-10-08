import AppKit
import MarknordCore
import SwiftUI

@main
struct MarknordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel.shared

    var body: some Scene {
        Window("Marknord", id: "main") {
            MainView()
                .environment(model)
                .environment(model.settings)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 860)
        .commands { MarknordCommands(model: model) }

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

struct MarknordCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Abrir…") { model.presentOpenPanel() }
                .keyboardShortcut("o")
            Button("Abrir pasta…") { model.presentFolderPanel() }
                .keyboardShortcut("o", modifiers: [.command, .shift])
            Divider()
            Button("Recarregar") {
                model.document?.reload()
                model.rescanAll()
            }
            .keyboardShortcut("r")
        }

        CommandMenu("Anotar") {
            Group {
                Button("Destacar") { model.highlightSelection() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Menu("Destacar com") {
                    ForEach(MarkColor.allCases) { color in
                        Button(color.displayName) { model.highlightSelection(color: color) }
                    }
                }
                Divider()
                Button("Comentar trecho…") { model.commentSelection() }
                    .keyboardShortcut("m", modifiers: [.command, .option])
                Button("Comentar o documento todo…") { model.commentWholeDocument() }
            }
            .disabled(model.document == nil)
        }

        CommandGroup(after: .sidebar) {
            Toggle("Arquivos", isOn: Binding(get: { model.showFiles }, set: { model.showFiles = $0 }))
                .keyboardShortcut("s", modifiers: [.command, .control])
            Toggle("Comentários", isOn: Binding(get: { model.showComments }, set: { model.showComments = $0 }))
                .keyboardShortcut("0", modifiers: [.command, .option])
            Divider()
            Menu("Tema") {
                ForEach(Array(ThemeID.allCases.enumerated()), id: \.element) { index, id in
                    Button(id.theme.name) { model.settings.choose(id) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
                }
            }
            Divider()
            Button("Aumentar texto") { model.settings.adjustFontSize(by: 1) }
                .keyboardShortcut("+")
            Button("Diminuir texto") { model.settings.adjustFontSize(by: -1) }
                .keyboardShortcut("-")
            Button("Tamanho padrão") { model.settings.fontSize = 16 }
                .keyboardShortcut("0")
            Divider()
        }
    }
}
