import JulliaCore
import SwiftUI

/// The comments inspector: open/resolved comments in reading order, the one being written, and the orphans whose
/// passage left the file.
struct CommentsSidebar: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppModel.self) private var model
    @State private var showResolved = false

    var body: some View {
        let listed = document.listedComments(resolved: showResolved)
        let orphans = document.orphanComments
        let orphanHighlights = document.orphanHighlights

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    model.commentsCollapsed.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.secondaryText.color)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(model.commentsCollapsed ? "Fixar comentários aberto (⌥⌘0)" : "Recolher comentários (⌥⌘0)")
                Text("Comentários")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.heading.color)
                Spacer()
                Picker("", selection: $showResolved) {
                    Text("Abertos").tag(false)
                    Text("Resolvidos").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.leading, 8)
            .padding(.trailing, 14)
            .padding(.top, 12)
            .padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if let composing = document.composing {
                            NewCommentCard(document: document, theme: theme, composing: composing)
                                .id("composer")
                        }

                        ForEach(listed) { comment in
                            CommentCard(document: document, comment: comment, theme: theme)
                                .id(comment.id)
                        }

                        if listed.isEmpty && document.composing == nil {
                            Text(showResolved ? "Nenhum comentário resolvido." : "Selecione um trecho e clique em 💬 para comentar.")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.secondaryText.color)
                                .padding(.vertical, 6)
                        }

                        if !showResolved, !orphans.isEmpty || !orphanHighlights.isEmpty {
                            Text("Órfãos · \(orphans.count + orphanHighlights.count)")
                                .font(.system(size: 10.5, weight: .semibold))
                                .tracking(0.8)
                                .textCase(.uppercase)
                                .foregroundStyle(theme.secondaryText.color)
                                .padding(.top, 8)
                                .help("O arquivo mudou e o trecho não foi mais encontrado.")
                            ForEach(orphans) { comment in
                                CommentCard(document: document, comment: comment, theme: theme, orphan: true)
                            }
                            ForEach(orphanHighlights) { highlight in
                                OrphanHighlightCard(document: document, highlight: highlight, theme: theme)
                            }
                        }

                        if !showResolved, document.composing == nil {
                            Button {
                                document.startComment(on: nil)
                            } label: {
                                Label("Comentar o documento todo", systemImage: "plus")
                                    .font(.system(size: 12))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(theme.secondaryText.color)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                                            .strokeBorder(theme.secondaryText.color.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 14)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: document.activeCommentID) { _, id in
                    guard let id else { return }
                    if document.comments.first(where: { $0.id == id })?.isResolved == true { showResolved = true }
                    withAnimation(.smooth) { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: document.composing) { _, composing in
                    if composing != nil {
                        showResolved = false
                        withAnimation(.smooth) { proxy.scrollTo("composer", anchor: .top) }
                    }
                }
            }
        }
    }
}
