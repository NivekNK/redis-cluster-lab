#!/bin/bash
# Monitorea TODOS los nodos Redis simultáneamente
# Cada línea se prefija con [nodo:puerto] y un color distinto
# Uso: SHARDS=N ./scripts/monitor-all.sh

SHARDS=${SHARDS:-3}
TOTAL_NODES=$((SHARDS * 2))

# Colores ANSI para diferenciar nodos
COLORS=(
    "\033[36m"   # Cyan
    "\033[32m"   # Green
    "\033[33m"   # Yellow
    "\033[35m"   # Magenta
    "\033[34m"   # Blue
    "\033[31m"   # Red
    "\033[96m"   # Light Cyan
    "\033[92m"   # Light Green
    "\033[93m"   # Light Yellow
    "\033[95m"   # Light Magenta
)
NC="\033[0m"
TOTAL_COLORS=${#COLORS[@]}

PIDS=()

cleanup() {
    echo ""
    echo -e "${NC}🛑 Deteniendo monitores..."
    for pid in "${PIDS[@]}"; do
        kill "$pid" 2>/dev/null
    done
    wait 2>/dev/null
    echo "✅ Monitores detenidos"
    exit 0
}

trap cleanup SIGINT SIGTERM

echo "👁️  Monitoreando $TOTAL_NODES nodos ($SHARDS shards)"
echo "Presiona Ctrl+C para salir"
echo "---"

for i in $(seq 1 "$TOTAL_NODES"); do
    PORT=$((6999 + i))
    NODE="redis-node-${i}"
    COLOR_IDX=$(( (i - 1) % TOTAL_COLORS ))
    COLOR="${COLORS[$COLOR_IDX]}"

    if [ "$i" -le "$SHARDS" ]; then
        LABEL="M${i}:${PORT}"
    else
        REPLICA_NUM=$((i - SHARDS))
        LABEL="R${REPLICA_NUM}:${PORT}"
    fi

    # Lanzar monitor en background, prefijando cada línea
    redis-cli -h redis-node-"${i}" -p "$PORT" MONITOR 2>/dev/null | \
        sed -u "s/^/$(echo -e "${COLOR}")[${LABEL}]$(echo -e "${NC}") /" &
    PIDS+=($!)
done

# Esperar a que el usuario cancele con Ctrl+C
wait
