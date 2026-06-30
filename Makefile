# Incluir variables de entorno si existe el archivo
-include .env

# Permitir modo verboso con V=1
ifeq ($(V),1)
  Q :=
else
  Q := @
endif

DOCKER_BIN ?= docker
DOCKER_COMPOSE_BIN ?= docker compose
DOCKER_BUILDKIT ?= 0
export DOCKER_BUILDKIT

# Redis Cluster Laboratory - Makefile
# Uso: make up SHARDS=N  (default: 3, minimo: 3)
# Cada shard = 1 master + 1 replica

.PHONY: help generate up down status info setup reset logs logs-% \
	suites scenarios test test-all install install-all lab shell shell-% \
	monitor monitor-% monitor-all queues

SHARDS ?= 3
export SHARDS
IP ?=
export IP
TOTAL_NODES = $(shell echo $$(($(SHARDS) * 2)))

RUN_ARGS = $(filter-out $@,$(MAKECMDGOALS))
FIRST_GOAL = $(firstword $(MAKECMDGOALS))

COMPOSE_FILE = docker-compose.generated.yml
LAB_COMPOSE_FILES = $(shell if [ -d suites ]; then find suites -mindepth 3 -maxdepth 3 -name docker-compose.lab.yml | sort | sed 's#^# -f #'; fi)
COMPOSE_FILES = -f $(COMPOSE_FILE) $(LAB_COMPOSE_FILES)
COMPOSE_FALLBACK_FILES = -f docker-compose.yml $(LAB_COMPOSE_FILES)

ifeq ($(OS),Windows_NT)
    CMD_GEN_COMPOSE := powershell.exe -ExecutionPolicy Bypass -File .\scripts\generate-compose.ps1 -SHARDS $(SHARDS) -IP "$(IP)"
    CMD_GEN_HAPROXY := powershell.exe -ExecutionPolicy Bypass -File .\scripts\generate-haproxy.ps1 -SHARDS $(SHARDS)
    CMD_CLUSTER_INIT := powershell.exe -ExecutionPolicy Bypass -File .\scripts\cluster-init.ps1 -SHARDS $(SHARDS)
    CMD_HOSTS_APPLY := powershell.exe -ExecutionPolicy Bypass -File .\scripts\hosts-apply.ps1 -SHARDS $(SHARDS)
    CMD_HOSTS_RESTORE := powershell.exe -ExecutionPolicy Bypass -File .\scripts\hosts-restore.ps1
    CMD_MONITOR_ALL := powershell.exe -ExecutionPolicy Bypass -File .\scripts\monitor-all.ps1 -SHARDS $(SHARDS)
    CMD_SETUP := powershell.exe -ExecutionPolicy Bypass -File .\scripts\setup.ps1
else
    CMD_GEN_COMPOSE := IP="$(IP)" ./scripts/generate-compose.sh $(SHARDS)
    CMD_GEN_HAPROXY := ./scripts/generate-haproxy.sh $(SHARDS)
    CMD_CLUSTER_INIT := SHARDS=$(SHARDS) ./scripts/cluster-init.sh
    CMD_HOSTS_APPLY := SHARDS=$(SHARDS) ./scripts/hosts-apply.sh
    CMD_HOSTS_RESTORE := ./scripts/hosts-restore.sh
    CMD_MONITOR_ALL := SHARDS=$(SHARDS) ./scripts/monitor-all.sh
    CMD_SETUP := ./scripts/setup.sh
endif

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
	$(Q)echo "${GREEN}Infraestructura:${NC}"
	$(Q)echo "  ${YELLOW}make up${NC}                         Inicia Redis, HAProxy y runners"
	$(Q)echo "  ${YELLOW}make down${NC}                       Detiene el laboratorio"
	$(Q)echo "  ${YELLOW}make status${NC}                     Muestra contenedores"
	$(Q)echo "  ${YELLOW}make info${NC}                       Muestra slots y endpoints"
	$(Q)echo "  ${YELLOW}make reset${NC}                      Limpia volumenes y reinicia"
	$(Q)echo ""
	$(Q)echo "${GREEN}Suites y escenarios:${NC}"
	$(Q)echo "  ${YELLOW}make scenarios${NC}                  Lista todas las suites"
	$(Q)echo "  ${YELLOW}make scenarios <language>${NC}       Lista librerias de un lenguaje"
	$(Q)echo "  ${YELLOW}make scenarios <language>/<library>${NC}"
	$(Q)echo "  ${YELLOW}make install <language>/<library>${NC}"
	$(Q)echo "  ${YELLOW}make install-all${NC}                Instala todas las suites"
	$(Q)echo "  ${YELLOW}make test <language>/<library>${NC}"
	$(Q)echo "  ${YELLOW}make test <language>/<library>/<scenario>${NC}"
	$(Q)echo "  ${YELLOW}make test-all [<language>[/<library>]]${NC}"
	$(Q)echo "  ${YELLOW}make lab <language>/<library>${NC}"
	$(Q)echo ""
	$(Q)echo "${GREEN}Redis:${NC}"
	$(Q)echo "  ${YELLOW}make shell${NC}                      Accede a redis-node-1"
	$(Q)echo "  ${YELLOW}make shell-N${NC}                    Accede a redis-node-N"
	$(Q)echo "  ${YELLOW}make monitor${NC}                    MONITOR en redis-node-1"
	$(Q)echo "  ${YELLOW}make monitor-N${NC}                  MONITOR en redis-node-N"
	$(Q)echo "  ${YELLOW}make monitor-all${NC}                Monitorea todos los nodos"
	$(Q)echo "  ${YELLOW}make queues${NC}                     Lista colas del cluster"

generate: ## Genera docker-compose y haproxy config
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "if ([int]'$(SHARDS)' -lt 3) { Write-Host 'SHARDS debe ser al menos 3' -ForegroundColor Red; exit 1 }"
else
	$(Q)if [ "$(SHARDS)" -lt 3 ] 2>/dev/null; then \
		echo "${RED}SHARDS debe ser al menos 3${NC}"; \
		exit 1; \
	fi
endif
	$(Q)$(CMD_GEN_COMPOSE)
	$(Q)$(CMD_GEN_HAPROXY)

up: generate ## Inicia Redis, HAProxy y runners de labs
	$(Q)echo "${BLUE}Iniciando Redis Cluster con $(SHARDS) shards ($(TOTAL_NODES) nodos)...${NC}"
	$(Q)$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) up -d --build --remove-orphans
	$(Q)echo "${YELLOW}Esperando que los nodos esten listos...${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "Start-Sleep -Seconds 3"
else
	$(Q)sleep 3
endif
	$(Q)echo "${BLUE}Inicializando cluster...${NC}"
	$(Q)$(CMD_CLUSTER_INIT)
	$(Q)echo "${GREEN}Cluster listo con $(SHARDS) shards.${NC}"
	$(Q)echo ""
	$(Q)echo "HAProxy:"
	$(Q)echo "  Masters:   localhost:6380  (master.local:6380)"
	$(Q)echo "  Discovery: localhost:6381  (clustercfg.local:6381)"
	$(Q)echo ""
	$(Q)echo "Suites:"
	$(Q)./scripts/suites.sh scenarios
	$(Q)$(CMD_HOSTS_APPLY)

down: ## Detiene el laboratorio
	$(Q)echo "${BLUE}Deteniendo laboratorio...${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)if exist $(COMPOSE_FILE) ($(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) down --remove-orphans) else ($(DOCKER_COMPOSE_BIN) $(COMPOSE_FALLBACK_FILES) down --remove-orphans)
else
	$(Q)if [ -f "$(COMPOSE_FILE)" ]; then \
		$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) down --remove-orphans; \
	else \
		$(DOCKER_COMPOSE_BIN) $(COMPOSE_FALLBACK_FILES) down --remove-orphans; \
	fi
endif
	$(Q)$(CMD_HOSTS_RESTORE)
	$(Q)echo "${GREEN}Laboratorio detenido.${NC}"

status: ## Muestra estado del cluster
ifeq ($(OS),Windows_NT)
	$(Q)powershell.exe -ExecutionPolicy Bypass -File .\scripts\status.ps1
else
	$(Q)./scripts/status.sh
endif

info: ## Muestra informacion del cluster y endpoints HAProxy
ifeq ($(OS),Windows_NT)
	$(Q)powershell.exe -ExecutionPolicy Bypass -File .\scripts\cluster-info.ps1
else
	$(Q)./scripts/cluster-info.sh
endif

setup: ## Setup inicial
	$(Q)$(CMD_SETUP)

suites:
	$(Q)echo "Comando obsoleto: usa make scenarios"
	$(Q)exit 2

scenarios: ## Lista escenarios por language/library
	$(Q)./scripts/suites.sh scenarios "$(RUN_ARGS)"

install: ## Instala dependencias de una suite
	$(Q)if [ -z "$(RUN_ARGS)" ]; then ./scripts/suites.sh help; exit 2; fi
	$(Q)./scripts/suites.sh install "$(RUN_ARGS)"

install-all: ## Instala dependencias de todas las suites
	$(Q)./scripts/suites.sh install-all

test: ## Ejecuta una suite o escenario: make test language/library[/scenario]
	$(Q)if [ -z "$(RUN_ARGS)" ]; then ./scripts/suites.sh help; exit 2; fi
	$(Q)./scripts/suites.sh test "$(RUN_ARGS)"

test-all: ## Ejecuta todas las suites o un scope
	$(Q)./scripts/suites.sh test-all "$(RUN_ARGS)"

lab: ## Shell en un runner: make lab language/library
	$(Q)if [ -z "$(RUN_ARGS)" ]; then ./scripts/suites.sh help; exit 2; fi
	$(Q)./scripts/suites.sh shell "$(RUN_ARGS)"

shell: ## Accede a redis-node-1
	$(Q)$(DOCKER_BIN) exec -it redis-node-1 redis-cli -c -p 7000

shell-%: ## Accede a un nodo especifico
	$(Q)$(DOCKER_BIN) exec -it redis-node-$* redis-cli -p $$(($* + 6999))

monitor: ## MONITOR en redis-node-1
	$(Q)echo "${YELLOW}Presiona Ctrl+C para salir${NC}"
	$(Q)$(DOCKER_BIN) exec -it redis-node-1 redis-cli -p 7000 MONITOR

monitor-%: ## MONITOR en un nodo especifico
	$(Q)$(DOCKER_BIN) exec -it redis-node-$* redis-cli -p $$(($* + 6999)) MONITOR

monitor-all: ## Monitorea todos los nodos
	$(Q)$(CMD_MONITOR_ALL)

reset: generate ## Limpia todo y reinicia
	$(Q)echo "${RED}Esto eliminara datos y volumenes del laboratorio.${NC}"
ifeq ($(OS),Windows_NT)
	$(Q)powershell -NoProfile -Command "$$confirm = Read-Host 'Continuar? [y/N]'; if ($$confirm -notmatch '^y$$|^Y$$') { exit 1 }"
	$(Q)$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) down -v --remove-orphans
	$(Q)$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) up -d --build --remove-orphans
	$(Q)powershell -NoProfile -Command "Start-Sleep -Seconds 3"
else
	$(Q)read -p "Continuar? [y/N] " confirm && [ "$$confirm" = y ] || exit 1
	$(Q)$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) down -v --remove-orphans
	$(Q)$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) up -d --build --remove-orphans
	$(Q)sleep 3
endif
	$(Q)$(CMD_CLUSTER_INIT)
	$(Q)echo "${GREEN}Laboratorio reiniciado con $(SHARDS) shards.${NC}"

logs: ## Muestra logs del laboratorio
ifeq ($(OS),Windows_NT)
	$(Q)if exist $(COMPOSE_FILE) ($(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) logs -f) else ($(DOCKER_COMPOSE_BIN) $(COMPOSE_FALLBACK_FILES) logs -f)
else
	$(Q)if [ -f "$(COMPOSE_FILE)" ]; then \
		$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) logs -f; \
	else \
		$(DOCKER_COMPOSE_BIN) $(COMPOSE_FALLBACK_FILES) logs -f; \
	fi
endif

logs-%: ## Muestra logs de redis-node-N
ifeq ($(OS),Windows_NT)
	$(Q)if exist $(COMPOSE_FILE) ($(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) logs -f redis-node-$*) else ($(DOCKER_COMPOSE_BIN) $(COMPOSE_FALLBACK_FILES) logs -f redis-node-$*)
else
	$(Q)if [ -f "$(COMPOSE_FILE)" ]; then \
		$(DOCKER_COMPOSE_BIN) $(COMPOSE_FILES) logs -f redis-node-$*; \
	else \
		$(DOCKER_COMPOSE_BIN) $(COMPOSE_FALLBACK_FILES) logs -f redis-node-$*; \
	fi
endif

queues: ## Lista las colas distribuidas en el cluster
ifeq ($(OS),Windows_NT)
	$(Q)powershell.exe -ExecutionPolicy Bypass -File .\scripts\list-queues.ps1
else
	$(Q)./scripts/list-queues.sh
endif

# Absorbe argumentos posicionales usados por comandos con rutas:
#   make test <language>/<library>/<scenario>
#   make test-all <language>/<library>
%:
	$(Q)case "$(FIRST_GOAL)" in \
		scenarios|install|test|test-all|lab) : ;; \
		*) echo "Comando desconocido: $@"; echo "Usa: make help"; exit 2 ;; \
	esac
