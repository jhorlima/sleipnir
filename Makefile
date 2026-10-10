.DEFAULT_GOAL := help
.PHONY: help env up down ps logs init clean

help: ## List the available targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-8s %s\n", $$1, $$2}'

env: ## Create .env from .env.example if .env does not exist yet
	@test -f .env || cp .env.example .env

up: ## Start storage (RustFS, Postgres, Lakekeeper) and the Traefik proxy
	docker compose up -d --wait

down: ## Stop and remove the containers (volumes are kept)
	docker compose down

ps: ## Show the status of the containers
	docker compose ps -a

logs: ## Follow the logs of all services
	docker compose logs -f

init: ## Create the bucket and bootstrap Lakekeeper with the lakehouse warehouse (idempotent)
	docker compose run --rm rustfs-create-bucket
	docker compose run --rm lakekeeper-bootstrap

clean: ## DESTRUCTIVE: stop the stack and delete its volumes (all lake data and catalog metadata)
	docker compose --profile init down --volumes --remove-orphans
