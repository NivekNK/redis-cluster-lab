$ErrorActionPreference = "Stop"

Write-Host "🔧 Redis Cluster Laboratory - Setup"
Write-Host "===================================="
Write-Host ""

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Host "❌ Docker no está instalado"
    Exit 1
}

if (-not (Get-Command docker-compose -ErrorAction SilentlyContinue) -and -not (docker compose version 2>$null)) {
    Write-Host "❌ Docker Compose no está instalado"
    Exit 1
}

Write-Host "✅ Docker y Docker Compose encontrados`n"

if (Get-Command composer -ErrorAction SilentlyContinue) {
    Write-Host "📦 Instalando dependencias PHP..."
    composer install --no-interaction
} else {
    Write-Host "⚠️  Composer no encontrado. Los tests se ejecutarán en el contenedor."
}

Write-Host "`n🚀 Setup completo!`n"
Write-Host "Próximos pasos:"
Write-Host "  1. make up      - Iniciar el cluster"
Write-Host "  2. make test    - Ejecutar tests"
Write-Host "  3. make scenarios - Ver escenarios disponibles"
