# Plano — PDF escuro sutil

Spec: `docs/superpowers/specs/2026-11-01-pdf-escuro-design.md`. Execução nesta sessão, por ordem. Cada tarefa começa pelo teste que falha.

Antes do commit: `swift test`, `./scripts/build-app.sh`, verificação ao vivo. Depois: `VERSION` 0.18.0, README, `docs/architecture.md`, commit e tag anotada local. Push só quando o usuário pedir.

## Atenção da revisão

1. Página girada: furo de foto e miniatura no lugar certo.
2. Documento recarregado do disco: overlays novos seguem o papel atual.
3. Ligar depois de abrir com o papel desligado: páginas já na tela escurecem.
4. Tema claro com a chave ligada: nada muda.
5. Tom salvo fora do intervalo: cai num tom válido.

## Tarefa 1 — cor (`JulliaCore`)

Arquivo novo `Sources/JulliaCore/PDFRecolor.swift`; `Theme.swift` ganha `pdfPapers`.

- `PDFPaper { name, paper: RGBA, ink: RGBA }`.
- `PDFRecolor.map(_: RGBA, on: PDFPaper) -> RGBA`, `PDFRecolor.cube(for: PDFPaper) -> Data`, `cubeDimension = 17`.
- `Theme.pdfPapers: [PDFPaper]`, `Theme.pdfPaper(_ tone: Int) -> PDFPaper?` com limite.
- Testes: branco → papel, preto → tinta, vermelho ≥ 4,5:1 em todo tom, matiz mantida, amarelo ≠ creme, cinzas monotônicos, tamanho e ordem da tabela, temas claros sem tons.

## Tarefa 2 — ajustes

`AppSettings`: `pdfDark` (padrão ligado), `pdfTone` (padrão 2), `pdfPaper`. Testes de persistência, tema claro, chave desligada, tom inválido.

## Tarefa 3 — exame da página

`Sources/Jullia/PDFPageSurvey.swift`: `PDFPageSurvey(page:)` com `recolors`, `pictures`, `size`. Testes com PDFs gerados: texto, página preta, página cheia de imagem, foto em página clara, screenshot, página girada.

## Tarefa 4 — overlay e leitor

`Sources/Jullia/Views/PDFPaperOverlay.swift`, `DocumentPDFView.swift`, `OutlineSidebar.swift`.

- `PDFPaper.filter`, `PDFPaperOverlay.show(_: CIFilter?)`.
- `AnnotatedPDFView.update(…, paper:)`: provider, registro de overlays, sombra, marcas com Snow.
- Botão na barra, miniaturas com `PDFPage.thumbnail(of:on:)`.
- Testes: filtro aplicado e limpo nos overlays vivos, página escura sem filtro, furo na máscara, marcas com Snow, miniatura branca vira papel e foto fica.

## Tarefa 5 — Ajustes

`Sources/Jullia/Views/PDFToneSettings.swift`: seção, prévia, cartões. Conferir renderizando a view real.

## Tarefa 6 — verificação ao vivo e versão

Sonda temporária com janela real no próprio processo, com o PDF do usuário: papel, seleção, destaque, impressão, zen. Remover a sonda e conferir com grep. Depois docs, versão, commit e tag.
