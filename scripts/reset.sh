#!/bin/bash
# Reset completo del laboratorio
# Uso: SHARDS=N ./scripts/reset.sh

SHARDS=${SHARDS:-3}
COMPOSE_FILE="docker-compose.generated.yml"
COMPOSE_ARGS=(-f "$COMPOSE_FILE")

while IFS= read -r lab_compose; do
    COMPOSE_ARGS+=(-f "$lab_compose")
done < <(find suites -mindepth 3 -maxdepth 3 -name docker-compose.lab.yml 2>/dev/null | sort)

echo "🧹 Reset del Laboratorio"
echo "========================"
echo ""
echo "⚠️  Esto eliminará TODOS los datos del cluster"
echo ""
read -p "¿Estás seguro? [y/N] " confirm

if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "❌ Cancelado"
    exit 0
fi

echo "🛑 Deteniendo contenedores..."
${DOCKER_COMPOSE_BIN:-docker compose} \
    "${COMPOSE_ARGS[@]}" \
    down -v --remove-orphans

echo "🔧 Regenerando configuración con $SHARDS shards..."
./scripts/generate-compose.sh "$SHARDS"
./scripts/generate-haproxy.sh "$SHARDS"

echo "🚀 Reiniciando cluster..."
${DOCKER_COMPOSE_BIN:-docker compose} \
    "${COMPOSE_ARGS[@]}" \
    up -d --build --remove-orphans

echo "⏳ Esperando nodos..."
sleep 3

echo "🔧 Inicializando cluster..."
SHARDS=$SHARDS ./scripts/cluster-init.sh

echo ""
echo "✅ Laboratorio reiniciado con $SHARDS shards"
