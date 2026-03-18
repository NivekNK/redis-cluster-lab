<?php
/**
 * ESCENARIO 2: Hash Tags {}
 * ========================
 * 
 * OBJETIVO: Comprender por qué los hash tags son CRÍTICOS en Redis Cluster.
 * 
 * CONCEPTOS CLAVE:
 * - Solo el contenido entre {} se usa para calcular el slot
 * - Keys con el mismo hash tag van al mismo slot
 * - Esto permite operaciones atómicas (MGET, pipelines, Lua)
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Por qué Laravel usa {default} en las colas?
 * (Respuesta: Para garantizar que todas las operaciones de la cola
 *  sean atómicas, ya que usan múltiples keys)
 */

require __DIR__ . '/../vendor/autoload.php';

use Predis\Client;
use Predis\Cluster\RedisStrategy;

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
    echo str_pad($label, 40) . " {$YELLOW}{$value}{$NC}\n";
}

function success($msg) {
    global $GREEN, $NC;
    echo "{$GREEN}✓ {$msg}{$NC}\n";
}

function error($msg) {
    global $RED, $NC;
    echo "{$RED}✗ {$msg}{$NC}\n";
}

require __DIR__ . '/cluster-config.php';

// Conectar al cluster
$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

$strategy = new RedisStrategy();

section("HASH TAGS: EL SECRETO DE LAS OPERACIONES ATÓMICAS");

echo "En Redis Cluster, solo el contenido entre {} se usa para calcular el slot.\n";
echo "Esto permite forzar que múltiples keys vayan al mismo slot.\n\n";

// Test 1: Comparar keys con y sin hash tag
section("TEST 1: Con vs Sin Hash Tag");

$comparisons = [
    ['queue:default', 'queue:{default}'],
    ['user:123:profile', 'user:{123}:profile'],
    ['session:abc:data', 'session:{abc}:data'],
    ['api-tee_queues:default', 'api-tee_queues:{default}'],
];

foreach ($comparisons as [$without, $with]) {
    $slotWithout = $strategy->getSlotByKey($without);
    $slotWith = $strategy->getSlotByKey($with);
    
    echo "Sin tag: '$without' → Slot $slotWithout\n";
    echo "Con tag: '$with' → Slot $slotWith\n";
    
    if ($slotWithout !== $slotWith) {
        success("Los slots son diferentes (comportamiento esperado)");
    } else {
        echo "  (Coincidencia casual)\n";
    }
    echo "\n";
}

// Test 2: Múltiples keys con el mismo hash tag
section("TEST 2: Múltiples Keys, Mismo Hash Tag");

$keysWithSameTag = [
    'queue:{default}',
    'queue:{default}:processing',
    'queue:{default}:delayed',
    'queue:{default}:failed',
    'queue:{default}:reserved',
];

echo "Todas estas keys usan el hash tag {default}:\n\n";

$slots = [];
foreach ($keysWithSameTag as $key) {
    $slot = $strategy->getSlotByKey($key);
    $slots[] = $slot;
    info($key, "Slot $slot");
}

$uniqueSlots = array_unique($slots);
if (count($uniqueSlots) === 1) {
    success("¡TODAS las keys van al mismo slot! (" . $uniqueSlots[0] . ")");
    echo "\n{$GREEN}Esto permite operaciones atómicas entre estas keys{$NC}\n";
} else {
    error("Las keys van a slots diferentes - ¡Esto no debería pasar!");
}

// Test 3: Operación MGET (requiere mismo slot)
section("TEST 3: Operación MGET (Multi-Get)");

echo "MGET requiere que todas las keys estén en el mismo slot.\n\n";

// Sin hash tags (puede fallar)
echo "Intentando MGET sin hash tags:\n";
try {
    $client->mget(['key1', 'key2', 'key3']);
    success("MGET funcionó (las keys coincidieron en el mismo slot por casualidad)");
} catch (Exception $e) {
    error("MGET falló: " . $e->getMessage());
    echo "{$YELLOW}Esto es esperado si las keys están en slots diferentes{$NC}\n";
}

// Con hash tags (siempre funciona)
echo "\nIntentando MGET con hash tags:\n";
try {
    $client->mget(['key1{test}', 'key2{test}', 'key3{test}']);
    success("MGET con hash tags funcionó correctamente");
} catch (Exception $e) {
    error("Error inesperado: " . $e->getMessage());
}

// Test 4: Pipeline con hash tags
section("TEST 4: Pipeline con Hash Tags");

echo "Los pipelines también requieren que las keys estén en el mismo slot.\n\n";

// Pipeline exitoso (mismo hash tag)
echo "Pipeline con mismo hash tag:\n";
try {
    $client->pipeline(function ($pipe) {
        $pipe->set('a{pipeline}', '1');
        $pipe->set('b{pipeline}', '2');
        $pipe->set('c{pipeline}', '3');
        $pipe->incr('counter{pipeline}');
    });
    success("Pipeline ejecutado exitosamente");
} catch (Exception $e) {
    error("Error: " . $e->getMessage());
}

// Test 5: Simulación de cola Laravel
section("TEST 5: Simulación de Cola Laravel");

echo "Laravel Horizon usa múltiples keys para cada cola:\n";
echo "- queues:{default} (cola principal)\n";
echo "- queues:{default}:reserved (jobs en proceso)\n";
echo "- queues:{default}:delayed (jobs retrasados)\n\n";

$laravelKeys = [
    'queues:{default}',
    'queues:{default}:reserved',
    'queues:{default}:delayed',
];

foreach ($laravelKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    info($key, "Slot $slot");
}

// Simular operación de cola
$queue = 'queues:{default}';
$processing = 'queues:{default}:processing';

echo "\nSimulando operación de cola (RPUSH + LPOP):\n";

$client->del([$queue, $processing]);
$client->rpush($queue, ['job1', 'job2', 'job3']);
$job = $client->rpoplpush($queue, $processing);

success("Job movido atómicamente: $job");

// Test 6: Hash tags anidados
section("TEST 6: Hash Tags Anidados");

echo "¿Qué pasa si hay múltiples {} en una key?\n";
echo "Redis usa SOLO el primero.\n\n";

$nestedKeys = [
    'a{tag1}b{tag2}c',
    'a{tag2}b{tag1}c',
    '{tag1}resto{tag2}',
];

foreach ($nestedKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    info($key, "Slot $slot (usa solo el primer {})");
}

// Verificar que tag1 y tag2 dan slots diferentes
$slot1 = $strategy->getSlotByKey('{tag1}');
$slot2 = $strategy->getSlotByKey('{tag2}');

if ($slot1 !== $slot2) {
    success("Confirmado: {tag1} y {tag2} dan slots diferentes");
}

// Test 7: Hash tags vacíos
section("TEST 7: Casos Especiales");

echo "Hash tag vacío '{}':\n";
$slotEmpty = $strategy->getSlotByKey('key{}');
info("key{}", "Slot $slotEmpty");

echo "\nSin hash tag:\n";
$slotNoTag = $strategy->getSlotByKey('key');
info("key", "Slot $slotNoTag");

echo "\nHash tag con espacios:\n";
$slotSpace = $strategy->getSlotByKey('key{my tag}');
info("key{my tag}", "Slot $slotSpace");

section("CONCLUSIONES");

echo "✓ Los hash tags fuerzan que múltiples keys vayan al mismo slot\n";
echo "✓ Esto permite operaciones atómicas (MGET, pipelines, Lua scripts)\n";
echo "✓ Laravel usa {default} para garantizar atomicidad en colas\n";
echo "✓ El trade-off: sacrificas sharding horizontal por consistencia\n";

echo "\n{$YELLOW}PREGUNTA CRÍTICA:{\$NC}\n";
echo "Si usas '{api-tee}' como prefix para TODAS tus keys,\n";
echo "¿cuántos slots de los 16384 estarás usando?\n";
echo "¿Qué implica esto para escalar tu cluster?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-03{$NC}\n";
