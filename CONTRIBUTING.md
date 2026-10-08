# Contribuindo

Use macOS 27+ e Xcode 27 com Swift 6.4. Clone o repositório e execute:

```bash
swift test
./scripts/build-app.sh
```

## Onde trabalhar

- Renderização, âncoras, temas, banco e árvore de arquivos: `Sources/JulliaCore`.
- Estado da janela, preferências, observação de arquivos e interface: `Sources/Jullia`.
- Exemplos e imagens do README: `examples` e `docs/screenshots`.

Consulte [Arquitetura](docs/architecture.md) antes de alterar o fluxo de documentos ou a persistência. Preserve os identificadores e os caminhos da migração legada.

## Validar uma mudança

Execute `swift test` e `./scripts/build-app.sh`. Para uma mudança visual, abra o bundle, confira os temas claros e escuros, painéis recolhidos e expandidos e as opções de transparência. Os snapshots de documentação não substituem essa revisão interativa.

Adicione testes quando a mudança afetar comportamento: texto renderizado, âncoras UTF-16, persistência, resolução de comentários ou recarregamento. Use diretórios temporários, domínios próprios de UserDefaults e bancos em memória ou temporários. Nunca use o banco pessoal de anotações nos testes.

Se a interface mudou, atualize as [imagens da documentação](docs/screenshots/README.md):

```bash
./scripts/screenshots.sh
```

Revise os PNGs antes do commit. Não versione `.build`, `build`, preferências locais ou bancos de anotações. Mantenha `Package.resolved` atualizado se alterar uma dependência.

## Pull requests

Descreva o problema, o comportamento resultante e como você validou a mudança. Inclua imagens em alterações visuais e mantenha cada PR focado. Para relatar um problema, informe as versões do macOS e do app e forneça um Markdown mínimo que reproduza o comportamento, sem conteúdo pessoal.
