# PDF e anotações por trecho

Escopo autorizado: abrir PDFs no Jullia e destacar/comentar trechos como no Markdown. Os arquivos originais permanecem intactos. Sem outros formatos e sem OCR nesta etapa.

## Design

- PDFKit apresenta as páginas; a sidebar e as ações existentes continuam compartilhadas.
- Um índice liga offsets UTF-16 globais às páginas. Âncoras PDF também guardam os intervalos selecionados e seu contexto por página, preservando seleções descontínuas e entre páginas.
- Uma coluna JSON opcional nas duas tabelas guarda os detalhes PDF. Migração aditiva mantém as anotações Markdown.
- Marcações PDF são objetos temporários em memória. Nenhum caminho do leitor salva o PDF.
- Recarregamento resolve os trechos novamente; trechos perdidos ficam órfãos. PDF protegido pede senha; PDF sem texto continua visível, com comentário geral disponível.

## Execução

1. Testar abertura, persistência sem alteração do PDF, seleção entre páginas/descontínua, recuperação e migração.
2. Implementar âncoras PDF, persistência e índice PDFKit; integrar DocumentModel.
3. Integrar PDFView, barra de seleção, cores, comentários, navegação e zoom; abrir por painel, árvore, links e Finder.
4. Executar testes, build do bundle, inspeção visual e revisão; documentar suporte e limites.

## Verificação prioritária

Unicode, páginas vazias, seleção parcial/perdida após edição, mudança de página, seleções descontínuas, marcações originais do PDF, senha, arquivos inválidos e regressão Markdown.

## Progresso

- Implementação concluída: índice e âncoras PDF, migração v2, leitor nativo, barra de seleção, comentários, zoom e integração com abertura/navegação.
- Testes iniciais falharam por ausência das APIs; os cenários de persistência, seleção e recuperação passaram após implementação.
- Revisão independente identificou união incorreta de intervalos separados na mesma linha e prioridade errada no menu contextual. Ambos tiveram regressões reproduzidas e corrigidas; desenho e hit-testing usam cada fragmento separadamente.
- Teste de pixels reproduziu ausência de marcações na renderização offscreen causada por `shouldPrint = false`; removido o override. As marcações seguem apenas em memória e o teste compara os bytes do arquivo original.
- Suíte completa passou: 20 testes de core, 9 testes de app/PDF executados e 1 captura de documentação opcional ignorada. Captura PDF e ações da barra verificadas adicionalmente com AppKit/PDFKit.
- Build release e assinatura ad-hoc verificados. Sem instalação em Applications, commit ou publicação.
- Limite de validação: não havia ferramenta de interação com apps nativos disponível para testar gestos físicos de mouse. Os testes exercitam seleção do PDFKit, callbacks da barra, menus e renderização nativa; capturas AppKit offscreen não incluem todas as camadas do compositor. PDFs com diagramação complexa continuam sujeitos à extração de texto do PDFKit.
