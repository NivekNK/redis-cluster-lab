# Redis Cluster Laboratory - Makefile
# Comandos simplificados para el laboratorio
#
# Uso: make up SHARDS=N  (default: 1, mínimo: 1)
# Cada shard = 1 master + 1 replica

.PHONY: help up down status test scenarios shell monitor monitor-all reset setup generate scenario-%

# Cantidad de shards (masters). Cada shard tiene 1 replica.
SHARDS ?= 3
TOTAL_NODES = $(shell echo $$(($(SHARDS) * 2)))
COMPOSE_FILE = docker-compose.generated.yml

# Colores para output
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m # No Color

help: ## Muestra esta ayuda
	@echo "${BLUE}Redis Cluster Laboratory${NC}"
	@echo "========================"
	@echo ""
	@echo "${GREEN}Uso: make <comando> SHARDS=N${NC}"
	@echo "  SHARDS: Cantidad de shards/masters (default: 3, mínimo: 3)"
	@echo "  Cada shard tiene 1 master + 1 replica"
	@echo ""
	@echo "${GREEN}Comandos disponibles:${NC}"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_%.-]+:.*?## / {printf "  ${YELLOW}%-15s${NC} %s\n", $$1, $$2}' $(MAKEFILE_LIST)

generate: ## Genera docker-compose y haproxy config
	@if [ "$(SHARDS)" -lt 3 ] 2>/dev/null; then \
		echo "${RED}❌ SHARDS debe ser al menos 3${NC}"; \
		exit 1; \
	fi
	@./scripts/generate-compose.sh $(SHARDS)
	@./scripts/generate-haproxy.sh $(SHARDS)

up: generate ## Inicia el cluster Redis (SHARDS=N)
	@echo "${BLUE}🚀 Iniciando Redis Cluster con $(SHARDS) shards ($(TOTAL_NODES) nodos)...${NC}"
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "${YELLOW}⏳ Esperando que los nodos estén listos...${NC}"
	@sleep 3
	@echo "${BLUE}🔧 Inicializando cluster...${NC}"
	@SHARDS=$(SHARDS) ./scripts/cluster-init.sh
	@echo "${GREEN}✅ Cluster listo con $(SHARDS) shards!${NC}"
	@echo ""
	@echo "Nodos disponibles:"
	@for i in $$(seq 1 $(SHARDS)); do \
		PORT=$$((6999 + i)); \
		echo "  Master $$i: localhost:$$PORT"; \
	done
	@for i in $$(seq 1 $(SHARDS)); do \
		NODE_NUM=$$((i + $(SHARDS))); \
		PORT=$$((6999 + NODE_NUM)); \
		echo "  Replica $$i: localhost:$$PORT"; \
	done
	@echo ""
	@echo "HAProxy:"
	@echo "  Masters (escritura):  localhost:6380  (master.local:6380)"
	@echo "  Discovery (lectura): localhost:6381  (clustercfg.local:6381)"
	@echo ""
	@SHARDS=$(SHARDS) ./scripts/hosts-apply.sh

down: ## Detiene el cluster
	@echo "${BLUE}🛑 Deteniendo cluster...${NC}"
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) down; \
	else \
		echo "${YELLOW}⚠️  No se encontró $(COMPOSE_FILE). Intentando docker-compose.yml...${NC}"; \
		docker compose down; \
	fi
	@./scripts/hosts-restore.sh
	@echo "${GREEN}✅ Cluster detenido${NC}"

status: ## Muestra estado del cluster
	@echo "${BLUE}📊 Estado del Cluster${NC}"
	@echo "====================="
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) ps; \
	else \
		docker compose ps; \
	fi
	@echo ""
	@echo "${BLUE}Nodos del Cluster:${NC}"
	@docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null | head -20 || echo "${RED}Cluster no inicializado. Ejecuta: make up${NC}"

test: install ## Ejecuta todos los tests
	@echo "${BLUE}🧪 Ejecutando tests...${NC}"
	@docker exec -e SHARDS=$(SHARDS) -it redis-lab php /app/tests/run-all-do.php
	@echo "${GREEN}✅ Tests completados${NC}"

scenarios: ## Muestra escenarios disponibles
	@echo "${BLUE}🎮 Escenarios Disponibles${NC}"
	@echo "========================="
	@echo ""
	@echo "${GREEN}Escenario 1:${NC}   make scenario-01  - Slots y Hash Tags"
	@echo "${GREEN}Escenario 2:${NC}   make scenario-02  - Hash Tags en profundidad"
	@echo "${GREEN}Escenario 3:${NC}   make scenario-03  - Routing de Predis"
	@echo "${GREEN}Escenario 4:${NC}   make scenario-04  - Redirecciones MOVED"
	@echo "${GREEN}Escenario 5:${NC}   make scenario-05  - Error READONLY"
	@echo "${GREEN}Escenario 6:${NC}   make scenario-06  - Error CROSSSLOT"
	@echo "${GREEN}Escenario 6a:${NC}  make scenario-06a - Error CROSSSLOT RAW"
	@echo "${GREEN}Escenario 7:${NC}   make scenario-07  - Failover"
	@echo "${GREEN}Escenario 8:${NC}   make scenario-08  - Patrones de Colas"
	@echo "${GREEN}Escenario 9:${NC}   make scenario-09  - Simulación Laravel"
	@echo ""
	@echo "${YELLOW}💡 Tip: Lee el código fuente de cada escenario para entender qué hace${NC}"

# Mapeo de escenarios a archivos
scenario-01: FILE=01-slots-basics.php
scenario-02: FILE=02-hash-tags.php
scenario-03: FILE=03-routing.php
scenario-04: FILE=04-moved-redirects.php
scenario-05: FILE=05-readonly-error.php
scenario-06: FILE=06-crossslot-error.php
scenario-06a: FILE=06-crossslot-error_raw.php
scenario-07: FILE=07-failover.php
scenario-08: FILE=08-queue-patterns.php
scenario-09: FILE=09-laravel-simulation.php

scenario-%: install ## Ejecuta un escenario específico (ej: make scenario-01)
	@echo "${BLUE}🎮 Ejecutando Escenario $*...${NC}"
	@if [ -z "$(FILE)" ]; then \
		echo "${RED}❌ Escenario $* no existe${NC}"; \
		exit 1; \
	fi
	@echo "${YELLOW}📖 Leyendo documentación del escenario...${NC}"
	@docker exec redis-lab head -20 /app/tests/$(FILE) | grep -A 15 "ESCENARIO" || true
	@echo ""
	@echo "${GREEN}▶ Ejecutando código...${NC}"
	@docker exec -e SHARDS=$(SHARDS) -it redis-lab php /app/tests/$(FILE)

shell: ## Accede a un nodo Redis (nodo 1 por defecto)
	@echo "${BLUE}🐚 Accediendo a redis-node-1:7000...${NC}"
	@redis-cli -h redis-node-1 -p 7000

shell-%: ## Accede a un nodo específico (ej: make shell-2)
	@echo "${BLUE}🐚 Accediendo a redis-node-$*:$$(($* + 6999))...${NC}"
	@redis-cli -h redis-node-$* -p $$(($* + 6999))

monitor: ## Monitorea comandos en tiempo real (nodo 1)
	@echo "${BLUE}👁️  Monitoreando redis-node-1:7000...${NC}"
	@echo "${YELLOW}Presiona Ctrl+C para salir${NC}"
	@redis-cli -h redis-node-1 -p 7000 MONITOR

monitor-%: ## Monitorea un nodo específico
	@echo "${BLUE}👁️  Monitoreando redis-node-$*:$$(($* + 6999))...${NC}"
	@redis-cli -h redis-node-$* -p $$(($* + 6999)) MONITOR

monitor-all: ## Monitorea TODOS los nodos simultáneamente
	@SHARDS=$(SHARDS) ./scripts/monitor-all.sh

reset: generate ## Limpia todo y reinicia (SHARDS=N)
	@echo "${RED}⚠️  Esto eliminará todos los datos${NC}"
	@read -p "¿Continuar? [y/N] " confirm && [ $$confirm = y ] || exit 1
	@echo "${BLUE}🧹 Limpiando...${NC}"
	@docker compose -f $(COMPOSE_FILE) down -v
	@docker compose -f $(COMPOSE_FILE) up -d
	@sleep 3
	@SHARDS=$(SHARDS) ./scripts/cluster-init.sh
	@echo "${GREEN}✅ Cluster reiniciado con $(SHARDS) shards${NC}"

logs: ## Muestra logs de todos los nodos
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) logs -f; \
	else \
		docker compose logs -f; \
	fi

logs-%: ## Muestra logs de un nodo específico
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) logs -f redis-node-$*; \
	else \
		docker compose logs -f redis-node-$*; \
	fi

install: ## Instala dependencias PHP localmente
	@if [ ! -d "vendor" ]; then \
		echo "${BLUE}📦 Instalando dependencias con Composer...${NC}"; \
		composer install; \
	fi

setup: ## Setup inicial completo
	@echo "${BLUE}🔧 Setup inicial...${NC}"
	@./scripts/setup.sh

info: ## Muestra información del cluster
	@echo "${BLUE}ℹ️  Información del Cluster${NC}"
	@echo "========================="
	@echo ""
	@echo "${GREEN}Slots distribuidos:${NC}"
	@docker exec redis-node-1 redis-cli -p 7000 CLUSTER SLOTS 2>/dev/null || echo "${RED}Cluster no disponible${NC}"
	@echo ""
	@echo "${GREEN}Nodos:${NC}"
	@docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null || echo "${RED}Cluster no disponible${NC}"
