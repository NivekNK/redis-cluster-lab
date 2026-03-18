#!/bin/bash
# Muestra el estado del cluster

echo "📊 Estado del Redis Cluster"
echo "==========================="
echo ""

echo "🖥️  Nodos del Cluster:"
echo "--------------------"
docker exec redis-node-1 redis-cli -p 7000 CLUSTER NODES 2>/dev/null | while read line; do
    node_id=$(echo $line | awk '{print $1}')
    ip=$(echo $line | awk '{print $2}')
    role=$(echo $line | awk '{print $3}')
    master_id=$(echo $line | awk '{print $4}')
    ping_sent=$(echo $line | awk '{print $5}')
    pong_recv=$(echo $line | awk '{print $6}')
    epoch=$(echo $line | awk '{print $7}')
    status=$(echo $line | awk '{print $8}')
    slots=$(echo $line | awk '{print $9}')
    
    if [[ $role == "master" ]]; then
        echo "  🔴 Master: $ip (slots: $slots)"
    elif [[ $role == "slave" ]]; then
        echo "  🔵 Replica: $ip -> master: $master_id"
    fi
done

echo ""
echo "🎰 Distribución de Slots:"
echo "------------------------"
docker exec redis-node-1 redis-cli -p 7000 CLUSTER SLOTS 2>/dev/null | grep -E "^[0-9]|^\[1" | head -20

echo ""
echo "📈 Estadísticas:"
echo "---------------"
docker exec redis-node-1 redis-cli -p 7000 CLUSTER INFO 2>/dev/null | grep -E "cluster_state|cluster_slots|cluster_known|cluster_size"
