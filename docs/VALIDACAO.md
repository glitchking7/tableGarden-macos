# Validação — SQLite real — 23/10/2026

Ambiente: macOS 15.8.1 Intel, Xcode 26.2, Swift 6.2.3; SQLite fornecido pelo macOS.

## Núcleo

11 testes automatizados passaram, sem falhas:

1. Metadados reais, views, colunas, índices e chaves estrangeiras; identificadores com aspas.
2. Valores tipados, Unicode, inteiros de 64 bits, NULL, texto vazio e BLOBs.
3. Parâmetros vinculados, texto com tentativa de injeção e caractere nulo como valor.
4. Múltiplos comandos, comentários finais e nomes de colunas duplicados.
5. Bloqueio de gravações, ATTACH, configuração de PRAGMA, extensão e VACUUM INTO.
6. Arquivos inválidos preservados; caminhos inexistentes não criados.
7. Paginação de 450 registros em três páginas; limite e detecção de truncamento.
8. Cancelamento de uma consulta longa e reutilização da mesma conexão.
9. Tempo limite e limite de tamanho de célula.
10. Restauração de queries, histórico, rascunho e caminhos recentes; criação/reabertura do exemplo.
11. Conexão anterior mantida após falha ao abrir outro arquivo.

Comando: `CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache" swift test --disable-sandbox`.

## Aplicativo

- Build de produção e empacotamento Intel concluídos.
- Capturas nativas feitas com um arquivo SQLite real de exemplo: tabelas, editor SQL executando SELECT e relações declaradas.
- O exemplo retorna 3 usuários ativos, e a lista de relacionamentos encontra 3 vínculos.
- Fonte incorporada e logo transparente preservados.
- Capturas isoladas do armazenamento normal do usuário.
- Assinatura ad hoc conferida com `codesign --verify --deep --strict`.

## Limites desta validação

Não houve automação de cliques e diálogos nativos. A renderização e o caminho de abertura/consulta das capturas foram executados; os comportamentos do núcleo foram testados separadamente. Não foram validados edição de dados, drivers PostgreSQL/MySQL, grandes volumes representativos de produção, Apple Silicon, assinatura Developer ID ou notarização. Esses itens não são declarados concluídos.
