#!/bin/bash
# scripts/status.sh
# Muestra el estado del cluster formateado

BLUE='\033[36m'
NC='\033[0m'

echo -e "${BLUE}📊 Estado de Contenedores${NC}"
echo "========================"

COMPOSE_FILE="docker-compose.generated.yml"
if [ ! -f "$COMPOSE_FILE" ]; then
    COMPOSE_FILE="docker-compose.yml"
fi

COMPOSE_ARGS=(-f "$COMPOSE_FILE")
while IFS= read -r lab_compose; do
    COMPOSE_ARGS+=(-f "$lab_compose")
done < <(find suites -mindepth 3 -maxdepth 3 -name docker-compose.lab.yml 2>/dev/null | sort)

${DOCKER_COMPOSE_BIN:-docker compose} "${COMPOSE_ARGS[@]}" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | \
    sed 's/0\.0\.0\.0://g' | \
    sed 's/->[0-9-]*\/tcp//g' | \
    sed 's/, \[::\]:[0-9-]*//g' | \
    sed 's/, [0-9]*\/tcp//g'
