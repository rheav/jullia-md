# Arquitetura

Jullia.md é um pacote Swift com um executável (`Jullia`) e um módulo de suporte (`JulliaCore`). A persistência usa SQLite do macOS; a única dependência direta externa é `swift-markdown`.

## Do arquivo à tela

1. `JulliaApp` executa a migração legada e injeta `AppModel` e `AppSettings` na janela.
2. `AppModel` mantém as pastas, os arquivos recentes, o documento aberto e os contadores da sidebar. `FileTree` monta e filtra a árvore.
3. `DocumentModel` lê o arquivo e chama `MarkdownRenderer` com tema, tamanho de fonte e diretório-base para links e imagens.
4. O parser produz a árvore Markdown; o renderer a converte em `NSAttributedString`. `TextBlocks` desenha blocos de código, citações e separadores.
5. `DocumentTextView` integra um `NSTextView` de TextKit 1 ao SwiftUI. O texto é selecionável e não editável. Destaques e sublinhados usam atributos temporários do layout, separados do texto renderizado.

O texto produzido pelo renderer deve ser o mesmo em todos os temas e tamanhos de fonte. As âncoras dependem dessa propriedade; há testes para protegê-la.

## PDF

`DocumentModel` distingue PDF de Markdown antes de ler o conteúdo. PDFs usam `PDFDocument` e `PDFTextIndex`; `PDFReader` integra `AnnotatedPDFView` à coluna de leitura. Não há conversão de PDF em Markdown.

`PDFTextIndex` reúne o texto das páginas em coordenadas UTF-16 e traduz as seleções do PDFKit para âncoras. Cada `PDFAnchorFragment` guarda índice da página e uma âncora local com texto, offsets e contexto. Isso preserva seleções entre páginas e seleções descontínuas. Ao recarregar, todas as partes precisam ser reencontradas; uma seleção parcialmente perdida torna-se órfã.

A seleção nativa alimenta as mesmas ações e a mesma sidebar usadas no Markdown. Destaques e sublinhados são `PDFAnnotation` temporários, removidos quando a view é desmontada. Somente objetos criados pelo Jullia são removidos; o app nunca escreve o `PDFDocument` no disco. O tema não recolore as páginas originais.

O esquema SQLite v2 acrescenta a coluna opcional `pdf_anchor` às tabelas de destaques e comentários. A migração é aditiva e transacional, e preserva registros Markdown; os metadados PDF são JSON. A senha de PDFs protegidos é usada apenas para desbloquear o documento em memória. OCR e exportação de anotações não fazem parte desta implementação.

## Anotações e persistência

`AnnotationStore` guarda destaques e comentários em tabelas separadas, com índices por caminho de documento. Respostas referenciam o comentário pai; sua exclusão usa uma foreign key com `ON DELETE CASCADE`. Contadores incluem destaques e comentários principais abertos, excluindo respostas e conversas resolvidas.

Uma `TextAnchor` contém offsets UTF-16, a citação e contexto anterior e posterior. `Anchoring.resolve` tenta a posição original e, depois, procura a citação usando o contexto para escolher entre ocorrências. Quando encontra o trecho em outra posição, `DocumentModel` atualiza os offsets. Se não o encontra, mantém a anotação como órfã.

O banco não escreve nos documentos. A chave de um documento é seu caminho padronizado com symlinks resolvidos, não um identificador que acompanhe mudanças de nome.

## Estado e observação

`InspectorSidebar` alterna entre comentários e **Chat com IA**. `DocumentModel` possui um `PassageChat` com uma cópia da `TextAnchor` selecionada, independente das seleções seguintes. Os dois leitores acionam `startChat` pela barra flutuante e pelos menus. `AppModel` revela a aba e cancela a geração ao trocar de documento.

`ApplePassageChat` é a integração exclusiva com `SystemLanguageModel` de Foundation Models. A cada pergunta, reconstrói uma `LanguageModelSession` com instruções, o trecho e pares completos de perguntas/respostas. Usa a contagem de tokens e o limite do modelo para remover turnos antigos inteiros, reservando espaço para a resposta. Nunca corta o trecho silenciosamente. Uma geração cancelada ou malsucedida não entra no contexto seguinte; identificadores por requisição rejeitam atualizações atrasadas. O limite da integração é o protocolo `PassageChatGenerating`, usado pelos testes para exercitar falhas e concorrência sem depender do modelo instalado.

O histórico é persistido por documento na tabela `chat_conversations`, acrescentada pela migração SQLite v4. Cada registro contém a âncora, mensagens com IDs estáveis, estado do contexto e data da última atividade. A primeira pergunta cria o registro; o app salva no início e fim de cada geração, em checkpoints durante o streaming e ao cancelar, trocar de conversa ou encerrar. Respostas que estavam em streaming na reabertura são tratadas como interrompidas. Excluir a conversa ativa cancela a geração e invalida seus callbacks antes de limpar o estado, sem recriar o registro apagado. O histórico permite reabrir e continuar uma conversa com os pares completos de perguntas e respostas.

Conversas e anotações têm persistências independentes: somente respostas completas salvas explicitamente viram comentários; excluir uma conversa preserva essas anotações. A migração SQLite v3 acrescenta `ai_generated`, com padrão falso para comentários existentes. O identificador da mensagem evita duplicação no salvamento, inclusive após reabrir o histórico; a âncora capturada é resolvida contra o documento atual, ou preservada como órfã se o trecho desapareceu. A origem da IA permanece após edições. Não há tráfego de texto para serviços externos, ferramentas de acesso ao documento ou fallback para nuvem.

Os modelos da interface usam `@Observable` e executam no `MainActor`. `AppSettings` persiste preferências em UserDefaults e observa mudanças do modo claro/escuro do sistema. Os construtores aceitam defaults e localização do banco para que testes usem sessões isoladas; a execução normal usa os valores compartilhados do app.

`FileWatcher` usa um dispatch source para observar o documento e reabre a observação quando um editor substitui o arquivo em um salvamento atômico. `FolderWatcher` usa FSEvents para atualizar a árvore. Mudanças de tema ou fonte renderizam novamente o documento; mudanças do texto também resolvem suas âncoras.

## Organização visual

`MainView` dispõe a sidebar de arquivos, a coluna de leitura e a sidebar de comentários. Cada painel pode se reduzir a uma barra de ícones. `Glass` reúne o desfoque da janela e os preenchimentos de cada painel, respeitando a preferência de acessibilidade para reduzir transparência.

Os cards de comentários ficam em `CommentCards`, a barra de seleção em `SelectionPill` e os menus em `JulliaCommands`. Essa divisão permite revisar componentes sem misturar desenho, menus e adaptação do TextKit.

## Compatibilidade

O nome atual dos módulos é Jullia. As referências a Marknord em `LegacyMigration` são intencionais: identificam preferências e dados de instalações até a versão 0.2.0. O bundle continua usando `dev.rheav.jullia`, e o banco continua em `Application Support/Jullia`.

A [especificação original](superpowers/specs/2026-10-08-marknord-v1-design.md) é um registro histórico do desenho inicial. O README descreve o comportamento da implementação atual.
