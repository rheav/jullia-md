# Jullia.md

Visualizador de Markdown nativo para macOS 27: Liquid Glass ajustável, quatro temas (Polar, Ink, Snow, Paper),
marca-texto em seis cores e comentários numa sidebar — salvos à parte, sem tocar no `.md`.

Desenho: `docs/superpowers/specs/2026-10-08-marknord-v1-design.md`.

## Rodando

```bash
swift test                 # suíte do MarknordCore (renderer, âncoras, store, árvore de arquivos, layout)
./scripts/build-app.sh     # build/Jullia.md.app (release, com ícone, assinado ad-hoc)
open build/Jullia.md.app
```

Versão em `VERSION`. Anotações em `~/Library/Application Support/Jullia/annotations.sqlite`.

O ícone é `assets/icon/AppIcon.icon` (formato do Icon Composer, em camadas de Liquid Glass); o `build-app.sh` o
compila com `actool`. O J é o contorno do Georgia Bold, guardado como path no SVG. Até a v0.2.0 o app se chamava
Marknord (`dev.rheav.marknord`); a primeira abertura como Jullia.md copia preferências e anotações de lá.

## Atalhos

| | |
|---|---|
| ⌘O / ⇧⌘O | Abrir arquivo / pasta |
| ⌘R | Recarregar |
| ⇧⌘H | Destacar com a última cor |
| ⌥⌘M | Comentar o trecho selecionado |
| ⌃⌘S / ⌥⌘0 | Sidebar de arquivos / de comentários |
| ⌃⌘1…4 | Polar, Ink, Snow, Paper |
| ⌘+ / ⌘− / ⌘0 | Tamanho do texto |
| ⌘, | Ajustes (tema, transparência de cada vidro) |
