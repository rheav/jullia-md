# Marknord v1 — desenho

Data: 2026-10-08. Estado: aprovado em conversa (mockups em `.superpowers/brainstorm/`), implementação direta a pedido.

## Objetivo

Visualizador de Markdown nativo para macOS 27, com Liquid Glass configurável, marca-texto colorido salvo e
sidebar de comentários no estilo do Copy Hub. A v1 só lê: não edita o `.md`.

## Decisões

| Tema | Decisão |
| --- | --- |
| Plataforma | macOS 27, Swift 6, SwiftUI + AppKit. Fora da App Store, sem sandbox |
| Projeto | Swift Package: `MarknordCore` (lógica, testável) + `Marknord` (app). `scripts/build-app.sh` monta o `.app` |
| Parser | `swift-markdown` (Apple, cmark-gfm): tabelas, tarefas, tachado |
| Renderização | `NSTextView` TextKit 1, só leitura. `NSTextTable`/`NSTextBlock` para código, citação e tabela |
| Persistência | SQLite do sistema em `~/Library/Application Support/Marknord/annotations.sqlite`. O `.md` nunca é tocado |
| Navegação | Pastas abertas numa sidebar com árvore de `.md` + Recentes + busca. Arquivo solto também abre |
| Temas | Polar (escuro, Nord índigo), Ink (escuro, quente, serifado), Snow (claro, Nord), Paper (claro, sépia, serifado) |
| Vidro | Três vidros independentes: janela, sidebar de arquivos, sidebar de comentários. Cada um liga/desliga + 0–55% de transparência. 0% = sólido. “Reduzir transparência” do sistema força sólido |
| Ajustes | Janela `Settings` (⌘,): abas Geral e Aparência. Tema e vidro só lá (e menu Visualizar › Tema, ⌃⌘1…4) |

## Âncoras

Destaques e comentários são ancorados no **texto renderizado** (o `string` do `NSAttributedString`, igual em
todos os temas): `start`, `end`, `quote` e 32 caracteres de `prefix`/`suffix`.

Ao abrir ou recarregar:

1. Se `text[start..<end] == quote`, fica onde está.
2. Senão, procura todas as ocorrências de `quote` e escolhe a de maior casamento de prefixo+sufixo, desempatando
   pela distância ao `start` antigo. Achou → grava os offsets novos.
3. Nenhuma ocorrência → **órfão**. Nada é apagado; aparece na seção Órfãos do inspector.

## Modelo

```sql
CREATE TABLE highlights (
  id TEXT PRIMARY KEY, doc_path TEXT NOT NULL,
  start INTEGER NOT NULL, "end" INTEGER NOT NULL, quote TEXT NOT NULL, prefix TEXT NOT NULL, suffix TEXT NOT NULL,
  color TEXT NOT NULL, created_at REAL NOT NULL
);
CREATE TABLE comments (
  id TEXT PRIMARY KEY, doc_path TEXT NOT NULL, parent_id TEXT REFERENCES comments(id) ON DELETE CASCADE,
  start INTEGER, "end" INTEGER, quote TEXT, prefix TEXT, suffix TEXT,   -- nulos = sobre o documento todo / resposta
  body TEXT NOT NULL, color TEXT, resolved_at REAL, created_at REAL NOT NULL, updated_at REAL NOT NULL
);
```

Cores (as seis do Copy Hub): `yellow`, `green`, `blue`, `pink`, `purple`, `orange`. Cada tema define seu tom.

## Interface

- **Janela**: sidebar de arquivos (vidro, flutuante) · documento · inspector de comentários (vidro, recolhível,
  botão 💬 na toolbar). Toolbar só com caminho e botões de sidebar/comentários.
- **Selecionar texto** → pílula de vidro flutuante: 6 cores, comentar, copiar. Igual no menu de contexto.
  Atalhos: ⌘⇧H destaca com a última cor, ⌘⌥M comenta.
- **Clicar num destaque** → pílula com trocar cor / remover.
- **Trecho comentado** = sublinhado grosso na cor do comentário (amarelo por padrão). Clique acende o card; clique
  no card rola até o trecho.
- **Inspector**: Abertos/Resolvidos, card com citação, corpo, respostas, editar, resolver, apagar, cor;
  “Comentar o documento todo”; seção Órfãos (comentários e destaques).
- **Ajustes › Geral**: reabrir últimas pastas, recarregar quando o arquivo muda, tamanho da fonte (⌘+/⌘−),
  largura da coluna de leitura.
- Sidebar mostra contagem de anotações por arquivo.

## Arquivos e recarga

- Pastas: varredura recursiva de `.md`/`.markdown`, ignorando ocultos, `node_modules`, `.build`. FSEvents
  revarre ao mudar.
- Arquivo aberto: observado; mudou no disco → re-renderiza e re-ancora (se “recarregar” ligado).

## Fora da v1

Edição, exportar anotações, busca dentro do documento além do ⌘F nativo, sincronização, imagens remotas.

## Testes

Unidade em `MarknordCore`: âncoras (re-ancoragem, órfão, empate), store (CRUD, cascata de respostas, contagens),
renderer (texto renderizado estável, blocos), varredura de pasta. App conferido ao vivo antes da tag.
