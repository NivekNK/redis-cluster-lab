param(
    [int]$SHARDS = 3
)

$DOCKER_COMPOSE_BIN = if ($env:DOCKER_COMPOSE_BIN) { $env:DOCKER_COMPOSE_BIN } else { "docker-compose" }

$DOCKER_BIN = if ($env:DOCKER_BIN) { $env:DOCKER_BIN } else { "docker" }
$ErrorActionPreference = "Stop"
$TOTAL_NODES = $SHARDS * 2
$OUTPUT = "docker-compose.generated.yml"

@"
# ⚠️  Archivo generado automáticamente - No editar manualmente
# Regenerar con: make generate SHARDS=N
version: '2.4'

services:
"@ | Out-File -FilePath $OUTPUT -Encoding ascii

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    $PORT = 6999 + $i
    $BUS_PORT = $PORT + 10000

    if ($i -le $SHARDS) {
        $COMMENT = "  # Master $i"
    } else {
        $REPLICA_NUM = $i - $SHARDS
        $COMMENT = "  # Replica $REPLICA_NUM (de Master $REPLICA_NUM)"
    }

    $nodeConfig = @"
$COMMENT
  redis-node-${i}:
    image: redis:7-alpine
    container_name: redis-node-$i
    ports:
      - `"${PORT}:${PORT}`"
      - `"${BUS_PORT}:${BUS_PORT}`"
    volumes:
      - ./config/redis.conf:/usr/local/etc/redis/redis.conf:ro
      - node-$i-data:/data
    command: >
      redis-server /usr/local/etc/redis/redis.conf
      --port $PORT
      --cluster-enabled yes
      --cluster-config-file nodes.conf
      --cluster-node-timeout 5000
      --cluster-announce-hostname redis-node-$i
      --cluster-preferred-endpoint-type hostname
      --cluster-announce-port $PORT
      --cluster-announce-bus-port $BUS_PORT
      --appendonly yes
      --protected-mode no
      --bind 0.0.0.0
    cpus: '`${REDIS_CPUS:-0.5}'
    mem_limit: '`${REDIS_MEM_LIMIT:-256m}'
    networks:
      - redis-cluster

"@
    Add-Content -Path $OUTPUT -Value $nodeConfig -Encoding ascii
}

$haproxyConfig = @"
  # HAProxy - Load Balancer
  haproxy:
    image: haproxy:2.9-alpine
    container_name: redis-haproxy
    ports:
      - `"6380:6380`"
      - `"6381:6381`"
    volumes:
      - ./haproxy.generated.cfg:/usr/local/etc/haproxy/haproxy.cfg:ro
    cpus: '`${HAPROXY_CPUS:-0.5}'
    mem_limit: '`${HAPROXY_MEM_LIMIT:-128m}'
    networks:
      - redis-cluster
    depends_on:
"@
Add-Content -Path $OUTPUT -Value $haproxyConfig -Encoding ascii

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    Add-Content -Path $OUTPUT -Value "      - redis-node-$i" -Encoding ascii
}

Add-Content -Path $OUTPUT -Value "`n" -Encoding ascii

$labConfig = @"
  # Contenedor para ejecutar tests PHP
  redis-lab:
    image: php:8.2-cli
    container_name: redis-lab
    volumes:
      - .:/app
    working_dir: /app
    command: tail -f /dev/null
    cpus: '`${LAB_CPUS:-0.5}'
    mem_limit: '`${LAB_MEM_LIMIT:-256m}'
    networks:
      - redis-cluster
    depends_on:
"@
Add-Content -Path $OUTPUT -Value $labConfig -Encoding ascii

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    Add-Content -Path $OUTPUT -Value "      - redis-node-$i" -Encoding ascii
}

$footConfig = @"

networks:
  redis-cluster:
    driver: bridge

volumes:
"@
Add-Content -Path $OUTPUT -Value $footConfig -Encoding ascii

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    Add-Content -Path $OUTPUT -Value "  node-$i-data:" -Encoding ascii
}
Add-Content -Path $OUTPUT -Value "`n" -Encoding ascii

Write-Host "✅ Generado $OUTPUT con $SHARDS shards ($TOTAL_NODES nodos: $SHARDS masters + $SHARDS replicas)"
