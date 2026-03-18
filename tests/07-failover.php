<?php
/**
 * ESCENARIO 7: Failover
 * ====================
 * 
 * OBJETIVO: Simular y comprender el comportamiento durante failover.
 */

require __DIR__ . '/../vendor/autoload.php';

use Predis\Client;

$BLUE = "\033[34m";
$GREEN = "\033[32m";
$YELLOW = "\033[33m";
$RED = "\033[31m";
$CYAN = "\033[36m";
$NC = "\033[0m";

function section($title) {
    global $BLUE, $NC;
    echo "\n{$BLUE}═══════════════════════════════════════════════════════════{$NC}\n";
    echo "{$BLUE}  $title{$NC}\n";
    echo "{$BLUE}═══════════════════════════════════════════════════════════{$NC}\n\n";
}

function info($label, $value) {
    global $YELLOW, $NC;
    echo str_pad($label, 35) . " {$YELLOW}{$value}{$NC}\n";
}

function success($msg) {
    global $GREEN, $NC;
    echo "{$GREEN}✓ {$msg}{$NC}\n";
}

function warning($msg) {
    global $YELLOW, $NC;
    echo "{$YELLOW}⚠ {$msg}{$NC}\n";
}

function error($msg) {
    global $RED, $NC;
    echo "{$RED}✗ {$msg}{$NC}\n";
}

require __DIR__ . '/cluster-config.php';

$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

section("FAILOVER EN REDIS CLUSTER");

echo "El failover ocurre cuando un master falla\n";
echo "y una réplica toma su lugar automáticamente.\n\n";

// Test 1: Estado inicial
section("TEST 1: Estado Inicial del Cluster");

// CLUSTER NODES devuelve string multilinea, no array
$nodesRaw = $client->executeRaw(['CLUSTER', 'NODES']);
$nodes = explode("\n", trim($nodesRaw));

$masters = [];
$replicas = [];

foreach ($nodes as $node) {
    if (empty($node)) continue;
    
    $parts = explode(' ', $node);
    $id = $parts[0];
    $endpoint = $parts[1];
    $flags = $parts[2];
    
    if (strpos($flags, 'master') !== false) {
        $masters[$id] = $endpoint;
        info("Master", $endpoint);
    } elseif (strpos($flags, 'slave') !== false) {
        $masterId = $parts[3];
        $replicas[$masterId] = $endpoint;
        info("Replica", $endpoint . " -> " . substr($masterId, 0, 8));
    }
}

// Test 2: Información del cluster
section("TEST 2: Información del Cluster");

// CLUSTER INFO devuelve string multilinea
$infoRaw = $client->executeRaw(['CLUSTER', 'INFO']);
$infoLines = explode("\n", trim($infoRaw));

foreach ($infoLines as $line) {
    if (strpos($line, ':') !== false) {
        list($key, $value) = explode(':', $line, 2);
        if (in_array($key, ['cluster_state', 'cluster_slots_assigned', 'cluster_known_nodes', 'cluster_size'])) {
            info($key, $value);
        }
    }
}

// Test 3: Simular carga continua
section("TEST 3: Simulando Carga Continua");

echo "Vamos a simular un worker de cola escribiendo constantemente.\n";
echo "Esto nos permitirá ver qué pasa durante el failover.\n\n";

$testKey = 'failover-test-' . uniqid();
$operations = 0;
$errors = [];

info("Key de prueba", $testKey);

echo "\n{$CYAN}Ejecutando 20 operaciones de escritura...{$NC}\n\n";

for ($i = 0; $i < 20; $i++) {
    try {
        $client->set($testKey, "value-$i");
        echo ".";
        $operations++;
        usleep(100000); // 100ms entre operaciones
    } catch (Exception $e) {
        echo "X";
        $errors[] = $e->getMessage();
    }
}

echo "\n\n";
success("Operaciones exitosas: $operations/20");

if (count($errors) > 0) {
    warning("Errores: " . count($errors));
    info("Último error", $errors[count($errors) - 1]);
}

// Test 4: Verificar replicación
section("TEST 4: Verificar Replicación");

echo "Las réplicas replican datos de sus masters.\n\n";

// Usar el cliente cluster para escribir (no conexión directa)
$testValue = 'replication-test-' . time();
$client->set('replication-key', $testValue);

echo "Valor escrito en cluster: $testValue\n";
echo "Esperando replicación...\n";

// Pequeña pausa
usleep(500000); // 500ms

// Leer desde el cluster (no desde réplica específica)
// El cliente cluster automáticamente va al nodo correcto
try {
    $replicatedValue = $client->get('replication-key');
    
    if ($replicatedValue === $testValue) {
        success("Valor recuperado correctamente desde el cluster");
        info("Valor leído", $replicatedValue);
    } else {
        warning("Valor diferente (replicación asíncrona)");
    }
} catch (Exception $e) {
    error("Error: " . $e->getMessage());
}

// Test 5: Instrucciones para failover manual
section("TEST 5: Instrucciones para Failover Manual");

echo "{$YELLOW}Para simular un failover real, ejecuta estos comandos:{$NC}\n\n";

echo "1. Identifica un master y su réplica:\n";
echo "   docker exec -e SHARDS=\$SHARDS -it redis-lab redis-cli -h redis-node-1 -p 7000 CLUSTER NODES\n\n";

echo "2. Conecta a la réplica:\n";
$replicaPort = 6999 + shardCount() + 1; // Assuming replica 1 of master 1 is node (shards+1)
echo "   docker exec -e SHARDS=\$SHARDS -it redis-lab redis-cli -h redis-node-" . (shardCount() + 1) . " -p $replicaPort\n\n";

echo "3. Ejecuta failover manual:\n";
echo "   CLUSTER FAILOVER\n\n";

echo "4. Verifica el cambio:\n";
echo "   docker exec -e SHARDS=\$SHARDS -it redis-lab redis-cli -h redis-node-1 -p 7000 CLUSTER NODES\n\n";

echo "{$CYAN}Observa cómo los puertos de master y replica se intercambian.{$NC}\n";

// Test 6: Comportamiento de Predis durante failover
section("TEST 6: Comportamiento de Predis");

echo "Cuando ocurre un failover:\n\n";

echo "1. {$CYAN}Master cae{$NC}\n";
echo "   - Las conexiones existentes fallan\n";
echo "   - Nuevas escrituras reciben errores\n\n";

echo "2. {$CYAN}Réplica detecta el fallo{$NC}\n";
echo "   - Basado en cluster-node-timeout (5s en nuestro lab)\n";
echo "   - Inicia elección de nuevo master\n\n";

echo "3. {$CYAN}Nuevo master elegido{$NC}\n";
echo "   - La réplica se promociona\n";
echo "   - El mapa de slots se actualiza\n\n";

echo "4. {$CYAN}Predis se recupera{$NC}\n";
echo "   - Recibe MOVED/ASK\n";
echo "   - Actualiza su mapa de slots\n";
echo "   - Reintenta operaciones\n\n";

// Test 7: Métricas importantes
section("TEST 7: Métricas de Failover");

echo "Métricas a monitorear en producción:\n\n";

echo "{$CYAN}Tiempo de detección:{$NC}\n";
echo "  - cluster-node-timeout (default: 15s)\n";
echo "  - Cuánto tarda en detectar que un nodo cayó\n\n";

echo "{$CYAN}Tiempo de failover:{$NC}\n";
echo "  - Tiempo desde detección hasta nuevo master\n";
echo "  - Generalmente < 1 segundo después de detección\n\n";

echo "{$CYAN}Tiempo de recuperación del cliente:{$NC}\n";
echo "  - Depende de la implementación\n";
echo "  - Predis: actualiza mapa en el siguiente comando\n\n";

section("CONCLUSIONES");

echo "✓ El failover es automático en Redis Cluster\n";
echo "✓ Las réplicas se promocionan cuando el master falla\n";
echo "✓ El cluster sigue operativo con nodos restantes\n";
echo "✓ Predis maneja el cambio de topología\n";
echo "✓ Hay un período de indisponibilidad durante el failover\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{$NC}\n";
echo "Si tienes un sistema de pagos y ocurre un failover,\n";
echo "¿qué estrategia usarías para manejar las operaciones\n";
echo "que fallan durante el cambio de master?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-08{$NC}\n";
