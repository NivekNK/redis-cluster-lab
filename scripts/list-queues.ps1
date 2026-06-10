
$DOCKER_COMPOSE_BIN = if ($env:DOCKER_COMPOSE_BIN) { $env:DOCKER_COMPOSE_BIN } else { "docker-compose" }

$DOCKER_BIN = if ($env:DOCKER_BIN) { $env:DOCKER_BIN } else { "docker" }
$ErrorActionPreference = "Stop"

Write-Host "`n🔍 Escaneando colas en el cluster Redis...`n" -ForegroundColor Cyan

$nodesInfo = & $DOCKER_BIN exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>$null
if (-not $nodesInfo) {
    Write-Host "❌ Error: El cluster no está inicializado o no es accesible." -ForegroundColor Red
    exit 1
}

Write-Host "📦 Colas encontradas por nodo:" -ForegroundColor Yellow
Write-Host "--------------------------------------------------------"

$foundAny = $false

$colors = @("Green", "Cyan", "Yellow", "Magenta", "Blue", "Red", "DarkGreen", "DarkCyan", "DarkYellow")
$shardColors = @{}
$colorIdx = 0

foreach ($line in $nodesInfo) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match "ERR") { continue }
    $parts = $line -split '\s+'
    $nodeId = $parts[0]
    $role = $parts[2]
    if ($role -match "master") {
        $shardColors[$nodeId] = $colors[$colorIdx % $colors.Length]
        $colorIdx++
    }
}

foreach ($line in $nodesInfo) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match "ERR") { continue }
    
    $parts = $line -split '\s+'
    $nodeId = $parts[0]
    $nodeInfo = $parts[1]
    $nodeIpPort = ($nodeInfo -split '@')[0]
    
    $hostname = ""
    if ($nodeInfo -match ",") {
        $hostname = ($nodeInfo -split ',')[1]
    }
    $displayName = if ($hostname) { $hostname } else { $nodeIpPort }
    
    $role = $parts[2]
    $masterId = $parts[3]
    
    $roleColor = "White"
    $roleText = "[UNKNOWN]"
    if ($role -match "master") {
        $roleColor = $shardColors[$nodeId]
        $roleText = "[MASTER]"
    } elseif ($role -match "slave" -or $role -match "replica") {
        if ($shardColors.ContainsKey($masterId)) {
            $roleColor = $shardColors[$masterId]
        } else {
            $roleColor = "Cyan"
        }
        $roleText = "[REPLICA]"
    }
    
    $ipPort = $nodeIpPort -split ':'
    $ip = $ipPort[0]
    $port = $ipPort[1]
    
    $keys = & $DOCKER_BIN exec redis-node-1 redis-cli -h $ip -p $port KEYS "queues*" 2>$null
    
    if ($keys) {
        $foundAny = $true
        Write-Host -NoNewline "$roleText " -ForegroundColor $roleColor
        Write-Host "$displayName" -ForegroundColor White
        foreach ($key in $keys) {
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            Write-Host "  ↳ " -NoNewline
            Write-Host "$key" -ForegroundColor Magenta
        }
        Write-Host ""
    }
}

if (-not $foundAny) {
    Write-Host "No se encontraron colas activas en ningún nodo." -ForegroundColor Yellow
}

Write-Host "`n✅ Escaneo completado." -ForegroundColor Cyan
