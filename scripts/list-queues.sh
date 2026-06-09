#!/bin/bash
# scripts/list-queues.sh
# Lista las colas (queues*) en el cluster Redis

BLUE='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
PURPLE='\033[35m'
NC='\033[0m'

echo -e "${BLUE}🔍 Escaneando colas en el cluster Redis...${NC}\n"

NODES_INFO=$(docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null)
if [ -z "$NODES_INFO" ] || echo "$NODES_INFO" | grep -q "ERR"; then
    echo -e "${RED}❌ Error: El cluster no está inicializado o no es accesible.${NC}"
    exit 1
fi

echo -e "${YELLOW}📦 Colas encontradas por nodo:${NC}"
echo "--------------------------------------------------------"

FOUND_ANY=0

COLORS=('\033[32m' '\033[36m' '\033[33m' '\033[35m' '\033[34m' '\033[31m' '\033[92m' '\033[96m' '\033[93m')
declare -A SHARD_COLORS
COLOR_IDX=0

# Pre-calcular colores por shard
while read -r line; do
    [ -z "$line" ] && continue
    NODE_ID=$(echo "$line" | awk '{print $1}')
    ROLE=$(echo "$line" | awk '{print $3}')
    if echo "$ROLE" | grep -q "master"; then
        SHARD_COLORS["$NODE_ID"]="${COLORS[$((COLOR_IDX % ${#COLORS[@]}))]}"
        COLOR_IDX=$((COLOR_IDX + 1))
    fi
done <<< "$NODES_INFO"

while read -r line; do
    [ -z "$line" ] && continue
    
    NODE_ID=$(echo "$line" | awk '{print $1}')
    NODE_INFO=$(echo "$line" | awk '{print $2}')
    NODE_IP_PORT=$(echo "$NODE_INFO" | cut -d'@' -f1)
    HOSTNAME=$(echo "$NODE_INFO" | cut -d',' -f2)
    
    if [ -z "$HOSTNAME" ] || [ "$HOSTNAME" == "$NODE_INFO" ]; then
        DISPLAY_NAME="$NODE_IP_PORT"
    else
        DISPLAY_NAME="$HOSTNAME"
    fi
    
    ROLE=$(echo "$line" | awk '{print $3}')
    MASTER_ID=$(echo "$line" | awk '{print $4}')
    
    if echo "$ROLE" | grep -q "master"; then
        ROLE_COLOR="${SHARD_COLORS[$NODE_ID]}[MASTER]${NC}"
    elif echo "$ROLE" | grep -q "slave" || echo "$ROLE" | grep -q "replica"; then
        ROLE_COLOR="${SHARD_COLORS[$MASTER_ID]:-${BLUE}}[REPLICA]${NC}"
    else
        ROLE_COLOR="${NC}[UNKNOWN]${NC}"
    fi
    
    IP=$(echo "$NODE_IP_PORT" | cut -d':' -f1)
    PORT=$(echo "$NODE_IP_PORT" | cut -d':' -f2)
    
    KEYS=$(docker exec redis-node-1 redis-cli -h "$IP" -p "$PORT" KEYS "queues*" 2>/dev/null | tr -d '\r')
    
    if [ -n "$KEYS" ]; then
        FOUND_ANY=1
        echo -e "$ROLE_COLOR \033[1m$DISPLAY_NAME\033[0m"
        echo "$KEYS" | while read -r key; do
            [ -z "$key" ] && continue
            echo -e "  ↳ ${PURPLE}$key${NC}"
        done
        echo ""
    fi
done <<< "$NODES_INFO"

if [ $FOUND_ANY -eq 0 ]; then
    echo -e "${YELLOW}No se encontraron colas activas en ningún nodo.${NC}"
fi

echo -e "\n${BLUE}✅ Escaneo completado.${NC}"
