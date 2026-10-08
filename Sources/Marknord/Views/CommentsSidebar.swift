import MarknordCore
import SwiftUI

/// The comments inspector: open/resolved comments in reading order, the one being written, and the orphans whose
/// passage left the file.
struct CommentsSidebar: View {
    let document: DocumentModel
    let theme: Theme
    @State private var showResolved = false

    var body: some View {
        let listed = document.listedComments(resolved: showResolved)
        let orphans = document.orphanComments
        let orphanHighlights = document.orphanHighlights

        VStack(alignment: .leading, spacing: 0) {
            HStack {
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
            .padding(.horizontal, 14)
            .padding(.top, 14)
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

// MARK: - Cards

private func cardBackground(_ color: MarkColor?, theme: Theme) -> Color {
    guard let color else { return theme.text.color.opacity(theme.isDark ? 0.05 : 0.04) }
    return theme.tone(color).stroke.color.opacity(theme.isDark ? 0.13 : 0.09)
}

private func cardBorder(_ color: MarkColor?, theme: Theme) -> Color {
    guard let color else { return theme.text.color.opacity(0.1) }
    return theme.tone(color).stroke.color.opacity(0.4)
}

/// The passage a comment is about, with a bar in its colour.
private struct Quote: View {
    let text: String
    let color: Color
    let theme: Theme
    var detached = false

    var body: some View {
        Text(text.replacingOccurrences(of: "\u{2028}", with: " "))
            .font(.system(size: 11.5))
            .lineLimit(3)
            .strikethrough(detached)
            .foregroundStyle(detached ? theme.secondaryText.color : theme.heading.color.opacity(0.85))
            .padding(.leading, 8)
            .overlay(alignment: .leading) {
                Capsule().fill(detached ? theme.secondaryText.color.opacity(0.4) : color).frame(width: 2)
            }
    }
}

struct CommentCard: View {
    let document: DocumentModel
    let comment: Comment
    let theme: Theme
    var orphan = false

    @State private var editing = false
    @State private var replying = false
    @State private var draft = ""

    private var active: Bool { document.activeCommentID == comment.id }
    private var stroke: Color { theme.tone(comment.color ?? .yellow).stroke.color }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let anchor = comment.anchor {
                Quote(text: anchor.quote, color: stroke, theme: theme, detached: orphan)
            } else {
                Text("Sobre o documento todo")
                    .font(.system(size: 11.5).italic())
                    .foregroundStyle(theme.secondaryText.color)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) { Capsule().fill(theme.secondaryText.color.opacity(0.4)).frame(width: 2) }
            }

            if editing {
                Composer(initial: comment.body, placeholder: "Comentário", submitLabel: "Salvar", theme: theme) { body in
                    document.edit(comment.id, body: body)
                    editing = false
                } onCancel: { editing = false }
            } else {
                Text(comment.body)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.text.color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer

            let replies = document.replies(to: comment.id)
            if !replies.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(replies) { reply in
                        ReplyRow(document: document, reply: reply, theme: theme)
                    }
                }
                .padding(.leading, 8)
                .overlay(alignment: .leading) { Rectangle().fill(theme.text.color.opacity(0.12)).frame(width: 1) }
                .padding(.leading, 4)
            }

            if replying {
                Composer(placeholder: "Responder…", submitLabel: "Responder", theme: theme) { body in
                    document.reply(to: comment.id, body: body)
                    replying = false
                } onCancel: { replying = false }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground(comment.color, theme: theme), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(active ? stroke.opacity(0.85) : cardBorder(comment.color, theme: theme), lineWidth: active ? 2 : 1)
        }
        .opacity(orphan || comment.isResolved ? 0.78 : 1)
        .contentShape(Rectangle())
        .onTapGesture { document.focusComment(comment.id) }
        .animation(.smooth(duration: 0.18), value: active)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(comment.createdAt, format: .relative(presentation: .named))
                .help(comment.createdAt.formatted(date: .abbreviated, time: .shortened))
            if !orphan {
                Button("Responder") { replying = true }
            }
            Button(comment.isResolved ? "Reabrir" : "Resolver") {
                document.setResolved(comment.id, !comment.isResolved)
            }
            Spacer(minLength: 0)
            Menu {
                Button("Editar") { editing = true }
                Menu("Cor") {
                    Button("Padrão") { document.recolorComment(comment.id, to: nil) }
                    ForEach(MarkColor.allCases) { color in
                        Button(color.displayName) { document.recolorComment(comment.id, to: color) }
                    }
                }
                Divider()
                Button("Apagar", role: .destructive) { document.deleteComment(comment.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .font(.system(size: 10.5))
        .foregroundStyle(theme.secondaryText.color)
    }
}

private struct ReplyRow: View {
    let document: DocumentModel
    let reply: Comment
    let theme: Theme
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if editing {
                Composer(initial: reply.body, placeholder: "Resposta", submitLabel: "Salvar", theme: theme) { body in
                    document.edit(reply.id, body: body)
                    editing = false
                } onCancel: { editing = false }
            } else {
                Text(reply.body)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.text.color)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Text(reply.createdAt, format: .relative(presentation: .named))
                Button("Editar") { editing = true }
                Button("Apagar") { document.deleteComment(reply.id) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundStyle(theme.secondaryText.color)
        }
    }
}

private struct NewCommentCard: View {
    let document: DocumentModel
    let theme: Theme
    let composing: Composing
    @State private var color: MarkColor?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let anchor = composing.anchor {
                Quote(text: anchor.quote, color: theme.tone(color ?? .yellow).stroke.color, theme: theme)
            } else {
                Text("Sobre o documento todo")
                    .font(.system(size: 11.5).italic())
                    .foregroundStyle(theme.secondaryText.color)
            }
            Composer(
                placeholder: composing.anchor == nil ? "O que vale lembrar sobre o documento?" : "O que você quer lembrar sobre este trecho?",
                submitLabel: "Comentar", theme: theme
            ) { body in
                document.submitComment(body: body, color: color)
            } onCancel: {
                document.composing = nil
            }
            ColorSwatches(selection: $color, theme: theme)
        }
        .padding(11)
        .background(cardBackground(color, theme: theme), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(theme.tone(color ?? .yellow).stroke.color.opacity(0.7), lineWidth: 1.5)
        }
    }
}

private struct OrphanHighlightCard: View {
    let document: DocumentModel
    let highlight: Highlight
    let theme: Theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "highlighter")
                .foregroundStyle(theme.tone(highlight.color).stroke.color)
            Quote(text: highlight.anchor.quote, color: theme.tone(highlight.color).stroke.color, theme: theme, detached: true)
            Spacer(minLength: 0)
            Button {
                document.removeHighlight(highlight.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.secondaryText.color)
            .help("Apagar destaque órfão")
        }
        .font(.system(size: 11.5))
        .padding(10)
        .background(cardBackground(nil, theme: theme), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .opacity(0.78)
    }
}

// MARK: - Bits

/// "Padrão" plus the six colours, for a comment's card.
private struct ColorSwatches: View {
    @Binding var selection: MarkColor?
    let theme: Theme

    var body: some View {
        HStack(spacing: 6) {
            swatch(nil, fill: theme.text.color.opacity(0.12), name: "Padrão")
            ForEach(MarkColor.allCases) { color in
                swatch(color, fill: theme.tone(color).fill.alpha(1).color, name: color.displayName)
            }
        }
    }

    private func swatch(_ color: MarkColor?, fill: Color, name: String) -> some View {
        Button { selection = color } label: {
            Circle()
                .fill(fill)
                .frame(width: 15, height: 15)
                .overlay {
                    if selection == color { Circle().strokeBorder(theme.heading.color, lineWidth: 2) }
                }
        }
        .buttonStyle(.plain)
        .help(name)
    }
}

/// A text box that grows with what is written; ⌘↩ sends, esc cancels.
private struct Composer: View {
    var initial = ""
    let placeholder: String
    let submitLabel: String
    let theme: Theme
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField(placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .lineLimit(2...10)
                .focused($focused)
                .padding(8)
                .background(theme.background.color.opacity(0.55), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.accent.color.opacity(focused ? 0.6 : 0.2))
                }
                .onKeyPress(.return, phases: .down) { press in
                    guard press.modifiers.contains(.command) else { return .ignored }
                    submit()
                    return .handled
                }
                .onExitCommand(perform: onCancel)
            HStack(spacing: 8) {
                Button("Cancelar", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.secondaryText.color)
                Button(submitLabel, action: submit)
                    .buttonStyle(.glassProminent)
                    .controlSize(.small)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .font(.system(size: 11.5))
        }
        .onAppear {
            text = initial
            focused = true
        }
    }

    private func submit() {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        onSubmit(body)
    }
}
