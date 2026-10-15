# Sidebar, abas e split — design

Data: 2026-10-15 · Versão de partida: 0.5.0

## Objetivo

Ler vários PDFs e Markdown ao mesmo tempo num monitor wide, sem a sidebar virar uma lista gigante.

1. **Sidebar**: navegar por pasta com árvore arrumada, não por uma árvore inteira de cada pasta raiz.
2. **Abas**: vários documentos abertos, com aba de prévia.
3. **Split**: até 4 documentos visíveis ao mesmo tempo, em colunas ou grade 2×2.

Entregas em três versões, cada uma validada, commitada e tagueada: **0.6.0** sidebar, **0.7.0** abas, **0.8.0** split.

## Decisões do usuário

| Tema | Decisão |
| --- | --- |
| Sidebar | Navegador de pasta. A pasta atual é a raiz de uma árvore; subpastas abrem no lugar e começam fechadas; só o caminho até o doc ativo fica aberto. Breadcrumb sobe; "Entrar na pasta" troca a raiz. Pastas raiz viram atalhos em **Locais**, com **Recentes**. Busca global com caminho. Ordenar por nome ou data. Nome quebra em 2 linhas. |
| Abas | Uma barra de abas única no topo. Cada painel mostra uma aba. Clicar numa aba visível foca o painel dela; uma aba não visível abre no painel focado. Abas visíveis ganham o número do painel. |
| Clique na sidebar | Aba de prévia (VS Code): nome em itálico, substituída pelo próximo clique. Vira fixa ao anotar, mudar de página/rolar, duplo-clique no arquivo ou na aba. Arquivo já aberto → vai para a aba dele. |
| Split | Seletor com 1, 2, 3 ou 4 colunas e grade 2×2. Divisórias arrastáveis. |

Suposições assumidas (o usuário pediu para seguir sem nova confirmação):

- Um único inspector (comentários/chat) à direita, que segue o **painel focado**.
- O mesmo arquivo não aparece em dois painéis. Selecionar a aba de um arquivo visível foca o painel onde ele está. Isso evita dois `DocumentModel` divergindo sobre as mesmas anotações.

## Estado atual (0.5.0)

- `AppModel.document` guarda um único `DocumentModel`; comandos, inspector, rail e testes leem essa propriedade.
- `FileSidebar` mostra "Recentes" e um `OutlineGroup` com a árvore inteira de cada raiz. Pastas grandes (Downloads) viram uma lista plana longa; nomes cortados no meio a 264 pt.
- O leitor é recriado por `.id(document.url)`; trocar de documento perde página e rolagem.
- `AnnotatedPDFView` filtra eventos pelos próprios limites, então várias instâncias convivem na janela.

## 1. Sidebar (0.6.0)

### Modelo

- `FileNode` ganha `modified: Date` (data de modificação), lido na varredura.
- `FileTree` ganha:
  - `scan(_:maxDepth:)` — profundidade configurável (pastas avulsas usam 4).
  - `sorted(_:by:)` — pastas primeiro; cada grupo por nome (localizado) ou por data (mais recente primeiro).
  - `node(at:in:)` — a subárvore de uma URL dentro de uma raiz.
  - `search(_:query:limit:)` — arquivos cujo nome contém a busca (sem caixa/acentos), em ordem de nome, com limite.
- `FileBrowser` (novo, `@Observable`, dono: `AppModel`) guarda a navegação:
  - `folder: URL?` — raiz da árvore mostrada; `mode`: `.folder` ou `.recents`.
  - `expanded: Set<URL>` — pastas abertas na árvore.
  - `sort: FileSort` (`.name`/`.date`), persistido em UserDefaults (`fileSort`).
  - `reveal(_ url:)` — chamado quando o doc focado muda. Se o arquivo está dentro da pasta mostrada, abre o caminho até ele; senão a pasta mostrada vira a pasta do arquivo. Navegação manual fica até o próximo doc focado.
  - `enter(_:)`, `up()`, `toggle(_:)`, `showRecents()`.
- `AppModel` resolve a árvore da pasta mostrada: subárvore da raiz que a contém (já varrida e observada) ou, para arquivos fora das raízes, uma varredura avulsa da pasta do arquivo (profundidade 4), também observada.
- O breadcrumb vai da raiz que contém a pasta até a pasta atual. Nunca sobe acima de uma raiz (evita varrer a home). Uma pasta avulsa mostra só ela, com a ação "Adicionar aos Locais".

### Interface (`FileSidebar`)

```
🔍 Buscar em todas as pastas
‹ Downloads › Cursos            ⇅
▸ 📁 Chris Haddad P.I.G. Method
▾ 📁 Organic-Scale-Limpo
     📄 03-realistic-skin-texture-
        guide.pdf                   ← selecionado
── Locais ──
⌂ Downloads   ⌂ Cursos   ⏱ Recentes
+ Abrir pasta…                 ⚙ ↻
```

- Linhas achatadas da árvore (pasta + profundidade) num `List` com seleção: clicar numa pasta abre/fecha; duplo-clique ou menu "Entrar na pasta" muda a raiz. Clicar num arquivo abre (prévia na 0.7.0); duplo-clique abre fixo.
- Nome em até 2 linhas, cortando no meio. Contador de anotações como hoje. Arquivos abertos em outras abas ganham um ponto (0.7.0).
- Busca não vazia troca a árvore por resultados planos: nome + caminho relativo à raiz ("Downloads › Organic-Scale-Limpo").
- **Locais**: cada raiz (clique mostra a raiz; menu: Mostrar no Finder, Atualizar, Remover) e **Recentes** (lista os recentes com a pasta embaixo).
- Menu de arquivo: Abrir, Abrir em nova aba (0.7.0), Abrir ao lado (0.8.0), Mostrar no Finder.
- A rail recolhida continua igual.

## 2. Abas (0.7.0)

### Modelo

- `Tab` (`@Observable`): `id`, `url`, `isPreview`, `document: DocumentModel?`. O documento é criado quando a aba fica visível; abas restauradas ficam leves até serem mostradas.
- `AppModel`:
  - `tabs: [Tab]`, `panes: [Pane]` (`Pane` guarda o `tabID` mostrado), `focusedPane: Int`.
  - `document` passa a ser **calculado**: o documento da aba do painel focado. Comandos, inspector e testes continuam funcionando.
  - `openFile(_:as:)` com `OpenKind`: `.preview` (sidebar, links, rail), `.permanent` (duplo-clique, painel Abrir, Finder, arrastar), `.newTab`, `.beside` (0.8.0).
    - Arquivo já em uma aba: se visível, foca o painel; se não, mostra no painel focado. `.permanent` fixa a aba.
    - Prévia nova substitui a aba de prévia existente, a menos que ela esteja visível em outro painel (aí essa vira fixa). No máximo uma aba de prévia.
    - Aba nova entra logo depois da aba do painel focado.
  - `selectTab`, `closeTab`, `closeOtherTabs`, `closeTabsToRight`, `pinTab`, `selectNextTab`/`Previous`, `selectTab(at:)`.
  - Fechar uma aba cancela o chat dela. O painel que a mostrava passa para a vizinha da direita (ou esquerda) que não esteja visível; sem nenhuma, o painel fica vazio.
- Fixação automática: `DocumentModel.onPinRequest` é chamado ao criar destaque/comentário e quando o leitor sai da posição restaurada (outra página no PDF, rolagem de mais de 120 pt no Markdown).
- Posição por aba: `DocumentModel.viewState` (PDF: página, ponto e escala; Markdown: origem da rolagem). O leitor salva ao ser desmontado e restaura ao ser montado.
- Sessão: `session` em UserDefaults (JSON com caminhos das abas, prévia, abas dos painéis, painel focado, layout e frações). Migra `lastFile` quando não há sessão. Só restaura com "Reabrir sessão anterior" ligado. Salva a cada mudança de abas/painéis e ao encerrar.

### Interface

- A faixa superior (onde hoje está o caminho "pasta › arquivo") vira a **barra de abas**: rolagem horizontal, aba com ícone, nome (corte no meio, 90–220 pt), ✕ ao passar o ponteiro ou na aba ativa, itálico na prévia, tooltip com o caminho completo. O espaço livre continua arrastando a janela. Botão **+** abre o painel Abrir.
- Menu da aba: Fixar aba, Abrir ao lado (0.8.0), Fechar, Fechar outras, Fechar à direita, Mostrar no Finder.
- Atalhos: ⌘W fecha a aba (sem abas, fecha a janela); ⇧⌘] / ⇧⌘[ próxima/anterior; ⌘1…⌘9 aba N.

## 3. Split (0.8.0)

### Modelo

- `PaneLayout`: `.one`, `.two`, `.three`, `.four` (colunas) e `.grid` (2×2); `slotCount` 1…4.
- `setLayout(_:)`: mais espaços → os painéis novos recebem as próximas abas não visíveis (ou ficam vazios); menos → saem os painéis do fim (as abas continuam na barra). Painel focado é ajustado.
- `openFile(_, as: .beside)`: abre num painel novo à direita (sobe de layout até 4 colunas); com 4 painéis, usa o painel seguinte ao focado.
- Fechar um painel (✕ no cabeçalho): remove o painel e reduz o layout; as abas ficam.
- Frações das divisórias por layout, guardadas na sessão; cada painel tem largura/altura mínima de 160 pt.

### Interface

- Seletor de layout no fim da barra de abas: cinco botões com desenho de colunas/grade. Menu Visualizar → Layout com ⌥⌘1…⌥⌘5.
- Com mais de um painel, cada painel tem um cabeçalho fino: número do painel, ícone, nome, ✕. O painel focado tem nome em destaque e um filete na cor de destaque; os outros ficam mais apagados.
- Clicar em qualquer ponto de um painel o foca: um monitor de eventos local por painel (mouse down dentro dos limites) chama `focusPane`, sem consumir o evento.
- Painel vazio: lista de abas não visíveis para escolher + "Abrir arquivo…".
- As abas visíveis mostram o número do painel na barra.
- O inspector e os comandos (destacar, comentar, zoom, recarregar) agem no painel focado.

## Erros e casos de borda

- Arquivo removido: a aba continua e o leitor mostra o erro de "Arquivo indisponível" que já existe; a sessão ignora caminhos inexistentes ao restaurar.
- Pasta mostrada removida do disco: o navegador volta para a primeira raiz (ou fica vazio).
- PDF protegido em aba: pede senha quando ficar visível, como hoje.
- Chat gerando numa aba que fica oculta: continua; só é cancelado ao fechar a aba ou encerrar o app.

## Testes

- `FileTree`: ordenação por nome/data, `node(at:)`, busca com limite e acentos.
- `FileBrowser`: `reveal` dentro/fora da pasta mostrada, `up` parando na raiz, `enter`, persistência da ordenação.
- Abas: prévia substitui prévia; anotação fixa a prévia; abrir arquivo já aberto não duplica; fechar aba escolhe vizinha; sessão salva e restaura abas, prévia e painel focado; migração de `lastFile`.
- Split: `setLayout` preenche e remove painéis; `.beside`; focar painel muda `document`; selecionar aba visível foca o painel dela; fechar painel reduz o layout.
- Testes existentes (`AppModelTests`, `PDFTests`, `ChatTests`, screenshots) continuam passando com `document` calculado.
- Verificação ao vivo de cada versão no app instalado.

## Fora do escopo

Arrastar abas para reordenar ou entre painéis, largura da sidebar ajustável, a mesma aba em dois painéis, várias janelas, busca no conteúdo dos arquivos.
