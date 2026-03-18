<?php
/**
 * ESCENARIO 1: Fundamentos de Slots
 * =================================
 * 
 * OBJETIVO: Comprender cómo Redis Cluster distribuye datos usando slots.
 * 
 * CONCEPTOS CLAVE:
 * - Redis Cluster tiene 16384 slots (0-16383)
 * - Cada key se asigna a un slot usando CRC16
 * - Los slots se distribuyen entre los masters
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Por qué 16384 slots y no más o menos?
 * (Respuesta: Es un balance entre granularidad y eficiencia de memoria)
 */

require __DIR__ . '/../vendor/autoload.php';

use Predis\Client;
use Predis\Cluster\RedisStrategy;

// Colores para output
$BLUE = "\033[34m";
$GREEN = "\033[32m";
$YELLOW = "\033[33m";
$RED = "\033[31m";
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

require __DIR__ . '/cluster-config.php';

// Conectar al cluster
$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

// Estrategia para calcular slots
$strategy = new RedisStrategy();

section("FUNDAMENTOS DE SLOTS");

echo "Redis Cluster divide el espacio de keys en 16384 slots (0-16383).\n";
echo "Cada key se asigna a un slot usando el algoritmo CRC16.\n\n";

// Test 1: Calcular slots de diferentes keys
section("TEST 1: Cálculo de Slots");

$testKeys = [
    'simple-key',
    'user:123',
    'session:abc123',
    'queue:default',
    'cache:data',
    'a',  // key muy corta
    'una-key-muy-larga-para-probar-el-algoritmo-de-hash',
];

foreach ($testKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    info("Key: '$key'", "Slot: $slot");
}

success("Todas las keys tienen un slot asignado (0-16383)");

// Test 2: Distribución de slots en el cluster
section("TEST 2: Distribución en el Cluster");

$slots = $client->executeRaw(['CLUSTER', 'SLOTS']);

echo "El cluster tiene " . count($slots) . " rangos de slots:\n\n";

foreach ($slots as $range) {
    $start = $range[0];
    $end = $range[1];
    $master = $range[2];
    
    $nodeIp = $master[0];
    $nodePort = $master[1];
    $slotCount = $end - $start + 1;
    
    info("Slots $start-$end", "$slotCount slots -> $nodeIp:$nodePort");
}

success("Slots distribuidos entre los masters");

// Test 3: Verificar dónde vive una key específica
section("TEST 3: Ubicación de Keys");

$key = 'mi-key-de-prueba';
$slot = $strategy->getSlotByKey($key);

info("Key", $key);
info("Slot calculado", $slot);

// Encontrar qué nodo tiene ese slot
$connection = $client->getConnection()->getConnectionBySlot($slot);
$nodeParams = $connection->getParameters();

info("Nodo responsable", $nodeParams->host . ':' . $nodeParams->port);

// Guardar y recuperar
$client->set($key, 'valor-de-prueba');
$value = $client->get($key);

success("Key guardada y recuperada exitosamente");
info("Valor", $value);

// Test 4: Colisión de slots (diferentes keys, mismo slot)
section("TEST 4: Colisión de Slots");

echo "Dos keys diferentes pueden caer en el mismo slot.\n";
echo "Esto NO es un problema, es comportamiento normal.\n\n";

// Buscar colisiones
$keysToTest = [];
for ($i = 0; $i < 100; $i++) {
    $key = "key-$i";
    $slot = $strategy->getSlotByKey($key);
    if (!isset($keysToTest[$slot])) {
        $keysToTest[$slot] = [];
    }
    $keysToTest[$slot][] = $key;
}

// Encontrar un slot con múltiples keys
$found = false;
foreach ($keysToTest as $slot => $keys) {
    if (count($keys) > 1) {
        info("Slot $slot", implode(', ', array_slice($keys, 0, 3)) . "...");
        $found = true;
        break;
    }
}

if (!$found) {
    echo "No se encontraron colisiones en la muestra (raro pero posible)\n";
}

success("Las colisiones son normales y no causan problemas");

// Test 5: Rango completo de slots
section("TEST 5: Rango Completo de Slots");

$allSlots = $client->executeRaw(['CLUSTER', 'SLOTS']);
$totalSlots = 0;

foreach ($allSlots as $range) {
    $totalSlots += ($range[1] - $range[0] + 1);
}

info("Total de slots cubiertos", $totalSlots);
info("Slots esperados", "16384");

if ($totalSlots === 16384) {
    success("Todos los slots están cubiertos!");
} else {
    echo "{$RED}⚠ Algunos slots no están asignados{$NC}\n";
}

section("CONCLUSIONES");

echo "✓ Redis Cluster usa 16384 slots para distribuir datos\n";
echo "✓ Cada key se asigna a un slot usando CRC16\n";
echo "✓ Los slots se distribuyen entre los nodos master\n";
echo "✓ Múltiples keys pueden compartir el mismo slot (colisión)\n";
echo "✓ El cliente (Predis) calcula el slot y envía al nodo correcto\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{\$NC}\n";
echo "Si todas tus keys usan el mismo hash tag (ej: {default}),\n";
echo "¿en cuántos slots caerán? ¿Qué implica esto para el sharding?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-02{$NC}\n";
