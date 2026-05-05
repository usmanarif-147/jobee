.DEFAULT_GOAL := help
.PHONY: help up down restart ps logs reset clean shell-postgres shell-redis seed-buckets

help: ## Show available commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

up: ## Start all services in the background
	docker compose up -d

down: ## Stop all services (volumes preserved)
	docker compose down

restart: ## Restart all services
	docker compose restart

ps: ## Show service status
	docker compose ps

logs: ## Tail logs from all services (or one: make logs s=kafka)
ifdef s
	docker compose logs -f $(s)
else
	docker compose logs -f --tail=100
endif

reset: ## Stop services AND DELETE all data volumes
	docker compose down -v

clean: ## Stop services, delete volumes, remove orphan containers
	docker compose down -v --remove-orphans

shell-postgres: ## psql shell into Postgres
	docker compose exec postgres psql -U $${POSTGRES_USER:-jobee}

shell-redis: ## redis-cli into Redis
	docker compose exec redis redis-cli

seed-buckets: ## Re-run MinIO bucket creation
	docker compose run --rm minio-init
