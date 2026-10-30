FROM python:3.12.15-slim

COPY --from=ghcr.io/astral-sh/uv:0.12.24 /uv /usr/local/bin/uv

# The docker CLI talks to the host daemon through the mounted socket (cold restarts, docker stats).
RUN apt-get update \
    && apt-get install -y --no-install-recommends docker-cli \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    PATH=/opt/venv/bin:$PATH

COPY harness/pyproject.toml harness/uv.lock ./
RUN uv sync --frozen --no-install-project

# Extensions are baked in so a run never downloads them (the DuckDB engine and the DuckDB reference).
RUN python -c "import duckdb; duckdb.sql('INSTALL iceberg; INSTALL httpfs; INSTALL avro; INSTALL postgres')"

# The harness and the queries are mounted at /repo/bench (compose/bench.yaml), not baked in.
WORKDIR /repo/bench/harness
