# LinkedIn post and cover image for the first Medium post

## LinkedIn (English)

A few weeks ago I wanted a public dataset big enough to push Cube.dev's pre-aggregations to their limit.

I found one. Over 260 years of daily weather records from stations all over the world, published by the US weather and climate agency (NOAA). From 1763 to 2025: 3.97 billion rows.

Then I thought... why stop at Cube when I had Claude to help me test more tools?! So I built a small lakehouse on my laptop and put four query engines in the same race: Trino, Spark, StarRocks and DuckDB. Same Iceberg tables, same CPU and memory limits, same questions, and every answer checked before its time counted.

It took ~40 hours of transformations alone, over 8 days, and more than one night with the Mac working the "night shift" while I slept.

My bet going in: DuckDB would win almost everything. It did "surprise" me, in the good way: no server, a single process, it loaded 742 M rows in 146 s and had the best TPC-H time. But it didn't win everything, and some of the best surprises came from elsewhere:
- Doubling the CPU made one Trino query 2× slower. The "bottleneck" wasn't the engine, it was the object store.
- Spark "couldn't forget": its server piled up 4.4 million Iceberg snapshot objects in memory, one batch at a time.
- Pre-aggregations answered in 16–34 ms at every scale. You only pay at build time.
- Postgres handled tens of millions of rows fine, but used 35× the disk of Parquet.

And a few things looked like engine problems and weren't: the laptop "sleeping on the job", macOS swapping, a full disk xD

To be honest, a laptop isn't the fairest lab, so the next round goes to the cloud, with more workers. I'll write a new post when I have the numbers (fingers crossed for a free VPS on Oracle haha).

Claude built the stack with me in days. Catching the wrong numbers was still on me :)

The whole story, with the tables and everything that broke: https://medium.com/@jhorlima
Code and results: https://github.com/jhorlima/sleipnir

## LinkedIn (Português)

Há algumas semanas eu queria um dataset público grande o bastante para levar as pré-agregações do Cube.dev ao limite.

Achei. Mais de 260 anos de registros diários de clima de estações do mundo todo, publicados pela agência de clima e meteorologia dos EUA (NOAA). De 1763 a 2025: 3,97 bilhões de linhas.

Aí pensei... por que parar no Cube se eu tinha o Claude para me ajudar a testar mais ferramentas?! Montei um pequeno lakehouse no meu notebook e coloquei quatro query engines na mesma corrida: Trino, Spark, StarRocks e DuckDB. Mesmas tabelas Iceberg, mesmos limites de CPU e memória, mesmas perguntas, e cada resposta conferida antes de o tempo valer.

Foram ~40 horas só de transformações, em 8 dias, e mais de uma noite com o Mac fazendo "plantão" enquanto eu dormia.

Minha aposta no começo: o DuckDB ia ganhar quase tudo. Ele me "surpreendeu", no bom sentido: sem servidor, um processo só, carregou 742 milhões de linhas em 146 s e teve o melhor tempo no TPC-H. Mas não ganhou tudo, e algumas das melhores surpresas vieram de outros lugares:
- Dobrar a CPU deixou uma query do Trino 2× mais lenta. O "gargalo" não era a engine, era o object store.
- O Spark "não conseguia esquecer": o servidor dele foi acumulando 4,4 milhões de objetos de snapshot do Iceberg na memória, um lote de cada vez.
- As pré-agregações responderam em 16–34 ms em todas as escalas. Você só paga no build.
- O Postgres deu conta de dezenas de milhões de linhas, mas usou 35× mais disco que o Parquet.

E algumas coisas pareciam problema de engine e não eram: o notebook "dormindo no trabalho", o swap do macOS, o disco cheio xD

Sendo honesto, um notebook não é o laboratório mais justo, então a próxima rodada vai para a nuvem, com mais workers. Faço um novo post quando tiver os números (torcendo para encontrar uma VPS gratuita na Oracle haha).

O Claude montou a stack comigo em dias. Pegar os números errados continuou sendo comigo :)

A história completa, com as tabelas e tudo que quebrou: https://medium.com/@jhorlima
Código e resultados: https://github.com/jhorlima/sleipnir

## Cover image prompt

> A wide editorial illustration for a data engineering blog post. Sleipnir, the eight-legged horse from Norse mythology, galloping across a stylised night sky made of faint weather-map lines and station dots spanning the globe. Beneath it, four racing lanes of light, each a different colour, run toward a finish line drawn as a simple bar chart: three bars of similar height and one much shorter bar marked "16 ms". In the background, a stack of translucent layers suggests a data lakehouse (storage, tables, a semantic layer). A small laptop sits at the start line, with a crescent moon above it, a quiet nod to benchmarks run overnight. Flat vector style, dark navy background, muted teal, amber, coral and violet accents, clean geometric shapes, no logos, no product names, no other text. 16:9.
