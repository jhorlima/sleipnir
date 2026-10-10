# Fase 2 — Benchmark: plano de execução

Detalha a fase 2 do §13 do [SPEC](../SPEC.md). Regras de medição em `.claude/rules/benchmark-integrity.md`.

## Restrição que define a ordem

A VM do Docker tem 8 GB e 6 CPUs. O perfil `M` dá 8 GB ao engine sob teste, e a infra (RustFS, Lakekeeper, Postgres, Traefik) usa cerca de 1 GB a mais. Por isso:

- **Só um engine fica de pé por vez**, inclusive nas validações dos workers, e não apenas nas medições. Workers escrevem código em paralelo, mas sobem engines em fila, um de cada vez.
- Antes das medições no perfil `M`, a VM sobe para **≥ 12 GB** (para o perfil `L`, ≥ 16 GB). Com 8 GB, quatro testes dbt simultâneos sobre a `r2` derrubaram o Trino por OOM (exit 137). Os limites usados ficam registrados no post.
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
| 5 | **Writers**: Spark 4.1 (Thrift Server, target `spark`, `maintain_table` do Spark, §4.1) e Postgres (container **próprio** com os limites do perfil, separado do Postgres do catálogo; DuckDB carrega `postgres_bronze`; target `postgres`; Cube `postgres`) | 2 | 2 × stack-worker, código em paralelo e validação em fila | `dbt build` passa nos três targets; `audit_helper` iguala Spark/Postgres ao Trino |
| 6 | **D2 TPC-H**: `dbgen` do DuckDB → namespace `duckdb_tpch` no SF que cabe em 2 GB; as 22 queries por engine; rótulo de fair use | 2, 4 | stack-worker | 22 queries validadas por checksum em todos os readers |
| 7 | **Medições B1–B4** no perfil `M`, um engine por vez | 2, 4, 5, 6 | bench-runner, sequencial | `results/b1…b4.parquet` + relatório |
| 8 | **B5**: a) MV `mv_weather_wide` do StarRocks com `EXPLAIN` obrigatório; b) MV do Trino (ou o fallback do V2); c) Cube Store sobre Trino e StarRocks | 3b, 7 | stack-worker por cenário (em fila) + bench-runner | `results/b5.parquet` com refresh, storage extra e validade de cada query |
| 9 | **B6**: matriz codec × tamanho de arquivo × partição em `bench_*`, mais manutenção medida por engine; o vencedor vira padrão (D-15) | 7 | stack-worker + bench-runner | `results/b6.parquet`; §14 atualizado; B3 repetido se o padrão mudar |
| 10 | **Escala `local`**: mais anos para trás até ~20 GB de bronze ou ~30 min de B1; avisar com a estimativa de disco antes | 7 (B1 medido) | sessão principal | Escala fixada no §6; B1–B4 repetidos nessa escala |

## O que roda em paralelo

- **Agora (durante a etapa 1):** nada que suba engine. A etapa 3a (4 spike-researchers, só pesquisa) pode começar.
- **Depois da etapa 1:** etapa 2 (harness) + 3a. Os arquivos não se cruzam: `bench/harness/` e `spikes/V*/`.
- **Depois da etapa 2:** etapas 4 e 5 com 4 stack-workers escrevendo código em paralelo (StarRocks, DuckDB-Cube, Spark, Postgres), cada um com SCOPE disjunto. A subida de engines para validação é serializada pela sessão principal.
- **Medições (7–9):** sempre um bench-runner por vez, sem nenhum worker subindo engine ao mesmo tempo.
- Cada worker recebe TASK / SCOPE / DONE WHEN e responde `DONE — …` ou `BLOCKED — …`. Cada etapa vira um ou mais commits pequenos nesta branch e entra no post no mesmo commit.
