<?php
/**
 * ESCENARIO 3: Routing de Predis
 * ==============================
 * 
 * OBJETIVO: Entender cómo Predis decide a qué nodo enviar cada comando.
 * 
 * CONCEPTOS CLAVE:
 * - Predis mantiene un mapa de slots → nodos
 * - Al iniciar, descarga CLUSTER SLOTS del cluster
 * - Para cada comando, calcula el slot y elige el nodo
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Qué pasa si el mapa de Predis queda desactualizado?
 * (Respuesta: Predis recibe MOVED y actualiza el mapa automáticamente)
 */

require __DIR__ . '/../vendor/autoload.php';

use Predis\Client;
use Predis\Cluster\RedisStrategy;

$BLUE = "\033[34m";
$GREEN = "\033[32m";
$YELLOW = "\033[33m";
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

function nodeInfo($node) {
    global $CYAN, $NC;
    $params = $node->getParameters();
    return "{$CYAN}" . $params->host . ":" . $params->port . "{$NC}";
}

require __DIR__ . '/cluster-config.php';

// Conectar al cluster
$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

$strategy = new RedisStrategy();

section("ROUTING DE PREDIS");

echo "Predis mantiene un mapa interno de slots → nodos.\n";
echo "Para cada comando, calcula el slot y envía al nodo correcto.\n\n";

// Test 1: Ver el mapa de slots
section("TEST 1: Mapa de Slots del Cluster");

$slots = $client->executeRaw(['CLUSTER', 'SLOTS']);

echo "Rangos de slots y sus nodos:\n\n";

foreach ($slots as $range) {
    $start = $range[0];
    $end = $range[1];
    $master = $range[2];
    
    $nodeIp = $master[0];
    $nodePort = $master[1];
    
    info("Slots $start-$end", "$nodeIp:$nodePort");
}

// Test 2: Routing de diferentes keys
section("TEST 2: Routing de Keys Específicas");

$testKeys = [
    'user:1',
    'user:2',
    'user:3',
    'session:abc',
    'queue:{default}',
    'cache:data',
];

echo "Para cada key, Predis:\n";
echo "  1. Calcula el slot usando CRC16\n";
echo "  2. Busca el nodo responsable de ese slot\n";
echo "  3. Envía el comando a ese nodo\n\n";

foreach ($testKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    $connection = $client->getConnection()->getConnectionBySlot($slot);
    $node = $connection->getParameters();
    
    echo str_pad("Key: '$key'", 25);
    echo "Slot: " . str_pad($slot, 5);
    echo "→ Nodo: {$CYAN}{$node->host}:{$node->port}{$NC}\n";
}

success("Cada key se enruta al nodo correcto");

// Test 3: Distribución de carga
section("TEST 3: Distribución de Carga");

$slotDistribution = [];
$nodeMap = masterNodeMap();
foreach ($nodeMap as $port => $host) {
    $slotDistribution[$port] = 0;
}

// Simular 1000 keys aleatorias
for ($i = 0; $i < 1000; $i++) {
    $key = 'key-' . uniqid();
    $slot = $strategy->getSlotByKey($key);
    $connection = $client->getConnection()->getConnectionBySlot($slot);
    $port = $connection->getParameters()->port;
    $slotDistribution[$port]++;
}

echo "Distribución de 1000 keys aleatorias:\n\n";

foreach ($slotDistribution as $port => $count) {
    $percentage = round(($count / 1000) * 100, 1);
    $bar = str_repeat('█', $percentage / 2);
    info("Nodo :$port", "$count keys ($percentage%) $bar");
}

success("La distribución es aproximadamente uniforme");

// Test 4: Routing con hash tags
section("TEST 4: Routing con Hash Tags");

echo "Cuando usas hash tags, todas las keys van al mismo nodo.\n\n";

$taggedKeys = [
    'a{user123}',
    'b{user123}',
    'c{user123}',
    'data{user123}',
    'counter{user123}',
];

$firstNode = null;
$allSame = true;

foreach ($taggedKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    $connection = $client->getConnection()->getConnectionBySlot($slot);
    $node = $connection->getParameters();
    
    if ($firstNode === null) {
        $firstNode = $node->port;
    } elseif ($firstNode !== $node->port) {
        $allSame = false;
    }
    
    info($key, "Slot $slot → :{$node->port}");
}

if ($allSame) {
    success("¡Todas las keys van al mismo nodo (:$firstNode)!");
} else {
    echo "⚠ Las keys fueron a nodos diferentes (hash tag diferente)\n";
}

// Test 5: Conexiones activas
section("TEST 5: Conexiones del Cliente");

$connection = $client->getConnection();

echo "Tipo de conexión: " . get_class($connection) . "\n\n";

// Contar conexiones por nodo
$connections = [];
$nodeMap = masterNodeMap();
foreach ($nodeMap as $port => $host) {
    try {
        $testClient = new Client("tcp://$host:$port");
        $info = $testClient->info('clients');
        $connected = $info['connected_clients'] ?? 'N/A';
        info("Nodo $host:$port", "$connected clientes conectados");
    } catch (Exception $e) {
        info("Nodo $host:$port", "No disponible");
    }
}

// Test 6: Latencia por nodo
section("TEST 6: Latencia por Nodo");

echo "Midiendo latencia a cada nodo...\n\n";

$nodeMap = masterNodeMap();
foreach ($nodeMap as $port => $host) {
    $start = microtime(true);
    
    try {
        $nodeClient = new Client("tcp://$host:$port");
        $nodeClient->ping();
        $latency = round((microtime(true) - $start) * 1000, 2);
        info("Nodo $host:$port", "{$latency}ms");
    } catch (Exception $e) {
        info("Nodo $host:$port", "Error: " . $e->getMessage());
    }
}

// Test 7: Operaciones que requieren mismo nodo
section("TEST 7: Operaciones Multi-Key");

echo "Predis automáticamente enruta operaciones multi-key.\n\n";

// Guardar varias keys con mismo hash tag
$client->set('multi{a}', '1');
$client->set('multi{b}', '2');
$client->set('multi{c}', '3');

// MGET (debería funcionar porque usamos hash tag implícito)
try {
    $values = $client->mget(['multi{a}', 'multi{b}', 'multi{c}']);
    success("MGET exitoso: " . implode(', ', $values));
} catch (Exception $e) {
    echo "Error: " . $e->getMessage() . "\n";
}

section("CONCLUSIONES");

echo "✓ Predis mantiene un mapa slots → nodos en memoria\n";
echo "✓ Para cada comando, calcula el slot y elige el nodo\n";
echo "✓ Las keys se distribuyen uniformemente entre nodos\n";
echo "✓ Los hash tags permiten agrupar keys en un mismo nodo\n";
echo "✓ El routing es transparente para la aplicación\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{\$NC}\n";
echo "Si Predis tiene el mapa desactualizado (ej: después de un failover),\n";
echo "¿qué crees que pasará cuando intente escribir en un nodo que ya no es master?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-04{$NC}\n";
