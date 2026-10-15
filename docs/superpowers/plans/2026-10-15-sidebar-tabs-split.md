# Plano — sidebar, abas e split

Spec: [2026-10-15-sidebar-tabs-split-design](../specs/2026-10-15-sidebar-tabs-split-design.md)

Cada fase termina com `swift test`, `./scripts/build-app.sh`, verificação ao vivo, bump de `VERSION`/README, commit e tag anotada local. Push só quando o usuário pedir.

## Fase 1 — Sidebar (0.6.0)

1. `JulliaCore/FileTree.swift`: `modified` em `FileNode`; `scan(_:maxDepth:)`; `sorted(_:by:)` com `FileSort`; `node(at:in:)`; `search(_:query:limit:)`. Testes em `RendererAndTreeTests`.
2. `Jullia/FileBrowser.swift` (novo): pasta mostrada, modo (pasta/recentes), pastas abertas, ordenação persistida, `reveal`, `enter`, `up`, `toggle`, linhas achatadas visíveis, breadcrumb.
3. `AppModel`: possui o `FileBrowser`; resolve a árvore mostrada (subárvore de raiz ou pasta avulsa com watcher); chama `reveal` ao abrir/focar documento; `addFolder` para "Adicionar aos Locais".
4. `Views/FileSidebar.swift`: busca global, breadcrumb + ordenação, árvore achatada, resultados de busca, Recentes, seção Locais, rodapé.
5. Testes de `FileBrowser`/`AppModel`; screenshot ao vivo; release 0.6.0.

## Fase 2 — Abas (0.7.0)

1. `Jullia/Workspace.swift` (novo): `Tab`, `Pane`, `PaneLayout`, `OpenKind`, `Session` (Codable).
2. `AppModel`: `tabs`, `panes`, `focusedPane`; `document` calculado; `openFile(_:as:)`, seleção/fechamento/fixação de abas; sessão (salvar, restaurar, migrar `lastFile`); `cancelAllChats()`.
3. `DocumentModel`: `viewState`, `onPinRequest` (anotações e navegação).
4. `DocumentPDFView` / `DocumentTextView`: restaurar e salvar posição; avisar navegação do usuário.
5. `Views/TabBar.swift` (novo) na faixa superior de `DocumentColumn`; menus e atalhos em `JulliaCommands`; `AppDelegate` cancela todos os chats e salva a sessão.
6. Sidebar: duplo-clique fixa, "Abrir em nova aba", ponto em arquivos abertos.
7. Testes de abas e sessão; verificação ao vivo; release 0.7.0.

## Fase 3 — Split (0.8.0)

1. `AppModel`: `layout`, `setLayout`, `.beside`, `closePane`, `focusPane`, frações.
2. `Views/PaneGrid.swift` (novo): colunas/grade com divisórias arrastáveis, cabeçalho de painel, painel vazio, monitor de foco.
3. Seletor de layout na barra de abas; números de painel nas abas; menu Layout ⌥⌘1…⌥⌘5; "Abrir ao lado" na sidebar e na aba.
4. Testes de layout/foco; verificação ao vivo com 4 PDFs; README e `docs/architecture.md`; release 0.8.0.
