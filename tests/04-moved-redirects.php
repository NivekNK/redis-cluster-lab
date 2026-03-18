<?php
/**
 * ESCENARIO 4: Redirecciones MOVED
 * ================================
 * 
 * OBJETIVO: Comprender qué es MOVED y cómo Predis lo maneja.
 * 
 * CONCEPTOS CLAVE:
 * - MOVED significa: "esta key no está en este nodo, ve a este otro"
 * - Ocurre cuando el mapa del cliente está desactualizado
 * - Predis actualiza automáticamente su mapa al recibir MOVED
 * 
 * PREGUNTA DE REFLEXIÓN:
 * ¿Cuándo ocurre MOVED en producción?
 * (Respuesta: Después de resharding, failover, o si el cliente
 *  se conectó inicialmente a un nodo diferente)
 */

require __DIR__ . '/../vendor/autoload.php';

use Predis\Client;
use Predis\Cluster\RedisStrategy;

$BLUE = "\033[34m";
$GREEN = "\033[32m";
$YELLOW = "\033[33m";
$CYAN = "\033[36m";
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

function warning($msg) {
    global $YELLOW, $NC;
    echo "{$YELLOW}⚠ {$msg}{$NC}\n";
}

require __DIR__ . '/cluster-config.php';

// Conectar al cluster
$client = new Client(clusterNodes(), [
    'cluster' => 'redis'
]);

$strategy = new RedisStrategy();

section("REDIRECCIONES MOVED");

echo "MOVED es la forma que tiene Redis de decir:\n";
echo "  'Esta key no está aquí, ve a este otro nodo'\n\n";
echo "Predis maneja MOVED automáticamente actualizando su mapa.\n\n";

// Test 1: Simular MOVED manualmente conectándose al nodo incorrecto
section("TEST 1: Provocar MOVED Manualmente");

echo "Vamos a conectarnos directamente a un nodo específico\n";
echo "y pedirle una key que no le corresponde.\n\n";

// Elegir una key y ver su slot
$key = 'test-moved-key';
$slot = $strategy->getSlotByKey($key);
info("Key de prueba", $key);
info("Slot calculado", $slot);

// Encontrar qué nodo debería tener esta key
$correctNode = $client->getConnection()->getConnectionBySlot($slot);
$correctParams = $correctNode->getParameters();
info("Nodo correcto", $correctParams->host . ":" . $correctParams->port);

// Intentar conectar a un nodo diferente y pedir la key
$wrongPort = ($correctParams->port == '7000') ? '7001' : '7000';
$wrongHost = ($correctParams->port == '7000') ? 'redis-node-2' : 'redis-node-1';
info("Nodo incorrecto", "$wrongHost:$wrongPort");

echo "\nConectando al nodo incorrecto y pidiendo la key...\n";

try {
    $wrongClient = new Client("tcp://$wrongHost:$wrongPort");
    $result = $wrongClient->get($key);
    echo "Resultado: $result\n";
    
    // Si llegamos aquí, el nodo redirigió o la key no existe
    success("El nodo respondió (posiblemente redirigió internamente)");
    
} catch (\Predis\Response\ServerException $e) {
    if (strpos($e->getMessage(), 'MOVED') !== false) {
        warning("¡Recibimos MOVED!");
        info("Respuesta", $e->getMessage());
        
        // Extraer información del error MOVED
        preg_match('/MOVED (\d+) ([^:]+):(\d+)/', $e->getMessage(), $matches);
        if ($matches) {
            info("Slot en MOVED", $matches[1]);
            info("Nodo correcto", $matches[2] . ":" . $matches[3]);
        }
    } else {
        echo "Error diferente: " . $e->getMessage() . "\n";
    }
}

// Test 2: Cómo Predis maneja MOVED
section("TEST 2: Predis Maneja MOVED Automáticamente");

echo "Cuando usas el cliente cluster de Predis, MOVED se maneja\n";
echo "automáticamente sin que la aplicación lo note.\n\n";

// Guardar una key
$testKey = 'moved-test-' . uniqid();
$client->set($testKey, 'valor-prueba');

// Recuperarla (Predis enruta correctamente)
$value = $client->get($testKey);
success("Key guardada y recuperada: $value");

echo "\n{$CYAN}¿Qué pasó detrás de escenas?{$NC}\n";
echo "  1. Predis calculó el slot de '$testKey'\n";
echo "  2. Consultó su mapa para encontrar el nodo\n";
echo "  3. Envió el comando al nodo correcto\n";
echo "  4. Si el nodo respondiera MOVED, Predis actualizaría el mapa\n";
echo "     y reintentaría automáticamente\n";

// Test 3: CLUSTER SLOTS vs mapa interno
section("TEST 3: Mapa Interno de Predis");

echo "Predis descarga el mapa de slots al iniciar:\n\n";

$slots = $client->executeRaw(['CLUSTER', 'SLOTS']);

echo "Rangos de slots:\n";
foreach ($slots as $range) {
    $start = $range[0];
    $end = $range[1];
    $master = $range[2];
    info("Slots $start-$end", $master[0] . ":" . $master[1]);
}

echo "\n{$CYAN}Predis mantiene este mapa en memoria para enrutar comandos.{\$NC}\n";

// Test 4: Simular cambio de topología
section("TEST 4: Simular Cambio de Topología");

echo "En producción, la topología cambia cuando:\n";
echo "  - Un master falla y una replica toma su lugar\n";
echo "  - Se hace resharding de slots\n";
echo "  - Se agregan o eliminan nodos\n\n";

echo "{$YELLOW}Para simular esto, necesitaríamos hacer failover manual.{\$NC}\n";
echo "Lo haremos en el escenario 7 (make scenario-07).\n";

// Test 5: MOVED vs ASK
section("TEST 5: MOVED vs ASK");

echo "Hay dos tipos de redirecciones:\n\n";

echo "{$CYAN}MOVED{$NC}:\n";
echo "  - El slot ha sido permanentemente movido a otro nodo\n";
echo "  - El cliente debe actualizar su mapa\n";
echo "  - Predis lo maneja automáticamente\n\n";

echo "{$CYAN}ASK{$NC}:\n";
echo "  - El slot está en proceso de migración\n";
echo "  - El cliente debe enviar ASKING antes del comando\n";
echo "  - Es temporal, durante resharding\n\n";

// Test 6: Rendimiento de redirecciones
section("TEST 6: Impacto de Redirecciones");

echo "Las redirecciones tienen un costo de rendimiento:\n\n";

echo "  1. RTT adicional para el reintento\n";
echo "  2. Actualización del mapa de slots\n";
echo "  3. Posible reconexión a otro nodo\n\n";

echo "{$GREEN}Predis optimiza esto cacheando el mapa y actualizándolo\n";
echo "solo cuando es necesario (lazy update).{\$NC}\n";

// Test 7: Verificar comportamiento real
section("TEST 7: Verificación de Comportamiento");

echo "Vamos a verificar que Predis enruta correctamente:\n\n";

// Crear varias keys y verificar que van al nodo correcto
$keys = [];
for ($i = 0; $i < 10; $i++) {
    $key = "verify-$i";
    $client->set($key, "value-$i");
    $keys[] = $key;
}

$allOk = true;
foreach ($keys as $key) {
    $expected = "value-" . explode('-', $key)[1];
    $actual = $client->get($key);
    
    if ($expected !== $actual) {
        echo "{$RED}✗ Error en $key: esperado '$expected', obtenido '$actual'{$NC}\n";
        $allOk = false;
    }
}

if ($allOk) {
    success("Todas las keys fueron enrutadas correctamente");
}

section("CONCLUSIONES");

echo "✓ MOVED indica que una key está en otro nodo\n";
echo "✓ Predis maneja MOVED automáticamente\n";
echo "✓ El cliente actualiza su mapa de slots cuando recibe MOVED\n";
echo "✓ ASK es similar pero para migraciones temporales\n";
echo "✓ Las redirecciones tienen costo de rendimiento\n";

echo "\n{$YELLOW}PREGUNTA PARA REFLEXIONAR:{\$NC}\n";
echo "Si tu aplicación empieza a ver muchos errores MOVED,\n";
echo "¿qué podría estar pasando en el cluster?\n";

echo "\n{$GREEN}Próximo escenario: make scenario-05{$NC}\n";
