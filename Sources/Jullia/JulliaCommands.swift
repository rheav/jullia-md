import AppKit
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

        CommandGroup(replacing: .saveItem) {
            Button("Fechar aba") { model.closeFocusedTab() }
                .keyboardShortcut("w")
            Button("Fechar janela") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandMenu("Abas") {
            Button("Próxima aba") { model.workspace.selectAdjacentTab(1) }
                .keyboardShortcut("]", modifiers: [.command, .shift])
            Button("Aba anterior") { model.workspace.selectAdjacentTab(-1) }
                .keyboardShortcut("[", modifiers: [.command, .shift])
            Menu("Ir para a aba") {
                ForEach(1..<9) { number in
                    Button("Aba \(number)") { model.workspace.selectTab(at: number - 1) }
                        .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                }
                Button("Última aba") { model.workspace.selectTab(at: model.workspace.tabs.count - 1) }
                    .keyboardShortcut("9", modifiers: .command)
            }
            Divider()
            Menu("Layout") {
                ForEach(Array(PaneLayout.allCases.enumerated()), id: \.element) { index, layout in
                    Button(layout.title) { model.workspace.setLayout(layout) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
            }
            .disabled(model.workspace.tabs.isEmpty)
            Divider()
            Button("Manter aba") { if let tab = model.workspace.focusedTab { model.workspace.pin(tab) } }
                .disabled(model.workspace.focusedTab?.isPreview != true)
            Button("Fechar aba") { model.closeFocusedTab() }
                .disabled(model.workspace.focusedTab == nil)
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
                Button("Conversar sobre trecho") { model.chatSelection() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                    .disabled(model.document?.hasSelection != true)
            }
            .disabled(model.document == nil)
        }

        CommandGroup(after: .sidebar) {
            Button(model.filesCollapsed ? "Expandir arquivos" : "Recolher arquivos") { model.filesCollapsed.toggle() }
                .keyboardShortcut("s", modifiers: [.command, .control])
                .disabled(model.zen)
            Button(model.commentsCollapsed ? "Expandir comentários" : "Recolher comentários") { model.commentsCollapsed.toggle() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(model.zen)
            Button(model.zen ? "Sair do modo zen" : "Modo zen") { model.toggleZen() }
                .keyboardShortcut("z", modifiers: [.command, .control])
                .disabled(!model.canZen)
            Divider()
            Menu("Tema") {
                ForEach(Array(ThemeID.allCases.enumerated()), id: \.element) { index, id in
                    Button(id.theme.name) { model.settings.choose(id) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .control])
                }
            }
            Divider()
            Button(model.document?.isPDF == true ? "Aumentar zoom" : "Aumentar texto") {
                if model.document?.isPDF == true { model.document?.zoomPDF(1) } else { model.settings.adjustFontSize(by: 1) }
            }
                .keyboardShortcut("+")
            Button(model.document?.isPDF == true ? "Diminuir zoom" : "Diminuir texto") {
                if model.document?.isPDF == true { model.document?.zoomPDF(-1) } else { model.settings.adjustFontSize(by: -1) }
            }
                .keyboardShortcut("-")
            Button(model.document?.isPDF == true ? "Ajustar PDF à janela" : "Tamanho padrão") {
                if model.document?.isPDF == true { model.document?.zoomPDF(0) } else { model.settings.fontSize = 16 }
            }
                .keyboardShortcut("0")
            Divider()
        }
    }
}
