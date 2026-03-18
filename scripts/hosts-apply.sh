#!/bin/bash
# Agrega los hosts del cluster Redis a /etc/hosts
# Uso: SHARDS=N ./scripts/hosts-apply.sh

SHARDS=${SHARDS:-3}
TOTAL_NODES=$((SHARDS * 2))
BACKUP_PATH="/etc/hosts.original"
HOSTS_FILE="/etc/hosts"

# Construir los hosts dinámicamente
NUEVOS_HOSTS="
# --- Redis Cluster Lab (inicio) ---"

for i in $(seq 1 "$TOTAL_NODES"); do
    NUEVOS_HOSTS="$NUEVOS_HOSTS
127.0.0.1   redis-node-${i}"
done

NUEVOS_HOSTS="$NUEVOS_HOSTS
127.0.0.1   master.local
127.0.0.1   clustercfg.local
# --- Redis Cluster Lab (fin) ---"

echo "🌐 Configurando /etc/hosts..."

# 1. Verificar si ya existe un respaldo
if [ -f "$BACKUP_PATH" ]; then
    echo "⚠️  Ya existe un respaldo en $BACKUP_PATH."
    echo "   Restaurando primero antes de re-aplicar..."
    sudo mv "$BACKUP_PATH" "$HOSTS_FILE"
fi

# 2. Crear el respaldo
sudo cp "$HOSTS_FILE" "$BACKUP_PATH"

# 3. Aplicar los cambios
echo "$NUEVOS_HOSTS" | sudo tee -a "$HOSTS_FILE" > /dev/null

echo "✅ Hosts del cluster agregados a /etc/hosts"
