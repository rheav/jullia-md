import JulliaCore
import SwiftUI

/// The floating glass pill over a selection or a highlight: six colours, comment, copy (and remove, on a highlight).
struct SelectionPill: View {
    let theme: Theme
    /// The colour of the highlight under the pill, when it is over one.
    let current: MarkColor?
    let onColor: (MarkColor) -> Void
    let onComment: () -> Void
    let onCopy: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(MarkColor.allCases) { color in
                Button { onColor(color) } label: {
                    Circle()
                        .fill(theme.tone(color).fill.alpha(1).color)
                        .frame(width: 16, height: 16)
                        .overlay {
                            if color == current {
                                Circle().strokeBorder(theme.heading.color, lineWidth: 2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.displayName)
            }
            Divider().frame(height: 16)
            pillButton("text.bubble", help: "Comentar", action: onComment)
            pillButton("doc.on.doc", help: "Copiar", action: onCopy)
            if current != nil {
                pillButton("eraser", help: "Remover destaque", action: onRemove)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, theme.isDark ? .dark : .light)
    }

    private func pillButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(theme.heading.color)
                .frame(width: 20, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
