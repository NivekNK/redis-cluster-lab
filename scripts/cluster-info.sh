#!/bin/bash
# scripts/cluster-info.sh
# Muestra información topológica del cluster Redis formateada

BLUE='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
NC='\033[0m'

echo -e "${BLUE}ℹ️  Información Topológica del Cluster${NC}\n"

NODES_INFO=$(docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null)
if [ -z "$NODES_INFO" ] || echo "$NODES_INFO" | grep -q "ERR"; then
    echo -e "${RED}❌ Error: El cluster no está inicializado o no es accesible.${NC}"
    exit 1
fi

COLORS=('\033[32m' '\033[36m' '\033[33m' '\033[35m' '\033[34m' '\033[31m' '\033[92m' '\033[96m' '\033[93m')
declare -A SHARD_COLORS
declare -A MASTER_NODES
declare -A REPLICA_NODES
declare -A MASTER_SLOTS
COLOR_IDX=0

# Parsear Nodos
while read -r line; do
    [ -z "$line" ] && continue
    NODE_ID=$(echo "$line" | awk '{print $1}')
    NODE_INFO=$(echo "$line" | awk '{print $2}')
    NODE_IP_PORT=$(echo "$NODE_INFO" | cut -d'@' -f1)
    HOSTNAME=$(echo "$NODE_INFO" | cut -d',' -f2)
    ROLE=$(echo "$line" | awk '{print $3}')
    MASTER_ID=$(echo "$line" | awk '{print $4}')
    SLOTS=$(echo "$line" | awk '{print $9}')
    
    if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" == "$NODE_INFO" ]; then
        DISPLAY_NAME="$NODE_IP_PORT"
    else
        DISPLAY_NAME="$HOSTNAME ($NODE_IP_PORT)"
    fi
    
    if echo "$ROLE" | grep -q "master"; then
        SHARD_COLORS["$NODE_ID"]="${COLORS[$((COLOR_IDX % ${#COLORS[@]}))]}"
        MASTER_NODES["$NODE_ID"]="${DISPLAY_NAME}"
        MASTER_SLOTS["$NODE_ID"]="${SLOTS}"
        COLOR_IDX=$((COLOR_IDX + 1))
    elif echo "$ROLE" | grep -q "slave" || echo "$ROLE" | grep -q "replica"; then
        if [ -z "${REPLICA_NODES[$MASTER_ID]}" ]; then
            REPLICA_NODES["$MASTER_ID"]="${DISPLAY_NAME}"
        else
            REPLICA_NODES["$MASTER_ID"]="${REPLICA_NODES[$MASTER_ID]}|${DISPLAY_NAME}"
        fi
    fi
done <<< "$NODES_INFO"

# Para ordenar por slots, extraemos los masters y los ordenamos por el inicio del slot
# Array para guardar master_id y slot_start
declare -a ORDERED_MASTERS
for MASTER_ID in "${!MASTER_NODES[@]}"; do
    SLOT_START=$(echo "${MASTER_SLOTS[$MASTER_ID]}" | cut -d'-' -f1)
    ORDERED_MASTERS+=("$SLOT_START:$MASTER_ID")
done

# Ordenar por el número de slot
IFS=$'\n' SORTED_MASTERS=($(sort -n <<<"${ORDERED_MASTERS[*]}"))
unset IFS

SHARD_NUM=1
for ITEM in "${SORTED_MASTERS[@]}"; do
    MASTER_ID=$(echo "$ITEM" | cut -d':' -f2)
    COLOR="${SHARD_COLORS[$MASTER_ID]}"
    
    echo -e "${COLOR}▶ Shard $SHARD_NUM${NC}"
    echo -e "  ${COLOR}[MASTER]${NC}  \033[1m${MASTER_NODES[$MASTER_ID]}\033[0m - Slots: ${YELLOW}${MASTER_SLOTS[$MASTER_ID]}${NC}"
    
    IFS='|' read -ra REPLICAS <<< "${REPLICA_NODES[$MASTER_ID]}"
    for REPLICA in "${REPLICAS[@]}"; do
        if [ -n "$REPLICA" ]; then
            echo -e "  ${COLOR}[REPLICA]${NC} ${REPLICA}"
        fi
    done
    echo ""
    SHARD_NUM=$((SHARD_NUM + 1))
done
