import JulliaCore
import SwiftUI

struct InspectorSidebar: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            Picker("Painel lateral", selection: $model.inspectorTab) {
                ForEach(AppModel.InspectorTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 12)
            .padding(.top, 12)
            if model.inspectorTab == .comments {
                CommentsSidebar(document: document, theme: theme)
            } else {
                ChatSidebar(document: document, theme: theme).id(document.key)
            }
        }
    }
}

struct ChatSidebar: View {
    let document: DocumentModel
    let theme: Theme
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var inputFocused: Bool
    @State private var showingHistory = false
    private var chat: PassageChat { document.chat }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let message = chat.persistenceError {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.secondaryText.color)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
            if !showingHistory, let anchor = chat.anchor {
                passage(anchor)
            }
            if !showingHistory, let reason = chat.unavailableReason {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Apple Intelligence indisponível", systemImage: "sparkles")
                        .fontWeight(.medium)
                    Text(reason)
                    Button("Verificar novamente") { chat.refreshAvailability() }
                }
                .font(.system(size: 12))
                .foregroundStyle(theme.secondaryText.color)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.text.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .padding(12)
            }

            if showingHistory {
                history
            } else if chat.anchor == nil {
                emptyState
            } else {
                conversation
                composer
            }
        }
        .foregroundStyle(theme.text.color)
        .onAppear {
            chat.refreshAvailability()
            showingHistory = chat.anchor == nil && !chat.conversations.isEmpty
            inputFocused = chat.anchor != nil
        }
        .onChange(of: chat.currentID) {
            if chat.currentID != nil { showingHistory = false; inputFocused = true }
        }
        .onChange(of: showingHistory) { if showingHistory { inputFocused = false } }
        .onChange(of: scenePhase) { if scenePhase == .active { chat.refreshAvailability() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Button { model.commentsCollapsed = true } label: {
                Image(systemName: "sidebar.right")
            }
            .buttonStyle(.plain)
            .help("Recolher painel (⌥⌘0)")
            .accessibilityLabel("Recolher painel")
            Label("No seu Mac", systemImage: "sparkles")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
            Button {
                showingHistory.toggle()
            } label: {
                Label(showingHistory && chat.anchor != nil ? "Voltar" : "Histórico", systemImage: "clock.arrow.circlepath")
            }
            .font(.system(size: 11))
            .disabled(chat.conversations.isEmpty && !showingHistory)
            .help("Ver conversas anteriores deste documento")
            Button {
                chat.clear()
                showingHistory = false
            } label: {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.plain)
            .help("Nova conversa — a conversa atual fica no histórico")
            .accessibilityLabel("Nova conversa")
            if !showingHistory, let id = chat.currentID, !chat.messages.isEmpty {
                deleteButton(id)
            }
        }
        .foregroundStyle(theme.secondaryText.color)
        .padding(12)
    }

    private var history: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Conversas deste documento")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.heading.color)
                .padding(.horizontal, 12)
            if chat.conversations.isEmpty {
                Text("Nenhuma conversa salva ainda.")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.secondaryText.color)
                    .padding(12)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(chat.conversations) { conversation in
                            HStack(alignment: .top, spacing: 8) {
                                Button {
                                    chat.openConversation(conversation.id)
                                    showingHistory = false
                                    inputFocused = true
                                } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(conversation.title)
                                            .font(.system(size: 12.5, weight: .semibold))
                                            .foregroundStyle(theme.heading.color)
                                            .lineLimit(2)
                                        Text(conversation.anchor.quote.replacingOccurrences(of: "\u{2028}", with: " "))
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(theme.secondaryText.color)
                                            .lineLimit(2)
                                        HStack(spacing: 5) {
                                            Text(conversation.updatedAt, format: .relative(presentation: .named))
                                            Text("· \(conversation.messages.count) mensagens")
                                        }
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(theme.secondaryText.color)
                                        if conversation.id == chat.currentID {
                                            Text(chat.isResponding ? "Respondendo…" : "Conversa atual")
                                                .font(.system(size: 10.5, weight: .medium))
                                                .foregroundStyle(theme.accent.color)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                deleteButton(conversation.id)
                            }
                            .padding(12)
                            .background(theme.text.color.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }
            Text("Salvas neste Mac. Excluir uma conversa mantém as anotações já salvas.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.secondaryText.color)
                .padding(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func deleteButton(_ id: String) -> some View {
        Button(role: .destructive) { chat.deleteConversation(id) } label: {
            Image(systemName: "trash")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.red)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Excluir conversa. As anotações salvas permanecem.")
        .accessibilityLabel("Excluir conversa")
    }

    private func passage(_ anchor: TextAnchor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("TRECHO EM CONVERSA")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.7)
                Spacer()
                Button { document.focusChatPassage() } label: {
                    Image(systemName: "arrow.up.left")
                }
                .buttonStyle(.plain)
                .help("Localizar trecho no documento")
                .accessibilityLabel("Localizar trecho no documento")
            }
            .foregroundStyle(theme.accent.color)
            ScrollView {
                Text(anchor.quote.replacingOccurrences(of: "\u{2028}", with: "\n"))
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxHeight: 110)
            if let fragments = anchor.pdf, !fragments.isEmpty {
                let pages = Array(Set(fragments.map { $0.pageIndex + 1 })).sorted().map(String.init).joined(separator: ", ")
                Text("Página(s) \(pages)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.secondaryText.color)
            }
        }
        .padding(12)
        .background(theme.accent.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .leading) {
            Capsule().fill(theme.accent.color.opacity(0.65)).frame(width: 2).padding(.vertical, 12)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(theme.accent.color)
            Text("Uma conversa a partir da leitura")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(theme.heading.color)
            Text("Selecione um trecho no PDF ou Markdown e escolha “Conversar sobre trecho” no botão ✨ ou no menu do botão direito.")
                .font(.system(size: 12.5))
                .foregroundStyle(theme.secondaryText.color)
            Button("Conversar sobre seleção") { model.chatSelection() }
                .disabled(!document.hasSelection)
            Text("As respostas são geradas localmente pela Apple Intelligence.")
                .font(.system(size: 11))
                .foregroundStyle(theme.secondaryText.color)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if chat.messages.isEmpty {
                        Text("O que você gostaria de entender?")
                            .font(.system(size: 13, weight: .medium))
                        ForEach(["Explique de forma simples.", "Resuma a ideia principal.", "Quais são os pontos mais importantes?"], id: \.self) { suggestion in
                            Button(suggestion) { chat.draft = suggestion; send() }
                                .buttonStyle(.plain)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.accent.color)
                                .disabled(chat.unavailableReason != nil)
                        }
                    }
                    ForEach(chat.messages) { message in
                        messageCard(message)
                    }
                    if chat.contextWasTrimmed {
                        Text("Para continuar, a IA usa o trecho e as mensagens mais recentes. O histórico completo continua visível aqui.")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.secondaryText.color)
                    }
                    if let error = chat.error {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.secondaryText.color)
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(12)
            }
            .onChange(of: chat.messages) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            .onChange(of: chat.error) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
    }

    private func messageCard(_ message: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message.role == .user ? "Você" : "Apple Intelligence", systemImage: message.role == .user ? "person.crop.circle" : "sparkles")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.secondaryText.color)
            if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 12.5))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if message.status == .streaming {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini)
                    Text(message.content.isEmpty ? "Preparando resposta…" : "Respondendo…")
                        .font(.system(size: 11))
                }
                .foregroundStyle(theme.secondaryText.color)
            } else if message.status == .interrupted || message.status == .failed {
                Text(message.status == .interrupted ? "Resposta interrompida" : "Resposta não concluída")
                    .font(.system(size: 11).italic())
                    .foregroundStyle(theme.secondaryText.color)
            } else if message.role == .assistant {
                let saved = document.comments.contains { $0.id == message.id }
                Button {
                    do { try document.saveChatResponse(message.id) }
                    catch { chat.error = "Não foi possível salvar: \(error.localizedDescription)" }
                } label: {
                    Label(saved ? "Anotação salva" : "Salvar como anotação", systemImage: saved ? "checkmark" : "text.badge.plus")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent.color)
                .disabled(saved)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.text.color.opacity(message.role == .user ? 0.07 : 0.035), in: RoundedRectangle(cornerRadius: 12))
    }

    private var composer: some View {
        @Bindable var chat = chat
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Pergunte sobre o trecho…", text: $chat.draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .font(.system(size: 12.5))
                .focused($inputFocused)
                .padding(10)
                .background(theme.text.color.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                .onSubmit { send() }
            HStack {
                Text("A IA pode errar. Confira no trecho.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.secondaryText.color)
                Spacer(minLength: 0)
                if chat.isResponding {
                    Button("Parar", systemImage: "stop.fill") { chat.cancel() }
                } else {
                    Button("Enviar", systemImage: "arrow.up") { send() }
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(chat.unavailableReason != nil || chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Text(chat.persistenceError == nil
                 ? "O histórico é salvo automaticamente neste Mac. Você também pode salvar respostas como anotações."
                 : "O histórico não foi salvo. Mantenha o documento aberto para não perder esta conversa.")
                .font(.system(size: 10.5))
                .foregroundStyle(theme.secondaryText.color)
        }
        .padding(12)
        .background(theme.surface.color.opacity(0.45))
    }

    private func send() { chat.send(); inputFocused = true }
}
