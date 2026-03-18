#!/usr/bin/env php
<?php
/**
 * Script para ejecutar todos los tests del laboratorio
 */

$BLUE = "\033[34m";
$GREEN = "\033[32m";
$YELLOW = "\033[33m";
$RED = "\033[31m";
$CYAN = "\033[36m";
$NC = "\033[0m";

echo "{$BLUE}╔═══════════════════════════════════════════════════════════╗{$NC}\n";
echo "{$BLUE}║         Redis Cluster Laboratory - Test Runner            ║{$NC}\n";
echo "{$BLUE}╚═══════════════════════════════════════════════════════════╝{$NC}\n\n";

$tests = [
    '01-slots-basics.php' => 'Fundamentos de Slots',
    '02-hash-tags.php' => 'Hash Tags',
    '03-routing.php' => 'Routing de Predis',
    '04-moved-redirects.php' => 'Redirecciones MOVED',
    '05-readonly-error.php' => 'Error READONLY',
    '06-crossslot-error.php' => 'Error CROSSSLOT',
    '07-failover.php' => 'Failover',
    '08-queue-patterns.php' => 'Patrones de Colas',
    '09-laravel-simulation.php' => 'Simulación Laravel',
];

$passed = 0;
$failed = 0;

foreach ($tests as $file => $name) {
    $filepath = __DIR__ . '/' . $file;
    
    if (!file_exists($filepath)) {
        echo "{$RED}✗{$NC} $name - Archivo no encontrado\n";
        $failed++;
        continue;
    }
    
    echo "{$YELLOW}▶{$NC} Ejecutando: {$CYAN}$name{$NC}\n";
    echo str_repeat('-', 50) . "\n";
    
    $output = [];
    $returnCode = 0;
    exec("php $filepath 2>&1", $output, $returnCode);
    
    echo implode("\n", $output) . "\n";
    
    if ($returnCode === 0) {
        echo "{$GREEN}✓{$NC} $name completado\n\n";
        $passed++;
    } else {
        echo "{$RED}✗{$NC} $name falló (código: $returnCode)\n\n";
        $failed++;
    }
}

echo "{$BLUE}═══════════════════════════════════════════════════════════{$NC}\n";
echo "{$GREEN}✓{$NC} Tests pasados: $passed\n";
if ($failed > 0) {
    echo "{$RED}✗{$NC} Tests fallidos: $failed\n";
}
echo "{$BLUE}═══════════════════════════════════════════════════════════{$NC}\n";

exit($failed > 0 ? 1 : 0);
