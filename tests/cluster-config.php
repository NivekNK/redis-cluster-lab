<?php
/**
 * Configuración dinámica del cluster Redis.
 * Genera la lista de nodos según la variable de entorno SHARDS.
 *
 * Uso en tests:
 *   require __DIR__ . '/cluster-config.php';
 *   $client = new Client(clusterNodes(), ['cluster' => 'redis']);
 */

/**
 * Retorna un array de URIs tcp:// para todos los masters del cluster.
 * Se basa en la variable de entorno SHARDS (default: 3).
 */
function clusterNodes(): array
{
    $shards = (int) (getenv('SHARDS') ?: 3);
    $nodes = [];

    for ($i = 1; $i <= $shards; $i++) {
        $port = 6999 + $i;
        $nodes[] = "tcp://redis-node-{$i}:{$port}";
    }

    return $nodes;
}

/**
 * Retorna el total de nodos (masters + replicas).
 */
function totalNodes(): int
{
    $shards = (int) (getenv('SHARDS') ?: 3);
    return $shards * 2;
}

/**
 * Retorna la cantidad de shards (masters).
 */
function shardCount(): int
{
    return (int) (getenv('SHARDS') ?: 3);
}

/**
 * Retorna un mapa port => host para todos los masters.
 */
function masterNodeMap(): array
{
    $shards = shardCount();
    $map = [];

    for ($i = 1; $i <= $shards; $i++) {
        $port = (string)(6999 + $i);
        $map[$port] = "redis-node-{$i}";
    }

    return $map;
}
