<?php
/**
 * ESCENARIO 8: Patrones de Colas
 * ==============================
 * 
 * OBJETIVO: Comprender cómo implementar colas correctamente en Redis Cluster.
 * 
 * CONCEPTOS CLAVE:
 * - Las colas usan múltiples keys (queue, processing, delayed)
 * - Todas deben compartir el mismo hash tag
 * - RPOPLPUSH permite mover jobs atómicamente
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Por qué Laravel usa {default} en lugar de un hash tag por cola?
 * (Respuesta: Para garantizar que todas las operaciones de una cola
 *  específica sean atómicas y vayan al mismo nodo)
 */

require __DIR__ . '/../vendor/autoload.php';

use Predis\Client;
use Predis\Cluster\RedisStrategy;

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

section("PATRONES DE COLAS EN REDIS CLUSTER");

echo "Las colas en Redis usan múltiples keys:\n";
echo "  - queue:{name} (cola principal)\n";
echo "  - queue:{name}:processing (jobs en proceso)\n";
echo "  - queue:{name}:delayed (jobs retrasados)\n";
echo "  - queue:{name}:failed (jobs fallidos)\n\n";

echo "Todas deben compartir el mismo hash tag para operaciones atómicas.\n\n";

// Test 1: Estructura de cola Laravel
section("TEST 1: Estructura de Cola Laravel");

$queueKeys = [
    'queues:{default}',
    'queues:{default}:reserved',
    'queues:{default}:delayed',
    'queues:{default}:notify',
];

echo "Keys usadas por Laravel Horizon:\n\n";

$slots = [];
foreach ($queueKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    $slots[] = $slot;
    info($key, "Slot $slot");
}

$uniqueSlots = array_unique($slots);
if (count($uniqueSlots) === 1) {
    success("¡Todas las keys van al mismo slot!");
    echo "\n{$GREEN}Esto permite operaciones atómicas en la cola.{$NC}\n";
} else {
    error("Las keys van a slots diferentes");
}

// Test 2: Implementación básica de cola
section("TEST 2: Implementación Básica de Cola");

$queue = 'queue:{test}';
$processing = 'queue:{test}:processing';

// Limpiar
$client->del([$queue, $processing]);

// Agregar jobs
$jobs = ['job-1', 'job-2', 'job-3'];
foreach ($jobs as $job) {
    $client->rpush($queue, [$job]);
}

$queueLen = $client->llen($queue);
success("Jobs en cola: $queueLen");

// Procesar jobs
$processed = [];
while ($client->llen($queue) > 0) {
    // RPOPLPUSH: mueve atómicamente de queue a processing
    $job = $client->rpoplpush($queue, $processing);
    $processed[] = $job;
    
    // Simular procesamiento
    echo "Procesando: $job\n";
    
    // Eliminar de processing cuando termina
    $client->lrem($processing, 0, $job);
}

success("Jobs procesados: " . count($processed));

// Test 3: Cola con delayed jobs
section("TEST 3: Cola con Jobs Retrasados");

$queue = 'queue:{delayed-test}';
$delayed = 'queue:{delayed-test}:delayed';
$processing = 'queue:{delayed-test}:processing';

$client->del([$queue, $delayed, $processing]);

// Agregar jobs normales
$client->rpush($queue, ['normal-job-1', 'normal-job-2']);

// Agregar job retrasado (con timestamp futuro)
$futureTime = time() + 3600; // 1 hora en el futuro
// Formato correcto: zadd key score member [score member ...]
$client->zadd($delayed, $futureTime, 'delayed-job-1');

echo "Jobs en cola normal: " . $client->llen($queue) . "\n";
echo "Jobs retrasados: " . $client->zcard($delayed) . "\n";

// Simular worker revisando jobs retrasados
$now = time() + 3700; // Simulamos que pasó 1 hora
$readyJobs = $client->zrangebyscore($delayed, 0, $now);

if (count($readyJobs) > 0) {
    echo "\nJobs listos para procesar:\n";
    foreach ($readyJobs as $job) {
        echo "  - $job\n";
        // Mover a cola normal
        $client->rpush($queue, [$job]);
        $client->zrem($delayed, $job);
    }
}

success("Jobs retrasados movidos a cola normal");

// Test 4: Múltiples colas
section("TEST 4: Múltiples Colas con Hash Tags");

$queues = [
    'emails' => 'queue:{emails}',
    'payments' => 'queue:{payments}',
    'notifications' => 'queue:{notifications}',
];

echo "Distribución de colas en el cluster:\n\n";

foreach ($queues as $name => $queue) {
    $slot = $strategy->getSlotByKey($queue);
    $connection = $client->getConnection()->getConnectionBySlot($slot);
    $node = $connection->getParameters();
    
    info("Cola $name", "Slot $slot → :{$node->port}");
}

echo "\n{$CYAN}Cada cola puede estar en un nodo diferente,{\$NC}\n";
echo "{$CYAN}pero todas las operaciones de una cola son atómicas.{\$NC}\n";

// Test 5: Worker concurrente
section("TEST 5: Simulación de Workers Concurrentes");

$queue = 'queue:{concurrent}';
$processing = 'queue:{concurrent}:processing';

$client->del([$queue, $processing]);

// Agregar jobs
for ($i = 1; $i <= 10; $i++) {
    $client->rpush($queue, ["concurrent-job-$i"]);
}

echo "Jobs en cola: " . $client->llen($queue) . "\n\n";

echo "Simulando 2 workers tomando jobs:\n\n";

$worker1Jobs = [];
$worker2Jobs = [];

while ($client->llen($queue) > 0) {
    // Worker 1 toma un job
    $job1 = $client->rpoplpush($queue, $processing);
    if ($job1) {
        $worker1Jobs[] = $job1;
        echo "Worker 1: $job1\n";
        $client->lrem($processing, 0, $job1);
    }
    
    // Worker 2 toma un job
    $job2 = $client->rpoplpush($queue, $processing);
    if ($job2) {
        $worker2Jobs[] = $job2;
        echo "Worker 2: $job2\n";
        $client->lrem($processing, 0, $job2);
    }
}

echo "\n";
success("Worker 1 procesó: " . count($worker1Jobs));
success("Worker 2 procesó: " . count($worker2Jobs));

// Test 6: Patrón de cola con prioridad
section("TEST 6: Cola con Prioridad");

$highPriority = 'queue:{priority}:high';
$normalPriority = 'queue:{priority}:normal';
$lowPriority = 'queue:{priority}:low';

$client->del([$highPriority, $normalPriority, $lowPriority]);

// Agregar jobs con diferentes prioridades
$client->rpush($lowPriority, ['low-1', 'low-2']);
$client->rpush($normalPriority, ['normal-1', 'normal-2']);
$client->rpush($highPriority, ['high-1', 'high-2']);

echo "Jobs por prioridad:\n";
echo "  Alta: " . $client->llen($highPriority) . "\n";
echo "  Normal: " . $client->llen($normalPriority) . "\n";
echo "  Baja: " . $client->llen($lowPriority) . "\n\n";

echo "Procesando en orden de prioridad:\n";

$processed = [];

// Procesar alta prioridad primero
while ($client->llen($highPriority) > 0) {
    $job = $client->lpop($highPriority);
    $processed[] = "[ALTA] $job";
}

// Luego normal
while ($client->llen($normalPriority) > 0) {
    $job = $client->lpop($normalPriority);
    $processed[] = "[NORMAL] $job";
}

// Finalmente baja
while ($client->llen($lowPriority) > 0) {
    $job = $client->lpop($lowPriority);
    $processed[] = "[BAJA] $job";
}

foreach ($processed as $job) {
    echo "  $job\n";
}

success("Jobs procesados por prioridad");

section("CONCLUSIONES");

echo "✓ Las colas usan múltiples keys que deben compartir hash tag\n";
echo "✓ RPOPLPUSH permite mover jobs atómicamente\n";
echo "✓ Múltiples workers pueden procesar la misma cola\n";
echo "✓ Se pueden implementar colas con prioridad\n";
echo "✓ Cada cola puede distribuirse en nodos diferentes\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{$NC}\n";
echo "Si tienes 100 colas diferentes y todas usan hash tags\n";
echo "diferentes, ¿cómo afecta esto la distribución de carga\n";
echo "en tu cluster?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-09{$NC}\n";

