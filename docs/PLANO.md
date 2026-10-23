# Plano de desenvolvimento

Requisitos permanentes: interface nativa macOS em SwiftUI/AppKit; Cascadia Code; identidade da suíte; processamento e persistência locais; sem conta, nuvem ou API paga obrigatória. Bibliotecas e ferramentas locais podem ser incorporadas conforme sua licença.

| Fase | Escopo | Estado |
| --- | --- | --- |
| 1 | Interface nativa, estados, atalhos, acessibilidade, redimensionamento | Interface criada; consolidação contínua |
| 2 | Núcleo, armazenamento, erros, cancelamento e credenciais | Núcleo SQLite e persistência entregues; Chaves do macOS quando houver credenciais |
| 3 | SQLite, arquivos, metadados, queries, parâmetros e resultados | Leitura real entregue; criação genérica e expansão pendentes |
| 4 | Edição de registros, prévia de alterações e transações | Pendente |
| 5 | PostgreSQL e MySQL locais | Pendente |
| 6 | Editor profissional: autocompletar, validação, formatação, abas | Pendente; execução e histórico já disponíveis |
| 7 | Gerenciamento de estrutura e prévia de DDL | Pendente |
| 8 | Importação, exportação, backups e restauração | Pendente |
| 9 | Diagramas reais, relações virtuais, zoom e navegação | Pendente; lista de FKs reais já disponível |
| 10 | Gráficos configuráveis e exportáveis | Pendente |
| 11 | Dashboards com indicadores, gráficos, tabelas e filtros compartilhados | Pendente |
| 12 | Explicações de consultas e planos de execução reais | Pendente |
| 13 | Comparação de dados/estrutura, migração e Git local | Pendente |
| 14 | Sessões, permissões, certificados, novos dialetos | Pendente |
| 15 | Assistência por modelo local opcional | Pendente; depende de validação de hardware/qualidade |
| 16 | Distribuição, documentação offline, testes Intel/Apple Silicon | Empacotamento Intel de desenvolvimento disponível; demais itens pendentes |

Cada fase deve ser validada com dados reais, erros e limites representativos. A conclusão de um incremento não significa paridade integral com o DataGrip.
