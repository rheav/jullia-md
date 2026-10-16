import JulliaCore
import PDFKit
import SwiftUI

/// The table of contents: the Markdown headings, or the PDF's own outline and its pages.
struct OutlineSidebar: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppModel.self) private var model
    /// For a PDF: the pages instead of the outline. A PDF without an outline starts on its pages.
    @State private var showsPages: Bool

    init(document: DocumentModel, theme: Theme) {
        self.document = document
        self.theme = theme
        _showsPages = State(initialValue: document.isPDF && document.outline.isEmpty)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if document.isPDF && showsPages {
                PageThumbnails(document: document, theme: theme)
            } else {
                headings
            }
        }
    }

    private var header: some View {
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
            .pointerStyle(.link)
            .help("Recolher painel (⌥⌘0)")
            Text("Sumário")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.heading.color)
            Spacer()
            if document.isPDF {
                Picker("", selection: $showsPages) {
                    Text("Índice").tag(false)
                    Text("Páginas").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var headings: some View {
        let items = document.outline
        if items.isEmpty {
            Text(document.isPDF ? "Este PDF não tem índice. Veja as páginas." : "Este documento não tem títulos.")
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            Spacer(minLength: 0)
        } else {
            // Indented from the document's own top level: a file that starts at ## is not pushed right.
            let top = items.map(\.level).min() ?? 1
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { item in
                        OutlineRow(item: item, depth: item.level - top, theme: theme) { document.go(to: item) }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 14)
            }
            .scrollContentBackground(.hidden)
        }
    }
}

private struct OutlineRow: View {
    let item: OutlineItem
    let depth: Int
    let theme: Theme
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(item.title)
                .font(.system(size: depth == 0 ? 13 : 12.5, weight: depth == 0 ? .semibold : .regular))
                .foregroundStyle(depth <= 1 ? theme.text.color : theme.secondaryText.color)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8 + CGFloat(min(depth, 5)) * 14)
                .padding(.trailing, 8)
                .padding(.vertical, 5)
                .background(hovering ? theme.selection.color : .clear, in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.title)
    }
}

/// The PDF's pages, two to a row, the one being read outlined; a click goes to a page. Each thumbnail is drawn when
/// it scrolls into view.
private struct PageThumbnails: View {
    let document: DocumentModel
    let theme: Theme

    var body: some View {
        let count = document.pdfDocument?.pageCount ?? 0
        let current = document.pdfPageNumber - 1
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 14) {
                    ForEach(0..<count, id: \.self) { index in
                        Button { document.goToPDFPage(index) } label: {
                            PageThumbnail(page: document.pdfDocument?.page(at: index), number: index + 1,
                                          current: index == current, theme: theme)
                        }
                        .buttonStyle(.plain)
                        .id(index)
                        .help("Página \(index + 1)")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
            .scrollContentBackground(.hidden)
            .onAppear { proxy.scrollTo(current, anchor: .center) }
            .onChange(of: document.pdfPageNumber) { _, page in
                withAnimation(.smooth) { proxy.scrollTo(page - 1, anchor: .center) }
            }
        }
    }
}

private struct PageThumbnail: View {
    let page: PDFPage?
    let number: Int
    let current: Bool
    let theme: Theme
    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                Color.white
                if let image { Image(nsImage: image).resizable().aspectRatio(contentMode: .fit) }
            }
            .aspectRatio(aspect, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(current ? theme.accent.color : theme.rule.color, lineWidth: current ? 2.5 : 1)
            }
            Text("\(number)")
                .font(.system(size: 11, weight: current ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(current ? theme.accent.color : theme.secondaryText.color)
        }
        .contentShape(Rectangle())
        .task(id: page.map(ObjectIdentifier.init)) {
            image = page?.thumbnail(of: NSSize(width: 260, height: 260 / aspect), for: .cropBox)
        }
    }

    /// Width over height, from the page's crop box; a portrait page until it is known.
    private var aspect: CGFloat {
        guard let bounds = page?.bounds(for: .cropBox), bounds.height > 0 else { return 0.75 }
        let rotated = (page?.rotation ?? 0) % 180 != 0
        return rotated ? bounds.height / bounds.width : bounds.width / bounds.height
    }
}
