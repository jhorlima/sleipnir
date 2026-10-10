# Fase 2 — Benchmark: plano de execução

Detalha a fase 2 do §13 do [SPEC](../SPEC.md). Regras de medição em `.claude/rules/benchmark-integrity.md`.

## Restrição que define a ordem

A VM do Docker tem 8 CPUs, 16 GB e 2 GB de swap. O perfil `M` dá 8 GB ao engine sob teste e o `L` dá 12 GB. A infra (RustFS, Lakekeeper, Postgres, Traefik) usa cerca de 2 GB, e o Cube com o Cube Store mais uns 3 GB. Por isso:

- **Só um engine fica de pé por vez**, inclusive nas validações dos workers, e não apenas nas medições. Workers escrevem código em paralelo, mas sobem engines em fila, um de cada vez. Engine + Cube cabem juntos no perfil `M`.
- Os containers dos engines têm `memswap_limit` igual ao limite de memória: sem swap, um engine sem memória falha em vez de ficar lento sem que ninguém perceba.
- Com a VM de 8 GB, quatro testes dbt simultâneos sobre a `r2` derrubaram o Trino por OOM (exit 137). É por isso que a VM tem 16 GB.
- O macOS não pode dormir durante uma execução: o sono congela a VM e o Trino perde as tasks (`ABANDONED_TASK`). Execuções longas rodam sob `caffeinate -i`, e o harness recusa medir sem isso.

## Etapas

| # | Etapa | Depende de | Worker | Pronto quando |
|---|---|---|---|---|
| 1 ✅ | **Escala `r2`**: GHCN 2010–2025, lotes `.csv.gz`, carga, `make dbt-backfill` no Trino, `storage-report` | — | sessão principal | Escalas fixadas no §6; números no post |
| 1b | **Unicidade do silver na `r2`**: o teste da tabela inteira estoura o spill de 10 GB. Proposta: restringir o teste à janela que a execução gravou (seguro porque delete+insert, merge e microbatch substituem a janela inteira) e manter uma checagem completa ano a ano como `run-operation` fora da medição | 1 | stack-worker | `dbt build` passa na `r2` com 1 thread |
| 2 | **Harness** `bench/harness/` (Python/uv, container na rede do Compose): grava `results/<suite>.parquet` no esquema do §10.7, amostra `docker stats`, faz cold/warm, timeout e checksum contra a referência DuckDB. Adaptadores: B1 (linhas JSON do `load.py`), B2 (`run_results.json` do dbt), B3 (SQL por engine), B4/B5 (REST do Cube). Relatório DuckDB (p50/p95). `make bench SUITE=… ENGINE=…`, `make report` | 1 | stack-worker | B1 e B2 do Trino geram parquet; relatório lê os dois |
| 3a | **Spikes, só pesquisa** (paralelo à etapa 2): V2 (Trino MV no conector Iceberg com catálogo REST), V3 (StarRocks reescreve join sobre Iceberg para MV), V9 (multi-stage do Cube no Cube Store), V13 (driver DuckDB do Cube com `ATTACH` no Lakekeeper) | — | 4 × spike-researcher | Cada `spikes/V*/README.md` com a resposta documentada e a prova mínima descrita |
| 3b | **Provas locais dos spikes**, em fila (um engine por vez) | 3a, 4 | spike-researcher | §15 atualizado |
| 4 | **Readers**: StarRocks (compose, `config/starrocks/`, external catalog `lakehouse`) e DuckDB (Cube `duckdb` data source); arquivos `cube/model/cubes/<engine>/` com `extends`; queries Q1–Q6 em `bench/queries/sql/q<n>.<engine>.sql` | 2 (para validar com o harness) | 2 × stack-worker (StarRocks; DuckDB), código em paralelo e validação em fila | Q1–Q6 batem o checksum da referência DuckDB; Cube Q1–Q10 respondem nos dois data sources |
| 5 | **Writers**: Spark 4.1 (Thrift Server, target `spark`, `maintain_table` do Spark, §4.1) e Postgres só na escala `small` (D-23; container **próprio** com os limites do perfil, separado do Postgres do catálogo; DuckDB carrega `postgres_bronze` com os lotes de 2025; target `postgres`; Cube `postgres`) | 2 | 2 × stack-worker, código em paralelo e validação em fila | `dbt build` passa nos três targets; `audit_helper` iguala Spark/Postgres ao Trino |
| 6 | **D2 TPC-H**: `dbgen` do DuckDB → namespace `duckdb_tpch` no SF que cabe em 2 GB; as 22 queries por engine; rótulo de fair use | 2, 4 | stack-worker | 22 queries validadas por checksum em todos os readers |
| 7 | **B6 antes das medições**: matriz ordenação × codec × tamanho de arquivo × partição em `bench_*` (sobre a `r2` atual), manutenção medida por engine (Trino, Spark) e o efeito nas leituras com as queries do B3; o vencedor vira padrão (D-15) | 2, 4, 5 | stack-worker + bench-runner | `results/b6.parquet`; layout padrão em §14 |
| 8 | **Medições B1–B4** na `r2` atual (2010–2025), perfil `M`, um engine por vez | 6, 7 | bench-runner, sequencial | `results/b1…b4.parquet` + relatório |
| 9 | **B5**: a) MV `mv_weather_wide` do StarRocks com `EXPLAIN` obrigatório; b) tabela equivalente via dbt no Trino (o Trino 483 não cria MV no catálogo REST, V2), apontada pelo Cube; c) Cube Store sobre Trino e StarRocks | 3b, 8 | stack-worker por cenário (em fila) + bench-runner | `results/b5.parquet` com refresh, storage extra e validade de cada query |
| 10 | **`r2` em bilhões**: com o layout do B6, ampliar os anos até encher os 6,5 GB do D1 (meta ≥ 1 bi linhas no bronze); avisar com a estimativa de disco antes; recarregar e repetir B1–B5 | 9 | sessão principal + bench-runner | `storage-report` ≤ 10 GB com D2; §6 com os anos finais |
| 8b | **Escala `small`** (2025): recarregar o bronze só com 2025 e rodar B2/B3/B4 em todos os engines, incluindo o Postgres; depois recarregar a `r2` | 8 | sessão principal + bench-runner | `results` com `data_scale=small` para todos os engines |
| 11 | **Escala `local`**: histórico completo do GHCN; avisar com a estimativa de disco antes | 10 | sessão principal | Escala fixada no §6; B1–B4 repetidos nessa escala |

O teste no Cloudflare R2 é a fase 6 do SPEC, depois de todas as fases locais.

## O que roda em paralelo

- **Agora (durante a etapa 1):** nada que suba engine. A etapa 3a (4 spike-researchers, só pesquisa) pode começar.
- **Depois da etapa 1:** etapa 2 (harness) + 3a. Os arquivos não se cruzam: `bench/harness/` e `spikes/V*/`.
- **Depois da etapa 2:** etapas 4 e 5 com 4 stack-workers escrevendo código em paralelo (StarRocks, DuckDB-Cube, Spark, Postgres), cada um com SCOPE disjunto. A subida de engines para validação é serializada pela sessão principal.
- **Medições (7–9):** sempre um bench-runner por vez, sem nenhum worker subindo engine ao mesmo tempo.
- Cada worker recebe TASK / SCOPE / DONE WHEN e responde `DONE — …` ou `BLOCKED — …`. Cada etapa vira um ou mais commits pequenos nesta branch e entra no post no mesmo commit.
