# Incluir variables de entorno si existe el archivo
-include .env

# Defaults para binarios configurables
# Permitir modo verboso con V=1
ifeq ($(V),1)
  Q :=
else
  Q := @
endif

DOCKER_BIN ?= docker
DOCKER_COMPOSE_BIN ?= docker compose
PHP_BIN ?= php
COMPOSER_BIN ?= composer

# Redis Cluster Laboratory - Makefile
# Comandos simplificados para el laboratorio
#
# Uso: make up SHARDS=N  (default: 1, mínimo: 1)
# Cada shard = 1 master + 1 replica

.PHONY: help up down status test scenarios shell monitor monitor-all reset setup generate scenario-% lab queues

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
BLUE := $(shell printf '\033[36m')
GREEN := $(shell printf '\033[32m')
YELLOW := $(shell printf '\033[33m')
RED := $(shell printf '\033[31m')
NC := $(shell printf '\033[0m')
endif

help: ## Muestra esta ayuda
	$(Q)echo "${BLUE}Redis Cluster Laboratory${NC}"
	$(Q)echo "========================"
	$(Q)echo ""
	$(Q)echo "${GREEN}Uso: make <comando> SHARDS=N${NC}"
	$(Q)echo "  SHARDS: Cantidad de shards/masters (default: 3, mínimo: 3)"
	$(Q)echo "  Cada shard tiene 1 master + 1 replica"
	$(Q)echo ""
	$(Q)echo "${GREEN}Comandos disponibles:${NC}"
	$(Q)echo "  ${YELLOW}help${NC}             Muestra esta ayuda"
	$(Q)echo "  ${YELLOW}generate${NC}         Genera docker-compose y haproxy config"
	$(Q)echo "  ${YELLOW}up${NC}               Inicia el cluster Redis (SHARDS=N)"
	$(Q)echo "  ${YELLOW}down${NC}             Detiene el cluster"
	$(Q)echo "  ${YELLOW}status${NC}           Muestra estado del cluster"
	$(Q)echo "  ${YELLOW}info${NC}             Muestra información detallada del cluster"
	$(Q)echo "  ${YELLOW}test${NC}             Ejecuta todos los tests"
	$(Q)echo "  ${YELLOW}scenarios${NC}        Muestra escenarios disponibles"
	$(Q)echo "  ${YELLOW}scenario-[N]${NC}     Ejecuta un escenario específico (ej: make scenario-01)"
	$(Q)echo "  ${YELLOW}lab${NC}              Entra al bash del contenedor de tests (redis-lab)"
	$(Q)echo "  ${YELLOW}shell${NC}            Accede a un nodo Redis (nodo 1 por defecto)"
	$(Q)echo "  ${YELLOW}shell-[N]${NC}        Accede a un nodo específico (ej: make shell-2)"
	$(Q)echo "  ${YELLOW}monitor${NC}          Monitorea comandos en tiempo real (nodo 1)"
	$(Q)echo "  ${YELLOW}monitor-[N]${NC}      Monitorea un nodo específico (ej: make monitor-3)"
	$(Q)echo "  ${YELLOW}monitor-all${NC}      Monitorea TODOS los nodos simultáneamente"
	$(Q)echo "  ${YELLOW}logs${NC}             Muestra logs de todos los nodos"
	$(Q)echo "  ${YELLOW}logs-[N]${NC}         Muestra logs de un nodo específico"
	$(Q)echo "  ${YELLOW}queues${NC}             Lista visualmente las colas del cluster"
	$(Q)echo "  ${YELLOW}reset${NC}            Limpia todo y reinicia (SHARDS=N)"
	$(Q)echo "  ${YELLOW}install${NC}          Instala dependencias PHP localmente"
	$(Q)echo "  ${YELLOW}setup${NC}            Setup inicial completo"

generate: ## Genera docker-compose y haproxy config
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "if ([int]'$(SHARDS)' -lt 3) { Write-Host '❌ SHARDS debe ser al menos 3' -ForegroundColor Red; exit 1 }"
else
	$(Q)if [ "$(SHARDS)" -lt 3 ] 2>/dev/null; then \
		echo "${RED}❌ SHARDS debe ser al menos 3${NC}"; \
		exit 1; \
	fi
endif
	$(Q)$(CMD_GEN_COMPOSE)
	$(Q)$(CMD_GEN_HAPROXY)

up: generate ## Inicia el cluster Redis (SHARDS=N)
	$(Q)echo "${BLUE}🚀 Iniciando Redis Cluster con $(SHARDS) shards ($(TOTAL_NODES) nodos)...${NC}"
	$(Q)$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) up -d
	$(Q)echo "${YELLOW}⏳ Esperando que los nodos estén listos...${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "Start-Sleep -Seconds 3"
else
	$(Q)sleep 3
endif
	$(Q)echo "${BLUE}🔧 Inicializando cluster...${NC}"
	$(Q)$(CMD_CLUSTER_INIT)
	$(Q)echo "${GREEN}✅ Cluster listo con $(SHARDS) shards!${NC}"
	$(Q)echo ""
	$(Q)echo "Nodos disponibles:"
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "for ($$i=1; $$i -le $(SHARDS); $$i++) { $$PORT=6999+$$i; Write-Host \"  Master $$i`: localhost:$$PORT\" }; for ($$i=1; $$i -le $(SHARDS); $$i++) { $$NODE_NUM=$$i+$(SHARDS); $$PORT=6999+$$NODE_NUM; Write-Host \"  Replica $$i`: localhost:$$PORT\" }"
else
	$(Q)for i in $$(seq 1 $(SHARDS)); do \
		PORT=$$((6999 + i)); \
		echo "  Master $$i: localhost:$$PORT"; \
	done
	$(Q)for i in $$(seq 1 $(SHARDS)); do \
		NODE_NUM=$$((i + $(SHARDS))); \
		PORT=$$((6999 + NODE_NUM)); \
		echo "  Replica $$i: localhost:$$PORT"; \
	done
endif
	$(Q)echo ""
	$(Q)echo "HAProxy:"
	$(Q)echo "  Masters (escritura):  localhost:6380  (master.local:6380)"
	$(Q)echo "  Discovery (lectura): localhost:6381  (clustercfg.local:6381)"
	$(Q)echo ""
	$(Q)$(CMD_HOSTS_APPLY)

down: ## Detiene el cluster
	$(Q)echo "${BLUE}🛑 Deteniendo cluster...${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)if exist $(COMPOSE_FILE) ($(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) down) else (echo ⚠️  No se encontró $(COMPOSE_FILE). Intentando docker-compose.yml... & $(DOCKER_COMPOSE_BIN) down)
else
	$(Q)if [ -f $(COMPOSE_FILE) ]; then \
		$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) down; \
	else \
		echo "${YELLOW}⚠️  No se encontró $(COMPOSE_FILE). Intentando docker-compose.yml...${NC}"; \
		$(DOCKER_COMPOSE_BIN) down; \
	fi
endif
	$(Q)$(CMD_HOSTS_RESTORE)
	$(Q)echo "${GREEN}✅ Cluster detenido${NC}"

status: ## Muestra estado del cluster
ifeq ($(OS),Windows_NT)
	$(Q)powershell.exe -ExecutionPolicy Bypass -File .\scripts\status.ps1
else
	$(Q)./scripts/status.sh
endif

test: install ## Ejecuta todos los tests
	$(Q)echo "${BLUE}🧪 Ejecutando tests...${NC}"
	$(Q)$(DOCKER_BIN) exec -e SHARDS=$(SHARDS) -it redis-lab $(PHP_BIN) /app/tests/run-all-do.php
	$(Q)echo "${GREEN}✅ Tests completados${NC}"

scenarios: ## Muestra escenarios disponibles
	$(Q)echo "${BLUE}🎮 Escenarios Disponibles${NC}"
	$(Q)echo "========================="
	$(Q)echo ""
	$(Q)echo "${GREEN}Escenario 1:${NC}   make scenario-01  - Slots y Hash Tags"
	$(Q)echo "${GREEN}Escenario 2:${NC}   make scenario-02  - Hash Tags en profundidad"
	$(Q)echo "${GREEN}Escenario 3:${NC}   make scenario-03  - Routing de Predis"
	$(Q)echo "${GREEN}Escenario 4:${NC}   make scenario-04  - Redirecciones MOVED"
	$(Q)echo "${GREEN}Escenario 5:${NC}   make scenario-05  - Error READONLY"
	$(Q)echo "${GREEN}Escenario 6:${NC}   make scenario-06  - Error CROSSSLOT"
	$(Q)echo "${GREEN}Escenario 6a:${NC}  make scenario-06a - Error CROSSSLOT RAW"
	$(Q)echo "${GREEN}Escenario 7:${NC}   make scenario-07  - Failover"
	$(Q)echo "${GREEN}Escenario 8:${NC}   make scenario-08  - Patrones de Colas"
	$(Q)echo "${GREEN}Escenario 9:${NC}   make scenario-09  - Simulación Laravel"
	$(Q)echo ""
	$(Q)echo "${YELLOW}💡 Tip: Lee el código fuente de cada escenario para entender qué hace${NC}"

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
	$(Q)echo "${BLUE}🎮 Ejecutando Escenario $*...${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)if "$(FILE)"=="" (echo ❌ Escenario $* no existe & exit /b 1)
	$(Q)echo "${YELLOW}📖 Leyendo documentación del escenario...${NC}"
	$(Q)powershell -NoProfile -Command "$(DOCKER_BIN) exec redis-lab head -20 /app/tests/$(FILE) 2>$$null | Select-String -Pattern 'ESCENARIO' -Context 0,15 | ForEach-Object { $$_.Line; $$_.Context.PostContext }"
else
	$(Q)if [ -z "$(FILE)" ]; then \
		echo "${RED}❌ Escenario $* no existe${NC}"; \
		exit 1; \
	fi
	$(Q)echo "${YELLOW}📖 Leyendo documentación del escenario...${NC}"
	$(Q)$(DOCKER_BIN) exec redis-lab head -20 /app/tests/$(FILE) | grep -A 15 "ESCENARIO" || true
endif
	$(Q)echo ""
	$(Q)echo "${GREEN}▶ Ejecutando código...${NC}"
	$(Q)$(DOCKER_BIN) exec -e SHARDS=$(SHARDS) -it redis-lab $(PHP_BIN) /app/tests/$(FILE)

lab: ## Entra al bash del contenedor redis-lab (tests)
	$(Q)echo "${BLUE}🧪 Accediendo al contenedor de laboratorio (redis-lab)...${NC}"
	$(Q)$(DOCKER_BIN) exec -e SHARDS=$(SHARDS) -it redis-lab bash

shell: ## Accede a un nodo Redis (nodo 1 por defecto)
	$(Q)echo "${BLUE}🐚 Accediendo a redis-node-1...${NC}"
	$(Q)$(DOCKER_BIN) exec -it redis-node-1 redis-cli -c -p 7000

shell-%: ## Accede a un nodo específico (ej: make shell-2)
	$(Q)echo "${BLUE}🐚 Accediendo a redis-node-$*...${NC}"
	$(Q)$(DOCKER_BIN) exec -it redis-node-$* redis-cli -p $$(($* + 6999))

monitor: ## Monitorea comandos en tiempo real (nodo 1)
	$(Q)echo "${BLUE}👁️  Monitoreando redis-node-1...${NC}"
	$(Q)echo "${YELLOW}Presiona Ctrl+C para salir${NC}"
	$(Q)$(DOCKER_BIN) exec -it redis-node-1 redis-cli -p 7000 MONITOR

monitor-%: ## Monitorea un nodo específico
	$(Q)echo "${BLUE}👁️  Monitoreando redis-node-$*...${NC}"
	$(Q)$(DOCKER_BIN) exec -it redis-node-$* redis-cli -p $$(($* + 6999)) MONITOR

monitor-all: ## Monitorea TODOS los nodos simultáneamente
	$(Q)$(CMD_MONITOR_ALL)

reset: generate ## Limpia todo y reinicia (SHARDS=N)
	$(Q)echo "${RED}⚠️  Esto eliminará todos los datos${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "$$confirm = Read-Host '¿Continuar? [y/N]'; if ($$confirm -notmatch '^y$$|^Y$$') { exit 1 }"
	$(Q)echo "${BLUE}🧹 Limpiando...${NC}"
	$(Q)$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) down -v
	$(Q)$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) up -d
	$(Q)powershell -NoProfile -Command "Start-Sleep -Seconds 3"
else
	$(Q)read -p "¿Continuar? [y/N] " confirm && [ $$confirm = y ] || exit 1
	$(Q)echo "${BLUE}🧹 Limpiando...${NC}"
	$(Q)$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) down -v
	$(Q)$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) up -d
	$(Q)sleep 3
endif
	$(Q)$(CMD_CLUSTER_INIT)
	$(Q)echo "${GREEN}✅ Cluster reiniciado con $(SHARDS) shards${NC}"

logs: ## Muestra logs de todos los nodos
ifeq ($(OS),Windows_NT)
	$(Q)if exist $(COMPOSE_FILE) ($(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) logs -f) else ($(DOCKER_COMPOSE_BIN) logs -f)
else
	$(Q)if [ -f $(COMPOSE_FILE) ]; then \
		$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) logs -f; \
	else \
		$(DOCKER_COMPOSE_BIN) logs -f; \
	fi
endif

logs-%: ## Muestra logs de un nodo específico
ifeq ($(OS),Windows_NT)
	$(Q)if exist $(COMPOSE_FILE) ($(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) logs -f redis-node-$*) else ($(DOCKER_COMPOSE_BIN) logs -f redis-node-$*)
else
	$(Q)if [ -f $(COMPOSE_FILE) ]; then \
		$(DOCKER_COMPOSE_BIN) -f $(COMPOSE_FILE) logs -f redis-node-$*; \
	else \
		$(DOCKER_COMPOSE_BIN) logs -f redis-node-$*; \
	fi
endif

install: ## Instala dependencias PHP localmente
ifeq ($(OS),Windows_NT)
	$(Q)if not exist "vendor" (echo ${BLUE}📦 Instalando dependencias con Composer...${NC} & $(COMPOSER_BIN) install)
else
	$(Q)if [ ! -d "vendor" ]; then \
		echo "${BLUE}📦 Instalando dependencias con Composer...${NC}"; \
		$(COMPOSER_BIN) install; \
	fi
endif

setup: ## Setup inicial completo
	$(Q)echo "${BLUE}🔧 Setup inicial...${NC}"
	$(Q)$(CMD_SETUP)

info: ## Muestra información del cluster y endpoints HAProxy
ifeq ($(OS),Windows_NT)
	$(Q)powershell.exe -ExecutionPolicy Bypass -File .\scripts\cluster-info.ps1
else
	$(Q)./scripts/cluster-info.sh
endif

queues: ## Lista las colas (queues*) distribuidas en el cluster
ifeq ($(OS),Windows_NT)
	$(Q)powershell.exe -ExecutionPolicy Bypass -File .\scripts\list-queues.ps1
else
	$(Q)./scripts/list-queues.sh
endif
