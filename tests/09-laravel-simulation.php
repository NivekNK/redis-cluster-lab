<?php
/**
 * ESCENARIO 9: Simulación de Laravel Horizon
 * ==========================================
 * 
 * OBJETIVO: Simular cómo Laravel Horizon usa Redis Cluster para colas.
 * 
 * CONCEPTOS CLAVE:
 * - Laravel usa scripts Lua para operaciones atómicas
 * - Múltiples keys por cola (queue, reserved, delayed, notify)
 * - El prefix {api-tee} fuerza todo al mismo slot
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Por qué Laravel usa scripts Lua en lugar de comandos simples?
 * (Respuesta: Para garantizar atomicidad y evitar race conditions
 *  entre múltiples workers)
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
    echo str_pad($label, 40) . " {$YELLOW}{$value}{$NC}\n";
}

function success($msg) {
    global $GREEN, $NC;
    echo "{$GREEN}✓ {$msg}{$NC}\n";
}

function metric($label, $value) {
    global $CYAN, $NC;
    echo str_pad($label, 35) . " {$CYAN}{$value}{$NC}\n";
}

require __DIR__ . '/cluster-config.php';

// Conectar al cluster
$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

$strategy = new RedisStrategy();

section("SIMULACIÓN DE LARAVEL HORIZON");

echo "Laravel Horizon usa Redis Cluster para colas distribuidas.\n";
echo "Vamos a simular su comportamiento interno.\n\n";

// Configuración similar a Laravel
$prefix = '{api-tee}';
$queue = 'default';

// Test 1: Estructura de keys de Laravel
section("TEST 1: Estructura de Keys de Laravel");

$laravelKeys = [
    "$prefix:queues:$queue",
    "$prefix:queues:$queue:reserved",
    "$prefix:queues:$queue:delayed",
    "$prefix:queues:$queue:notify",
    "$prefix:queues:$queue:failed",
];

echo "Keys que Laravel usa para la cola '$queue':\n\n";

$slots = [];
foreach ($laravelKeys as $key) {
    $slot = $strategy->getSlotByKey($key);
    $slots[] = $slot;
    info($key, "Slot $slot");
}

$uniqueSlots = array_unique($slots);
if (count($uniqueSlots) === 1) {
    success("¡Todas las keys van al mismo slot (" . $uniqueSlots[0] . ")!");
    echo "\n{$GREEN}Esto garantiza atomicidad en todas las operaciones.{\$NC}\n";
} else {
    error("Las keys van a slots diferentes");
}

// Test 2: Simular push de job
section("TEST 2: Simular Push de Job");

$queueKey = "$prefix:queues:$queue";
$jobPayload = json_encode([
    'id' => uniqid('job_'),
    'displayName' => 'App\\Jobs\\ProcessPayment',
    'job' => 'Illuminate\\Queue\\CallQueuedHandler@call',
    'data' => ['order_id' => 12345],
    'attempts' => 0,
]);

$client->del([$queueKey]);
$client->rpush($queueKey, [$jobPayload]);

$queueLen = $client->llen($queueKey);
success("Job agregado a la cola");
info("Jobs en cola", $queueLen);
info("Payload", substr($jobPayload, 0, 60) . "...");

// Test 3: Simular worker tomando job (RPOPLPUSH)
section("TEST 3: Simular Worker Tomando Job");

$reservedKey = "$prefix:queues:$queue:reserved";

$client->del([$reservedKey]);

// Worker toma job atómicamente
$job = $client->rpoplpush($queueKey, $reservedKey);

if ($job) {
    $jobData = json_decode($job, true);
    success("Job tomado atómicamente");
    info("Job ID", $jobData['id'] ?? 'N/A');
    info("Job Class", $jobData['displayName'] ?? 'N/A');
    info("Queue length", $client->llen($queueKey));
    info("Reserved length", $client->llen($reservedKey));
}

// Test 4: Simular procesamiento y release
section("TEST 4: Simular Procesamiento y Release");

echo "Si el job falla, Laravel lo devuelve a la cola\n";
echo "o lo mueva a delayed para retry.\n\n";

// Simular fallo y release
$client->lrem($reservedKey, 0, $job);
$client->rpush($queueKey, [$job]);

success("Job devuelto a la cola para reintento");
info("Queue length", $client->llen($queueKey));
info("Reserved length", $client->llen($reservedKey));

// Test 5: Simular delayed jobs
section("TEST 5: Simular Delayed Jobs");

$delayedKey = "$prefix:queues:$queue:delayed";
$client->del([$delayedKey]);

// Agregar job con delay
$delay = 60; // segundos
$availableAt = time() + $delay;

$delayedJob = json_encode([
    'id' => uniqid('delayed_job_'),
    'displayName' => 'App\\Jobs\\SendEmail',
    'payload' => ['email' => 'user@example.com'],
    'available_at' => $availableAt,
]);

// Formato correcto: zadd key score member
$client->zadd($delayedKey, $availableAt, $delayedJob);

success("Job agregado con delay de $delay segundos");
info("Available at", date('Y-m-d H:i:s', $availableAt));
info("Delayed jobs", $client->zcard($delayedKey));

// Test 6: Métricas de Laravel
section("TEST 6: Métricas que Laravel Monitorea");

echo "Laravel Horizon monitorea estas métricas:\n\n";

// Simular algunas operaciones
for ($i = 0; $i < 5; $i++) {
    $client->rpush($queueKey, [json_encode(['id' => $i])]);
}

$metrics = [
    'Queue size' => $client->llen($queueKey),
    'Reserved jobs' => $client->llen($reservedKey),
    'Delayed jobs' => $client->zcard($delayedKey),
    'Failed jobs' => $client->llen("$prefix:queues:$queue:failed"),
];

foreach ($metrics as $name => $value) {
    metric($name, $value);
}

// Test 7: Script Lua (como Laravel)
section("TEST 7: Script Lua (Operaciones Atómicas)");

echo "Laravel usa scripts Lua para operaciones atómicas.\n";
echo "Ejemplo: mover jobs de delayed a queue.\n\n";

$luaScript = <<<'LUA'
local delayed = KEYS[1]
local queue = KEYS[2]
local now = tonumber(ARGV[1])

-- Obtener jobs listos
local jobs = redis.call('zrangebyscore', delayed, 0, now)

-- Mover a queue
for i, job in ipairs(jobs) do
    redis.call('rpush', queue, job)
    redis.call('zrem', delayed, job)
end

return #jobs
LUA;

// Preparar datos
$client->del(['{test}:delayed', '{test}:queue']);
$client->zadd('{test}:delayed', time() - 10, 'job-past-1');
$client->zadd('{test}:delayed', time() - 5, 'job-past-2');
$client->zadd('{test}:delayed', time() + 100, 'job-future');

// Ejecutar script
$moved = $client->eval($luaScript, 2, '{test}:delayed', '{test}:queue', time());

success("Script Lua ejecutado");
info("Jobs movidos", $moved);
info("Jobs en queue", $client->llen('{test}:queue'))
;
info("Jobs restantes en delayed", $client->zcard('{test}:delayed'));

// Test 8: Análisis de tu configuración
section("TEST 8: Análisis de tu Configuración");

echo "Basado en tu dump de Predis, tenías:\n\n";

echo "{$CYAN}Prefix: {api-tee}{\$NC}\n";
echo "  → Todas las keys usan el mismo hash tag\n";
echo "  → Todas caen en el mismo slot\n";
echo "  → Operaciones atómicas garantizadas\n\n";

$slot = $strategy->getSlotByKey('{api-tee}');
$connection = $client->getConnection()->getConnectionBySlot($slot);
$node = $connection->getParameters();

info("Slot de {api-tee}", $slot);
info("Nodo responsable", $node->host . ":" . $node->port);

echo "\n{$YELLOW}Implicación:{\$NC}\n";
echo "Con prefix '{api-tee}', TODO tu tráfico Redis va a un solo nodo.\n";
echo "El cluster no distribuye carga, solo proporciona failover.\n";

section("CONCLUSIONES");

echo "✓ Laravel usa múltiples keys por cola\n";
echo "✓ Todas las keys comparten el mismo hash tag\n";
echo "✓ Los scripts Lua garantizan atomicidad\n";
echo "✓ RPOPLPUSH permite mover jobs sin race conditions\n";
echo "✓ Tu configuración con {api-tee} es segura pero no escalable\n";

echo "\n{$YELLOW}PREGUNTA FINAL:{\$NC}\n";
echo "Si tu sistema crece y necesitas distribuir carga,\n";
echo "¿qué estrategias podrías usar manteniendo atomicidad?\n";
echo "\nOpciones:\n";
echo "  1. Múltiples colas con diferentes hash tags\n";
echo "  2. SQS para colas, Redis para cache\n";
echo "  3. Redis Streams en lugar de Listas\n";

echo "\n{$GREEN}Laboratorio completado!{$NC}\n";
echo "\nComandos útiles:\n";
echo "  make status    - Ver estado del cluster\n";
echo "  make monitor   - Monitorear comandos\n";
echo "  make reset     - Reiniciar el laboratorio\n";
