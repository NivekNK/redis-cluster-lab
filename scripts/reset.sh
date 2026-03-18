#!/bin/bash
# Reset completo del laboratorio
# Uso: SHARDS=N ./scripts/reset.sh

SHARDS=${SHARDS:-1}
COMPOSE_FILE="docker-compose.generated.yml"

echo "🧹 Reset del Laboratorio"
echo "========================"
echo ""
echo "⚠️  Esto eliminará TODOS los datos del cluster"
echo ""
read -p "¿Estás seguro? [y/N] " confirm

if [[ $confirm != "y" && $confirm != "Y" ]]; then
    echo "❌ Cancelado"
    exit 0
fi

echo "🛑 Deteniendo contenedores..."
docker compose -f "$COMPOSE_FILE" down -v

echo "🗑️  Eliminando volúmenes..."
docker volume prune -f

echo "🔧 Regenerando configuración con $SHARDS shards..."
./scripts/generate-compose.sh "$SHARDS"
./scripts/generate-haproxy.sh "$SHARDS"

echo "🚀 Reiniciando cluster..."
docker compose -f "$COMPOSE_FILE" up -d

echo "⏳ Esperando nodos..."
sleep 3

echo "🔧 Inicializando cluster..."
SHARDS=$SHARDS ./scripts/cluster-init.sh

echo ""
echo "✅ Laboratorio reiniciado con $SHARDS shards"
