#!/bin/bash
# Genera docker-compose.generated.yml dinámicamente según la cantidad de shards
# Uso: ./scripts/generate-compose.sh <SHARDS>
# Cada shard = 1 master + 1 replica. Total de nodos = SHARDS * 2

set -e

SHARDS=${1:-1}
TOTAL_NODES=$((SHARDS * 2))
OUTPUT="docker-compose.generated.yml"

cat > "$OUTPUT" <<'HEADER'
# ⚠️  Archivo generado automáticamente - No editar manualmente
# Regenerar con: make generate SHARDS=N

services:
HEADER

# Generar servicios Redis (masters + replicas)
for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))  # 7000, 7001, ...
    BUS_PORT=$((PORT + 10000))

    if [ "$i" -le "$SHARDS" ]; then
        COMMENT="  # Master $i"
    else
        REPLICA_NUM=$((i - SHARDS))
        COMMENT="  # Replica $REPLICA_NUM (de Master $REPLICA_NUM)"
    fi

    cat >> "$OUTPUT" <<EOF
$COMMENT
  redis-node-${i}:
    image: redis:7-alpine
    container_name: redis-node-${i}
    ports:
      - "${PORT}:${PORT}"
      - "${BUS_PORT}:${BUS_PORT}"
    volumes:
      - ./config/redis.conf:/usr/local/etc/redis/redis.conf:ro
      - node-${i}-data:/data
    command: >
      redis-server /usr/local/etc/redis/redis.conf
      --port ${PORT}
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --cluster-announce-ip redis-node-${i}
      --cluster-announce-port ${PORT}
      --cluster-announce-bus-port ${BUS_PORT}
      --appendonly yes
      --protected-mode no
      --bind 0.0.0.0
    networks:
      - redis-cluster

EOF
done

# Generar servicio HAProxy
cat >> "$OUTPUT" <<'HAPROXY_HEADER'
  # HAProxy - Load Balancer
  haproxy:
    image: haproxy:2.9-alpine
    container_name: redis-haproxy
    ports:
      - "6380:6380"
      - "6381:6381"
    volumes:
      - ./haproxy.generated.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    networks:
      - redis-cluster
    depends_on:
HAPROXY_HEADER

for i in $(seq 1 "$TOTAL_NODES"); do
    echo "      - redis-node-${i}" >> "$OUTPUT"
done

echo "" >> "$OUTPUT"

# Generar servicio redis-lab (PHP test container)
cat >> "$OUTPUT" <<'LAB_HEADER'
  # Contenedor para ejecutar tests PHP
  redis-lab:
    image: php:8.2-cli
    container_name: redis-lab
    volumes:
      - .:/app
    working_dir: /app
    command: tail -f /dev/null
    networks:
      - redis-cluster
    depends_on:
LAB_HEADER

for i in $(seq 1 "$TOTAL_NODES"); do
    echo "      - redis-node-${i}" >> "$OUTPUT"
done

# Generar networks y volumes
cat >> "$OUTPUT" <<'NETWORKS'

networks:
  redis-cluster:
    driver: bridge

NETWORKS

echo "volumes:" >> "$OUTPUT"
for i in $(seq 1 "$TOTAL_NODES"); do
    echo "  node-${i}-data:" >> "$OUTPUT"
done
echo "" >> "$OUTPUT"

echo "✅ Generado $OUTPUT con $SHARDS shards ($TOTAL_NODES nodos: $SHARDS masters + $SHARDS replicas)"
