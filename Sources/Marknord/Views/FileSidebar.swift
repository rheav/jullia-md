import AppKit
import MarknordCore
import SwiftUI

struct FileSidebar: View {
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            // Room for the traffic lights, which sit over this panel.
            Color.clear.frame(height: 26)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme.secondaryText.color)
                TextField("Buscar arquivos", text: $model.fileQuery)
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
            .padding(.horizontal, 10)

            List(selection: selection) {
                if model.fileQuery.isEmpty, !model.recents.isEmpty {
                    Section("Recentes") {
                        ForEach(model.recents.prefix(4), id: \.self) { url in
                            FileRow(name: url.lastPathComponent, isDirectory: false, count: model.count(for: url), theme: theme)
                                .tag(RowID.recent(url))
                                .help(url.path)
                        }
                    }
                }

                ForEach(model.roots) { root in
                    if let tree = FileTree.filter(root, query: model.fileQuery), let children = tree.children {
                        Section {
                            OutlineGroup(children, children: \.children) { node in
                                FileRow(name: node.name, isDirectory: node.isDirectory, count: node.isDirectory ? 0 : model.count(for: node.url), theme: theme)
                                    .tag(RowID.tree(node.url))
                            }
                        } header: {
                            Text(root.name)
                                .contextMenu { rootMenu(root.url) }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .environment(\.sidebarRowSize, .medium)

            HStack {
                Button {
                    model.presentFolderPanel()
                } label: {
                    Label("Abrir pasta…", systemImage: "plus")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.secondaryText.color)
                Spacer()
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

    /// A row's identity. The same file can be listed under Recentes and in its folder; only the folder row shows as
    /// selected.
    enum RowID: Hashable {
        case recent(URL)
        case tree(URL)
    }

    /// Selecting a file opens it; folders only expand.
    private var selection: Binding<RowID?> {
        Binding(
            get: { model.document.map { .tree($0.url) } },
            set: { row in
                guard let row else { return }
                let url = switch row {
                case .recent(let url), .tree(let url): url
                }
                guard FileTree.isMarkdown(url) else { return }
                // Not from inside the list's own selection callback: opening reloads the list.
                DispatchQueue.main.async { model.openFile(url) }
            }
        )
    }

    @ViewBuilder
    private func rootMenu(_ url: URL) -> some View {
        Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Atualizar") { model.rescan(url) }
        Divider()
        Button("Remover da sidebar") { model.removeFolder(url) }
    }
}

private struct FileRow: View {
    let name: String
    let isDirectory: Bool
    let count: Int
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: isDirectory ? "folder" : "doc.text")
                .foregroundStyle(isDirectory ? theme.accent.color : theme.secondaryText.color)
                .frame(width: 16)
            Text(name)
                .foregroundStyle(theme.text.color)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
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
