param(
    [int]$SHARDS = 3
)

$DOCKER_COMPOSE_BIN = if ($env:DOCKER_COMPOSE_BIN) { $env:DOCKER_COMPOSE_BIN } else { "docker-compose" }

$DOCKER_BIN = if ($env:DOCKER_BIN) { $env:DOCKER_BIN } else { "docker" }
if ($env:SHARDS) { $SHARDS = $env:SHARDS }
$COMPOSE_FILE = "docker-compose.generated.yml"
$labComposeFiles = Get-ChildItem -Path suites -Recurse -Filter docker-compose.lab.yml -ErrorAction SilentlyContinue |
    Sort-Object FullName |
    ForEach-Object { "-f $($_.FullName)" }
$COMPOSE_ARGS = "-f $COMPOSE_FILE " + ($labComposeFiles -join " ")

Write-Host "🧹 Reset del Laboratorio"
Write-Host "========================"
Write-Host "`n⚠️  Esto eliminará TODOS los datos del cluster`n"

$confirm = Read-Host "¿Estás seguro? [y/N]"
if ($confirm -notmatch "^y$|^Y$") {
    Write-Host "❌ Cancelado"
    Exit 0
}

Write-Host "🛑 Deteniendo contenedores..."
Invoke-Expression "$DOCKER_COMPOSE_BIN $COMPOSE_ARGS down -v --remove-orphans"

Write-Host "🔧 Regenerando configuración con $SHARDS shards..."
powershell -ExecutionPolicy Bypass -File .\scripts\generate-compose.ps1 -SHARDS $SHARDS
powershell -ExecutionPolicy Bypass -File .\scripts\generate-haproxy.ps1 -SHARDS $SHARDS

Write-Host "🚀 Reiniciando cluster..."
Invoke-Expression "$DOCKER_COMPOSE_BIN $COMPOSE_ARGS up -d --build --remove-orphans"

Write-Host "⏳ Esperando nodos..."
Start-Sleep -Seconds 3

Write-Host "🔧 Inicializando cluster..."
$env:SHARDS = $SHARDS
powershell -ExecutionPolicy Bypass -File .\scripts\cluster-init.ps1 -SHARDS $SHARDS

Write-Host "`n✅ Laboratorio reiniciado con $SHARDS shards"
