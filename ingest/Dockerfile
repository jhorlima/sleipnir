FROM python:3.12.15-slim

COPY --from=ghcr.io/astral-sh/uv:0.12.24 /uv /usr/local/bin/uv

WORKDIR /app
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    PATH=/opt/venv/bin:$PATH

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

# Extensions are baked in so a measured load never downloads them.
RUN python -c "import duckdb; duckdb.sql('INSTALL iceberg; INSTALL httpfs; INSTALL avro; INSTALL postgres')"

COPY *.py ./

ENTRYPOINT ["python"]
CMD ["load.py"]
