param(
    [int]$SHARDS = 3
)
if ($env:SHARDS) { $SHARDS = $env:SHARDS }
$TOTAL_NODES = $SHARDS * 2

$COLORS = @(
    "Cyan", "Green", "Yellow", "Magenta", "Blue", "Red",
    "DarkCyan", "DarkGreen", "DarkYellow", "DarkMagenta"
)
$TOTAL_COLORS = $COLORS.Length

Write-Host "👁️  Monitoreando $TOTAL_NODES nodos ($SHARDS shards)"
Write-Host "Se abrirá una nueva ventana para cada nodo."
Write-Host "---"

for ($i = 1; $i -le $TOTAL_NODES; $i++) {
    $PORT = 6999 + $i
    $NODE = "redis-node-$i"
    $COLOR_IDX = ($i - 1) % $TOTAL_COLORS
    $COLOR = $COLORS[$COLOR_IDX]

    if ($i -le $SHARDS) {
        $LABEL = "M$i:$PORT"
    } else {
        $REPLICA_NUM = $i - $SHARDS
        $LABEL = "R$REPLICA_NUM:$PORT"
    }

    # Start a new PowerShell window executing redis-cli MONITOR.
    # The title will reflect the node. Note: Requires redis-cli to be available in PATH.
    $title = "Redis Monitor - $LABEL ($NODE)"
    $cmd = "docker exec $NODE redis-cli -p $PORT MONITOR"
    
    Start-Process powershell -ArgumentList "-NoProfile -Command `"`$host.UI.RawUI.WindowTitle = '$title'; Write-Host '--- Monitoreando $LABEL ---' -ForegroundColor $COLOR; $cmd`""
}

Write-Host "✅ Ventanas de monitoreo creadas."
