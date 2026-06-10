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

${DOCKER_COMPOSE_BIN:-docker compose} -f "$COMPOSE_FILE" ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | \
    sed 's/0\.0\.0\.0://g' | \
    sed 's/->[0-9-]*\/tcp//g' | \
    sed 's/, \[::\]:[0-9-]*//g' | \
    sed 's/, [0-9]*\/tcp//g'
