# SPEC — Sleipnir: ELT Lakehouse + Benchmark de Query Engines

> Status: **v0.3** (2026-10-09) · Itens marcados com ⚠️ precisam ser validados antes/durante a implementação (§15).
> Versão em inglês (`SPEC.en.md`) será gerada quando esta versão estabilizar.

## 1. Objetivos

1. **Stack ELT local** — mover dados públicos (CSV) até um lakehouse Iceberg, modelado em medalhão (bronze → silver → gold) com dbt, exposto por uma semantic layer (Cube).
2. **Benchmark reprodutível** — medir, com recursos fixos e iguais e **um engine por vez** (nunca duas transformações simultâneas):
   - tempo/throughput de **ingestão**;
   - tempo de **cada etapa** da transformação (por model dbt), por engine e por estratégia incremental;
   - latência de **leitura** por engine (direto e via Cube);
   - ganho de **aceleração**: MV do StarRocks × MV do Trino × pre-aggregations do Cube Store;
   - impacto de **manutenção/layout** (compactação, tamanho de arquivo, codec).
3. **Portabilidade para R2** — uma execução cabe em **≤ 10 GB** no bucket, para repetir o benchmark no free tier do Cloudflare R2.
4. **Publicação** — repositório público reprodutível + artigo (blog e LinkedIn) apresentando o estudo de benchmark (§16).

### Fora de escopo (por agora)
- Airflow/Cosmos, Superset, Dagster, R2 → fases posteriores (§13).
- Airbyte — só se surgir necessidade de conectores que o DuckDB não cobre.
- Iceberg v3 — reavaliar quando o ecossistema suportar (§15, V6).
- Alta disponibilidade, auth, multi-nó real, streaming/CDC, execução simultânea de engines.

## 2. Ambiente e restrições

- Host: macOS, 12 CPU, 24 GB RAM. Docker Desktop: limites globais removidos durante as execuções do benchmark.
- **Docker Compose** (sem Swarm): `deploy.resources.limits` (cpus/memory) por serviço, `profiles` para subir só o necessário e `include` para separar os arquivos por domínio.
- **Um engine sob teste por vez:** nunca duas transformações ao mesmo tempo (ex.: Trino e Spark em paralelo). Dentro de uma execução, o dbt pode rodar models em paralelo com `threads = DBT_THREADS` (**mesmo valor para todos os engines**, padrão 4); o resto do paralelismo fica a cargo de cada engine.
- Números absolutos vêm de uma VM em macOS; o valor está na **comparação relativa**.
- **Rede:** nenhuma porta publicada por padrão. UIs HTTP via Traefik (`trino.localhost`, `starrocks.localhost`, `spark.localhost`, `cube.localhost`, `lakekeeper.localhost`, `rustfs.localhost`). O harness de benchmark roda num container na mesma rede e fala direto com os serviços, sem passar pelo proxy. Portas de banco (MySQL do StarRocks, Postgres, SQL API do Cube) são publicadas só em `127.0.0.1` e só quando for preciso usar um cliente local (ex.: DBeaver).

## 3. Arquitetura

```
 [CSV público] ─► landing/ (disco local) ─► DuckDB ─► duckdb_bronze (append)
                                                        │
                RustFS (S3) ◄─► Lakekeeper (Iceberg REST) ◄─► Postgres (metadados)
                                                        │
        Transformação (dbt Core 1.x, threads=N): Trino ─► trino_silver/gold
                                                 Spark ─► spark_silver/gold
                                                 Postgres ─► postgres_* (baseline, fora do lake)
                                                        │
        Leitura dos marts: StarRocks (+ MV) · Trino · DuckDB · Postgres
                                                        │
                    Cube (+ Cube Store) ─► Benchmark harness ─► results/*.parquet
                                       └─► [fase 4] Superset
```

### 3.1 Catálogo e nomenclatura
Hierarquia do Lakekeeper: **project → warehouse → namespace → table**.

- Um único Lakekeeper, um project, um warehouse: `lakehouse` (bucket `lakehouse` no RustFS).
- Cada engine registra esse warehouse como um catálogo chamado `lakehouse` (Trino: `catalog/lakehouse.properties`; Spark: `spark.sql.catalog.lakehouse`; StarRocks: `CREATE EXTERNAL CATALOG lakehouse`; DuckDB: `ATTACH ... AS lakehouse`).
- **Namespaces com prefixo do engine que escreveu:** `<engine>_<camada>`.

| Namespace | Escrito por | Conteúdo |
|---|---|---|
| `duckdb_bronze` | DuckDB (ingestão) | dados crus, compartilhados por todos os writers |
| `trino_silver`, `trino_gold` | Trino via dbt | silver/gold oficiais (fonte padrão dos readers) |
| `spark_silver`, `spark_gold` | Spark via dbt | mesmo projeto dbt, escrito pelo Spark |
| `bench_*` | harness | tabelas temporárias de experimentos de layout (apagadas com `PURGE`) |
| `postgres_bronze/silver/gold` | DuckDB + dbt-postgres | baseline, em schemas do Postgres (fora do lake) |

- Os readers leem `trino_gold` por padrão (`GOLD_NAMESPACE`). Cenário extra: ler `spark_gold` para medir o efeito do layout gerado por cada writer.

## 4. Componentes

| Camada | Escolha | Futuro / alternativa | Notas |
|---|---|---|---|
| Object storage | **RustFS** | R2 (fase 4) | MinIO community descontinuado. |
| Catálogo | **Lakekeeper** (Iceberg REST) | Polaris, R2 Data Catalog | Backend Postgres. |
| Formato | **Parquet + Iceberg v2** | Iceberg v3 (V6) | Codec e tamanho de arquivo definidos pelo B6. |
| Ingestão | **DuckDB** | Airbyte (se precisar de conectores) | ⚠️ V1: escrita Iceberg via REST. |
| Transformação | **dbt Core 1.12** + dbt-trino 1.10 (Trino 483) | dbt Core v2 quando houver adapter Trino/Postgres | `dbt-trino`, `dbt-spark`, `dbt-postgres`. |
| Engines de transformação | **Trino**, **Spark 4.1.x** | — | Postgres como baseline. |
| Engines de leitura | **StarRocks**, Trino, DuckDB, Postgres | — | StarRocks via external catalog. |
| Aceleração | **StarRocks async MV**, Trino MV, **Cube Store** | — | §10.3. |
| Semantic layer | **Cube** | — | Drivers oficiais: Trino, DuckDB, Postgres; StarRocks via driver MySQL. Sem Spark. |
| Orquestração | **Makefile** (fases 1–2) → Airflow 3 + Cosmos | Dagster | |
| Proxy | **Traefik** (apenas UIs) | — | §2. |
| BI | Superset via SQL API do Cube (fase 4) | — | |

Versões pinadas em `.env`; nenhuma tag `latest`.

### 4.1 Spark 4.1.x
- Iceberg runtime: `org.apache.iceberg:iceberg-spark-runtime-4.1_2.13` + `iceberg-aws-bundle` (Iceberg ≥ 1.11; Scala 2.13 obrigatório).
- dbt-spark via **Spark Thrift Server** (`method: thrift`).
- Ajuste ao container (valores derivados dos limites do perfil, não fixos):
  - `local[N]`, com N = CPUs do perfil (um único JVM, sem overhead de cluster);
  - `spark.driver.memory` ≈ 75% da memória do container (o resto fica para overhead da JVM/off-heap);
  - `spark.sql.shuffle.partitions` = 2–3 × N; AQE ligado (`spark.sql.adaptive.enabled`, `coalescePartitions`, `skewJoin`);
  - `spark.sql.iceberg.vectorization.enabled=true` (padrão) e `spark.serializer=KryoSerializer`;
  - `write.distribution-mode=hash` nas tabelas particionadas, para evitar arquivos pequenos.
- Os parâmetros finais são registrados em `config/spark/` e em `results` (`engine_config`).

## 5. Datasets

| ID | Dataset | Origem | Uso |
|---|---|---|---|
| **D1** | **NOAA GHCN-Daily** | `https://www.ncei.noaa.gov/pub/data/ghcn/daily/by_year/{YYYY}.csv.gz` · `.../daily/ghcnd-stations.txt` · `.../daily/ghcnd-countries.txt` (layout em `.../daily/readme.txt`) | Narrativa ELT/medalhão, dedup, Cube, aceleração |
| **D2** | **TPC-H** | Gerado pelo DuckDB: `INSTALL tpch; CALL dbgen(sf = N)` | Benchmark padronizado de leitura (22 queries) |
| D3 (opcional) | Datasets de agricultura do awesome-public-datasets | `https://github.com/awesomedata/awesome-public-datasets#agriculture` | Dimensões/enriquecimento |

- D1 colunas (sem cabeçalho): `id, date, element, value, m_flag, q_flag, s_flag, obs_time`.
- O volume é definido pelo **orçamento de storage (§6)**, não pelo tamanho do CSV. O CSV pode passar de 10 GB, desde que o lakehouse resultante caiba no orçamento.
- Downloads são idempotentes: arquivo já presente em `landing/` com o mesmo tamanho/ETag não é baixado de novo.

### Simulação de duplicados
Ingestão em **lotes incrementais com janela sobreposta**: cada lote `n` inclui os últimos 30 dias do lote `n-1`, mais ~1% de linhas reemitidas com `value` alterado (simula revisão da fonte). Chave natural: `(station_id, date, element)`; vence o maior `_ingested_at`. Como `date` faz parte da chave, um duplicado sempre cai no mesmo batch temporal — isso viabiliza microbatch/insert_overwrite sem perder o dedup.

## 6. Orçamento de storage (≤ 10 GB)

| Item | Teto |
|---|---|
| D1 — `duckdb_bronze` + silver/gold de **um** engine | 6,5 GB |
| D2 — TPC-H | 2 GB |
| Metadados Iceberg, `bench_*`, margem | 1,5 GB |
| **Total no bucket** | **≤ 10 GB** |

Regras:
- O teto vale para **uma execução** (bronze + silver/gold de um único writer + D2). Comparar vários writers lado a lado é feito **localmente**, onde não há teto.
- Fora do bucket: `landing/` (CSV em disco local), baseline Postgres, MVs do StarRocks (storage local do BE) e Cube Store.
- **Dimensionamento empírico:** na fase 1, ingerir 1 ano de D1, medir o tamanho por namespace e calcular quantos anos cabem no teto de uma execução. Para D2, gerar SF1, medir e escalar o SF.
- Manutenção após cada carga (§10.4): snapshots antigos contam no orçamento.
- `make storage-report ENGINE=<engine>` mostra o uso por namespace e falha se bronze + `<engine>_*` + D2 passar do teto.
- ⚠️ V5: confirmar os limites atuais do free tier do R2 (storage e operações Class A/B) e estimar os GETs do benchmark antes de rodar no R2.

## 7. Modelo de dados (medalhão)

### Bronze — cópia fiel da fonte (`duckdb_bronze`)
- `ghcn_daily_raw` — colunas da fonte + `_source_file`, `_batch_id`, `_ingested_at`. **Append-only**, particionado por `_batch_id`.
- `ghcn_stations_raw`, `ghcn_countries_raw` — substituídas a cada carga (são pequenas).

### Silver — limpo, tipado, deduplicado (`<engine>_silver`)
- `ghcn_daily` — tipos corretos, `value` convertido (décimos → unidades), linhas com `q_flag` preenchido removidas, **dedup** pela chave natural. Incremental (estratégia em §7.1). Partição `month(date)` (granularidade validada no B6).
- `stations` — parse do fixed-width, país via `ghcnd-countries`.

### Gold — marts (`<engine>_gold`)
- `dim_station`, `dim_date` — `table` (recriadas; são pequenas).
- `fct_weather_daily` — 1 linha por estação/dia, pivot de `TMAX, TMIN, PRCP, SNOW`. Incremental.
- `agg_weather_monthly_country` — agregado mensal por país. Incremental por mês.

### 7.1 Estratégias incrementais (matriz do B2)
Bronze é sempre `append`. Nas camadas silver/gold, cada estratégia suportada é medida por engine; a vencedora vira o padrão daquele engine.

| Estratégia | Trino | Spark | Postgres | Observação |
|---|---|---|---|---|
| `merge` (chave natural) | ✅ | ✅ | ✅ | Referência. No Spark, testar `write.merge.mode` copy-on-write × merge-on-read. |
| `delete+insert` | ✅ | — | ✅ | Apaga a janela afetada e reinsere. |
| `insert_overwrite` (partição) | — | ✅ | — | Reescreve só as partições tocadas pelo lote. |
| `microbatch` (`event_time = date`, `batch_size = month`) | ✅ | ✅ | ✅ | `concurrent_batches` com o mesmo valor em todos os engines. Tempo medido **por batch**. |

- No Trino, o microbatch é `DELETE` + `INSERT` por batch filtrado por `event_time` (ignora `unique_key`; usa tabela temporária). Cada batch gera dois snapshots e position deletes, então a manutenção (§10.4) pesa mais nessa estratégia.
- Janela incremental: datas presentes no último `_batch_id` + `lookback` igual à sobreposição dos lotes (30 dias).
- Cada execução de B2 é de um engine × uma estratégia, a partir do mesmo estado inicial do bronze (`duckdb_bronze` é só lido).
- **Correção do incremental:** ao fim de cada execução, o resultado incremental é comparado com um `--full-refresh` em `bench_*` (`audit_helper.compare_relations`). Divergência invalida a medição daquela estratégia.

### 7.2 Convenções do projeto dbt
- `profiles.yml` com um target por engine (`trino`, `spark`, `postgres`), escolhido por `DBT_TARGET`; `threads` vem de `DBT_THREADS`.
- Namespace gerado por macro `generate_schema_name`: `<target>_<camada>`, com a camada derivada da pasta (`models/silver/` → `silver`). Model sem camada falha na compilação. Execuções de experimento usam `RUN_ID` → `bench_<run_id>_<camada>`.
- SQL específico de engine só via `adapter.dispatch`; propriedades de tabela (partição, ordenação) por adapter no `config`.
- Dedup: `ROW_NUMBER() OVER (PARTITION BY <chave natural> ORDER BY _ingested_at DESC) = 1`.
- Manutenção (compactação, expire, orphan files, manifests) é **uma macro** `maintain_table` com `adapter.dispatch` (Trino `ALTER TABLE ... EXECUTE optimize/expire_snapshots/remove_orphan_files`; Spark procedures Iceberg; Postgres `VACUUM ANALYZE`), usada de dois jeitos:
  - **uso normal:** post-hook dos models incrementais, ligado por `var('maintenance', true)`;
  - **benchmark:** execuções medidas passam `--vars '{maintenance: false}'` (o post-hook contaminaria o tempo do model) e a mesma macro roda depois como etapa própria via `dbt run-operation maintain_table` (§10.4, B6);
  - na fase 3, a manutenção vira uma task/DAG separada no Airflow chamando o mesmo `run-operation`.
- Pacotes pinados nas versões atuais: `dbt_utils`, `audit_helper`, `dbt_project_evaluator`.

### 7.3 Testes dbt
Executados como etapa própria (`dbt test`), separados do tempo dos models.

| Tipo | Onde | Regra |
|---|---|---|
| `unique_combination_of_columns` (dbt_utils) | `silver.ghcn_daily` | `(station_id, date, element)` |
| `unique` + `not_null` | PKs do gold | — |
| `relationships` | fato → dims | — |
| `accepted_values` | `element` | `TMAX, TMIN, PRCP, SNOW, SNWD, ...` |
| `accepted_range` (dbt_utils) | silver/gold | `tmax`, `tmin` entre −90 e 60 °C; `prcp ≥ 0`; `latitude` −90..90; `longitude` −180..180 |
| `expression_is_true` (dbt_utils) | `fct_weather_daily` | `tmax >= tmin` (quando ambos existem) |
| `fewer_rows_than` (dbt_utils) | silver × bronze | dedup nunca aumenta linhas |
| `recency` (dbt_utils) | `fct_weather_daily` | última data ≥ limite esperado do último lote |
| **Unit tests** (dbt ≥ 1.8) | `silver.ghcn_daily` | dedup (vence o maior `_ingested_at`) e conversão de unidades |
| `source freshness` | `duckdb_bronze.ghcn_daily_raw` | por `_ingested_at` |

## 8. Semantic layer (Cube)

Regras de modelagem em `.claude/rules/cube-models.md`.

O Cube lê **somente pelos engines** (SQL nas tabelas gold). Ele não importa nem depende de artefatos do dbt (manifest, semantic models); o schema do Cube é mantido à parte.

### 8.1 Deploy
- Cube e Cube Store na **mesma versão** (`v1.7.18` como ponto de partida, pinada em `.env`); imagem do Cube Store com `${CUBESTORE_ARCH_SUFFIX}` (`-arm64v8` no Apple Silicon).
- Serviços: `cube-api` (REST + SQL API, `CUBEJS_REFRESH_WORKER=false`), `cube-refresh-worker` (`CUBEJS_REFRESH_WORKER=true`), `cubestore-router` + `cubestore-worker` (1 worker local). Env comum via anchor `x-cube-env-common`.
- Flags: `CUBEJS_TESSERACT_SQL_PLANNER=true`, `CUBEJS_SCHEDULED_REFRESH_TIMEZONES=UTC`, `CUBEJS_DEV_MODE=false` nas execuções medidas.
- Modelos só em YAML.

### 8.2 Data sources
Uma única instância do Cube com **multi data source**:
`CUBEJS_DATASOURCES=default,trino,starrocks,duckdb,postgres` + `CUBEJS_DS_<NOME>_DB_{TYPE,HOST,PORT,NAME,USER,PASS}`.

| Data source | Driver | Observação |
|---|---|---|
| `trino` | `trino` | catálogo `lakehouse`, schema `GOLD_NAMESPACE` |
| `starrocks` | `mysql` (porta 9030 do FE) | nomes em três partes: `lakehouse.<gold_namespace>.<tabela>` |
| `duckdb` | `duckdb` | init SQL carrega `iceberg`/`httpfs` e faz `ATTACH` no Lakekeeper |
| `postgres` | `postgres` | schema `postgres_gold` |

- O `data_source` é fixo em cada cube, então os cubes são gerados por data source a partir de **um único template** (Jinja do Cube, um laço simples sobre a lista de data sources), com prefixo: `trino_weather_daily`, `starrocks_weather_daily`, etc.
- Joins e rollups não cruzam data sources (limitação do Cube; irrelevante aqui).

### 8.3 Modelo
Cubes (internos, `public: false`): `weather_daily` (sobre `fct_weather_daily`), `stations`, `dates`. Views públicas: `<ds>_weather`.

| Tipo | Itens |
|---|---|
| Medidas | `avg_tmax`, `avg_tmin`, `total_prcp`, `days_with_rain`, `station_count`, `observation_count` |
| Dimensões | `country`, `station_id`, `elevation`, `latitude`, `longitude`, `date` (day/month/year) |
| Derivadas | `temp_range = avg_tmax - avg_tmin`, `rain_day_ratio = days_with_rain / observation_count` |
| Percentis | `median_tmax`, `p95_prcp` — `type: number` com a função de cada engine (Trino `approx_percentile`, StarRocks `PERCENTILE_CONT(x, p)`, DuckDB/Postgres `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)`) |
| Agregado aninhado | `median_station_annual_prcp` — soma anual por estação (cube interno + dimensão `sub_query: true`), mediana entre estações |
| Share of total | `prcp_share_of_total` — multi-stage, helper `grain: keep_only: []`, `format: percent`; variante por país com `keep_only: [country]` |
| Period-over-period | `avg_tmax_prior_year` (`time_shift` 1 year prior), `tmax_yoy_delta`, `prcp_mom_ratio` (1 month prior) |

- Multi-stage (`multi_stage`, `grain`, `time_shift`) depende do Tesseract, ligado por padrão a partir do Cube 1.7.
- Medidas não aditivas (percentis, mediana) não são reagregadas pelo Cube Store; só usam rollup se ele tiver exatamente a mesma granularidade da query (⚠️ V9).
- **Precisão em pre-aggregations:** os drivers SQL do Cube mandam DECIMAL para o Cube Store como `Decimal(18,5)` (trunca em 5 casas; `CUBEJS_DB_PRECISE_DECIMAL_IN_CUBESTORE` não resolve). Toda medida que entra em rollup é feita com `CAST(... AS DOUBLE)` (`DOUBLE PRECISION` no Postgres). Detalhes em `.claude/rules/cube-models.md`.
- Sintaxe específica por engine (ex.: `PERCENTILE_CONT` no StarRocks recebe 2 argumentos) fica no template, por data source.

### 8.4 Pre-aggregations (só no B5c)
- Rollup `monthly_country` (país × mês) e `yearly_station` (estação × ano), `partition_granularity: month`/`year`, índices pelas dimensões filtradas.
- No benchmark, o build é disparado explicitamente no passo 6 do §9 (não pelo timer do refresh worker), e o tempo é medido.
- Conferir que as colunas de medida no Cube Store são `Float`.

## 9. Fluxo de uma execução completa

Cada etapa é executada e medida isoladamente, na ordem:

1. Download → `landing/` (fora da medição).
2. **Ingestão** do lote → `duckdb_bronze` (B1).
3. **Transformação** (B2): `dbt run` com `threads = DBT_THREADS`; o tempo de cada model (etapa) vem do `run_results.json`, além do tempo total. Variante opcional com `threads = 1` para medir o custo isolado de cada etapa, sem disputa entre models.
4. **Testes** dbt (etapa própria).
5. **Manutenção** das tabelas tocadas (§10.4).
6. **Refresh das acelerações**: `REFRESH MATERIALIZED VIEW` no StarRocks/Trino e build das pre-aggregations do Cube Store (cada um medido).
7. **Leitura** direta (B3), via Cube (B4) e acelerada (B5).

## 10. Especificação do benchmark

### 10.1 Perfis de recursos
| Perfil | CPU | Memória | Uso |
|---|---|---|---|
| `S` | 2 | 4 GB | pouco recurso |
| `M` | 4 | 8 GB | **padrão** |
| `L` | 8 | 12 GB | escalabilidade |

Os limites valem para o engine sob teste (soma FE+BE no StarRocks; coordinator+worker no Trino; o JVM único no Spark). Infra compartilhada (RustFS, Lakekeeper, Postgres-catálogo, Cube) fica fora do limite e é constante entre execuções.

### 10.2 Suítes
| ID | O que mede | Participantes | Métrica principal |
|---|---|---|---|
| **B1** Ingestão | CSV → `duckdb_bronze` | DuckDB | MB/s, linhas/s, tempo por lote, pico de memória |
| **B2** Transformação | cada model, por estratégia (§7.1) | Trino, Spark, Postgres | tempo por model (e por batch no microbatch), linhas afetadas, arquivos escritos |
| **B3** Leitura direta | queries SQL nos marts / TPC-H | StarRocks, Trino, DuckDB, Postgres | p50/p95, cold × warm |
| **B4** Via Cube | mesmas perguntas via Cube REST/SQL API, sem aceleração | idem | p50/p95, overhead vs B3 |
| **B5** Aceleração | mesmas perguntas do B4, acelerado | §10.3 | p50/p95, tempo de refresh, storage extra |
| **B6** Manutenção/layout | operações de manutenção; codec × tamanho de arquivo × partição | Trino e Spark (manutenção) + readers | storage, tempo de escrita/compactação, efeito em B3 |

### 10.3 Cenários de aceleração (B5)
| Cenário | Mecanismo | Como o Cube usa |
|---|---|---|
| **B5a** | **StarRocks async MV** `mv_weather_wide`: o SQL "cru" que o Cube gera — o tabelão `fct_weather_daily` × `dim_station` × `dim_date` com todas as colunas usadas pelos cubes. Propriedade `force_external_table_query_rewrite = true`; sessão com `enable_materialized_view_rewrite = true`. | O Cube continua lendo os marts; o otimizador do StarRocks reescreve a query para a MV. |
| **B5b** | **Trino materialized view** equivalente no conector Iceberg (⚠️ V2). | Trino não reescreve automaticamente: o Cube aponta para a MV (via `sql_table` por variável). |
| **B5c** | **Cube Store** pre-aggregations (país × mês, estação × ano) sobre Trino e sobre StarRocks. | O Cube roteia para o Cube Store. |

- DDL do B5a: `PARTITION BY date_trunc('month', date)`, `DISTRIBUTED BY HASH(station_id)` com buckets pelo volume (< 5M linhas → 4; 5–50M → 8; 50–200M → 16; > 200M → 32), `ORDER BY` pelas dimensões filtradas, `REFRESH MANUAL`. Não existe `CREATE OR REPLACE` para MV: recriar é `DROP` + `CREATE`.
- Refresh **depois da transformação e antes da leitura** (passo 6 do §9), com `WITH SYNC MODE` (ou assíncrono + polling de `SHOW MATERIALIZED VIEWS` até estado final), e medido.
- Sem a MV, o StarRocks cai silenciosamente na tabela base. Por isso o B4 do StarRocks (sem MV) é a linha de base do B5a, e o `EXPLAIN` confirma qual dos dois caminhos rodou.
- **Validação obrigatória no B5a:** o `EXPLAIN` de cada query precisa mostrar `mv_weather_wide`; se a reescrita não ocorrer, a medição é marcada como inválida (⚠️ V3).
- Q4–Q6 (§10.5) servem de controle; Q1–Q3 são as candidatas a ganho.

### 10.4 Manutenção (aplicada após cada carga; parâmetros do B6)
- `expire_snapshots` (mantém o último), `remove_orphan_files`, `rewrite_data_files`, `rewrite_manifests` — via `dbt run-operation maintain_table` no engine que escreveu a tabela, cada operação medida.
- **B6 é o benchmark só das otimizações:** custo de cada operação por engine e o efeito dela nas leituras (B3 antes × depois).
- **Matriz do B6** (sobre cópias em `bench_*`, mesmos dados):

| Dimensão | Valores |
|---|---|
| `write.target-file-size-bytes` | 128 MB, 256 MB, 512 MB |
| `write.parquet.compression-codec` | **zstd** (padrão do Iceberg), snappy, gzip |
| Partição de `ghcn_daily` / `fct_weather_daily` | `month(date)`, `year(date)` |

- Hipótese a validar: **zstd** é o melhor equilíbrio entre tamanho e velocidade de leitura; gzip comprime parecido, mas descomprime mais devagar; snappy é o maior em disco. Com ~1–2 GB por camada, partições pequenas (por mês) limitam o tamanho real dos arquivos — por isso partição entra na matriz junto com o tamanho de arquivo.
- O resultado do B6 define os padrões usados nas demais suítes (registrado em §14).

### 10.5 Queries de leitura (D1)
1. Contagem de observações por ano.
2. Média de `tmax` por país e mês (ano filtrado).
3. Top 20 estações por precipitação total em um ano.
4. Join fato × `dim_station` com filtro geográfico (bounding box).
5. Média móvel 7 dias de `tmax` para N estações (window function).
6. Lookup pontual: uma estação, intervalo de 30 dias.

Perguntas só via Cube (B4/B5), que geram SQL mais pesado (CTEs, window, subqueries):

7. Mediana e p95 de `tmax` por país em um ano.
8. Mediana entre estações da precipitação anual (agregado aninhado).
9. Share da precipitação por país sobre o total.
10. Variação ano contra ano de `avg_tmax` por país, mês a mês.

D2: 22 queries TPC-H (dialeto ajustado por engine, semântica igual).

### 10.6 Protocolo
- Nunca dois engines ao mesmo tempo. Nas leituras (B3–B5), uma query por vez.
- **Cold:** reiniciar o engine e limpar os caches → 1 execução.
- **Warm:** 1 warm-up descartado + **5 execuções** medidas.
- Timeout: 300 s por query (registra `timeout` e segue).
- Validar o resultado (row count + checksum) contra a referência DuckDB; resultado divergente invalida a medição.
- Coletar `docker stats` (CPU/mem) durante cada execução.

### 10.7 Formato dos resultados
`results/<suite>.parquet`, uma linha por etapa/execução:
`run_id, ts, suite, scenario, step, dataset, engine, engine_version, engine_config, profile, strategy, query_id, batch, run_type, latency_ms, rows, files_written, checksum_ok, status, peak_mem_mb, avg_cpu_pct, file_count, storage_bytes, notes`

Relatório: script DuckDB que gera p50/p95 por engine × perfil × cenário e o tempo por etapa da transformação.

### 10.8 Observabilidade e linhagem (fase 4)

| Tema | Escolha | Como integra |
|---|---|---|
| Métricas de recursos | **cAdvisor + Prometheus + Grafana** | Substitui a amostragem de `docker stats` no harness (scrape de 1 s só durante a medição). |
| Métricas dos engines | endpoints Prometheus/OpenMetrics nativos | Trino (`/metrics`), StarRocks FE/BE (`/metrics`), Spark (`spark.ui.prometheus.enabled`), Lakekeeper. ⚠️ V7: confirmar endpoint de cada versão. |
| Linhagem | **OpenLineage + Marquez** | dbt via `dbt-ol`, Spark via listener `openlineage-spark`, Airflow 3 via provider OpenLineage, Trino via event listener OpenLineage. |
| Qualidade de dados | **Elementary** (pacote dbt) | Histórico de testes, anomalias de volume/freshness e relatório HTML. |
| Linhagem no dbt | `dbt docs` | Já disponível sem infra extra. |

- Catálogos completos (OpenMetadata, DataHub) ficam fora: pesados para uma stack local; reavaliar se precisar de busca/governança.
- Durante as suítes medidas, a coleta de métricas roda com o mesmo intervalo em todos os engines, para o custo da coleta ser igual.

## 11. Convenções de código

Regras completas em `.claude/rules/code-style.md` e `.claude/rules/benchmark-integrity.md` (fonte única). Resumo:

- Legibilidade primeiro: nomes claros, funções pequenas, sem abstrações especulativas.
- Comentários só quando explicam o *porquê*; nada de comentário que repete o código.
- Compose: um arquivo por domínio, ligados por `include`; `profiles` por engine; limites via variáveis com default (`${TRINO_CPUS:-4}`) e perfis S/M/L em `env/*.env`.
- Versões e credenciais locais em `.env` (com `.env.example` versionado).
- Scripts idempotentes: rodar duas vezes não duplica dados nem quebra.
- Uma entrada por tarefa no `Makefile`; o `Makefile` é a documentação executável.
- **Bash legível acima de compacto:** variáveis com nomes claros (`engine`, `batch_id`, `target_namespace`), um comando por linha, sem loops aninhados nem one-liners encadeados. Se a lógica passar de poucas linhas, vai para `scripts/<tarefa>.sh` (com `set -euo pipefail`) e o `Makefile` só chama o script.
- SQL: SQLFluff 3.x com templater dbt e dialeto por engine; `pre-commit` com SQLFluff e checagem de bash.
- **Python no mesmo espírito:** sem comprehensions aninhadas nem truques de uma linha; laços explícitos e funções com nome que explica o que fazem.

## 12. Estrutura do repositório

```
compose.yaml              # só include dos arquivos abaixo
compose/
  storage.yaml            # rustfs, postgres, lakekeeper
  engines.yaml            # trino, spark, starrocks (profiles)
  serving.yaml            # cube, cubestore (profiles)
  proxy.yaml              # traefik (UIs)
  orchestration.yaml      # airflow (fase 3)
  observability.yaml      # prometheus, grafana, cadvisor, marquez (fase 4)
config/                   # trino/, spark/, starrocks/, lakekeeper/
env/                      # s.env, m.env, l.env
.env.example
Makefile
scripts/                  # bash chamado pelo Makefile
ingest/                   # DuckDB: download, lotes, escrita bronze
dbt/                      # projeto único; profiles por engine
cube/                     # schema Cube
bench/                    # harness, queries/, sql/ (MVs, manutenção), results/
spikes/                   # provas descartáveis dos itens V* (§15)
CLAUDE.md, .claude/       # regras, agents (workers) e hooks do Claude Code
docs/SPEC.md
docs/SPEC.en.md           # ao estabilizar
```

## 13. Fases e critérios de aceite

| Fase | Entrega | Pronto quando |
|---|---|---|
| **0 — Specs** | Este documento | Aprovado; pendências viram spikes (§15) |
| **1 — MVP lakehouse** | Spikes V1/V4; storage + Lakekeeper + Trino + Traefik; ingestão D1 (1 ano → dimensionar); dbt-trino bronze→gold com testes; Cube sobre Trino | `make up ingest dbt` do zero sem erro; testes dbt passam; Cube responde às 6 perguntas; `storage-report` dentro do teto |
| **2 — Benchmark** | Harness; Spark e Postgres no B2; StarRocks, DuckDB, Postgres como readers; D2; B5 (MVs + Cube Store); B6 | B1–B6 geram `results/*.parquet` no perfil `M`; relatório gerado |
| **3 — Orquestração** | Airflow 3 + Cosmos (`ExecutionMode.WATCHER`, CeleryExecutor) executando o fluxo do §9 | DAG ponta a ponta; tempos por model ≈ fase 2; overhead do orquestrador registrado |
| **4 — Extras** | R2 (+ R2 Data Catalog); Superset via Cube; observabilidade e linhagem (§10.8); Polaris; Airbyte se necessário; `SPEC.en.md` | Resultado documentado por item |
| **5 — Comparação de orquestração** | Dagster + dbt (`dagster-dbt`) executando o mesmo fluxo | Overhead Dagster × Airflow/Cosmos documentado |
| **6 — Publicação** | README em inglês, resultados, gráficos, artigo (§16); CI no GitHub Actions (`docker compose config`, SQLFluff, `dbt parse`) | Repo público; CI verde; qualquer pessoa reproduz com `make` |
| **Futuro** | Iceberg v3; dbt Core v2 | — |

## 14. Decisões registradas

| # | Decisão | Motivo |
|---|---|---|
| D-01 | Docker Compose (`include` + `profiles`) em vez de Swarm | Limites de recurso nativos; preferência do time. |
| D-02 | DuckDB na ingestão; Airbyte só se precisar de conectores | Airbyte exige k8s e ~8 GB só para rodar. |
| D-03 | Writers: Trino e Spark, em namespaces próprios; readers usam `trino_gold` por padrão | Comparar transformação sem misturar arquivos; leitura sobre os mesmos dados. |
| D-04 | StarRocks somente leitura | É onde ele é forte; escrita em Iceberg via dbt é imatura. |
| D-05 | Lakekeeper único, warehouse `lakehouse`, namespaces `<engine>_<camada>` | Um catálogo, rastreabilidade de quem escreveu cada tabela. |
| D-06 | RustFS local; R2 como cenário separado | Latência de rede contaminaria o benchmark local. |
| D-07 | Cube só com drivers oficiais (StarRocks via MySQL); sem Spark | Menos risco; o protocolo MySQL do StarRocks é compatível com o driver oficial. |
| D-08 | Aceleração: StarRocks MV (tabelão do Cube, rewrite forçado) × Trino MV × Cube Store | Objetivo explícito do projeto. |
| D-09 | ≤ 10 GB por execução (um writer); comparação multi-engine só local | Free tier do R2. |
| D-10 | dbt Core 1.x | v2 sem adapter Trino/Postgres confirmado. |
| D-11 | Traefik só para UIs HTTP; harness dentro da rede do Compose | Evita expor portas sem colocar proxy no caminho medido. |
| D-12 | **Iceberg v2** | Trino ainda não escreve v3 (leitura experimental); StarRocks 4.1 rejeita tabelas v3 com deletion vectors; suporte do Lakekeeper não confirmado. |
| D-13 | Spark 4.1.x + Iceberg ≥ 1.11 (Scala 2.13), `local[N]` ajustado ao perfil | Versão mais recente; um JVM evita overhead de cluster em um nó. |
| D-14 | Um engine por vez; dbt com `threads` igual para todos; medição por model | Comparação justa sem disputa entre engines; o paralelismo interno é mérito de cada engine. |
| D-15 | Codec/tamanho de arquivo/partição definidos pelo B6 | Escolha baseada em medição, não em suposição. |
| D-16 | Uma instância do Cube com multi data source; cubes gerados por template | Um só schema para todos os engines, sem duplicar definições. |
| D-17 | Medidas de rollup sempre `CAST AS DOUBLE` | Drivers truncam DECIMAL a 5 casas no Cube Store. |
| D-18 | Cube lê só pelos engines, sem integração com dbt | O benchmark mede o caminho engine → Cube; schema do Cube independente. |
| D-19 | Medidas avançadas via recursos nativos do Cube (multi-stage, `time_shift`, `sub_query`) | Abordagem atual recomendada pelo Cube; gera SQL mais exigente para os engines. |
| D-20 | Manutenção numa macro única: post-hook no uso normal, desligada e medida à parte nos benchmarks | Um só código para operação e benchmark; tempo dos models não é contaminado. |

## 15. Validações pendentes (spikes)

| # | Validação | Quando | Fallback |
|---|---|---|---|
| V1 | DuckDB escreve Iceberg via REST (Lakekeeper) | Fase 1, início | Parquet no S3 + CTAS via Trino |
| V2 | Trino MV no conector Iceberg com catálogo REST | Fase 2 | Tabela equivalente via dbt |
| V3 | StarRocks reescreve automaticamente para MV de join sobre Iceberg | Fase 2 | Documentar limitação; Cube aponta para a MV |
| V4 | ✅ Resolvido: dbt-trino suporta `microbatch` desde 1.9.0; `concurrent_batches` desde 1.10.2 (detalhes em `spikes/V4/README.md`). A validar na prática: `event_time` DATE comparado com literais TIMESTAMP e conflitos de commit com `concurrent_batches` | Fase 1 | — |
| V5 | Limites atuais do free tier do R2 (storage, ops Class A/B) | Antes da fase 4 | Reduzir repetições/volume |
| V6 | Iceberg v3: escrita no Trino, deletion vectors no StarRocks, suporte no Lakekeeper | Revisão periódica | Manter v2 |
| V7 | Endpoints de métricas e integração OpenLineage de cada engine na versão pinada | Fase 4 | Manter só cAdvisor + `dbt-ol` |
| V8 | Cosmos `ExecutionMode.WATCHER` com Airflow 3 + CeleryExecutor + dbt-trino/dbt-spark | Fase 3 | `ExecutionMode.LOCAL` com `DbtTaskGroup` |
| V9 | Medidas multi-stage e não aditivas do Cube com pre-aggregations no Cube Store | Fase 2 | Q7–Q10 ficam fora do B5c e o motivo é documentado |

## 16. Publicação

| Entrega | Conteúdo |
|---|---|
| Repositório público | Código em inglês, `README.md` (arquitetura, como reproduzir, resultados), licença Apache-2.0, `SPEC.en.md`. |
| Resultados | `results/*.parquet` + relatório gerado (tabelas e gráficos) versionados, com versões e `engine_config` de cada execução. |
| Artigo | Blog (versão completa) + post no LinkedIn (resumo com 2–3 gráficos e link). |
| Rascunho | `docs/blog/post.md` — esqueleto do artigo e diário do projeto, atualizado a cada decisão, spike e resultado. |
| Assets | Capa; cards com os números (resultados renderizados como imagem); diagrama da arquitetura; screenshots das UIs; vídeo explicativo da ferramenta e dos benchmarks (skill `/brag`). |

Estrutura do artigo:
1. Motivação e perguntas do estudo.
2. Arquitetura e por que cada peça (link para as decisões §14).
3. Metodologia: perfis de recursos, protocolo cold/warm, validação por checksum, limitações (VM em macOS, nó único).
4. Resultados por suíte (B1–B6) e aceleração (MV × Cube Store).
5. Orquestração: Airflow/Cosmos watcher × Dagster.
6. Conclusões, o que mudaria, como reproduzir.

Cuidados:
- TPC-H: rotular como "derivado do TPC-H, não comparável a resultados TPC-H publicados" (política de fair use do TPC).
- NOAA GHCN-Daily: citar a fonte (dados públicos da NOAA/NCEI).
- Não publicar `.env`, credenciais ou caminhos locais.
