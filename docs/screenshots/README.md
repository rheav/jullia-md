# Imagens da documentação

Estes PNGs são snapshots das views reais de Jullia.md, renderizados por AppKit. Não são mockups nem capturas de documentos pessoais. A geração usa `MainView`, `DocumentTextView` e os mesmos componentes de sidebar do app.

```bash
./scripts/screenshots.sh
```

O comando executa somente `ScreenshotTests`, um teste opcional ativado pela variável `JULLIA_SCREENSHOTS`. A suíte normal (`swift test`) pula a captura. É necessário um Mac com os mesmos requisitos de build do app e uma sessão gráfica disponível.

| Arquivo | Conteúdo |
| --- | --- |
| `polar.png` | Tema Polar com arquivos, destaques e comentários |
| `ink.png` | Tema Ink com tipografia serifada |
| `snow.png` | Tema Snow |
| `paper.png` | Tema Paper com tipografia serifada |
| `focus.png` | Tema Polar com os painéis recolhidos |

A janela de renderização tem 1320 × 880 pontos. A resolução em pixels depende da escala do Mac. As capturas não incluem os controles de janela do sistema. Usam superfícies opacas para evitar variação conforme o desktop; não demonstram o desfoque atrás da janela. A seleção da lista de arquivos é desmarcada na captura para evitar artefatos de composição fora da tela.

Os documentos vêm de `examples`. Destaques e comentários são criados em um banco em memória, e as preferências usam um domínio temporário de UserDefaults removido ao terminar. Nenhum dado da instalação pessoal é necessário. Horários relativos dos comentários e métricas de fontes podem variar entre execuções.

O teste verifica a geração e as dimensões dos arquivos; não faz comparação pixel a pixel com uma imagem de referência. Sempre inspecione os cinco PNGs antes de publicá-los.
