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
- **Memória da VM:** limites de container não são reservas; a VM do Docker precisa caber o perfil do engine + ~2 GB de infra + ~3 GB de Cube/Cube Store. As campanhas no perfil `M` rodaram numa VM de 8 CPU / 16 GB; o perfil `L` (≈ 17 GB com o Cube) roda numa VM de 10 CPU / 20 GB, swap de 2 GB nas duas. Os limites do engine vêm do perfil e não mudam com a VM, mas uma VM maior deixa mais page cache para o RustFS: o B3 do Trino no perfil `M` é repetido na VM nova como controle (§10). Desde a campanha `L`, o tamanho da VM é gravado no `engine_config` (`docker_vm`).
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
- **Caches do catálogo desligados** (`cache-enabled=false`, `rest-table-cache.max-entries=0`, V14): o Thrift Server mantém vivas as sessões JDBC fechadas, cada uma com o seu `SparkCatalog`, e o dbt-spark abre uma sessão por microbatch; com os caches ligados, cada catálogo retido segura uma `TableMetadata` inteira, o heap cresce com commits × sessões e o B2 na escala `local` termina em GC thrash (perfis `M` e `L`). Desligados, cada comando recarrega a tabela no Lakekeeper; resta uma fuga linear de ~1 MB por sessão. As medições do Spark anteriores a esta mudança têm os caches ligados no `engine_config`.
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
| `r2` (padrão) | **GHCN 1998–2025** (`data_scale = r2_1998`): 336 lotes mensais, **1,29 bi de linhas no bronze**. As primeiras medições usaram 2010–2025 (`data_scale = r2`, 742 M linhas) e continuam em `results/` com esse rótulo | 4,86 GB | ~5,9 GB | 3,41 GB | **6,0 GB** (silver 1,88, gold 0,71) + D2 1,88 GB = **7,9 GB** | Medida pelo `make storage-report` |
| `small` | só 2025: 12 lotes mensais, ~44 M linhas no bronze | 0,17 GB | ~0,2 GB | ~0,12 GB | ~0,23 GB (no Postgres: 8,15 GB de dados + até 8 GB de WAL) | Medida; escala da comparação com o Postgres (D-23) |
| `local` | histórico completo, **1763–2025** (1750–1762 não existem no NOAA): 3.156 lotes, **3,97 bi de linhas no bronze**. `landing/` num SSD externo (USB, exFAT) | 14,4 GB | ~17 GB | ~10 GB | ~18 GB (sem teto: só local) | B1, B2 Trino, B3 e B4 medidos no perfil `M`; B3, B4 (Trino, StarRocks, DuckDB) e B5a no perfil `L`; B5a também no `M` com 2 buckets por partição. O B2 do Spark falha no `M` (memória); o B2 do Trino e do Spark no `L` ainda não rodaram |

  - **Meta da `r2`: bilhões de linhas dentro de 10 GB.** Na `r2` atual o bronze ocupa ~2,7 bytes/linha e o lakehouse 3,75 GB, só ~38% do orçamento. O teto de 6,5 GB do D1 comporta ~1,3 bi linhas no bronze com o layout atual. Se o B6 confirmar o ganho de ordenar antes de gravar (o Parquet caiu à metade na fase 1), comporta mais. As medições começam na `r2` atual; depois do B6, a `r2` é ampliada em anos até encher o teto e as suítes são repetidas ([plano](specs/phase-2.md), etapa 10).
  - A escala `local` é limitada pelo tamanho do histórico, não pelo tempo: o B1 da `r2` levou 142 s de insert (5,2 M linhas/s), então ~30 min de B1 exigiriam muito mais dados do que o GHCN tem. O histórico completo chega a ~20 GB.
  - Os lotes de `landing/batches` são `.csv.gz` (3,4 GB em vez de ~25 GB). O DuckDB lê gzip na mesma vazão do CSV puro, e gerar os lotes (fora da medição) leva ~1 min por ano.
  - A partir da `r2`, silver e gold são construídos do zero mês a mês (`make dbt-backfill`, D-21).
  - Na `local`, o build do zero é por ano até 1949 (anos pequenos; por mês o custo fixo de 2.244 lotes dominaria) e por mês a partir de 1950: um lote anual de ~28 M linhas estoura a memória do dedup do silver no Trino perfil `M`. O `batch_size` do microbatch é uma variável do dbt (`microbatch_batch_size`, padrão `month`).
- Fora do bucket: `landing/` (CSV em disco local), baseline Postgres, MVs do StarRocks (storage local do BE) e Cube Store.
- **D2 = TPC-H SF8: 1,875 GB** medidos (SF1 = 0,227 GB; SF9 passaria de 2 GB), em `lakehouse.duckdb_tpch`, gerado pelo DuckDB em ~65 s (`make tpch SF=8`). Na `r2`, bronze + um writer + D2 = 5,63 GB.
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

### Materialização por camada e model
| Camada | Model / tabela | Materialização | Como atualiza | Primeira carga |
|---|---|---|---|---|
| Bronze | `ghcn_daily_raw` | tabela Iceberg (DuckDB) | **append** por lote mensal (`_batch_id`); nunca reescrita | os 192 lotes, um a um (B1) |
| Bronze | `ghcn_stations_raw`, `ghcn_countries_raw` | tabela | **substituída** a cada carga (arquivos de referência pequenos) | idem |
| Silver | `ghcn_daily` | **incremental** | estratégia do engine (§7.1): `delete+insert` no Trino e no Postgres, `merge` no Spark; janela = datas dos lotes novos − overlap | **por mês** com microbatch (`make dbt-backfill`, D-21) |
| Silver | `stations` | `table` (**full refresh**) | reconstruída a cada execução (133 k linhas, ~1 s) | idem |
| Gold | `fct_weather_daily` | **incremental** (ordenada, D-15) | igual ao silver | por mês com microbatch |
| Gold | `agg_weather_monthly_country` | **incremental** | igual ao silver, por mês | por mês com microbatch |
| Gold | `dim_station`, `dim_date` | `table` (**full refresh**) | reconstruídas a cada execução (pequenas) | idem |
| Gold (só B5b, Trino) | `mv_weather_wide` | `table` (**full refresh**) | o "refresh" medido do B5b | idem |

- Regra: tabelas grandes e com eixo de tempo são incrementais; tabelas pequenas de referência são reconstruídas inteiras, porque o custo é de segundos e não há janela para errar.
- Do zero, nenhuma tabela grande é construída numa query só a partir da `r2`: o build é mês a mês (D-21). Depois disso, cada execução processa só a janela do lote novo.

### Regra de particionamento (D-25)
- **A ordenação (*cluster by*) é o primeiro ajuste**: `sorted_by` no Trino, `WRITE ORDERED BY` no Spark. No B6, ela cortou a fato pela metade e acelerou as leituras sem piorar nenhuma.
- **Partição por tempo continua valendo quando os filtros são por período**, mesmo com partições pequenas: na `r2`, tirar a partição mensal de uma fato já ordenada deixou as queries com filtro de período 60–80% mais lentas no Trino (Q2: 378 → 679 ms), com partições de 2–4 MB. Sem filtros alinhados à partição, ela não paga o custo de arquivos pequenos.
- **Partição que serve a escrita** também fica: bronze por `_batch_id` (ingestão e leitura incremental por lote) e silver alinhada às janelas do `delete+insert`.
- Partição grossa (ano) sem ordenação é a pior combinação: a Q1 levou 197 s, contra 0,5 s com a mesma partição ordenada.
- Revista na `r2_1998` (1,29 bi de linhas): a conclusão se mantém, porque adicionar anos aumenta o número de partições, não o tamanho de cada uma (~1,9 MB por mês nas duas escalas). Partições só engordam com mais dados por período, como uma escala com mais estações ou mais variáveis.

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
| Unicidade de `(station_id, date)` | `gold.fct_weather_daily` | Igual à do silver: teste singular na janela da última execução e `assert_unique_by_year` fora da medição (`make dbt-check-unique` checa as duas tabelas); agrupar as 190 M linhas derruba o Trino no perfil `M` |
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
Rollups provados no V9 (proposta em `spikes/V9/proof_model.diff`, a aplicar em cada engine no B5c):

| Rollup | Grão | Serve |
|---|---|---|
| `monthly_country` | país × mês, só medidas aditivas | Q9 (as duas etapas multi-stage) |
| `monthly_country_avg` | país × mês, médias no grão exato | Q2, Q10 (inclusive a etapa deslocada de 2024) |
| `yearly_station` | estação × ano | Q3 |
| `yearly_country_percentiles` | país × ano | Q7 só como variante com `granularity: year`, registrada à parte |
| `yearly_median_station_prcp` (no cube `station_years`) | estação × ano | Q8, com diferença de 4,6% (percentil aproximado); fica fora do conjunto principal |

- Q4 (filtros de lat/lon) não tem rollup e vai para o engine. Um `dateRange` sem `granularity` casa com rollup quando todas as medidas são aditivas (Q3, Q9); medidas não aditivas exigem o grão exato.
- Os percentis precisam de `CAST(... AS DOUBLE)` dentro da função; com isso, todas as colunas de medida no Cube Store são `float`.
- O cache de resultados do Cube fica no volume do Cube Store e sobrevive a reinícios: toda requisição medida no B4/B5 manda `renewQuery: true`, e o volume é recriado antes de uma execução completa.
- Implementação: os rollups ficam só nos cubes `trinopa_*` / `starrockspa_*` (views `trinopa_weather`, `starrockspa_weather`), então o B4 nunca chega ao Cube Store. São quatro rollups (`monthly_country`, `monthly_country_avg`, `yearly_station`, `yearly_country_percentiles`), com uma partição por ano (64 por engine) e `refresh_key` de 365 dias, para o build não disparar no meio de uma medição. No StarRocks, `sql_alias` curto, porque o driver MySQL recusa nomes de tabela com mais de 64 caracteres. O `make cube-up` não sobe o refresh worker; o build medido (`make b5-refresh SCENARIO=b5c ENGINE=…`) usa um refresh worker avulso com o mesmo limite de CPU e conta do início até as 64 partições prontas (granularidade de ~10 s). Na `r2`: 516 s no Trino e 134 s no StarRocks, ~20 MB no Cube Store.
- No benchmark, o build é medido no passo 6 do §9. A API `/v1/pre-aggregations/jobs` recusou o JWT (`API scope is missing: jobs`); até resolver, o build é o do refresh worker, medido do início do refresh até a última partição pronta. Na prova (2024–2025): ~3 min 20 s com o Trino no perfil `M` e o refresh worker em 0,5 CPU; 31 MB no Cube Store.

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
| `L2` | 8 | 12 GB | o `L` sobre o RustFS revisto (D-26, V15): 1.0.2, scanner desligado, 2 CPU, 5 GiB (`env/l2.env`) |

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
| **B5b** | **Tabela equivalente à MV** no Trino: model dbt `table` `trino_gold.mv_weather_wide` com o mesmo SQL do B5a. O Trino 483 não cria MV no catálogo REST (V2). O "refresh" medido é `dbt run --select mv_weather_wide` (273,5 s na `r2`). Partição anual + ordenação `(station_id, date)`: com partição mensal o CTAS estoura a memória do escritor no perfil `M`. No Cube: cubes `trinomv_*` e view `trinomv_weather` | O Cube aponta para a tabela via `sql_table`, sem reescrita. |
| **B5c** | **Cube Store** pre-aggregations (país × mês, estação × ano) sobre Trino e sobre StarRocks. | O Cube roteia para o Cube Store. |

- DDL do B5a: `PARTITION BY date_trunc('month', date)`, `DISTRIBUTED BY HASH(station_id)` com buckets pelas linhas **por partição** (no StarRocks o número de buckets vale para cada partição): ~0,5–1 M linhas por bucket na partição mais cheia, o que dá 2 buckets na fato em todas as escalas (o mês mais cheio tem ~1 M linhas); tabelas sem partição (dimensões) seguem o volume total (< 5 M linhas → 4). Até a campanha `L` a fato usava 16 buckets (regra pelo volume da tabela): na `local`, 16 × 3.156 meses deram ~50 mil tablets e o refresh estourou a memória do BE nos perfis `M` e `L`; as linhas B5a da `r2` e da `r2_1998` foram medidas com 16 buckets. Além disso: `ORDER BY` pelas dimensões filtradas, `REFRESH DEFERRED MANUAL` (sem `DEFERRED`, a criação já popula a MV e o primeiro refresh medido não faz nada). Não existe `CREATE OR REPLACE` para MV: recriar é `DROP` + `CREATE`. DDL em `bench/sql/`. Os arquivos de uma MV apagada ficam na lixeira do BE por 1 h (`catalog_trash_expire_second`).
- Refresh **depois da transformação e antes da leitura** (passo 6 do §9), com `WITH SYNC MODE` e `SET query_timeout = 3600` na mesma sessão (o SYNC é morto em 300 s), e medido. Depois do refresh o BE compacta por ~10 min; a leitura só começa quando a CPU do container cai abaixo de 10%, senão as queries falham por memória. Na `r2`, a MV larga da prova do V3 levou 540–589 s de refresh e ocupou 4,8 GB depois da compactação (storage local do BE, fora do bucket).
- Medido na `r2` com uma MV por tabela (DDL em `bench/sql/b5a_*.starrocks.sql`, `make starrocks-mv-create|refresh|drop`): refresh de 382 s para a fato (16 buckets) e 1–2 s para as dimensões; ~1,3 GB depois da compactação, que leva ~25 min. Depois da compactação o BE fica perto do limite de memória mesmo sem queries, então o StarRocks é reiniciado antes da primeira leitura medida (as MVs persistem).
- A Q8 estoura a memória do BE no perfil `M` com e sem MV, e a Q5 não roda no StarRocks: as duas entram como `failed` para o StarRocks, não como inválidas.
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

- Execução (`make b6 VARIANT=… ENGINE=trino`, `make b6-all`): um fator por vez a partir da base (layout atual do gold), 9 variantes: `baseline`, `file128`/`file256`/`file512`, `snappy`, `gzip`, `year`, `sorted` (`sorted_by (station_id, date)` no Trino) e `zorder` (Spark: CTAS + `rewrite_data_files` com `zorder(station_id, date)` e `rewrite-all`, porque uma partição com um único arquivo é ignorada). Cada variante vive em `bench_<run>_<variante>` com a fato e cópias das dimensões (o DuckDB não lê views Iceberg), é lida pelo B3 e apagada com espera do purge antes da próxima.
- No Trino, a escrita das variantes é um `INSERT` por ano: um CTAS ordenado das 192 partições estoura a memória do `TableWriterOperator` no perfil `M`.
- Com partição mensal, os arquivos ficam com 2–4 MB; o tamanho-alvo de arquivo (128/256/512 MB) só pesa se a partição for maior. A partição por ano é a variante que testa isso.
- Hipótese a validar: **zstd** é o melhor equilíbrio entre tamanho e velocidade de leitura; gzip comprime parecido, mas descomprime mais devagar; snappy é o maior em disco. Com ~1–2 GB por camada, partições pequenas (por mês) limitam o tamanho real dos arquivos — por isso partição entra na matriz junto com o tamanho de arquivo.
- O resultado do B6 define os padrões usados nas demais suítes (D-15, D-25). A Q1 lenta da partição `year(date)` (197 s quente) some quando a tabela é ordenada (0,49 s): o problema é a partição grossa sem ordenação, não a partição anual em si.

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

D2: 22 queries TPC-H com os parâmetros padrão (`bench/queries/tpch/`, um arquivo por engine), validadas por checksum contra o DuckDB em DuckDB, Trino e StarRocks. A fração da Q11 segue a especificação, `0.0001 / SF`; a Q15 usa CTE no lugar da view; Trino e StarRocks usam `substr` na Q22 e `GROUP BY l_suppkey` na Q15. Resultados rotulados "derived from TPC-H, not comparable to published TPC-H results".

### 10.6 Protocolo
- Nunca dois engines ao mesmo tempo. Nas leituras (B3–B5), uma query por vez.
- **Infra no mesmo estado para cada engine:** o RustFS é reiniciado antes da campanha de cada engine. Depois de ~10 h de uso contínuo, ele chegou a 1,5 de 2 GiB e passou a responder devagar; os lotes do Spark subiram de 10 s para 100–500 s e terminaram em timeout de leitura no S3. Com o RustFS recém-iniciado, ele mede o engine, não o desgaste da infraestrutura.
- O Mac fica acordado durante **toda a campanha**, inclusive nos intervalos entre execuções (um app de "keep awake" com tempo definido): o `caffeinate -i` de cada comando só vale enquanto o comando roda. Num intervalo sem ele, o Mac entrou em *Idle Sleep*; a execução seguinte começou com a máquina dormindo, a VM congelou e o Trino perdeu as queries.
- **Cold:** reiniciar o engine e limpar os caches → 1 execução.
- **Warm:** 1 warm-up descartado + **5 execuções** medidas.
- Timeout: 300 s por query (registra `timeout` e segue).
- Validar o resultado (row count + checksum) contra a referência DuckDB; resultado divergente invalida a medição. Exceção: medidas aproximadas (percentis via `approx_percentile`) são comparadas com tolerância relativa de 5%, e a tolerância é registrada no resultado.
- Coletar `docker stats` (CPU/mem) durante cada execução.
- Implementação (`bench/harness/`, `make bench SUITE=b3|b4|b5 ENGINE=… DATASET=ghcn|tpch`): o cliente roda no container `bench`, na rede do Compose, com o socket do Docker para reiniciar o engine (frio), limpar o page cache da VM e amostrar `docker stats` entre e durante as execuções. As queries diretas ficam em `bench/queries/sql/qN.<engine>.sql`, escritas por engine. A referência DuckDB é calculada fora das etapas medidas. Execuções com timeout ou erro ficam como `timeout`/`failed`, resultados divergentes como `invalid`; o warm-up é gravado com `run_type=warmup` e fica fora do p50/p95.
- No Cube 1.7.50, só `cache: "no-cache"` no topo do corpo do `/v1/load` força a execução (o `renewQuery: true` sozinho ainda devolveu resultado do cache). Toda requisição medida manda os dois, e isso fica registrado em `notes`.

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
| **2 — Benchmark** ✅ r2, r2_1998, small e local medidas no perfil `M` ([plano](specs/phase-2.md); perfil `L` na `local` em andamento, em duas campanhas: RustFS em 1 CPU e com mais CPU, D-26) | Carga das escalas `r2` (GHCN 2010–2025) e `local` (§6); harness; Spark e Postgres no B2; StarRocks, DuckDB, Postgres como readers; D2; B5 (MVs + Cube Store); B6 | B1–B6 geram `results/*.parquet` no perfil `M`; relatório gerado |
| **3 — Orquestração** | Airflow 3 + Cosmos (`ExecutionMode.WATCHER`, CeleryExecutor) executando o fluxo do §9; tarefas que não são dbt (ingestão DuckDB, manutenção, refresh de MV, harness) rodam como **containers** via `DockerOperator` com imagens do projeto, para a imagem do Airflow ter só Cosmos, o provider Docker e as connections dos engines | DAG ponta a ponta; tempos por model ≈ fase 2; overhead do orquestrador registrado |
| **4 — Extras** | Superset via Cube; observabilidade e linhagem (§10.8); Polaris; Airbyte se necessário; `SPEC.en.md` | Resultado documentado por item |
| **5 — Comparação de orquestração** | Dagster + dbt (`dagster-dbt`) executando o mesmo fluxo | Overhead Dagster × Airflow/Cosmos documentado |
| **6 — Cloudflare R2** | A escala `r2` final (≥ 1 bi linhas no bronze) rodando com o bucket no R2 (+ R2 Data Catalog), depois de todas as fases locais. Credenciais e endpoint do R2 entram como variáveis próprias em `.env.example` (nunca as reais no repo). **Rede medida à parte:** antes de cada campanha, linha de base de upload/download de um arquivo conhecido e latência de GETs pequenos, gravada em `results/`; cada suíte registra a contagem de GET/PUT (classes A/B) | B1–B5 no R2 comparados com os mesmos passos no RustFS local (mesmos dados, engine e perfil): a diferença é o custo da rede e do object store remoto; operações dentro do free tier (V5) |
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
| D-15 | Layout padrão de `fct_weather_daily`, definido pelo B6 (`results/b6.parquet`, Trino `M`, `r2`): zstd + partição `month(date)` + ordenação `(station_id, date)`. No Trino, `sorted_by` ordena toda escrita; no Spark, `WRITE ORDERED BY` só existe depois da criação da tabela, então a ordenação é aplicada pela manutenção (`rewrite_data_files` com `strategy => 'sort'` e `rewrite-all`) | Ordenar reduziu a fato de 0,732 para 0,383 GB (−48%) e a Q1 quente de 806 para 506 ms, sem piorar nenhuma leitura. O tamanho-alvo de arquivo não muda nada (arquivos mensais de 2–4 MB); snappy ocupa 22% a mais e gzip 3% a menos, com leituras no ruído; z-order não melhorou as leituras; partição por ano deixou a Q1 ~250× mais lenta (anomalia em investigação). |
| D-16 | Uma instância do Cube com multi data source; membros na base e engines via `extends` | Semântica idêntica entre engines sem template; cada arquivo de engine mostra só o que difere. |
| D-17 | Medidas de rollup sempre `CAST AS DOUBLE` | Drivers truncam DECIMAL a 5 casas no Cube Store. |
| D-18 | Cube lê só pelos engines, sem integração com dbt | O benchmark mede o caminho engine → Cube; schema do Cube independente. |
| D-19 | Medidas avançadas via recursos nativos do Cube (multi-stage, `time_shift`, `sub_query`) | Abordagem atual recomendada pelo Cube; gera SQL mais exigente para os engines. |
| D-20 | Manutenção numa macro única: post-hook no uso normal, desligada e medida à parte nos benchmarks | Um só código para operação e benchmark; tempo dos models não é contaminado. |
| D-21 | Construção do zero em janelas mensais (`make dbt-backfill`: microbatch e manutenção uma vez por tabela) | Na `r2`, o dedup do silver numa query só (~740 M linhas) e o teste de unicidade da tabela inteira estouram o spill de 10 GB do perfil `M`. Por mês, cada lote leva 2–9 s. |
| D-22 | Nas medições do DuckDB via Cube (B4/B5), o `cube-api` recebe os limites do perfil (`ENGINE_CPUS`/`ENGINE_MEMORY`), e o DuckDB recebe 75% dessa memória e `ENGINE_CPUS` threads; tudo registrado em `engine_config`. O `make cube-up` não lê o perfil: para o DuckDB os limites vão por variável (perfil `M`: `CUBE_API_CPUS=4 CUBE_API_MEMORY=8g CUBE_DUCKDB_THREADS=4 CUBE_DUCKDB_MEMORY_LIMIT=6GB`; `L`: `8`, `12g`, `8`, `9GB`); para os outros engines o `cube-api` fica no padrão (1 CPU / 1 GB) | O DuckDB roda dentro do processo do Cube. Com os limites padrão do Cube (1 CPU / 1 GB, DuckDB 512 MB), a Q8 estoura a memória na `r2`. O overhead do Node fica dentro do mesmo orçamento, e isso é citado junto dos números. |
| D-23 | Postgres (writer e reader) só na escala `small` (GHCN 2025), num container próprio (`postgres-bench`, perfil `postgres`, auth `trust` só na rede do Compose) com os limites do perfil e `shared_buffers`/`effective_cache_size`/`work_mem` derivados dele (`config/postgres-bench/entrypoint.sh`); tabelas sem partição; o bronze é copiado do Iceberg pelo DuckDB (`make postgres-load`); nessa escala todos os engines rodam B2/B3 para a comparação | Em linhas, o Postgres usa ~65 bytes/linha contra ~2,7 do Parquet: a `r2` daria ~90 GB e não cabe no disco do Docker. A escala `small` mantém o Postgres como baseline com os mesmos dados que os outros engines. |
| D-24 | B5a com uma MV do StarRocks por tabela do gold (cópia de todas as colunas, sem join e sem agregação), em vez de uma MV larga com os joins | O StarRocks só reescreve para MV de join quando a query junta as mesmas tabelas, e o Cube junta só os cubes usados. Com uma MV por tabela, cada leitura de tabela é trocada pela sua MV, qualquer que seja o join; é o padrão usado em produção pelo autor. O Cube continua lendo os marts, e o storage extra fica no BE, fora do bucket. |
| D-25 | Ordenação (*cluster by*) primeiro; partição por tempo só quando os filtros são por período (mesmo com partições pequenas) ou quando serve a escrita (bronze por lote, janelas do `delete+insert`); nunca partição sem ordenação | Segunda rodada do B6 (`results/b6.parquet`): sem partição, a fato ordenada ficou 60–80% mais lenta nos filtros de período; partição anual sem ordenação deixou a Q1 ~400× mais lenta que com ordenação. O limite em bytes da primeira versão desta regra não se sustentou para filtros de tempo no Trino. |
| D-26 | O perfil `L` na escala `local` roda duas vezes: primeiro com o RustFS em 1 CPU, igual a todos os perfis (infra constante, §10.1), e 5 GiB de memória no B2 a partir do microbatch do Trino e em todo o Spark (com 3 GiB ele foi morto por OOM três vezes no B2 do Trino); os limites do RustFS vão para o `engine_config` (`docker_vm: … rustfs_cpus rustfs_memory_gib`); depois uma segunda campanha `L` com a infra do RustFS revista — versão 1.0.2 (correções de memória do scanner, V15), scanner desligado, 5 GiB e 2 CPU (8 do engine + 2 = os 10 da VM) — onde todos os engines repetem B2–B5 e o B2 do Spark na `local` é medido de novo; é o perfil `l2` (`env/l2.env`), e a campanha exporta `COMPOSE_ENV_FILES=.env,env/l2.env` para que todo `docker compose` (inclusive `make cube-up`) use a mesma infra. As medições no perfil `M` e a primeira campanha `L` ficam com o RustFS 1.0.1, registrado no `engine_config` | Na primeira campanha `L`, o Trino com 8 CPU ficou mais lento nos scans da tabela inteira que no perfil `M` (B3 Q1 +15%, Q1 via Cube 2×), com as queries filtradas estáveis: o object store de 1 CPU limita o engine. A primeira campanha mostra o perfil com a infra constante; a segunda mostra quanto o engine ganha quando o object store não é o gargalo. |

## 15. Validações pendentes (spikes)

| # | Validação | Quando | Fallback |
|---|---|---|---|
| V1 | ✅ Resolvido: DuckDB 1.5.6 escreve Iceberg v2 (CREATE, INSERT, particionado) via Lakekeeper com `ACCESS_DELEGATION_MODE 'none'` + secret S3 estático (detalhes em `spikes/V1/README.md`). Trino 483 lê as tabelas do DuckDB com poda de partição; Spark e StarRocks validados na fase 2 | Fase 1 | — |
| V2 | ✅ Resolvido: **não suportado**. O Trino 483 responde `createMaterializedView is not supported for Iceberg REST catalog` (o `CREATE VIEW` lógico funciona); o código no master é igual. Fallback adotado no B5b (detalhes em `spikes/V2/README.md`). Revalidar a cada upgrade do Trino | Fase 2 | — |
| V3 | ✅ Resolvido (StarRocks 4.1.6, `spikes/V3/README.md` §9): a MV de join é reescrita só quando a query tem **o mesmo formato de join** da MV. O SQL do Cube junta só os cubes usados, então nunca casa com a MV larga; View Delta Join não funcionou com constraints declaradas nas tabelas Iceberg. Resultados iguais com e sem MV (tolerância 1e-9). Adotado e provado: uma MV por tabela, sem join (D-24): todas as leituras de Iceberg do SQL do Cube (Q1–Q4, Q6–Q10) e das queries escritas à mão passam a ler as MVs, com resultados iguais (`spikes/V3/README.md` §10) | Fase 2 | — |
| V4 | ✅ Resolvido: dbt-trino suporta `microbatch` desde 1.9.0; `concurrent_batches` desde 1.10.2 (detalhes em `spikes/V4/README.md`). A validar na prática: `event_time` DATE comparado com literais TIMESTAMP e conflitos de commit com `concurrent_batches` | Fase 1 | — |
| V5 | Limites atuais do free tier do R2 (storage, ops Class A/B) | Antes da fase 6 | Reduzir repetições/volume |
| V6 | Iceberg v3: escrita no Trino, deletion vectors no StarRocks, suporte no Lakekeeper | Revisão periódica | Manter v2 |
| V7 | Endpoints de métricas e integração OpenLineage de cada engine na versão pinada | Fase 4 | Manter só cAdvisor + `dbt-ol` |
| V8 | Cosmos `ExecutionMode.WATCHER` com Airflow 3 + CeleryExecutor + dbt-trino/dbt-spark | Fase 3 | `ExecutionMode.LOCAL` com `DbtTaskGroup` |
| V9 | ✅ Resolvido no Trino (`spikes/V9/README.md` §8): Q2, Q3, Q9 e Q10 são servidas por rollups como estão escritas, com resultados iguais à fonte; Q7 só com `granularity: year`; Q8 é servida, mas difere 4,6% (percentil aproximado); Q4 não. Falta repetir no StarRocks | Fase 2 | — |
| V10 | STS do RustFS (AssumeRole) com a session policy do Lakekeeper → vended credentials para todos os engines | Fase 4 | Manter chaves estáticas |
| V11 | Cosmos: `ExecutionMode.WATCHER` (dbt instalado na imagem do Airflow/worker) × `ExecutionMode.DOCKER` (dbt numa imagem própria, uma task por model) — overhead e isolamento | Fase 3 | `DockerOperator` chamando `dbt build` |
| V12 | "Modo seguro": IdP OIDC leve (Dex ou Zitadel) + Lakekeeper com autenticação OIDC (sem OpenFGA) + vended credentials via STS do RustFS (depende do V10); engines com OAuth2 client credentials (DuckDB `CLIENT_ID`/`CLIENT_SECRET`/`OAUTH2_SERVER_URI`). Medido como cenário à parte; o cenário sem auth e com chaves estáticas segue como linha de base | Fase 4 | Manter chaves estáticas sem auth |
| V15 | Parcial: o RustFS 1.0.1 cresce em memória sob horas de S3 com muitos objetos pequenos até o OOM (3 GiB com o Trino, 5 GiB com o Spark no B2 da `local`). Causa documentada: o scanner de uso de dados guarda metadados em memória e o mimalloc não devolve (rustfs#8456, corrigido na 1.0.2 de 16/10/2026 via #8460; rustfs#8121 fechado sem causa completa). Nenhuma variável limita a memória do processo; `RUSTFS_SCANNER_ENABLED=false` desliga o scanner. Prova local (18 min, 8 threads, PUT/GET/LIST de objetos de 20 KB): +39 MB/min por padrão, +29 MB/min sem scanner, sem platô em nenhum |
| V14 | ✅ Resolvido em parte: o crescimento do heap do Spark Thrift Server no B2 da escala `local` (4,4 M `BaseSnapshot` vivos, GC thrash) vem das sessões JDBC fechadas que ficam retidas, cada uma com um `SparkCatalog` cujo `CachingCatalog` e `RESTTableCache` (Iceberg 1.12) seguram a `TableMetadata`. Prova no perfil `S` (30 sessões): com os dois caches desligados, nenhuma `TableMetadata`/`BaseSnapshot` retida (antes ~18 mil snapshots), heap 109 MB contra 166 MB. Limites da UI e `spark.ui.enabled=false` não resolvem. Em aberto: qual objeto segura a `SessionState` (fuga linear de ~1 MB por sessão; parecido com SPARK-34689) |
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
