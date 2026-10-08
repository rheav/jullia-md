import MarknordCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Geral", systemImage: "gearshape") { GeneralSettings() }
            Tab("Aparência", systemImage: "circle.lefthalf.filled") { AppearanceSettings() }
        }
        .frame(width: 580)
    }
}

private struct GeneralSettings: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Abrir") {
                Toggle("Reabrir as pastas e o último arquivo ao iniciar", isOn: $settings.reopenFolders)
                Toggle("Recarregar quando o arquivo mudar no disco", isOn: $settings.liveReload)
            }
            Section("Leitura") {
                LabeledContent("Tamanho do texto") {
                    HStack {
                        Slider(value: $settings.fontSize, in: AppSettings.fontSizes, step: 1)
                            .frame(width: 200)
                        Text("\(Int(settings.fontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                LabeledContent("Largura da coluna") {
                    HStack {
                        Slider(value: $settings.readingWidth, in: AppSettings.readingWidths, step: 20)
                            .frame(width: 200)
                        Text("\(Int(settings.readingWidth))")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AppearanceSettings: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Tema") {
                Toggle(isOn: $settings.followSystem) {
                    Text("Seguir o sistema")
                    Text("Claro e escuro trocam junto com o macOS")
                }
                if settings.followSystem {
                    Picker("Tema escuro", selection: $settings.darkTheme) {
                        ForEach(ThemeID.allCases.filter { $0.theme.isDark }) { Text($0.theme.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Picker("Tema claro", selection: $settings.lightTheme) {
                        ForEach(ThemeID.allCases.filter { !$0.theme.isDark }) { Text($0.theme.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } else {
                    Picker("Tema", selection: $settings.fixedTheme) {
                        ForEach(ThemeID.allCases) { Text($0.theme.name).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                HStack(spacing: 12) {
                    ForEach(ThemeID.allCases) { id in
                        ThemeCard(theme: id.theme, selected: isSelected(id)) { settings.choose(id) }
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                GlassRow(title: "Janela", subtitle: "Fundo do documento", glass: $settings.windowGlass)
                GlassRow(title: "Sidebar de arquivos", subtitle: nil, glass: $settings.filesGlass)
                GlassRow(title: "Sidebar de comentários", subtitle: nil, glass: $settings.commentsGlass)
            } header: {
                Text("Transparência (Liquid Glass)")
            } footer: {
                Text(reduceTransparency
                    ? "“Reduzir transparência” está ligado no macOS: tudo aparece sólido."
                    : "0% = sólido. Máximo de \(Int(GlassSetting.maxPercent))% para o texto continuar legível.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func isSelected(_ id: ThemeID) -> Bool {
        settings.followSystem ? (id == settings.darkTheme || id == settings.lightTheme) : id == settings.fixedTheme
    }
}

private struct GlassRow: View {
    let title: String
    let subtitle: String?
    @Binding var glass: GlassSetting

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $glass.enabled)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            Slider(value: $glass.percent, in: 0...GlassSetting.maxPercent, step: 5)
                .frame(width: 170)
                .disabled(!glass.enabled)
            Text("\(Int(glass.percent))%")
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
                .foregroundStyle(glass.enabled ? .primary : .tertiary)
        }
    }
}

private struct ThemeCard: View {
    let theme: Theme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aa")
                        .font(.system(size: 17, weight: .semibold, design: theme.serif ? .serif : .default))
                        .foregroundStyle(theme.heading.color)
                    Capsule().fill(theme.accent.color).frame(width: 46, height: 4)
                    Capsule().fill(theme.tone(.yellow).fill.color).frame(height: 4)
                    Capsule().fill(theme.secondaryText.color.opacity(0.5)).frame(width: 56, height: 4)
                }
                .padding(9)
                .frame(width: 112, height: 70, alignment: .bottomLeading)
                .background(theme.background.color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2.5 : 1)
                }
                Text(theme.name).font(.caption)
            }
        }
        .buttonStyle(.plain)
    }
}
