import JulliaCore
import SwiftUI

struct JulliaCommands: Commands {
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
            Button(model.filesCollapsed ? "Expandir arquivos" : "Recolher arquivos") { model.filesCollapsed.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
            Button(model.commentsCollapsed ? "Expandir comentários" : "Recolher comentários") { model.commentsCollapsed.toggle() }
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
