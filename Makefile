SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

ROOT_DIR := $(shell pwd)
COMPOSE  := docker compose -f docker/docker-compose.yaml

.PHONY: help
help: ## List the available targets
	@awk 'BEGIN{FS=":.*##"; printf "Targets:\n"} /^[a-zA-Z0-9_.-]+:.*##/{printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: config
config: ## Render docker/Dockerfile, docker-compose.yaml and prometheus.yml from templates
	@bash generate_config.sh

.PHONY: build
build: config ## Build the hl_exporter image
	$(COMPOSE) build

.PHONY: up
up: config ## Bring the stack up (builds if missing)
	$(COMPOSE) up -d --build

.PHONY: down
down: ## Stop the stack (keeps volumes)
	$(COMPOSE) down

.PHONY: restart
restart: ## Restart all services
	$(COMPOSE) restart

.PHONY: logs
logs: ## Tail logs from every service
	$(COMPOSE) logs -f --tail=200

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: pull
pull: ## Pull latest Prometheus / Grafana / node-exporter images
	$(COMPOSE) pull prometheus grafana node_exporter

.PHONY: reload
reload: ## Reload Prometheus config without restarting
	$(COMPOSE) exec prometheus wget --quiet --post-data='' http://127.0.0.1:9090/-/reload -O- > /dev/null && echo "Prometheus config reloaded"

.PHONY: nuke
nuke: ## Stop AND delete all volumes (irreversibly wipes Prometheus + Grafana data)
	$(COMPOSE) down -v
