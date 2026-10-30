# LinkedIn post and cover image for the first Medium post

## LinkedIn (English)

I spent the last few weeks racing four query engines on the same lakehouse, on a laptop.

Same Iceberg tables, same CPU and memory limits, same questions, and every answer checked against a reference before its time counted. The data is NOAA's daily weather history, 1763 to 2025: 3.97 billion rows.

Trino, Spark, StarRocks and DuckDB, with dbt for the transformations and Cube on top.

A few results (for this setup only, so test your own case):
- Filtered queries barely noticed the data growing 5×. Sorting + time partitions did most of the work.
- Pre-aggregations in Cube Store answered in 16–34 ms at every scale. You pay at build time instead.
- Doubling the CPU made one Trino query 2× slower... because the object store was the bottleneck. With 2 CPUs on the object store, that query went from 65 s to 25 s.
- A materialized view that only copies a table didn't beat reading Iceberg directly.
- Postgres handled tens of millions of rows fine, but stored them 35× bigger than Parquet: the disk decides before the queries do. DuckDB loaded 742 M rows in 146 s.

Most of the work went into things that looked like engine problems and weren't: the laptop going to sleep mid-run, macOS swapping, a Spark session leak holding 4.4 million snapshot objects, the object store running out of memory, a full disk.

The stack was built with an AI coding assistant, which made it possible in days. Catching the wrong numbers was still a human job :)

Next: the same benchmark in the cloud, with more workers. New post when I have results.

The full story, with the numbers and what broke: https://medium.com/@jhorlima
Code and results: https://github.com/jhorlima/sleipnir

## LinkedIn (Português)

Passei as últimas semanas colocando quatro query engines para competir no mesmo lakehouse, num notebook.

Mesmas tabelas Iceberg, mesmos limites de CPU e memória, mesmas perguntas, e cada resposta conferida com uma referência antes de o tempo valer. Os dados são o histórico diário de clima da NOAA, de 1763 a 2025: 3,97 bilhões de linhas.

Trino, Spark, StarRocks e DuckDB, com dbt nas transformações e Cube por cima.

Alguns resultados (valem para este cenário, então teste o seu caso):
- As queries com filtro quase não sentiram os dados crescerem 5×. Ordenação + partição por tempo fizeram a maior parte do trabalho.
- As pré-agregações no Cube Store responderam em 16–34 ms em todas as escalas. O custo vai para o build.
- Dobrar a CPU deixou uma query do Trino 2× mais lenta... porque o gargalo era o object store. Com 2 CPUs no object store, essa query caiu de 65 s para 25 s.
- Uma materialized view que só copia a tabela não ganhou de ler o Iceberg direto.
- O Postgres deu conta de dezenas de milhões de linhas, mas ocupou 35× mais espaço que o Parquet: o disco decide antes das queries. O DuckDB carregou 742 milhões de linhas em 146 s.

A maior parte do trabalho foi em coisas que pareciam problema de engine e não eram: o notebook dormindo no meio da execução, o swap do macOS, um vazamento de sessões no Spark segurando 4,4 milhões de objetos de snapshot, o object store sem memória, o disco cheio.

A stack foi construída com um assistente de código com IA, o que permitiu fazer em dias. Pegar os números errados continuou sendo trabalho humano :)

Próximo passo: o mesmo benchmark na nuvem, com mais workers. Novo post quando tiver resultados.

A história completa, com os números e o que quebrou: https://medium.com/@jhorlima
Código e resultados: https://github.com/jhorlima/sleipnir

## Cover image prompt

> A wide editorial illustration for a data engineering blog post. Sleipnir, the eight-legged horse from Norse mythology, galloping across a stylised night sky made of faint weather-map lines and station dots spanning the globe. Beneath it, four racing lanes of light, each a different colour, run toward a finish line drawn as a simple bar chart: three bars of similar height and one much shorter bar marked "16 ms". In the background, a stack of translucent layers suggests a data lakehouse (storage, tables, a semantic layer). A small laptop sits at the start line, with a crescent moon above it, a quiet nod to benchmarks run overnight. Flat vector style, dark navy background, muted teal, amber, coral and violet accents, clean geometric shapes, no logos, no product names, no other text. 16:9.
