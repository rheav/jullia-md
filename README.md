# Marknord

Visualizador de Markdown nativo para macOS 27: Liquid Glass ajustável, quatro temas (Polar, Ink, Snow, Paper),
marca-texto em seis cores e comentários numa sidebar — salvos à parte, sem tocar no `.md`.

Desenho: `docs/superpowers/specs/2026-10-08-marknord-v1-design.md`.

## Rodando

```bash
swift test                 # suíte do MarknordCore (renderer, âncoras, store, árvore de arquivos, layout)
./scripts/build-app.sh     # build/Marknord.app (release, assinado ad-hoc)
open build/Marknord.app
```

Versão em `VERSION`. Anotações em `~/Library/Application Support/Marknord/annotations.sqlite`.

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
