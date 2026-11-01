# PDF escuro sutil — design

Data: 2026-11-01 · Versão de partida: 0.17.0

## Objetivo

Num tema escuro, a página do PDF deixa de ser branca: vira um escuro sutil, à escolha do leitor entre quatro tons, sem contraste exagerado e sem perder o que as cores do documento dizem. O arquivo nunca muda.

## Raiz

O tema só pinta o fundo em volta das páginas (`AnnotatedPDFView.update`). O PDFKit desenha cada página com os pixels originais.

## Decisões, medidas num `PDFView` real (M3 Pro, macOS 27)

- **Recolorir por cima, não dentro.** Um overlay por página (`PDFPageOverlayViewProvider`) com `backgroundFilters`. Uma subclasse de `PDFPage` foi descartada: o PDFKit pinta seleção e destaque em multiply depois de `draw(with:to:)`, o que some sobre papel escuro, e a impressão sairia escura. Filtro único em `documentView` foi descartado: não decide por página.
- **Tabela de cor de 17 pontos**, com `CIColorCubeWithColorSpace`. 33 pontos caem para 82 fps; 17 ficam em 117 fps em janela grande, com a mesma cor (±1 nível). Sem espaço de cor o papel sai errado.
- **Curva de cor em OKLCH.** Branco vira o papel, preto vira a tinta, a matiz fica, o croma é limitado. Tons médios sobem (`L' = 1 − L²` e um reforço por croma), senão o vermelho afunda.
- **Decisão por página.** Página escura (mediana < 200) ou cheia de imagem (≥ 55 % de meios-tons) fica como está. Sem isso, PDFs já escuros clareariam.
- **Foto mantém a cor; screenshot recolore.** As imagens vêm do conteúdo da página (`CGPDFScanner`, operador `Do`). Imagem clara e chapada (mediana ≥ 200, meios-tons < 45 %) recolore; o resto abre um furo na máscara do overlay.
- **Ligar e desligar troca `backgroundFilters` nos overlays vivos.** Tirar o `pageOverlayViewProvider` não remove os overlays.
- **Sem sombra de página** com o papel escuro: o filtro a transforma em halo.
- **Marcas do Jullia com as cores do Snow** enquanto o papel escuro está ligado: elas são pintadas no papel claro e passam pelo filtro. Em Polar, ficavam fracas e os sublinhados sumiam.
- **Troca de tom no PDF é instantânea.** `CATransition` não anima `backgroundFilters`. A prévia nos Ajustes anima.

## Interface

- Ajustes → Aparência → **PDF escuro**: chave, prévia animada (0,28 s, respeita "Reduzir movimento"), quatro cartões. Passar o mouse mostra na prévia; clicar aplica.
- Botão na barra do PDF, só em tema escuro: liga e desliga.
- A chave é global, ligada por padrão, com o tom **Painel**.
- A aba Aparência passa a ter altura fixa e rolar: com a nova seção, ela passaria da altura de um notebook.
- Tons por tema, com papel e tinta:
  - Polar: Contínuo `#2A2F3C`, Nord `#2E3440`, Painel `#323848` (tinta `#D8DEE9`), Suave `#3B4252` (tinta `#E5E9F0`).
  - Ink: Contínuo `#121214`, Grafite `#17171A`, Painel `#1B1B1E`, Suave `#26262B` (tinta `#E6E1D6`).
- Temas claros não têm tons e mantêm o PDF original.
- Miniaturas de **Páginas** seguem o papel.

## Fora do escopo

Lembrar a escolha por documento, tom nos temas claros, proteger gradiente e desenho vetorial (recolorem com a página) e fade do tom no próprio PDF.
