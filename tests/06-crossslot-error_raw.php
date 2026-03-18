<?php
/**
 * ESCENARIO 6: Error CROSSSLOT
 * ============================
 * 
 * OBJETIVO: Comprender el error CROSSSLOT y por qué ocurre.
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

function error($msg) {
    global $RED, $NC;
    echo "{$RED}✗ {$msg}{$NC}\n";
}

require __DIR__ . '/cluster-config.php';

$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

$strategy = new RedisStrategy();

section("ERROR CROSSSLOT");

echo "CROSSSLOT ocurre cuando intentas operar sobre keys\n";
echo "que están en slots diferentes.\n\n";

// Test 1: Provocar CROSSSLOT con MGET usando executeRaw
section("TEST 1: CROSSSLOT con MGET");

$key1 = 'key-alpha';
$key2 = 'key-beta';

$slot1 = $strategy->getSlotByKey($key1);
$slot2 = $strategy->getSlotByKey($key2);

info("Key 1", "$key1 → Slot $slot1");
info("Key 2", "$key2 → Slot $slot2");

if ($slot1 !== $slot2) {
    echo "\n{$CYAN}Las keys están en slots diferentes. Intentando MGET...{$NC}\n\n";
    
    // Usar executeRaw para forzar el comando sin validación de Predis
    try {
        $client->executeRaw(['MGET', $key1, $key2]);
        success("MGET funcionó (sorpresa!)");
    } catch (\Predis\Response\ServerException $e) {
        if (strpos($e->getMessage(), 'CROSSSLOT') !== false) {
            error("¡CROSSSLOT ERROR!");
            info("Mensaje", $e->getMessage());
            echo "\n{$GREEN}✓ Esto es el comportamiento esperado{$NC}\n";
        } else {
            echo "Error diferente: " . $e->getMessage() . "\n";
        }
    } catch (\Predis\NotSupportedException $e) {
        // Si Predis bloquea, mostrar mensaje educativo
        error("Predis bloqueó la operación antes de enviarla a Redis");
        info("Razón", "Las keys están en slots diferentes");
        echo "\n{$YELLOW}Nota: Para ver el error real de Redis, usa redis-cli directamente:${NC}\n";
        echo "  docker exec -e SHARDS=\$SHARDS -it redis-lab redis-cli -h redis-node-1 -p 7000 MGET $key1 $key2\n";
    }
}

// Test 2: Solución con hash tags
section("TEST 2: Solución con Hash Tags");

$key1 = 'a{same-slot}';
$key2 = 'b{same-slot}';
$key3 = 'c{same-slot}';

$slot1 = $strategy->getSlotByKey($key1);
$slot2 = $strategy->getSlotByKey($key2);
$slot3 = $strategy->getSlotByKey($key3);

info("Key 1", "$key1 → Slot $slot1");
info("Key 2", "$key2 → Slot $slot2");
info("Key 3", "$key3 → Slot $slot3");

if ($slot1 === $slot2 && $slot2 === $slot3) {
    echo "\n{$GREEN}✓ Todas las keys van al mismo slot!{$NC}\n\n";
    
    // Guardar valores
    $client->set($key1, 'valor-1');
    $client->set($key2, 'valor-2');
    $client->set($key3, 'valor-3');
    
    // MGET debería funcionar ahora porque Predis detecta mismo slot
    try {
        $values = $client->mget([$key1, $key2, $key3]);
        success("MGET exitoso: " . implode(', ', $values));
    } catch (Exception $e) {
        error("Error inesperado: " . $e->getMessage());
    }
}

// Test 3: Pipeline y CROSSSLOT
section("TEST 3: Pipeline con Slots Diferentes");

echo "Los pipelines en Predis manejan automáticamente el routing.\n";
echo "Veamos qué pasa con slots diferentes:\n\n";

$keyA = 'pipeline-a';
$keyB = 'pipeline-b';

$slotA = $strategy->getSlotByKey($keyA);
$slotB = $strategy->getSlotByKey($keyB);

info("Key A", "$keyA → Slot $slotA");
info("Key B", "$keyB → Slot $slotB");

if ($slotA !== $slotB) {
    echo "\n{$YELLOW}Nota: Predis enviará cada comando al nodo correcto{$NC}\n";
    echo "No habrá error CROSSSLOT porque son comandos separados.\n\n";
    
    try {
        $client->pipeline(function ($pipe) use ($keyA, $keyB) {
            $pipe->set($keyA, '1');
            $pipe->set($keyB, '2');
        });
        success("Pipeline funcionó correctamente (comandos separados)");
    } catch (Exception $e) {
        error("Error: " . $e->getMessage());
    }
}

// Test 4: Pipeline con mismo hash tag (comandos agrupados)
section("TEST 4: Pipeline con Hash Tags");

echo "Pipeline con mismo hash tag (garantiza mismo nodo):\n\n";

try {
    $client->pipeline(function ($pipe) {
        $pipe->set('x{pipeline}', '1');
        $pipe->set('y{pipeline}', '2');
        $pipe->set('z{pipeline}', '3');
    });
    success("Pipeline con hash tags exitoso");
    
    // Verificar que están en el mismo nodo
    $values = $client->mget(['x{pipeline}', 'y{pipeline}', 'z{pipeline}']);
    success("MGET posterior también funciona: " . implode(', ', $values));
    
} catch (Exception $e) {
    error("Error: " . $e->getMessage());
}

// Test 5: RPOPLPUSH (operación atómica de cola)
section("TEST 5: RPOPLPUSH y Colas");

echo "RPOPLPUSH mueve un elemento entre dos listas atómicamente.\n";
echo "Requiere que ambas listas estén en el mismo slot.\n\n";

// Sin hash tags (puede fallar)
$source = 'queue:source';
$dest = 'queue:destination';

$slotSource = $strategy->getSlotByKey($source);
$slotDest = $strategy->getSlotByKey($dest);

info("Source", "$source → Slot $slotSource");
info("Dest", "$dest → Slot $slotDest");

if ($slotSource !== $slotDest) {
    echo "\nIntentando RPOPLPUSH con slots diferentes...\n";
    
    $client->rpush($source, ['job1']);
    
    try {
        // Usar executeRaw para forzar el comando
        $client->executeRaw(['RPOPLPUSH', $source, $dest]);
        success("RPOPLPUSH funcionó (sorpresa!)");
    } catch (\Predis\Response\ServerException $e) {
        if (strpos($e->getMessage(), 'CROSSSLOT') !== false) {
            error("¡CROSSSLOT! No se puede mover entre slots");
            info("Mensaje", $e->getMessage());
        } else {
            echo "Error: " . $e->getMessage() . "\n";
        }
    } catch (\Predis\NotSupportedException $e) {
        error("Predis bloqueó: " . $e->getMessage());
    }
}

// Test 6: RPOPLPUSH con hash tags
section("TEST 6: RPOPLPUSH con Hash Tags");

$source = 'queue:{default}';
$dest = 'queue:{default}:processing';

$slotSource = $strategy->getSlotByKey($source);
$slotDest = $strategy->getSlotByKey($dest);

info("Source", "$source → Slot $slotSource");
info("Dest", "$dest → Slot $slotDest");

if ($slotSource === $slotDest) {
    echo "\n{$GREEN}✓ Ambas listas están en el mismo slot{$NC}\n\n";
    
    $client->del([$source, $dest]);
    $client->rpush($source, ['job1', 'job2', 'job3']);
    
    $job = $client->rpoplpush($source, $dest);
    success("Job movido atómicamente: $job");
    
    $sourceLen = $client->llen($source);
    $destLen = $client->llen($dest);
    
    info("Items en source", $sourceLen);
    info("Items en dest", $destLen);
}

// Test 7: Demo con redis-cli para ver error real
section("TEST 7: Ver CROSSSLOT real con redis-cli");

echo "Para ver el error CROSSSLOT directamente de Redis:\n\n";

$cmd = "docker exec -e SHARDS=\$SHARDS -it redis-lab redis-cli -h redis-node-1 -p 7000 MGET $key1 $key2";
echo "{$CYAN}\$ $cmd{$NC}\n";

// Ejecutar el comando
$output = [];
$returnCode = 0;
exec($cmd . ' 2>&1', $output, $returnCode);

if ($returnCode !== 0 || strpos(implode("\n", $output), 'CROSSSLOT') !== false) {
    error("Error CROSSSLOT confirmado:");
    echo "  " . implode("\n  ", $output) . "\n";
} else {
    echo "  " . implode("\n  ", $output) . "\n";
}

// Test 8: Por qué existe CROSSSLOT
section("TEST 8: ¿Por qué existe CROSSSLOT?");

echo "{$CYAN}La razón fundamental:{$NC}\n\n";

echo "Redis Cluster NO tiene transacciones distribuidas.\n";
echo "Una operación solo puede ejecutarse en UN nodo.\n\n";

echo "Si tuvieras:\n";
echo "  - Key A en Nodo 1\n";
echo "  - Key B en Nodo 2\n\n";

echo "Un MGET tendría que:\n";
echo "  1. Pedir valor de A a Nodo 1\n";
echo "  2. Pedir valor de B a Nodo 2\n";
echo "  3. Combinar resultados\n\n";

echo "Esto NO es atómico y agrega complejidad.\n";
echo "Redis prefiere rechazar la operación.\n\n";

echo "{$GREEN}Solución: Hash Tags{$NC}\n";
echo "Fuerza que las keys vayan al mismo nodo.\n";

section("CONCLUSIONES");

echo "✓ CROSSSLOT ocurre con operaciones multi-key en slots diferentes\n";
echo "✓ Predis protege enviando solo comandos válidos al cluster\n";
echo "✓ Los hash tags fuerzan keys al mismo slot\n";
echo "✓ Laravel usa {default} para evitar CROSSSLOT en colas\n";
echo "✓ Es una limitación de diseño, no un bug\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{$NC}\n";
echo "Si necesitas hacer MGET de 100 keys y todas usan hash tags\n";
echo "diferentes, ¿qué estrategia podrías usar?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-07{$NC}\n";
