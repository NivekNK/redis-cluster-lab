#!/bin/bash
# Setup inicial del laboratorio

set -e

DOCKER_COMPOSE_BIN=${DOCKER_COMPOSE_BIN:-"docker compose"}

echo "Redis Cluster Laboratory - Setup"
echo "================================="
echo ""

if ! command -v docker >/dev/null 2>&1; then
    echo "Docker no esta instalado"
    exit 1
fi

if ! $DOCKER_COMPOSE_BIN version >/dev/null 2>&1; then
    echo "Docker Compose no esta disponible con: $DOCKER_COMPOSE_BIN"
    exit 1
fi

echo "Docker y Docker Compose encontrados"
echo ""
echo "Proximos pasos:"
echo "  1. make up"
echo "  2. make install-all"
echo "  3. make test-all"
