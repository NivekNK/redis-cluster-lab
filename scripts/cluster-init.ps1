param(
    [int]$SHARDS = 3
)
if ($env:SHARDS) { $SHARDS = $env:SHARDS }
$ErrorActionPreference = "Stop"
$TOTAL_NODES = $SHARDS * 2

Write-Host "⏳ Esperando que todos los nodos estén listos ($TOTAL_NODES nodos, $SHARDS shards)..."

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    $PORT = 6999 + $i
    $NODE = "redis-node-$i"
    $ready = $false
    while (-not $ready) {
        $out = docker exec $NODE redis-cli -p $PORT PING 2>$null
        if ($out -match "PONG") {
            $ready = $true
        } else {
            Write-Host "  Esperando $NODE en puerto $PORT..."
            Start-Sleep -Seconds 1
        }
    }
    Write-Host "  ✅ $NODE:$PORT listo"
}

Write-Host "`n✅ Todos los nodos responden`n"
Write-Host "🧹 Limpiando estado previo de los nodos..."

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    $PORT = 6999 + $i
    $NODE = "redis-node-$i"
    try { docker exec $NODE redis-cli -p $PORT FLUSHALL 2>$null } catch {}
    try { docker exec $NODE redis-cli -p $PORT CLUSTER RESET HARD 2>$null } catch {}
}
Write-Host "✅ Nodos limpios`n"
Write-Host "🔧 Creando cluster con $SHARDS shards..."

$nodesArgs = @()
for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    $PORT = 6999 + $i
    $nodesArgs += "redis-node-$i`:$PORT"
}

$args = @("exec", "redis-node-1", "redis-cli", "--cluster", "create") + $nodesArgs + @("--cluster-replicas", "1", "--cluster-yes")
& docker $args

Write-Host "`n✅ Cluster creado exitosamente con $SHARDS shards`n"
Write-Host "📊 Distribución de slots:"
docker exec redis-node-1 redis-cli -p 7000 CLUSTER SLOTS
