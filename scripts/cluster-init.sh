#!/bin/bash
# Inicializa el cluster Redis - Dinámico según SHARDS
# Uso: SHARDS=N ./scripts/cluster-init.sh

set -e

SHARDS=${SHARDS:-1}
TOTAL_NODES=$((SHARDS * 2))

echo "⏳ Esperando que todos los nodos estén listos ($TOTAL_NODES nodos, $SHARDS shards)..."

# Esperar a que cada nodo responda PONG
for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))
    NODE="redis-node-${i}"

    until docker exec "$NODE" redis-cli -p "$PORT" PING 2>/dev/null | grep -q "PONG"; do
        echo "  Esperando $NODE en puerto $PORT..."
        sleep 1
    done
    echo "  ✅ $NODE:$PORT listo"
done

echo ""
echo "✅ Todos los nodos responden"
echo ""
echo "🧹 Limpiando estado previo de los nodos..."
for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))
    NODE="redis-node-${i}"
    docker exec "$NODE" redis-cli -p "$PORT" FLUSHALL 2>/dev/null || true
    docker exec "$NODE" redis-cli -p "$PORT" CLUSTER RESET HARD 2>/dev/null || true
done
echo "✅ Nodos limpios"
echo ""
echo "🔧 Creando cluster con $SHARDS shards..."

# Construir la lista de nodos para redis-cli --cluster create
NODES=""
for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))
    NODES="$NODES redis-node-${i}:${PORT}"
done

# Crear el cluster con replicas (SHARDS >= 3 garantizado)
docker exec redis-node-1 redis-cli --cluster create \
    $NODES \
    --cluster-replicas 1 \
    --cluster-yes

echo ""
echo "✅ Cluster creado exitosamente con $SHARDS shards"
echo ""
echo "📊 Distribución de slots:"
docker exec redis-node-1 redis-cli -p 7000 CLUSTER SLOTS
