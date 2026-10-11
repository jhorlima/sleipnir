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
- **Memória da VM:** limites de container não são reservas; a VM do Docker precisa caber o perfil do engine + ~3 GB de infra (perfil L → VM ≥ 16 GB). Com 8 GB, só o perfil M sem outros processos pesados ao lado.
- **Um engine sob teste por vez:** nunca duas transformações ao mesmo tempo (ex.: Trino e Spark em paralelo). Dentro de uma execução, o dbt pode rodar models em paralelo com `threads = DBT_THREADS` (**mesmo valor para todos os engines**, padrão 4); o resto do paralelismo fica a cargo de cada engine.
- Números absolutos vêm de uma VM em macOS; o valor está na **comparação relativa**.
- **Disco:** os CSVs são baixados **antes** da ingestão para `LANDING_DIR` (padrão `./landing`; pode apontar para um SSD externo) e o DuckDB lê de lá — download nunca entra na medição. Para mais espaço no lake, mover a **imagem de disco do Docker Desktop** para o SSD (Settings → Resources → Disk image location) e manter os volumes nomeados: bind mount de disco externo passa pelo compartilhamento de arquivos da VM e adicionaria overhead de I/O ao RustFS.
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
| `postgres_bronze/silver/gold` | DuckDB + dbt-postgres | baseline só na escala `small` (D-23), em schemas de um Postgres próprio do benchmark (fora do lake, separado do Postgres do catálogo) |

- **Trino (não padrão, em `config/trino/`):** spill-to-disk ligado e `optimizer.optimize-top-n-ranking=false` — o `ROW_NUMBER() ... = 1` do dedup vira um operador TopNRanking que não faz spill e estoura a memória por query do perfil M.
- **Acesso ao S3 — o mesmo caminho para todos os engines:** o warehouse tem `sts-enabled: false` e `remote-signing-enabled: false`, então todos leem e escrevem com as mesmas chaves S3 estáticas. Sem isso, Spark/PyIceberg cairiam em silêncio no remote signing pelo Lakekeeper, enquanto Trino (sem remote signing para REST), DuckDB e StarRocks (que não suportam) usariam chaves — caminhos de I/O diferentes contaminariam a comparação. Spark envia também `X-Iceberg-Access-Delegation: client-managed`; DuckDB usa `ACCESS_DELEGATION_MODE 'none'` + secret S3. Warehouse com `key-prefix: lakehouse` e `delete-profile: hard`.
- Os readers diretos (B3) leem `trino_gold` por padrão (`GOLD_NAMESPACE`); no Cube o namespace é fixo em cada arquivo de engine. Cenário extra: ler `spark_gold` para medir o efeito do layout gerado por cada writer.

## 4. Componentes

| Camada | Escolha | Futuro / alternativa | Notas |
|---|---|---|---|
| Object storage | **RustFS** | R2 (fase 6) | MinIO community descontinuado. |
| Catálogo | **Lakekeeper** (Iceberg REST) | Polaris, R2 Data Catalog | Backend Postgres. |
| Formato | **Parquet + Iceberg v2** | Iceberg v3 (V6) | Codec e tamanho de arquivo definidos pelo B6. |
| Ingestão | **DuckDB 1.5** | Airbyte (se precisar de conectores) | Escreve Iceberg v2 direto no Lakekeeper (V1). |
| Transformação | **dbt Core 1.12** + dbt-trino 1.10 (Trino 483) | dbt Core v2 quando houver adapter Trino/Postgres | `dbt-trino`, `dbt-spark`, `dbt-postgres`. |
| Engines de transformação | **Trino**, **Spark 4.1.x** | — | Postgres como baseline na escala `small`. |
| Engines de leitura | **StarRocks**, Trino, DuckDB, Postgres | — | StarRocks via external catalog. |
| Aceleração | **StarRocks async MV**, Trino MV, **Cube Store** | — | §10.3. |
| Semantic layer | **Cube** | — | Drivers oficiais: Trino, DuckDB, Postgres; StarRocks via driver MySQL. Sem Spark. |
| Orquestração | **Makefile** (fases 1–2) → Airflow 3 + Cosmos | Dagster | |
| Proxy | **Traefik** (apenas UIs) | — | §2. |
| BI | Superset via SQL API do Cube (fase 4) | — | |

Versões pinadas em `.env`; nenhuma tag `latest`.

### 4.1 Spark 4.1.x
- Imagem do projeto (`config/spark/Dockerfile`): `apache/spark:4.1.3-scala2.13-java21-ubuntu` + `iceberg-spark-runtime-4.1_2.13` e `iceberg-aws-bundle` do Iceberg 1.12.0, embutidos (nada é baixado durante uma medição). dbt-spark 1.11.0 com PyHive.
- O PyHive sempre envia `USE default`, então o Thrift Server cria um namespace `lakehouse.default` vazio ao subir (também visível no Trino); o healthcheck conecta nele.
- O `remove_orphan_files` do Spark não aceita retenção abaixo de 24 h; no Spark ela é de 25 h (no Trino, 0 s), e a diferença é registrada junto dos números do B6.
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

### Evolução da ingestão (depois que o fluxo estiver validado)
Adicionar uma fonte nova não deve exigir código novo:
- **Uma fonte = um arquivo de configuração** (`ingest/sources/<nome>.yaml`): URLs/padrão de arquivos, formato (CSV, gzip, fixed-width), colunas e tipos, regra de lotes, tabela de destino em `duckdb_bronze` e partição.
- **Um único comando genérico** na imagem `sleipnir-ingest`: `ingest run --source <nome> [--batch <id>]`, com download e carga idempotentes.
- **Orquestração:** uma task por fonte no Airflow/Dagster via `DockerOperator` chamando essa imagem (DuckDB → Iceberg no S3), sem dependências de ingestão na imagem do orquestrador.
- GHCN-Daily passa a ser a primeira fonte descrita nesse formato.

### Simulação de duplicados
Ingestão em **lotes incrementais com janela sobreposta**: cada lote `n` inclui os últimos 7 dias do lote `n-1`, mais ~1% de linhas reemitidas com `value` alterado (simula revisão da fonte). A revisão **substitui** a cópia sobreposta dentro do lote (uma linha por chave por lote), para que "vence o maior `_ingested_at`" nunca empate. Chave natural: `(station_id, date, element)`; vence o maior `_ingested_at`. Como `date` faz parte da chave, um duplicado sempre cai no mesmo batch temporal — isso viabiliza microbatch/insert_overwrite sem perder o dedup.

## 6. Orçamento de storage (≤ 10 GB)

| Item | Teto |
|---|---|
| D1 — `duckdb_bronze` + silver/gold de **um** engine | 6,5 GB |
| D2 — TPC-H | 2 GB |
| Metadados Iceberg, `bench_*`, margem | 1,5 GB |
| **Total no bucket** | **≤ 10 GB** |

Regras:
- O teto vale para **uma execução** (bronze + silver/gold de um único writer + D2). Comparar vários writers lado a lado é feito **localmente**, onde não há teto.
- **Duas escalas de dados**, escolhidas por `DATA_SCALE`. Resultados de escalas diferentes nunca são comparados entre si; `results` registra a escala de cada execução.

| Escala | D1 (GHCN) | Download | Lotes `.csv.gz` | Bronze | Lakehouse (bronze + 1 writer) | Status |
|---|---|---|---|---|---|---|
| `r2` (padrão) | hoje 2010–2025: 192 lotes mensais, 741,9 M linhas no bronze. **Meta: ≥ 1 bi linhas no bronze dentro do teto**; anos ampliados depois do B6 | 2,81 GB | 3,36 GB | 1,98 GB | **3,75 GB** (silver 1,02, gold 0,75) + D2 ≤ 2 GB | Medida pelo `make storage-report` |
| `small` | só 2025: 12 lotes mensais, ~44 M linhas no bronze | 0,17 GB | ~0,2 GB | ~0,12 GB | ~0,23 GB (no Postgres: ~6 GB) | Medida na fase 1; escala da comparação com o Postgres (D-23) |
| `local` | histórico completo, 1750–2025 | ~14,4 GB | ~17 GB | ~10 GB | ~19 GB | Estimada; carga na etapa 10 de [`specs/phase-2.md`](specs/phase-2.md), com aviso de disco antes |

  - **Meta da `r2`: bilhões de linhas dentro de 10 GB.** Na `r2` atual o bronze ocupa ~2,7 bytes/linha e o lakehouse 3,75 GB, só ~38% do orçamento. O teto de 6,5 GB do D1 comporta ~1,3 bi linhas no bronze com o layout atual. Se o B6 confirmar o ganho de ordenar antes de gravar (o Parquet caiu à metade na fase 1), comporta mais. As medições começam na `r2` atual; depois do B6, a `r2` é ampliada em anos até encher o teto e as suítes são repetidas ([plano](specs/phase-2.md), etapa 10).
  - A escala `local` é limitada pelo tamanho do histórico, não pelo tempo: o B1 da `r2` levou 142 s de insert (5,2 M linhas/s), então ~30 min de B1 exigiriam muito mais dados do que o GHCN tem. O histórico completo chega a ~20 GB.
  - Os lotes de `landing/batches` são `.csv.gz` (3,4 GB em vez de ~25 GB). O DuckDB lê gzip na mesma vazão do CSV puro, e gerar os lotes (fora da medição) leva ~1 min por ano.
  - A partir da `r2`, silver e gold são construídos do zero mês a mês (`make dbt-backfill`, D-21).
- Fora do bucket: `landing/` (CSV em disco local), baseline Postgres, MVs do StarRocks (storage local do BE) e Cube Store.
- **Dimensionamento empírico do D2:** gerar SF1, medir e escalar o SF até o teto de 2 GB.
- Manutenção após cada carga (§10.4): snapshots antigos contam no orçamento.
- `make storage-report ENGINE=<engine>` mostra o uso por namespace e falha se bronze + `<engine>_*` + D2 passar do teto.
- ⚠️ V5: confirmar os limites atuais do free tier do R2 (storage e operações Class A/B) e estimar os GETs do benchmark antes de rodar no R2.

## 7. Modelo de dados (medalhão)

### Bronze — cópia fiel da fonte (`duckdb_bronze`)
- `ghcn_daily_raw` — colunas da fonte + `_source_file`, `_batch_id`, `_ingested_at`. **Append-only**, particionado por `_batch_id`. Criada com `CREATE TABLE ... PARTITIONED BY (_batch_id) WITH ('format-version'='2', 'write.parquet.compression-codec'=...)` e carregada com `INSERT` (o codec padrão do DuckDB é snappy; o valor vem do B6). O DuckDB nomeia o campo de partição `identity__batch_id_<id>` — o Trino lê e poda essas partições normalmente; Spark e StarRocks são validados na fase 2.
- `ghcn_stations_raw`, `ghcn_countries_raw` — substituídas a cada carga (são pequenas).

### Silver — limpo, tipado, deduplicado (`<engine>_silver`)
- `ghcn_daily` — só os elementos `TMAX, TMIN, PRCP, SNOW, SNWD`; tipos corretos; `value` convertido (TMAX/TMIN em décimos de °C e PRCP em décimos de mm → unidades; SNOW/SNWD já vêm em mm); **dedup** pela chave natural; o filtro de QC (`q_flag` preenchido) roda depois do dedup, para uma revisão reprovada esconder a versão anterior. Incremental (estratégia em §7.1). Partição `month(date)` (granularidade validada no B6).
- `stations` — parse do fixed-width, país via `ghcnd-countries`.

### Gold — marts (`<engine>_gold`)
- `dim_station`, `dim_date` — `table` (recriadas; são pequenas).
- `fct_weather_daily` — 1 linha por estação/dia, pivot de `TMAX, TMIN, PRCP, SNOW`. Incremental.
- `agg_weather_monthly_country` — agregado mensal por país. Incremental por mês.

### 7.1 Estratégias incrementais (matriz do B2)
Bronze é sempre `append`. Nas camadas silver/gold, cada estratégia suportada é medida por engine; a vencedora vira o padrão daquele engine. Padrão atual: **`delete+insert`** no Trino e **`merge`** no Spark (que não tem delete+insert), escolhido pelo target na var `incremental_strategy` (janela derivada dos dados, substitui datas inteiras). O microbatch do dbt é guiado pelo relógio: em dados históricos precisa de `--event-time-start/--event-time-end` explícitos.

| Estratégia | Trino | Spark | Postgres | Observação |
|---|---|---|---|---|
| `merge` (chave natural) | ✅ | ✅ | ✅ | Referência. No Spark, testar `write.merge.mode` copy-on-write × merge-on-read. |
| `delete+insert` | ✅ | — | ✅ | Apaga a janela afetada e reinsere. |
| `insert_overwrite` (partição) | — | ✅ | — | Reescreve só as partições tocadas pelo lote. |
| `microbatch` (`event_time = date`, `batch_size = month`) | ✅ | ✅ | ✅ | `concurrent_batches` com o mesmo valor em todos os engines. Tempo medido **por batch**. |

- No Trino, o microbatch é `DELETE` + `INSERT` por batch filtrado por `event_time` (ignora `unique_key`; usa tabela temporária). Cada batch gera dois snapshots e position deletes, então a manutenção (§10.4) pesa mais nessa estratégia.
- Janela incremental: datas presentes no último `_batch_id` + `lookback` igual à sobreposição dos lotes (7 dias).
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
| Unicidade de `(station_id, date, element)` | `silver.ghcn_daily` | Teste singular só na janela que a última execução pode ter gravado (mês mais recente + 2 × overlap). A tabela inteira é checada ano a ano pela macro `assert_unique_by_year`, fora da medição, porque um `GROUP BY` único estoura o spill no perfil `M` a partir da `r2` |
| `unique` + `not_null` | PKs do gold | — |
| `relationships` | fato → dims | — |
| `accepted_values` | `element` | `TMAX, TMIN, PRCP, SNOW, SNWD` |
| `accepted_range` (dbt_utils) | silver/gold | `tmax`, `tmin` entre −90 e 60 °C; `prcp ≥ 0`; `latitude` −90..90; `longitude` −180..180 |
| `expression_is_true` (dbt_utils) | `fct_weather_daily` | `tmax >= tmin` (quando ambos existem) |
| Teste singular | silver × bronze | dedup nunca aumenta linhas (`dbt_utils.fewer_rows_than` não funciona no Trino) |
| Teste singular | `fct_weather_daily` | a fato alcança a última data do lote mais recente do bronze (`dbt_utils.recency` compara com o relógio, inútil para dados históricos) |
| **Unit tests** (dbt ≥ 1.8) | `silver.ghcn_daily` | dedup (vence o maior `_ingested_at`) e conversão de unidades |
| `source freshness` | `duckdb_bronze.ghcn_daily_raw` | por `_ingested_at` |

## 8. Semantic layer (Cube)

Regras de modelagem em `.claude/rules/cube-models.md`.

O Cube lê **somente pelos engines** (SQL nas tabelas gold). Ele não importa nem depende de artefatos do dbt (manifest, semantic models); o schema do Cube é mantido à parte.

### 8.1 Deploy
- Cube e Cube Store na **mesma versão** (`v1.7.50`, uma única variável `CUBE_VERSION`); imagem do Cube Store com `${CUBESTORE_ARCH_SUFFIX}` (`-arm64v8` no Apple Silicon).
- Serviços: `cube-api` (REST + SQL API, `CUBEJS_REFRESH_WORKER=false`), `cube-refresh-worker` (`CUBEJS_REFRESH_WORKER=true`), `cubestore-router` + `cubestore-worker` (1 worker local). Env comum via anchor `x-cube-env-common`.
- Flags: `CUBEJS_TESSERACT_SQL_PLANNER=true`, `CUBEJS_SCHEDULED_REFRESH_TIMEZONES=UTC`, `CUBEJS_DEV_MODE=false` nas execuções medidas.
- Modelos só em YAML.

### 8.2 Data sources
Uma única instância do Cube com **multi data source**:
`CUBEJS_DATASOURCES=default,trino,starrocks,duckdb,postgres` (hoje: `default,trino,duckdb`) + `CUBEJS_DS_<NOME>_DB_{TYPE,HOST,PORT,NAME,USER,PASS}`.

| Data source | Driver | Observação |
|---|---|---|
| `trino` | `trino` | catálogo `lakehouse`, tabelas `lakehouse.trino_gold.*` |
| `starrocks` | `mysql` (porta 9030 do FE) | nomes em três partes: `lakehouse.<gold_namespace>.<tabela>` |
| `duckdb` | `duckdb` | DuckDB 1.5.5 **embutido no processo do Cube** (a ingestão usa 1.5.6). Extensões via `CUBEJS_DS_DUCKDB_DB_DUCKDB_EXTENSIONS`; `CREATE SECRET` + `ATTACH` no Lakekeeper exigem um `driverFactory` no `cube.js` (V13). Usa os limites de CPU/memória do container do Cube; nas medições valem os do perfil (D-22). `cube/cube.js` monta o init SQL; o Cube depende do Lakekeeper saudável, porque um init SQL que falha fica em cache |
| `postgres` | `postgres` | schema `postgres_gold` do Postgres do benchmark; só na escala `small` |

- O `data_source` é fixo em cada cube. Os membros são escritos uma vez em `cube/model/cubes/base/` (cubes `base_*`, data source placeholder, não públicos) e cada engine tem arquivos curtos em `cube/model/cubes/<engine>/` com `extends`, `data_source`, `sql_table` e só o que difere (percentis, joins e referências a outros cubes, que o `extends` não renomeia). Nomes com prefixo: `trino_weather_daily`, `starrocks_weather_daily`, etc. Sem Jinja.
- Joins e rollups não cruzam data sources (limitação do Cube; irrelevante aqui).

### 8.3 Modelo
Cubes (internos, `public: false`): `weather_daily` (sobre `fct_weather_daily`), `stations`, `dates`. Views públicas: `<ds>_weather`.

| Tipo | Itens |
|---|---|
| Medidas | `avg_tmax`, `avg_tmin`, `total_prcp`, `days_with_rain`, `station_count`, `observation_count` |
| Dimensões | `country`, `station_id`, `elevation`, `latitude`, `longitude`, `date` (day/month/year) |
| Derivadas | `temp_range = avg_tmax - avg_tmin`, `rain_day_ratio = days_with_rain / observation_count` |
| Janela móvel | `avg_tmax_7d` (`rolling_window` trailing 7 day; Q5) |
| Percentis | `median_tmax`, `p95_tmax`, `p95_prcp` — `type: number` com a função de cada engine (Trino `approx_percentile`, StarRocks `PERCENTILE_CONT(x, p)`, DuckDB/Postgres `PERCENTILE_CONT(p) WITHIN GROUP (ORDER BY x)`) |
| Agregado aninhado | `median_station_annual_prcp` — soma anual por estação no cube interno `station_years` (estação × ano, dimensão `sub_query: true`), mediana entre estações |
| Share of total | `prcp_share_of_total` — multi-stage, helper `grain: keep_only: []`, `format: percent`; `prcp_share_of_country` com `keep_only: [country]` (também remove o grão de tempo do denominador) |
| Period-over-period | `avg_tmax_prior_year` (`time_shift` 1 year prior), `tmax_yoy_delta`, `prcp_mom_ratio` (1 month prior) |

- Multi-stage (`multi_stage`, `grain`, `time_shift`) depende do Tesseract, ligado por padrão a partir do Cube 1.7. Queries multi-stage podem trazer linhas extras do período deslocado com medidas NULL.
- O data source `default` é obrigatório no Cube: aponta para um DuckDB em memória que nenhum cube usa.
- `approx_percentile` (Trino) não é determinístico: Q7/Q8 são validadas com tolerância (§10.6).
- Medidas não aditivas (percentis, mediana) não são reagregadas pelo Cube Store; só usam rollup se ele tiver exatamente a mesma granularidade da query (⚠️ V9).
- **Precisão em pre-aggregations:** os drivers SQL do Cube mandam DECIMAL para o Cube Store como `Decimal(18,5)` (trunca em 5 casas; `CUBEJS_DB_PRECISE_DECIMAL_IN_CUBESTORE` não resolve). Toda medida que entra em rollup é feita com `CAST(... AS DOUBLE)` (`DOUBLE PRECISION` no Postgres). Detalhes em `.claude/rules/cube-models.md`.
- Sintaxe específica por engine (ex.: `PERCENTILE_CONT` no StarRocks recebe 2 argumentos) fica no arquivo daquele engine, sobrescrevendo o membro da base.

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
| **B5a** | **StarRocks async MVs, uma por tabela do gold** (D-24): `mv_fct_weather_daily`, `mv_dim_station`, `mv_dim_date`, cada uma a cópia da tabela com todas as colunas, sem join e sem agregação. Propriedade `force_external_table_query_rewrite = true`; sessão com `enable_materialized_view_rewrite = true` e `enable_materialized_view_union_rewrite = false` (bug #79345). | O Cube continua lendo os marts; o otimizador do StarRocks reescreve a query para a MV. |
| **B5b** | **Tabela equivalente à MV** no Trino: model dbt `table` `trino_gold.mv_weather_wide` com o mesmo SQL do B5a. O Trino 483 não cria MV no catálogo REST (V2). O "refresh" medido é `dbt run --select mv_weather_wide` | O Cube aponta para a tabela via `sql_table`, sem reescrita. |
| **B5c** | **Cube Store** pre-aggregations (país × mês, estação × ano) sobre Trino e sobre StarRocks. | O Cube roteia para o Cube Store. |

- DDL do B5a: `PARTITION BY date_trunc('month', date)`, `DISTRIBUTED BY HASH(station_id)` com buckets pelo volume (< 5M linhas → 4; 5–50M → 8; 50–200M → 16; > 200M → 32), `ORDER BY` pelas dimensões filtradas, `REFRESH DEFERRED MANUAL` (sem `DEFERRED`, a criação já popula a MV e o primeiro refresh medido não faz nada). Não existe `CREATE OR REPLACE` para MV: recriar é `DROP` + `CREATE`. DDL em `bench/sql/`. Os arquivos de uma MV apagada ficam na lixeira do BE por 1 h (`catalog_trash_expire_second`).
- Refresh **depois da transformação e antes da leitura** (passo 6 do §9), com `WITH SYNC MODE` e `SET query_timeout = 3600` na mesma sessão (o SYNC é morto em 300 s), e medido. Depois do refresh o BE compacta por ~10 min; a leitura só começa quando a CPU do container cai abaixo de 10%, senão as queries falham por memória. Na `r2`, a MV larga da prova do V3 levou 540–589 s de refresh e ocupou 4,8 GB depois da compactação (storage local do BE, fora do bucket).
- Evolução possível: MVs com as agregações que o Cube usa (país × mês, estação × ano), se o StarRocks reescrever as queries do Cube para elas; avaliar depois do B5a com as MVs por tabela.
- Sem a MV, o StarRocks cai silenciosamente na tabela base. Por isso o B4 do StarRocks (sem MV) é a linha de base do B5a, e o `EXPLAIN` confirma qual dos dois caminhos rodou.
- **Validação obrigatória no B5a:** o `EXPLAIN` de cada query precisa mostrar as MVs no lugar de cada tabela lida; se a reescrita não ocorrer, a medição é marcada como inválida.
- A Q5 (janela móvel de 7 dias) não roda no StarRocks via Cube: o Cube gera `WITH RECURSIVE` e `CAST(... AS DATETIME(6))`, que o StarRocks 4.1.6 não aceita. Fica registrada como não suportada.
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
| Ordenação (*cluster by*) de `fct_weather_daily` | nenhuma; `sorted_by (station_id, date)` (Trino) / `WRITE ORDERED BY` (Spark); z-order `(station_id, date)` via `rewrite_data_files(strategy => 'sort')` no Spark |

- Hipótese a validar: **zstd** é o melhor equilíbrio entre tamanho e velocidade de leitura; gzip comprime parecido, mas descomprime mais devagar; snappy é o maior em disco. Com ~1–2 GB por camada, partições pequenas (por mês) limitam o tamanho real dos arquivos — por isso partição entra na matriz junto com o tamanho de arquivo.
- O resultado do B6 define os padrões usados nas demais suítes (registrado em §14).

### 10.5 Queries de leitura (D1)
1. Contagem de observações por ano.
2. Média de `tmax` por país e mês (ano filtrado).
3. Top 20 estações por precipitação total em um ano, só entre estações com precipitação (filtro `set` na medida: no `ORDER BY ... DESC` o Postgres põe os NULLs primeiro, e os outros engines por último).
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
- Validar o resultado (row count + checksum) contra a referência DuckDB; resultado divergente invalida a medição. Exceção: medidas aproximadas (percentis via `approx_percentile`) são comparadas com tolerância relativa de 5%, e a tolerância é registrada no resultado.
- Coletar `docker stats` (CPU/mem) durante cada execução.

### 10.7 Formato dos resultados
`results/<suite>.parquet`, uma linha por etapa/execução:
`run_id, ts, suite, scenario, step, dataset, data_scale, engine, engine_version, engine_config, profile, strategy, query_id, batch, run_type, latency_ms, rows, files_written, checksum_ok, status, peak_mem_mb, avg_cpu_pct, file_count, storage_bytes, notes`

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
| **0 — Specs** ✅ | Este documento | Aprovado; pendências viram spikes (§15) |
| **1 — MVP lakehouse** ✅ | Spikes V1/V4; storage + Lakekeeper + Trino + Traefik; ingestão D1 (1 ano → dimensionar); dbt-trino bronze→gold com testes; Cube sobre Trino | `make up ingest dbt` do zero sem erro; testes dbt passam; Cube responde às 6 perguntas; `storage-report` dentro do teto |
| **2 — Benchmark** ([plano](specs/phase-2.md)) | Carga das escalas `r2` (GHCN 2010–2025) e `local` (§6); harness; Spark e Postgres no B2; StarRocks, DuckDB, Postgres como readers; D2; B5 (MVs + Cube Store); B6 | B1–B6 geram `results/*.parquet` no perfil `M`; relatório gerado |
| **3 — Orquestração** | Airflow 3 + Cosmos (`ExecutionMode.WATCHER`, CeleryExecutor) executando o fluxo do §9; tarefas que não são dbt (ingestão DuckDB, manutenção, refresh de MV, harness) rodam como **containers** via `DockerOperator` com imagens do projeto, para a imagem do Airflow ter só Cosmos, o provider Docker e as connections dos engines | DAG ponta a ponta; tempos por model ≈ fase 2; overhead do orquestrador registrado |
| **4 — Extras** | Superset via Cube; observabilidade e linhagem (§10.8); Polaris; Airbyte se necessário; `SPEC.en.md` | Resultado documentado por item |
| **5 — Comparação de orquestração** | Dagster + dbt (`dagster-dbt`) executando o mesmo fluxo | Overhead Dagster × Airflow/Cosmos documentado |
| **6 — Cloudflare R2** | A escala `r2` final (≥ 1 bi linhas no bronze) rodando com o bucket no R2 (+ R2 Data Catalog), depois de todas as fases locais | B1–B5 no R2 comparados com os mesmos passos no RustFS local; custo de operações dentro do free tier (V5) |
| **7 — Publicação** | README em inglês, resultados, gráficos, artigo (§16); CI no GitHub Actions (`docker compose config`, SQLFluff, `dbt parse`) | Repo público; CI verde; qualquer pessoa reproduz com `make` |
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
| D-13 | Spark 4.1.3 + Iceberg 1.12.0 (Scala 2.13) + dbt-spark 1.11.0 (Thrift), `local[N]` ajustado ao perfil | Versão mais recente; um JVM evita overhead de cluster em um nó. |
| D-14 | Um engine por vez; dbt com `threads` igual para todos; medição por model | Comparação justa sem disputa entre engines; o paralelismo interno é mérito de cada engine. |
| D-15 | Codec/tamanho de arquivo/partição definidos pelo B6 | Escolha baseada em medição, não em suposição. |
| D-16 | Uma instância do Cube com multi data source; membros na base e engines via `extends` | Semântica idêntica entre engines sem template; cada arquivo de engine mostra só o que difere. |
| D-17 | Medidas de rollup sempre `CAST AS DOUBLE` | Drivers truncam DECIMAL a 5 casas no Cube Store. |
| D-18 | Cube lê só pelos engines, sem integração com dbt | O benchmark mede o caminho engine → Cube; schema do Cube independente. |
| D-19 | Medidas avançadas via recursos nativos do Cube (multi-stage, `time_shift`, `sub_query`) | Abordagem atual recomendada pelo Cube; gera SQL mais exigente para os engines. |
| D-20 | Manutenção numa macro única: post-hook no uso normal, desligada e medida à parte nos benchmarks | Um só código para operação e benchmark; tempo dos models não é contaminado. |
| D-21 | Construção do zero em janelas mensais (`make dbt-backfill`: microbatch e manutenção uma vez por tabela) | Na `r2`, o dedup do silver numa query só (~740 M linhas) e o teste de unicidade da tabela inteira estouram o spill de 10 GB do perfil `M`. Por mês, cada lote leva 2–9 s. |
| D-22 | Nas medições do DuckDB via Cube (B4/B5), o `cube-api` recebe os limites do perfil (`ENGINE_CPUS`/`ENGINE_MEMORY`), e o DuckDB recebe 75% dessa memória e `ENGINE_CPUS` threads; tudo registrado em `engine_config` | O DuckDB roda dentro do processo do Cube. Com os limites padrão do Cube (1 CPU / 1 GB, DuckDB 512 MB), a Q8 estoura a memória na `r2`. O overhead do Node fica dentro do mesmo orçamento, e isso é citado junto dos números. |
| D-23 | Postgres (writer e reader) só na escala `small` (GHCN 2025), num container próprio (`postgres-bench`, perfil `postgres`, auth `trust` só na rede do Compose) com os limites do perfil e `shared_buffers`/`effective_cache_size`/`work_mem` derivados dele (`config/postgres-bench/entrypoint.sh`); tabelas sem partição; o bronze é copiado do Iceberg pelo DuckDB (`make postgres-load`); nessa escala todos os engines rodam B2/B3 para a comparação | Em linhas, o Postgres usa ~65 bytes/linha contra ~2,7 do Parquet: a `r2` daria ~90 GB e não cabe no disco do Docker. A escala `small` mantém o Postgres como baseline com os mesmos dados que os outros engines. |
| D-24 | B5a com uma MV do StarRocks por tabela do gold (cópia de todas as colunas, sem join e sem agregação), em vez de uma MV larga com os joins | O StarRocks só reescreve para MV de join quando a query junta as mesmas tabelas, e o Cube junta só os cubes usados. Com uma MV por tabela, cada leitura de tabela é trocada pela sua MV, qualquer que seja o join; é o padrão usado em produção pelo autor. O Cube continua lendo os marts, e o storage extra fica no BE, fora do bucket. |

## 15. Validações pendentes (spikes)

| # | Validação | Quando | Fallback |
|---|---|---|---|
| V1 | ✅ Resolvido: DuckDB 1.5.6 escreve Iceberg v2 (CREATE, INSERT, particionado) via Lakekeeper com `ACCESS_DELEGATION_MODE 'none'` + secret S3 estático (detalhes em `spikes/V1/README.md`). Trino 483 lê as tabelas do DuckDB com poda de partição; Spark e StarRocks validados na fase 2 | Fase 1 | — |
| V2 | ✅ Resolvido: **não suportado**. O Trino 483 responde `createMaterializedView is not supported for Iceberg REST catalog` (o `CREATE VIEW` lógico funciona); o código no master é igual. Fallback adotado no B5b (detalhes em `spikes/V2/README.md`). Revalidar a cada upgrade do Trino | Fase 2 | — |
| V3 | ✅ Resolvido (StarRocks 4.1.6, `spikes/V3/README.md` §9): a MV de join é reescrita só quando a query tem **o mesmo formato de join** da MV. O SQL do Cube junta só os cubes usados, então nunca casa com a MV larga; View Delta Join não funcionou com constraints declaradas nas tabelas Iceberg. Resultados iguais com e sem MV (tolerância 1e-9). Adotado: uma MV por tabela, sem join (D-24), a provar com o SQL do Cube | Fase 2 | — |
| V4 | ✅ Resolvido: dbt-trino suporta `microbatch` desde 1.9.0; `concurrent_batches` desde 1.10.2 (detalhes em `spikes/V4/README.md`). A validar na prática: `event_time` DATE comparado com literais TIMESTAMP e conflitos de commit com `concurrent_batches` | Fase 1 | — |
| V5 | Limites atuais do free tier do R2 (storage, ops Class A/B) | Antes da fase 6 | Reduzir repetições/volume |
| V6 | Iceberg v3: escrita no Trino, deletion vectors no StarRocks, suporte no Lakekeeper | Revisão periódica | Manter v2 |
| V7 | Endpoints de métricas e integração OpenLineage de cada engine na versão pinada | Fase 4 | Manter só cAdvisor + `dbt-ol` |
| V8 | Cosmos `ExecutionMode.WATCHER` com Airflow 3 + CeleryExecutor + dbt-trino/dbt-spark | Fase 3 | `ExecutionMode.LOCAL` com `DbtTaskGroup` |
| V9 | Parcial (pesquisa, `spikes/V9/README.md`): Q9 (share, só somas) e Q10 (`time_shift` na granularidade exata país × mês) devem casar com rollups; Q7 (percentis) só num rollup na granularidade exata e com `granularity` na query; Q8 (`sub_query`) sem evidência. A confirmar na prova: se `dateRange` sem `granularity` casa com rollup | Fase 2 | Q7/Q8 ficam fora do B5c e o motivo é documentado |
| V10 | STS do RustFS (AssumeRole) com a session policy do Lakekeeper → vended credentials para todos os engines | Fase 4 | Manter chaves estáticas |
| V11 | Cosmos: `ExecutionMode.WATCHER` (dbt instalado na imagem do Airflow/worker) × `ExecutionMode.DOCKER` (dbt numa imagem própria, uma task por model) — overhead e isolamento | Fase 3 | `DockerOperator` chamando `dbt build` |
| V12 | "Modo seguro": IdP OIDC leve (Dex ou Zitadel) + Lakekeeper com autenticação OIDC (sem OpenFGA) + vended credentials via STS do RustFS (depende do V10); engines com OAuth2 client credentials (DuckDB `CLIENT_ID`/`CLIENT_SECRET`/`OAUTH2_SERVER_URI`). Medido como cenário à parte; o cenário sem auth e com chaves estáticas segue como linha de base | Fase 4 | Manter chaves estáticas sem auth |
| V13 | ✅ Resolvido: o Cube v1.7.50 embute DuckDB 1.5.5 e lê os marts Iceberg via Lakekeeper. Extensões por env; `CREATE SECRET` + `ATTACH` (`ACCESS_DELEGATION_MODE 'none'`) via `driverFactory` em `cube/cube.js`. Q1–Q10 respondem e Q1–Q3 batem com a referência DuckDB direta (detalhes em `spikes/V13/README.md`). Pegadinhas: erro no init SQL é engolido e fica em cache até reiniciar o Cube; `INSTALL` baixa extensões a cada start | Fase 2 | — |

## 16. Publicação

| Entrega | Conteúdo |
|---|---|
| Repositório público | Código em inglês, `README.md` (arquitetura, como reproduzir, resultados), licença Apache-2.0, `SPEC.en.md`. |
| Resultados | `results/*.parquet` + relatório gerado (tabelas e gráficos) versionados, com versões e `engine_config` de cada execução. |
| Artigo | Blog (versão completa) + post no LinkedIn (resumo com 2–3 gráficos e link). |
| Rascunho | `docs/blog/post.md` — esqueleto do artigo e diário do projeto, atualizado a cada decisão, spike e resultado. Escrito em inglês; tradução para PT-BR quando estiver pronto. |
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
