#!/bin/bash
# Setup inicial del laboratorio

set -e

echo "🔧 Redis Cluster Laboratory - Setup"
echo "===================================="
echo ""

# Verificar Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker no está instalado"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose no está instalado"
    exit 1
fi

echo "✅ Docker y Docker Compose encontrados"
echo ""

# Instalar dependencias PHP si está disponible
if command -v composer &> /dev/null; then
    echo "📦 Instalando dependencias PHP..."
    composer install --no-interaction
else
    echo "⚠️  Composer no encontrado. Los tests se ejecutarán en el contenedor."
fi

echo ""
echo "🚀 Setup completo!"
echo ""
echo "Próximos pasos:"
echo "  1. make up      - Iniciar el cluster"
echo "  2. make test    - Ejecutar tests"
echo "  3. make scenarios - Ver escenarios disponibles"
