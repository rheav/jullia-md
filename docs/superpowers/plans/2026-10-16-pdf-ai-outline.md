# Plano — índice gerado para PDFs sem índice

Hoje a aba **Sumário** mostra o índice gravado no PDF (`outlineRoot`). Muitos PDFs não têm um: artigos, apostilas, livros exportados sem marcadores, digitalizações. Este plano gera um índice para eles, página por página, só com frameworks do macOS e sem tráfego de rede.

Cada fase termina com `swift test`, `./scripts/build-app.sh`, verificação ao vivo, bump de `VERSION`/README, commit e tag anotada local. Push só quando o usuário pedir.

## Princípios

- **O modelo não lê páginas nem escreve títulos.** Uma etapa sem IA escolhe as linhas candidatas; o modelo só as classifica, referindo-se a elas por número. Um título que não está no PDF não pode aparecer no índice.
- **Contexto curto.** Cada chamada leva uma página: seus candidatos e os últimos títulos aceitos, para manter a hierarquia. Páginas sem candidatos não chamam o modelo.
- **Nada é gravado no PDF.** O índice gerado fica no SQLite, como as anotações, marcado como gerado por IA.
- **Funciona sem Apple Intelligence**, com a heurística sozinha, identificada como tal.

## O que o macOS oferece

| Peça | Uso |
| --- | --- |
| PDFKit | Texto por página; linhas com posição (`PDFSelection.selectionsByLine`, `bounds(for:)`); fontes e tamanhos por trecho (`PDFPage.attributedString`). `PDFTextIndex` já reúne o texto em UTF-16. |
| Vision | OCR com caixa por linha (`RecognizeTextRequest`, pt-BR) para páginas sem texto. No macOS 26+, `RecognizeDocumentsRequest` devolve a estrutura do documento; falta verificar se identifica títulos. |
| Foundation Models | O modelo local já usado em `ApplePassageChat`. Geração guiada (`@Generable`) devolve uma estrutura tipada; a contagem de tokens já é usada para respeitar o contexto. |

## Fase 0 — Medir antes de construir (sem versão)

1. Um teste opt-in (como `ScreenshotTests`, ativado por variável de ambiente) que roda a heurística da Fase 1 sobre uma pasta de PDFs e grava, por arquivo, os candidatos e o índice resultante em texto.
2. Rodar com 3 ou 4 PDFs reais do usuário: um livro, um artigo, slides e uma digitalização. Os PDFs não entram no repositório.
3. Medir: quantas páginas têm candidatos, quantos títulos verdadeiros a heurística acerta e quantos falsos inclui, e o tempo por página.
4. Verificar o que `PDFPage.attributedString` preserva das fontes nesses arquivos e o que `RecognizeDocumentsRequest` devolve para uma página com títulos.

Decisão ao fim: se a heurística já basta para a maioria dos casos, a Fase 2 vira refinamento opcional.

## Fase 1 — Heurística, painel e persistência (0.15.0)

1. `Jullia/OutlineCandidates.swift` (novo): para cada página, as linhas com texto, bounds, tamanho de fonte dominante, negrito e numeração (`1`, `2.3`, `IV`, `Capítulo`, `Parte`). Tamanho do corpo = moda dos tamanhos no documento.
2. Filtros: linhas que se repetem em muitas páginas na mesma posição (cabeçalho e rodapé); números de página; linhas longas (mais de ~12 palavras) ou terminadas em ponto. Candidata = fonte ≥ 1,15× o corpo, ou negrito curto, ou numeração no início, com espaço acima.
3. Níveis pela heurística: tamanhos de fonte agrupados em faixas (maior = nível 1), ajustados pela profundidade da numeração (`2` → 1, `2.3` → 2). Sem saltos de nível maiores que 1.
4. `JulliaCore/AnnotationStore`: migração v5 com a tabela `generated_outlines` (`doc_path`, impressão digital do arquivo = tamanho + data de modificação, `items` em JSON, `source` = heurística/IA, `created_at`). A migração é aditiva e transacional, como as anteriores.
5. `DocumentModel`: `outline` passa a vir do PDF, ou, sem índice no arquivo, do índice gerado salvo para aquela impressão digital. `OutlineItem` ganha `isGenerated`.
6. `OutlineSidebar`, para um PDF sem índice: botão **Gerar índice**, progresso ("página 37 de 210"), **Cancelar**, itens aparecendo enquanto as páginas são processadas. Índice gerado identificado ("gerado automaticamente") com **Gerar de novo** e **Apagar**. Arquivo mudou (impressão digital diferente): aviso e **Gerar de novo**.
7. A geração roda numa `Task` do documento, cancelada ao fechar a aba ou encerrar o app, como o chat.
8. Testes: PDFs gerados por Core Graphics com tamanhos de fonte, negrito, numeração, cabeçalho e rodapé repetidos (o mesmo recurso de `OutlineTests.pdfWithOutline`); persistência, invalidação por impressão digital e cancelamento.

## Fase 2 — Classificação pelo modelo local (0.16.0)

1. Protocolo `OutlineClassifying` (como `PassageChatGenerating`): recebe a página, seus candidatos numerados e os últimos títulos aceitos; devolve, por número, se é título, o nível (1 a 3) e se continua na próxima linha (título quebrado em duas linhas).
2. `AppleOutlineClassifier` (novo): `LanguageModelSession` com instruções fixas e saída `@Generable`. Uma sessão nova por página; contagem de tokens antes de enviar e corte dos candidatos excedentes, nunca do texto de um candidato.
3. Entrada por candidato: número, texto, tamanho relativo ao corpo, negrito, numeração e posição na página. Os títulos anteriores entram só como texto e nível.
4. Validação da resposta: números inexistentes são ignorados, níveis fora de 1–3 são limitados, junções só entre linhas vizinhas. Erro ou modelo indisponível naquela página: mantém o resultado da heurística para ela.
5. Disponibilidade: sem Apple Intelligence, o botão gera só pela heurística e o painel diz isso.
6. Testes com um classificador falso: respostas inválidas, falhas no meio do documento, cancelamento, ordem e hierarquia finais.

## Fase 3 — Páginas digitalizadas (0.17.0)

1. Página sem texto extraível: renderizar em ~2× e passar ao Vision; a altura das caixas das linhas faz o papel do tamanho da fonte. Depois, os mesmos filtros e a mesma classificação.
2. Resultado do OCR em cache por página no SQLite, com a impressão digital, para não repetir o trabalho.
3. À parte, fora desta fase: o mesmo OCR poderia tornar digitalizações pesquisáveis e selecionáveis. Hoje o README declara o OCR fora do escopo.
4. Testes com uma página renderizada como imagem dentro de um PDF.

## Fase 4 — Sumário impresso (0.18.0)

Sumários impressos feitos de links já viram índice desde a 0.15.0 (`PDFLinkedContents`): os links dão a página, sem conversão. Esta fase cuida dos sumários sem links.

1. Detectar páginas de sumário no início do documento: muitas linhas terminando em número, com pontilhado ou espaço antes dele.
2. Extrair título, nível (pelo recuo) e página impressa.
3. Converter a página impressa na página do PDF: pelos rótulos (`PDFPage.label`) quando existem; senão, pelo deslocamento obtido ao encontrar dois ou três títulos nas páginas indicadas.
4. Quando o sumário impresso é encontrado e confere, ele tem prioridade sobre as Fases 1 e 2.

## Estimativas e riscos

| Fase | Trabalho estimado |
| --- | --- |
| 0 | meio dia |
| 1 | ~2 dias |
| 2 | 1–2 dias |
| 3 | 1–2 dias |
| 4 | ~1 dia |

Tempo de geração, a medir na Fase 0: cerca de 0,5–2 s por chamada ao modelo; um livro de 300 páginas com ~60 páginas com candidatos levaria de 1 a 2 minutos com a Fase 2.

- O modelo local é pequeno: pode errar níveis ou aceitar legendas, citações e cabeçalhos de tabela. Os candidatos e a resposta por número limitam o erro ao que já estava na página.
- Layouts em duas colunas, slides e pôsteres confundem o "tamanho do corpo". Slides: o título é a maior linha da página.
- Apple Intelligence precisa estar ligada, num Mac compatível e com o idioma suportado; o chat já trata a indisponibilidade.
- Fontes embutidas sem nomes úteis ou com tamanhos transformados podem tirar a informação de negrito e tamanho do PDFKit. A Fase 0 mede isso.
