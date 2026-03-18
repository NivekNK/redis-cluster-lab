param(
    [int]$SHARDS = 3
)
$ErrorActionPreference = "Stop"
$TOTAL_NODES = $SHARDS * 2
$OUTPUT = "docker-compose.generated.yml"

@"
# ⚠️  Archivo generado automáticamente - No editar manualmente
# Regenerar con: make generate SHARDS=N

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
      --cluster-announce-ip redis-node-$i
      --cluster-announce-port $PORT
      --cluster-announce-bus-port $BUS_PORT
      --appendonly yes
      --protected-mode no
      --bind 0.0.0.0
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
