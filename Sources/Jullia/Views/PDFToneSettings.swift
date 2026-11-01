import JulliaCore
import SwiftUI

/// Whether PDF pages darken and on which paper. Hovering a tone shows it in the sample; a click applies it.
struct PDFToneSection: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: Int?

    /// The theme whose papers are offered: the one in use, or the dark one while a light theme is on.
    private var theme: Theme { settings.theme.isDark ? settings.theme : settings.darkTheme.theme }

    private var shown: PDFPaper? {
        settings.pdfDark ? theme.pdfPaper(hovered ?? settings.pdfTone) : nil
    }

    var body: some View {
        @Bindable var settings = settings
        Section {
            Toggle(isOn: $settings.pdfDark) {
                Text("Escurecer páginas de PDF")
                Text("Fotos e páginas já escuras ficam como estão")
            }
            VStack(spacing: 12) {
                ZStack {
                    PDFToneSample(paper: shown).id(shown).transition(.opacity)
                }
                .padding([.horizontal, .top], 14)
                .frame(height: 136, alignment: .top)
                .background(theme.background.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: shown)
                HStack(spacing: 12) {
                    ForEach(Array(theme.pdfPapers.enumerated()), id: \.element.id) { index, paper in
                        PDFToneCard(paper: paper, selected: selectedTone == index) { settings.pdfTone = index }
                            .onHover { hovered = $0 ? index : (hovered == index ? nil : hovered) }
                    }
                }
                .disabled(!settings.pdfDark)
                .opacity(settings.pdfDark ? 1 : 0.45)
            }
            .padding(.vertical, 4)
        } header: {
            Text("PDF escuro")
        } footer: {
            Text("Vale nos temas escuros.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// A saved tone out of range shows on the card it falls on.
    private var selectedTone: Int { min(max(settings.pdfTone, 0), theme.pdfPapers.count - 1) }
}

/// A piece of a page: its text, with what a document's colours say. Without a paper, its original colours.
private struct PDFToneSample: View {
    let paper: PDFPaper?

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Título do documento")
                .font(.custom("Arial-BoldMT", size: 13))
                .foregroundStyle(color(0x434343))
            Text(paragraph("Um parágrafo comum, com ", marked: "um trecho marcado em amarelo", fill: 0xFFFF00, then: " no meio do texto."))
            Text(paragraph("", marked: "Vermelho para o que pede atenção.", ink: 0xFF0000, then: " Depois, o texto segue normal."))
            Text(paragraph("", marked: "Verde para os benefícios", fill: 0xD9EAD3, then: " e ", second: "creme para as notas.", fill2: 0xFFF2CC))
        }
        .font(.custom("ArialMT", size: 11.5))
        .foregroundStyle(color(0x000000))
        .lineSpacing(2)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color(0xFFFFFF), in: UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
    }

    private func color(_ hex: UInt32) -> Color {
        (paper.map { PDFRecolor.map(RGBA(hex), on: $0) } ?? RGBA(hex)).color
    }

    private func paragraph(_ lead: String, marked: String, ink: UInt32? = nil, fill: UInt32? = nil, then: String,
                           second: String? = nil, fill2: UInt32? = nil) -> AttributedString {
        var text = AttributedString(lead)
        var mark = AttributedString(marked)
        if let ink {
            mark.foregroundColor = color(ink)
            mark.font = .custom("Arial-BoldMT", size: 11.5)
        }
        if let fill { mark.backgroundColor = color(fill) }
        text += mark
        text += AttributedString(then)
        if let second, let fill2 {
            var more = AttributedString(second)
            more.backgroundColor = color(fill2)
            text += more
        }
        return text
    }
}

/// The same shape as a theme card, in the paper's colours.
private struct PDFToneCard: View {
    let paper: PDFPaper
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aa")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(paper.ink.color)
                    Capsule().fill(PDFRecolor.map(RGBA(0xFF0000), on: paper).color).frame(width: 46, height: 4)
                    Capsule().fill(PDFRecolor.map(RGBA(0xFFFF00), on: paper).color).frame(height: 4)
                    Capsule().fill(paper.ink.color.opacity(0.5)).frame(width: 56, height: 4)
                }
                .padding(9)
                .frame(width: 112, height: 70, alignment: .bottomLeading)
                .background(paper.paper.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                }
                Text(paper.name).font(.caption)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
