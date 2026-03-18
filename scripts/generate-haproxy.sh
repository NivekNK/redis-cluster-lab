#!/bin/bash
# Genera haproxy.generated.cfg dinámicamente según la cantidad de shards
# Uso: ./scripts/generate-haproxy.sh <SHARDS>

set -e

SHARDS=${1:-1}
TOTAL_NODES=$((SHARDS * 2))
OUTPUT="haproxy.generated.cfg"

cat > "$OUTPUT" <<'HEADER'
# ⚠️  Archivo generado automáticamente - No editar manualmente
# Regenerar con: make generate SHARDS=N

defaults
    mode tcp
    timeout connect 5s
    timeout client 1m
    timeout server 1m

# ---------------------------------------------------------------------
# FRONTEND: master.local (Puerto 6380)
# Solo para escrituras y colas (siempre cae en un maestro)
# ---------------------------------------------------------------------
frontend redis-masters-fe
    bind *:6380
    default_backend redis-masters-be

backend redis-masters-be
    option tcp-check
    # Verifica que el nodo responda "role:master"
    tcp-check send info\ replication\r\n
    tcp-check expect string role:master
HEADER

for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))
    echo "    server node${i} redis-node-${i}:${PORT} check inter 2s" >> "$OUTPUT"
done

cat >> "$OUTPUT" <<'MIDDLE'

# ---------------------------------------------------------------------
# FRONTEND: clustercfg.local (Puerto 6381)
# Punto de entrada general (Discovery)
# ---------------------------------------------------------------------
frontend redis-all-nodes-fe
    bind *:6381
    default_backend redis-all-nodes-be

backend redis-all-nodes-be
    option tcp-check
    # Solo verifica que el nodo esté vivo (PING)
    tcp-check send PING\r\n
    tcp-check expect string +PONG
MIDDLE

for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))
    echo "    server node${i} redis-node-${i}:${PORT} check inter 2s" >> "$OUTPUT"
done

echo "" >> "$OUTPUT"

echo "✅ Generado $OUTPUT con $TOTAL_NODES nodos"
