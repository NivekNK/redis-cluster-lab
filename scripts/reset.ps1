param(
    [int]$SHARDS = 3
)

$DOCKER_BIN = if ($env:DOCKER_BIN) { $env:DOCKER_BIN } else { "docker" }
if ($env:SHARDS) { $SHARDS = $env:SHARDS }
$COMPOSE_FILE = "docker-compose.generated.yml"

Write-Host "🧹 Reset del Laboratorio"
Write-Host "========================"
Write-Host "`n⚠️  Esto eliminará TODOS los datos del cluster`n"

$confirm = Read-Host "¿Estás seguro? [y/N]"
if ($confirm -notmatch "^y$|^Y$") {
    Write-Host "❌ Cancelado"
    Exit 0
}

Write-Host "🛑 Deteniendo contenedores..."
& $DOCKER_BIN compose -f $COMPOSE_FILE down -v

Write-Host "🗑️  Eliminando volúmenes..."
& $DOCKER_BIN volume prune -f

Write-Host "🔧 Regenerando configuración con $SHARDS shards..."
powershell -ExecutionPolicy Bypass -File .\scripts\generate-compose.ps1 -SHARDS $SHARDS
powershell -ExecutionPolicy Bypass -File .\scripts\generate-haproxy.ps1 -SHARDS $SHARDS

Write-Host "🚀 Reiniciando cluster..."
& $DOCKER_BIN compose -f $COMPOSE_FILE up -d

Write-Host "⏳ Esperando nodos..."
Start-Sleep -Seconds 3

Write-Host "🔧 Inicializando cluster..."
$env:SHARDS = $SHARDS
powershell -ExecutionPolicy Bypass -File .\scripts\cluster-init.ps1 -SHARDS $SHARDS

Write-Host "`n✅ Laboratorio reiniciado con $SHARDS shards"
