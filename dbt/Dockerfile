FROM python:3.12.15-slim

COPY --from=ghcr.io/astral-sh/uv:0.12.24 /uv /usr/local/bin/uv

# dbt debug checks for git.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV UV_PROJECT_ENVIRONMENT=/opt/venv \
    UV_COMPILE_BYTECODE=1 \
    PATH=/opt/venv/bin:$PATH \
    DBT_PROFILES_DIR=/app \
    DBT_PACKAGES_DIR=/opt/dbt_packages \
    DBT_SEND_ANONYMOUS_USAGE_STATS=false \
    DBT_USE_COLORS=false

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-install-project

# Packages live outside /app so mounting the project for development does not hide them,
# and a measured run never downloads anything.
COPY dbt_project.yml packages.yml package-lock.yml ./
RUN dbt deps

COPY . .

ENTRYPOINT ["dbt"]
CMD ["build"]
