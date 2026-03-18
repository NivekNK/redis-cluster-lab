#!/bin/bash
# Restaura /etc/hosts a su estado original
# Uso: ./scripts/hosts-restore.sh

BACKUP_PATH="/etc/hosts.original"
HOSTS_FILE="/etc/hosts"

echo "🌐 Restaurando /etc/hosts..."

# 1. Verificar si el respaldo existe
if [ ! -f "$BACKUP_PATH" ]; then
    echo "ℹ️  No se encontró respaldo ($BACKUP_PATH). /etc/hosts no fue modificado."
    exit 0
fi

# 2. Restaurar el archivo original
sudo mv "$BACKUP_PATH" "$HOSTS_FILE"

echo "✅ /etc/hosts restaurado a su estado original"
