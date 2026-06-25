$DOCKER_COMPOSE_BIN = if ($env:DOCKER_COMPOSE_BIN) { $env:DOCKER_COMPOSE_BIN } else { "docker compose" }
$ErrorActionPreference = "Stop"

Write-Host "Redis Cluster Laboratory - Setup"
Write-Host "================================="
Write-Host ""

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "Docker no esta instalado"
    Exit 1
}

$composeCheck = Invoke-Expression "$DOCKER_COMPOSE_BIN version 2>`$null"
if (-not $composeCheck) {
    Write-Host "Docker Compose no esta disponible con: $DOCKER_COMPOSE_BIN"
    Exit 1
}

Write-Host "Docker y Docker Compose encontrados`n"
Write-Host "Proximos pasos:"
Write-Host "  1. make up"
Write-Host "  2. make install-all"
Write-Host "  3. make test-all"
