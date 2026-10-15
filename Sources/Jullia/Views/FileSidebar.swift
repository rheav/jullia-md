import AppKit
import JulliaCore
import SwiftUI

/// The file panel: a search over every folder, the tree of one folder at a time (the focused document's, or one
/// picked by hand) with a breadcrumb to climb back up, and the places the reader opened.
struct FileSidebar: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(theme.secondaryText.color)
                    TextField("Buscar em todas as pastas", text: $model.fileQuery)
                        .textFieldStyle(.plain)
                    if !model.fileQuery.isEmpty {
                        Button { model.fileQuery = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryText.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 12.5))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(theme.text.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 9, style: .continuous))

                Button {
                    model.filesCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText.color)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Recolher arquivos (⌃⌘S)")
            }
            .padding(.leading, 10)
            .padding(.trailing, 6)
            .padding(.top, 10)

            if !model.fileQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                SearchResults(theme: theme)
            } else if model.browser.mode == .recents {
                RecentFiles(theme: theme)
            } else {
                FolderBrowser(theme: theme)
            }

            PlacesList(theme: theme)

            HStack {
                Button {
                    model.presentFolderPanel()
                } label: {
                    Label("Abrir pasta…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText.color)
                Spacer()
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText.color)
                .help("Ajustes (⌘,)")
                Button {
                    model.rescanAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText.color)
                .help("Atualizar pastas")
            }
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .dropDestination(for: URL.self) { urls, _ in
            urls.forEach(model.open)
            return !urls.isEmpty
        }
    }
}

/// A row's identity in the file lists. Selecting a file opens it; selecting a folder opens or closes it in place.
enum FileRowID: Hashable {
    case file(URL)
    case folder(URL)

    init(_ node: FileNode) {
        let url = node.url.standardizedFileURL
        self = node.isDirectory ? .folder(url) : .file(url)
    }
}

extension AppModel {
    /// The selection the file lists show: the focused document. Setting it acts on the row instead of storing it.
    var fileSelection: Binding<FileRowID?> {
        Binding(
            get: { self.document.map { .file($0.url.standardizedFileURL) } },
            set: { row in
                // Not from inside the list's own selection callback: opening reloads the list.
                DispatchQueue.main.async {
                    switch row {
                    case .file(let url): if FileTree.isSupported(url) { self.openFile(url) }
                    case .folder(let url): self.browser.toggle(url)
                    case nil: break
                    }
                }
            }
        )
    }
}

/// The tree of the folder shown, under its breadcrumb.
private struct FolderBrowser: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let tree = model.browserTree
        VStack(alignment: .leading, spacing: 4) {
            Breadcrumb(theme: theme)
            if let tree {
                let rows = FileTree.rows(tree, expanded: model.browser.expanded)
                if rows.isEmpty {
                    Note(text: "Nenhum Markdown ou PDF nesta pasta.", theme: theme)
                } else {
                    List(selection: model.fileSelection) {
                        ForEach(rows) { row in
                            TreeRow(row: row, theme: theme)
                                .tag(FileRowID(row.node))
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .environment(\.sidebarRowSize, .medium)
                }
            } else {
                Note(text: "Abra uma pasta para navegar pelos seus Markdown e PDFs.", theme: theme)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// Where the tree starts: up one level, the path from the root down, and the order of the files.
private struct Breadcrumb: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var browser = model.browser
        let trail = browser.trail(from: browser.folder.flatMap { model.root(containing: $0)?.url })
        HStack(spacing: 4) {
            Button {
                if trail.count > 1 { browser.show(trail[trail.count - 2]) }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(trail.count > 1 ? theme.text.color : theme.secondaryText.color.opacity(0.4))
            .disabled(trail.count < 2)
            .help(trail.count > 1 ? "Subir para \(trail[trail.count - 2].lastPathComponent)" : "")

            HStack(spacing: 3) {
                if trail.count > 2 {
                    crumb(trail[0], current: false)
                    separator
                    Menu {
                        ForEach(trail.dropFirst().dropLast(), id: \.self) { folder in
                            Button(folder.lastPathComponent) { browser.show(folder) }
                        }
                    } label: {
                        Text("…")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    separator
                    crumb(trail[trail.count - 1], current: true)
                } else {
                    ForEach(Array(trail.enumerated()), id: \.element) { index, folder in
                        if index > 0 { separator }
                        crumb(folder, current: index == trail.count - 1)
                    }
                }
            }
            .font(.system(size: 12))
            .lineLimit(1)

            Spacer(minLength: 2)

            if model.browsingLooseFolder, let folder = browser.folder {
                Button {
                    model.addFolder(folder)
                } label: {
                    Image(systemName: "plus.circle")
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText.color)
                .help("Adicionar \(folder.lastPathComponent) aos Locais")
            }

            Menu {
                Picker("Ordenar por", selection: $browser.sort) {
                    Text("Nome").tag(FileSort.name)
                    Text("Data de modificação").tag(FileSort.date)
                }
                .pickerStyle(.inline)
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 11, weight: .medium))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundStyle(theme.secondaryText.color)
            .help(browser.sort == .name ? "Ordenado por nome" : "Ordenado por data")
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .frame(height: 26)
    }

    private var separator: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(theme.secondaryText.color.opacity(0.7))
    }

    private func crumb(_ folder: URL, current: Bool) -> some View {
        Button {
            model.browser.show(folder)
        } label: {
            Text(folder.lastPathComponent)
                .fontWeight(current ? .semibold : .regular)
                .foregroundStyle(current ? theme.heading.color : theme.secondaryText.color)
                .truncationMode(.middle)
        }
        .buttonStyle(.plain)
        .layoutPriority(current ? 1 : 0)
        .help(folder.path)
    }
}

/// One line of the tree: a folder that opens in place, or a file.
private struct TreeRow: View {
    let row: FileTreeRow
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let node = row.node
        let url = node.url.standardizedFileURL
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Color.clear.frame(width: CGFloat(row.depth) * 14, height: 1)
            if node.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(theme.secondaryText.color)
                    .rotationEffect(.degrees(model.browser.isExpanded(url) ? 90 : 0))
                    .frame(width: 10)
            } else {
                Color.clear.frame(width: 10, height: 1)
            }
            FileLabel(name: node.name, isDirectory: node.isDirectory, count: node.isDirectory ? 0 : model.count(for: url), theme: theme,
                      isOpen: !node.isDirectory && model.isOpen(url))
        }
        .contentShape(Rectangle())
        .help(node.name)
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if node.isDirectory { model.browser.show(url) } else { model.openFile(url, as: .permanent) }
        })
        .contextMenu {
            if node.isDirectory {
                Button("Entrar na pasta") { model.browser.show(url) }
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            } else {
                FileMenu(url: url)
            }
        }
    }
}

/// Files whose name matches the search, in every folder, each with where it lives.
private struct SearchResults: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let results = FileTree.search(model.searchableTrees, query: model.fileQuery)
        if results.isEmpty {
            Note(text: "Nenhum arquivo encontrado.", theme: theme)
                .frame(maxHeight: .infinity, alignment: .top)
        } else {
            List(selection: model.fileSelection) {
                Section("Resultados · \(results.count)") {
                    ForEach(results) { node in
                        let url = node.url.standardizedFileURL
                        FileLabel(name: node.name, isDirectory: false, count: model.count(for: url), theme: theme,
                                  detail: location(of: url), isOpen: model.isOpen(url))
                            .contentShape(Rectangle())
                            .tag(FileRowID.file(url))
                            .help(url.path)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.openFile(url, as: .permanent) })
                            .contextMenu {
                                FileMenu(url: url)
                                Button("Mostrar pasta na sidebar") {
                                    model.fileQuery = ""
                                    model.browser.show(url.deletingLastPathComponent())
                                }
                            }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.sidebarRowSize, .medium)
        }
    }

    /// "Root › folder › folder" for a file found by the search.
    private func location(of url: URL) -> String {
        let folder = url.deletingLastPathComponent().standardizedFileURL
        guard let root = model.root(containing: folder) ?? model.looseTree else { return folder.lastPathComponent }
        let relative = folder.path.dropFirst(root.url.standardizedFileURL.path.count).split(separator: "/").map(String.init)
        return ([root.name] + relative).joined(separator: " › ")
    }

}

/// The recently opened files, newest first, each with its folder.
private struct RecentFiles: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Button {
                    model.browser.show(model.browser.folder)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 20, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.text.color)
                .help("Voltar à pasta")
                Text("Recentes")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.heading.color)
                Spacer()
            }
            .padding(.leading, 8)
            .frame(height: 26)

            if model.recents.isEmpty {
                Note(text: "Nenhum arquivo aberto ainda.", theme: theme)
            } else {
                List(selection: model.fileSelection) {
                    ForEach(model.recents, id: \.self) { url in
                        let url = url.standardizedFileURL
                        FileLabel(name: url.lastPathComponent, isDirectory: false, count: model.count(for: url), theme: theme,
                                  detail: url.deletingLastPathComponent().lastPathComponent, isOpen: model.isOpen(url))
                            .contentShape(Rectangle())
                            .tag(FileRowID.file(url))
                            .help(url.path)
                            .simultaneousGesture(TapGesture(count: 2).onEnded { model.openFile(url, as: .permanent) })
                            .contextMenu { FileMenu(url: url) }
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .environment(\.sidebarRowSize, .medium)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// The folders the reader opened, and the recent files: the starting points of the browser.
private struct PlacesList: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        let browser = model.browser
        let shownRoot = browser.folder.flatMap { model.root(containing: $0) }?.url
        VStack(alignment: .leading, spacing: 1) {
            Text("Locais")
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .textCase(.uppercase)
                .foregroundStyle(theme.secondaryText.color)
                .padding(.horizontal, 8)
                .padding(.bottom, 3)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(model.roots) { root in
                        PlaceRow(symbol: "folder", name: root.name, theme: theme,
                                 active: browser.mode == .folder && shownRoot == root.url) {
                            model.fileQuery = ""
                            browser.show(root.url)
                        }
                        .help(root.url.path)
                        .contextMenu {
                            Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([root.url]) }
                            Button("Atualizar") { model.rescan(root.url) }
                            Divider()
                            Button("Remover da sidebar") { model.removeFolder(root.url) }
                        }
                    }
                    PlaceRow(symbol: "clock", name: "Recentes", theme: theme, active: browser.mode == .recents) {
                        model.fileQuery = ""
                        browser.showRecents()
                    }
                }
            }
            .frame(maxHeight: 150)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.rule.color).frame(height: 1).padding(.horizontal, 10)
        }
    }
}

private struct PlaceRow: View {
    let symbol: String
    let name: String
    let theme: Theme
    let active: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .foregroundStyle(theme.accent.color)
                    .frame(width: 16)
                Text(name)
                    .foregroundStyle(active ? theme.heading.color : theme.text.color)
                    .fontWeight(active ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                active ? theme.accent.color.opacity(0.14) : (hovering ? theme.text.color.opacity(0.06) : .clear),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// The actions on a file row.
private struct FileMenu: View {
    let url: URL
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Abrir") { model.openFile(url) }
        Button("Abrir em nova aba") { model.openFile(url, as: .newTab) }
        Button("Abrir ao lado") { model.openFile(url, as: .beside) }
        Divider()
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }
}

/// A quiet line of text where a list would be.
private struct Note: View {
    let text: String
    let theme: Theme

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(theme.secondaryText.color)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
    }
}

/// A file or folder: icon, a name that wraps to a second line instead of losing its middle, an optional detail
/// line, whether it is open in a tab, and the annotation count.
struct FileLabel: View {
    let name: String
    let isDirectory: Bool
    let count: Int
    let theme: Theme
    var detail: String? = nil
    /// Open in a tab: marked with a dot.
    var isOpen = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: isDirectory ? "folder" : (name.lowercased().hasSuffix(".pdf") ? "doc.richtext" : "doc.text"))
                .foregroundStyle(isDirectory ? theme.accent.color : theme.secondaryText.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .foregroundStyle(theme.text.color)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.secondaryText.color)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer(minLength: 4)
            if isOpen {
                Circle()
                    .fill(theme.accent.color)
                    .frame(width: 5, height: 5)
                    .help("Aberto numa aba")
            }
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(theme.accent.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(theme.accent.color.opacity(0.16), in: Capsule())
            }
        }
        .font(.system(size: 12.5))
    }
}
