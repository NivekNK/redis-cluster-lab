
$DOCKER_COMPOSE_BIN = if ($env:DOCKER_COMPOSE_BIN) { $env:DOCKER_COMPOSE_BIN } else { "docker-compose" }

$DOCKER_BIN = if ($env:DOCKER_BIN) { $env:DOCKER_BIN } else { "docker" }
Write-Host "📊 Estado del Redis Cluster"
Write-Host "==========================="
Write-Host "`n🖥️  Nodos del Cluster:"
Write-Host "--------------------"

$nodesRaw = & $DOCKER_BIN exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>$null
$nodes = $nodesRaw -split "`n" | Where-Object { $_.Trim() -ne "" }

foreach ($line in $nodes) {
    $parts = $line -split " "
    $ip = $parts[1]
    $role = $parts[2]
    $master_id = $parts[3]
    $slots = $parts[8]
    
    if ($role -match "master") {
        Write-Host "  🔴 Master: $ip (slots: $slots)"
    }
    elseif ($role -match "slave") {
        Write-Host "  🔵 Replica: $ip -> master: $master_id"
    }
}

Write-Host "`n🎰 Distribución de Slots:"
Write-Host "------------------------"
$slotsOutput = & $DOCKER_BIN exec redis-node-1 redis-cli -p 7000 CLUSTER SLOTS 2>$null
$slotsOutput -split "`n" | Where-Object { $_ -match "^[0-9]|\[1" } | Select-Object -First 20 | ForEach-Object { Write-Host $_ }

Write-Host "`n📈 Estadísticas:"
Write-Host "---------------"
$infoOutput = & $DOCKER_BIN exec redis-node-1 redis-cli -p 7000 CLUSTER INFO 2>$null
$infoOutput -split "`n" | Where-Object { $_ -match "cluster_state|cluster_slots|cluster_known|cluster_size" } | ForEach-Object { Write-Host $_ }
