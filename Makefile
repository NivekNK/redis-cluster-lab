# Redis Cluster Laboratory - Makefile
# Comandos simplificados para el laboratorio
#
# Uso: make up SHARDS=N  (default: 1, mínimo: 1)
# Cada shard = 1 master + 1 replica

.PHONY: help up down status test scenarios shell monitor monitor-all reset setup generate scenario-% lab

# Cantidad de shards (masters). Cada shard tiene 1 replica.
SHARDS ?= 3
TOTAL_NODES = $(shell echo $$(($(SHARDS) * 2)))
COMPOSE_FILE = docker-compose.generated.yml

ifeq ($(OS),Windows_NT)
    CMD_GEN_COMPOSE := powershell.exe -ExecutionPolicy Bypass -File .\scripts\generate-compose.ps1 -SHARDS $(SHARDS)
    CMD_GEN_HAPROXY := powershell.exe -ExecutionPolicy Bypass -File .\scripts\generate-haproxy.ps1 -SHARDS $(SHARDS)
    CMD_CLUSTER_INIT := powershell.exe -ExecutionPolicy Bypass -File .\scripts\cluster-init.ps1 -SHARDS $(SHARDS)
    CMD_HOSTS_APPLY := powershell.exe -ExecutionPolicy Bypass -File .\scripts\hosts-apply.ps1 -SHARDS $(SHARDS)
    CMD_HOSTS_RESTORE := powershell.exe -ExecutionPolicy Bypass -File .\scripts\hosts-restore.ps1
    CMD_MONITOR_ALL := powershell.exe -ExecutionPolicy Bypass -File .\scripts\monitor-all.ps1 -SHARDS $(SHARDS)
    CMD_RESET := powershell.exe -ExecutionPolicy Bypass -File .\scripts\reset.ps1 -SHARDS $(SHARDS)
    CMD_SETUP := powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup.ps1
    CMD_STATUS := powershell.exe -ExecutionPolicy Bypass -File .\scripts\cluster-status.ps1
else
    CMD_GEN_COMPOSE := ./scripts/generate-compose.sh $(SHARDS)
    CMD_GEN_HAPROXY := ./scripts/generate-haproxy.sh $(SHARDS)
    CMD_CLUSTER_INIT := SHARDS=$(SHARDS) ./scripts/cluster-init.sh
    CMD_HOSTS_APPLY := SHARDS=$(SHARDS) ./scripts/hosts-apply.sh
    CMD_HOSTS_RESTORE := ./scripts/hosts-restore.sh
    CMD_MONITOR_ALL := SHARDS=$(SHARDS) ./scripts/monitor-all.sh
    CMD_RESET := SHARDS=$(SHARDS) ./scripts/reset.sh
    CMD_SETUP := ./scripts/setup.sh
    CMD_STATUS := ./scripts/cluster-status.sh
endif

# Colores para output
ifeq ($(OS),Windows_NT)
BLUE := 
GREEN := 
YELLOW := 
RED := 
NC := 
else
BLUE := \033[36m
GREEN := \033[32m
YELLOW := \033[33m
RED := \033[31m
NC := \033[0m
endif

help: ## Muestra esta ayuda
	@echo "${BLUE}Redis Cluster Laboratory${NC}"
	@echo "========================"
	@echo ""
	@echo "${GREEN}Uso: make <comando> SHARDS=N${NC}"
	@echo "  SHARDS: Cantidad de shards/masters (default: 3, mínimo: 3)"
	@echo "  Cada shard tiene 1 master + 1 replica"
	@echo ""
	@echo "${GREEN}Comandos disponibles:${NC}"
	@echo "  ${YELLOW}help${NC}             Muestra esta ayuda"
	@echo "  ${YELLOW}generate${NC}         Genera docker-compose y haproxy config"
	@echo "  ${YELLOW}up${NC}               Inicia el cluster Redis (SHARDS=N)"
	@echo "  ${YELLOW}down${NC}             Detiene el cluster"
	@echo "  ${YELLOW}status${NC}           Muestra estado del cluster"
	@echo "  ${YELLOW}info${NC}             Muestra información detallada del cluster"
	@echo "  ${YELLOW}test${NC}             Ejecuta todos los tests"
	@echo "  ${YELLOW}scenarios${NC}        Muestra escenarios disponibles"
	@echo "  ${YELLOW}scenario-[N]${NC}     Ejecuta un escenario específico (ej: make scenario-01)"
	@echo "  ${YELLOW}lab${NC}              Entra al bash del contenedor de tests (redis-lab)"
	@echo "  ${YELLOW}shell${NC}            Accede a un nodo Redis (nodo 1 por defecto)"
	@echo "  ${YELLOW}shell-[N]${NC}        Accede a un nodo específico (ej: make shell-2)"
	@echo "  ${YELLOW}monitor${NC}          Monitorea comandos en tiempo real (nodo 1)"
	@echo "  ${YELLOW}monitor-[N]${NC}      Monitorea un nodo específico (ej: make monitor-3)"
	@echo "  ${YELLOW}monitor-all${NC}      Monitorea TODOS los nodos simultáneamente"
	@echo "  ${YELLOW}logs${NC}             Muestra logs de todos los nodos"
	@echo "  ${YELLOW}logs-[N]${NC}         Muestra logs de un nodo específico"
	@echo "  ${YELLOW}reset${NC}            Limpia todo y reinicia (SHARDS=N)"
	@echo "  ${YELLOW}install${NC}          Instala dependencias PHP localmente"
	@echo "  ${YELLOW}setup${NC}            Setup inicial completo"

generate: ## Genera docker-compose y haproxy config
ifeq ($(OS),Windows_NT)
	@powershell -NoProfile -Command "if ([int]'$(SHARDS)' -lt 3) { Write-Host '❌ SHARDS debe ser al menos 3' -ForegroundColor Red; exit 1 }"
else
	@if [ "$(SHARDS)" -lt 3 ] 2>/dev/null; then \
		echo "${RED}❌ SHARDS debe ser al menos 3${NC}"; \
		exit 1; \
	fi
endif
	@$(CMD_GEN_COMPOSE)
	@$(CMD_GEN_HAPROXY)

up: generate ## Inicia el cluster Redis (SHARDS=N)
	@echo "${BLUE}🚀 Iniciando Redis Cluster con $(SHARDS) shards ($(TOTAL_NODES) nodos)...${NC}"
	@docker compose -f $(COMPOSE_FILE) up -d
	@echo "${YELLOW}⏳ Esperando que los nodos estén listos...${NC}"
ifeq ($(OS),Windows_NT)
	@powershell -NoProfile -Command "Start-Sleep -Seconds 3"
else
	@sleep 3
endif
	@echo "${BLUE}🔧 Inicializando cluster...${NC}"
	@$(CMD_CLUSTER_INIT)
	@echo "${GREEN}✅ Cluster listo con $(SHARDS) shards!${NC}"
	@echo ""
	@echo "Nodos disponibles:"
ifeq ($(OS),Windows_NT)
	@powershell -NoProfile -Command "for ($$i=1; $$i -le $(SHARDS); $$i++) { $$PORT=6999+$$i; Write-Host \"  Master $$i`: localhost:$$PORT\" }; for ($$i=1; $$i -le $(SHARDS); $$i++) { $$NODE_NUM=$$i+$(SHARDS); $$PORT=6999+$$NODE_NUM; Write-Host \"  Replica $$i`: localhost:$$PORT\" }"
else
	@for i in $$(seq 1 $(SHARDS)); do \
		PORT=$$((6999 + i)); \
		echo "  Master $$i: localhost:$$PORT"; \
	done
	@for i in $$(seq 1 $(SHARDS)); do \
		NODE_NUM=$$((i + $(SHARDS))); \
		PORT=$$((6999 + NODE_NUM)); \
		echo "  Replica $$i: localhost:$$PORT"; \
	done
endif
	@echo ""
	@echo "HAProxy:"
	@echo "  Masters (escritura):  localhost:6380  (master.local:6380)"
	@echo "  Discovery (lectura): localhost:6381  (clustercfg.local:6381)"
	@echo ""
	@$(CMD_HOSTS_APPLY)

down: ## Detiene el cluster
	@echo "${BLUE}🛑 Deteniendo cluster...${NC}"
ifeq ($(OS),Windows_NT)
	@if exist $(COMPOSE_FILE) (docker compose -f $(COMPOSE_FILE) down) else (echo ⚠️  No se encontró $(COMPOSE_FILE). Intentando docker-compose.yml... & docker compose down)
else
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) down; \
	else \
		echo "${YELLOW}⚠️  No se encontró $(COMPOSE_FILE). Intentando docker-compose.yml...${NC}"; \
		docker compose down; \
	fi
endif
	@$(CMD_HOSTS_RESTORE)
	@echo "${GREEN}✅ Cluster detenido${NC}"

status: ## Muestra estado del cluster
	@echo "${BLUE}📊 Estado del Cluster${NC}"
	@echo "====================="
ifeq ($(OS),Windows_NT)
	@if exist $(COMPOSE_FILE) (docker compose -f $(COMPOSE_FILE) ps) else (docker compose ps)
	@echo ""
	@echo "${BLUE}Nodos del Cluster:${NC}"
	@powershell -NoProfile -Command "$$out = docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>$$null; if ($$LASTEXITCODE -ne 0) { Write-Host 'Cluster no inicializado. Ejecuta: make up' -ForegroundColor Red } else { $$out | Select-Object -First 20 }"
else
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) ps; \
	else \
		docker compose ps; \
	fi
	@echo ""
	@echo "${BLUE}Nodos del Cluster:${NC}"
	@docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null | head -20 || echo "${RED}Cluster no inicializado. Ejecuta: make up${NC}"
endif

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
ifeq ($(OS),Windows_NT)
	@if "$(FILE)"=="" (echo ❌ Escenario $* no existe & exit /b 1)
	@echo "${YELLOW}📖 Leyendo documentación del escenario...${NC}"
	@powershell -NoProfile -Command "docker exec redis-lab head -20 /app/tests/$(FILE) 2>$$null | Select-String -Pattern 'ESCENARIO' -Context 0,15 | ForEach-Object { $$_.Line; $$_.Context.PostContext }"
else
	@if [ -z "$(FILE)" ]; then \
		echo "${RED}❌ Escenario $* no existe${NC}"; \
		exit 1; \
	fi
	@echo "${YELLOW}📖 Leyendo documentación del escenario...${NC}"
	@docker exec redis-lab head -20 /app/tests/$(FILE) | grep -A 15 "ESCENARIO" || true
endif
	@echo ""
	@echo "${GREEN}▶ Ejecutando código...${NC}"
	@docker exec -e SHARDS=$(SHARDS) -it redis-lab php /app/tests/$(FILE)

lab: ## Entra al bash del contenedor redis-lab (tests)
	@echo "${BLUE}🧪 Accediendo al contenedor de laboratorio (redis-lab)...${NC}"
	@docker exec -e SHARDS=$(SHARDS) -it redis-lab bash

shell: ## Accede a un nodo Redis (nodo 1 por defecto)
	@echo "${BLUE}🐚 Accediendo a redis-node-1...${NC}"
	@docker exec -it redis-node-1 redis-cli -p 7000

shell-%: ## Accede a un nodo específico (ej: make shell-2)
	@echo "${BLUE}🐚 Accediendo a redis-node-$*...${NC}"
	@docker exec -it redis-node-$* redis-cli -p $$(($* + 6999))

monitor: ## Monitorea comandos en tiempo real (nodo 1)
	@echo "${BLUE}👁️  Monitoreando redis-node-1...${NC}"
	@echo "${YELLOW}Presiona Ctrl+C para salir${NC}"
	@docker exec -it redis-node-1 redis-cli -p 7000 MONITOR

monitor-%: ## Monitorea un nodo específico
	@echo "${BLUE}👁️  Monitoreando redis-node-$*...${NC}"
	@docker exec -it redis-node-$* redis-cli -p $$(($* + 6999)) MONITOR

monitor-all: ## Monitorea TODOS los nodos simultáneamente
	@$(CMD_MONITOR_ALL)

reset: generate ## Limpia todo y reinicia (SHARDS=N)
	@echo "${RED}⚠️  Esto eliminará todos los datos${NC}"
ifeq ($(OS),Windows_NT)
	@powershell -NoProfile -Command "$$confirm = Read-Host '¿Continuar? [y/N]'; if ($$confirm -notmatch '^y$$|^Y$$') { exit 1 }"
	@echo "${BLUE}🧹 Limpiando...${NC}"
	@docker compose -f $(COMPOSE_FILE) down -v
	@docker compose -f $(COMPOSE_FILE) up -d
	@powershell -NoProfile -Command "Start-Sleep -Seconds 3"
else
	@read -p "¿Continuar? [y/N] " confirm && [ $$confirm = y ] || exit 1
	@echo "${BLUE}🧹 Limpiando...${NC}"
	@docker compose -f $(COMPOSE_FILE) down -v
	@docker compose -f $(COMPOSE_FILE) up -d
	@sleep 3
endif
	@$(CMD_CLUSTER_INIT)
	@echo "${GREEN}✅ Cluster reiniciado con $(SHARDS) shards${NC}"

logs: ## Muestra logs de todos los nodos
ifeq ($(OS),Windows_NT)
	@if exist $(COMPOSE_FILE) (docker compose -f $(COMPOSE_FILE) logs -f) else (docker compose logs -f)
else
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) logs -f; \
	else \
		docker compose logs -f; \
	fi
endif

logs-%: ## Muestra logs de un nodo específico
ifeq ($(OS),Windows_NT)
	@if exist $(COMPOSE_FILE) (docker compose -f $(COMPOSE_FILE) logs -f redis-node-$*) else (docker compose logs -f redis-node-$*)
else
	@if [ -f $(COMPOSE_FILE) ]; then \
		docker compose -f $(COMPOSE_FILE) logs -f redis-node-$*; \
	else \
		docker compose logs -f redis-node-$*; \
	fi
endif

install: ## Instala dependencias PHP localmente
ifeq ($(OS),Windows_NT)
	@if not exist "vendor" (echo ${BLUE}📦 Instalando dependencias con Composer...${NC} & composer install)
else
	@if [ ! -d "vendor" ]; then \
		echo "${BLUE}📦 Instalando dependencias con Composer...${NC}"; \
		composer install; \
	fi
endif

setup: ## Setup inicial completo
	@echo "${BLUE}🔧 Setup inicial...${NC}"
	@$(CMD_SETUP)

info: ## Muestra información del cluster
	@echo "${BLUE}ℹ️  Información del Cluster${NC}"
	@echo "========================="
	@echo ""
	@echo "${GREEN}Slots distribuidos:${NC}"
	@docker exec redis-node-1 redis-cli -p 7000 CLUSTER SLOTS 2>/dev/null || echo "${RED}Cluster no disponible${NC}"
	@echo ""
	@echo "${GREEN}Nodos:${NC}"
	@docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null || echo "${RED}Cluster no disponible${NC}"
