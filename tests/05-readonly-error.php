<?php
/**
 * ESCENARIO 5: Error READONLY
 * ===========================
 * 
 * OBJETIVO: Reproducir y comprender el error READONLY.
 * 
 * CONCEPTOS CLAVE:
 * - Las réplicas son solo lectura por defecto
 * - Si intentas escribir en una réplica, obtienes READONLY
 * - Usar el endpoint master evita esto
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Por qué cambiar de clustercfg a master endpoint solucionó tu problema?
 * (Respuesta: clustercfg puede conectar a cualquier nodo incluyendo réplicas,
 *  master endpoint solo conecta a masters)
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

section("ERROR READONLY");

echo "Este es el error que experimentaste en producción:\n";
echo "  READONLY You can't write against a read only replica.\n\n";

echo "Ocurre cuando intentas escribir en una réplica de Redis.\n";
echo "Las réplicas son solo lectura por diseño.\n\n";

// Test 1: Identificar masters y réplicas
section("TEST 1: Topología del Cluster");

require __DIR__ . '/cluster-config.php';

$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

$strategy = new RedisStrategy();

$nodes = $client->executeRaw(['CLUSTER', 'NODES']);
$nodesLines = explode("\n", trim($nodes));

echo "Nodos del cluster:\n\n";

$masters = [];
$replicas = [];

foreach ($nodesLines as $node) {
    if (empty($node)) continue;
    $parts = explode(' ', $node);
    $id = $parts[0];

    $endpoint = $parts[1];
    $endpoint = explode('@', $endpoint)[0];

    $flags = $parts[2];
    $masterId = $parts[3];

    if (strpos($flags, 'master') !== false) {
        $masters[$id] = $endpoint;
        info("🔴 Master", $endpoint);
    } elseif (strpos($flags, 'slave') !== false) {
        $replicas[$masterId][] = $endpoint;
        info("🔵 Replica", $endpoint . " -> " . substr($masterId, 0, 8));
    }
}

echo "\n";
success("Identificados " . count($masters) . " masters y réplicas asociadas");

// Elegir una key específica para estos tests
$testKey = 'readonly-test-key';
$slot = $strategy->getSlotByKey($testKey);
$correctNodeInfo = $client->getConnection()->getConnectionBySlot($slot)->getParameters();
$masterEndpoint = "{$correctNodeInfo->host}:{$correctNodeInfo->port}";

// Buscar el ID de este master y su réplica
$targetMasterId = null;
foreach ($masters as $id => $ep) {
    if ($ep === $masterEndpoint) {
        $targetMasterId = $id;
        break;
    }
}

$targetReplicaEp = isset($replicas[$targetMasterId]) ? $replicas[$targetMasterId][0] : null;

// Test 2: Conectar a una réplica e intentar escribir
section("TEST 2: Provocar READONLY");

if (!$targetReplicaEp) {
    echo "{$YELLOW}No se encontró réplica para la key seleccionada{$NC}\n";
} else {
    $parts = explode(':', $targetReplicaEp);
    $host = $parts[0];
    $port = $parts[1];
    
    info("Key de prueba", "$testKey (Slot: $slot)");
    info("Conectando a réplica responsable", "$host:$port");
    
    try {
        $replicaClient = new Client("tcp://$host:$port");
        
        // Verificar que es réplica
	$info = $replicaClient->info('replication');
        info("Rol", $info['Replication']['role'] ?? 'unknown');
        
        // Intentar escribir en la réplica
        echo "\nIntentando escribir en la réplica...\n";
        $replicaClient->set($testKey, 'test-value');
        error("¡La escritura funcionó! Esto no debería pasar.");

    } catch (\Predis\Response\ServerException $e) {
        info("Resultado temporal", $e->getMessage());
        
        echo "\n{$CYAN}DIFERENCIA CLAVE: OSS REDIS vs AWS ELASTICACHE{$NC}\n";
        echo "En Redis Open Source (como este laboratorio), si intentas escribir\n";
        echo "en una réplica, Redis te redirige al master devolviendo un error 'MOVED'.\n\n";

        echo "Sin embargo, en {$YELLOW}AWS ElastiCache{$NC}, si te conectas al endpoint de una\n";
        echo "réplica (o si el Configuration Endpoint resuelve a una réplica) e intentas\n";
        echo "escribir, el proxy interno bloquea la escritura directamente y devuelve:\n";
        echo "  {$RED}'READONLY You can't write against a read only replica.'{$NC}\n\n";

        echo "{$GREEN}✓ En ambos casos, la lección es la misma: NO puedes escribir en una réplica.{$NC}\n";
    }
}

// Test 3: Conectar a un master (debería funcionar)
section("TEST 3: Escribir en Master (Funciona)");

$parts = explode(':', $masterEndpoint);
$host = $parts[0];
$port = $parts[1];

info("Key de prueba", "$testKey (Slot: $slot)");
info("Conectando a master responsable", "$host:$port");

try {
    $masterClient = new Client("tcp://$host:$port");
    
    // Verificar que es master
    $info = $masterClient->info('replication');
    info("Rol", $info['Replication']['role'] ?? 'unknown');
    
    // Intentar escribir
    echo "\nIntentando escribir en el master...\n";
    $masterClient->set($testKey, 'test-value');
    
    success("¡Escritura exitosa en el master!");
    
    // Verificar lectura
    $value = $masterClient->get($testKey);
    info("Valor leído", $value);
    
} catch (Exception $e) {
    error("Error inesperado: " . $e->getMessage());
}

// Test 4: Simular el problema de clustercfg
section("TEST 4: Simulando el Problema de clustercfg");

echo "{$CYAN}Hipótesis de lo que pasó en tu sistema:{\$NC}\n\n";

echo "1. Usabas el endpoint clustercfg (Configuration Endpoint)\n";
echo "2. Este endpoint puede resolver a cualquier nodo del cluster\n";
echo "3. Si resolvió a una réplica, tu conexión inicial fue a una réplica\n";
echo "4. Cuando intentaste escribir, obtuviste READONLY\n\n";

echo "{$CYAN}Solución:{\$NC}\n";
echo "Cambiar al endpoint master, que SIEMPRE resuelve a un master.\n\n";

// Test 5: Verificar comportamiento de réplicas
section("TEST 5: Réplicas y Replicación");

echo "Las réplicas sí permiten lecturas (si están configuradas):\n\n";

if ($targetReplicaEp) {
    $parts = explode(':', $targetReplicaEp);
    $host = $parts[0];
    $port = $parts[1];
    
    try {
        $replicaClient = new Client("tcp://$host:$port");
        
        // Primero escribir en master usando el cliente cluster general
        $client->set($testKey, 'valor-desde-master');
        
        // Pequeña pausa para replicación
        usleep(100000); // 100ms
        
        // Leer de réplica
        // Enviar comando READONLY primero localmente en esta conexión
        $replicaClient->executeRaw(['READONLY']);
        $value = $replicaClient->get($testKey);
        
        if ($value === 'valor-desde-master') {
            success("Réplica tiene el valor replicado: $value");
        } else {
            echo "Réplica no tiene el valor aún (replicación asíncrona)\n";
        }
        
    } catch (Exception $e) {
        echo "Nota: " . $e->getMessage() . "\n";
    }
}

// Test 6: Configuración de réplicas
section("TEST 6: Configuración de Réplicas");

echo "Redis permite configurar réplicas de diferentes maneras:\n\n";

echo "{$CYAN}1. Réplica solo lectura (por defecto):{\$NC}\n";
echo "   - Rechaza escrituras\n";
echo "   - Usada para failover y read replicas\n\n";

echo "{$CYAN}2. Réplica con READONLY comando:{\$NC}\n";
echo "   - Cliente puede enviar READONLY\n";
echo "   - Permite lecturas consistentes\n\n";

echo "{$CYAN}3. Réplica con slave-read-only no:{\$NC}\n";
echo "   - Permite escrituras (no recomendado)\n";
echo "   - Las escrituras no se replican de vuelta\n\n";

// Test 7: Mejores prácticas
section("TEST 7: Mejores Prácticas");

echo "{$GREEN}Para evitar READONLY en producción:{\$NC}\n\n";

echo "1. Usa el endpoint master para operaciones de escritura\n";
echo "2. Configura Predis con 'cluster' => 'redis'\n";
echo "3. Monitorea conexiones a réplicas\n";
echo "4. Implementa retry logic para READONLY\n\n";

echo "{$GREEN}Configuración recomendada para Laravel:{\$NC}\n";
echo "  'redis' => [\n";
echo "      'client' => 'predis',\n";
echo "      'clusters' => [\n";
echo "          'default' => [\n";
echo "              'host' => 'master.tu-cluster.cache.amazonaws.com',\n";
echo "              'port' => 6379,\n";
echo "          ],\n";
echo "      ],\n";
echo "  ],\n";

section("CONCLUSIONES");

echo "✓ READONLY ocurre al intentar escribir en una réplica\n";
echo "✓ Las réplicas son solo lectura por diseño\n";
echo "✓ clustercfg puede conectar a cualquier nodo (incluyendo réplicas)\n";
echo "✓ master endpoint solo conecta a masters\n";
echo "✓ Tu solución de usar master endpoint fue correcta\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{\$NC}\n";
echo "Si tienes muchas réplicas y quieres distribuir lecturas,\n";
echo "¿cómo podrías hacerlo sin arriesgarte a escribir en una réplica?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-06{$NC}\n";
