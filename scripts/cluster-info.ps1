$ErrorActionPreference = "Stop"

Write-Host "`nℹ️  Información Topológica del Cluster`n" -ForegroundColor Cyan

$nodesInfo = docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>$null
if (-not $nodesInfo) {
    Write-Host "❌ Error: El cluster no está inicializado o no es accesible." -ForegroundColor Red
    exit 1
}

$colors = @("Green", "Cyan", "Yellow", "Magenta", "Blue", "Red", "DarkGreen", "DarkCyan", "DarkYellow")
$shardColors = @{}
$masterNodes = @{}
$masterSlots = @{}
$replicaNodes = @{}
$colorIdx = 0

foreach ($line in $nodesInfo) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line -match "ERR") { continue }
    
    $parts = $line -split '\s+'
    $nodeId = $parts[0]
    $nodeInfoStr = $parts[1]
    $nodeIpPort = ($nodeInfoStr -split '@')[0]
    
    $hostname = ""
    if ($nodeInfoStr -match ",") {
        $hostname = ($nodeInfoStr -split ',')[1]
    }
    $displayName = if ($hostname) { "$hostname ($nodeIpPort)" } else { $nodeIpPort }
    
    $role = $parts[2]
    $masterId = $parts[3]
    $slots = if ($parts.Length -ge 9) { $parts[8] } else { "" }
    
    if ($role -match "master") {
        $shardColors[$nodeId] = $colors[$colorIdx % $colors.Length]
        $masterNodes[$nodeId] = $displayName
        $masterSlots[$nodeId] = $slots
        $colorIdx++
    } elseif ($role -match "slave" -or $role -match "replica") {
        if (-not $replicaNodes.ContainsKey($masterId)) {
            $replicaNodes[$masterId] = New-Object System.Collections.ArrayList
        }
        [void]$replicaNodes[$masterId].Add($displayName)
    }
}

# Crear objetos personalizados para poder ordenar por Slot Inicial
$shards = @()
foreach ($masterId in $masterNodes.Keys) {
    $slots = $masterSlots[$masterId]
    $slotStart = 0
    if ($slots -match "-") {
        $slotStart = [int]($slots -split '-')[0]
    }
    
    $shards += [PSCustomObject]@{
        MasterId = $masterId
        SlotStart = $slotStart
    }
}

$sortedShards = $shards | Sort-Object SlotStart
$shardNum = 1

foreach ($shard in $sortedShards) {
    $masterId = $shard.MasterId
    $color = $shardColors[$masterId]
    
    Write-Host "▶ Shard $shardNum" -ForegroundColor $color
    Write-Host "  [MASTER]  " -NoNewline -ForegroundColor $color
    Write-Host $masterNodes[$masterId] -NoNewline -ForegroundColor White
    Write-Host " - Slots: " -NoNewline -ForegroundColor White
    Write-Host $masterSlots[$masterId] -ForegroundColor Yellow
    
    if ($replicaNodes.ContainsKey($masterId)) {
        foreach ($replica in $replicaNodes[$masterId]) {
            Write-Host "  [REPLICA] " -NoNewline -ForegroundColor $color
            Write-Host $replica -ForegroundColor White
        }
    }
    Write-Host ""
    $shardNum++
}
