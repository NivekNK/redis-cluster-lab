#!/usr/bin/env php
<?php

declare(strict_types=1);

$root = dirname(__DIR__);
$scenarioDir = $root . DIRECTORY_SEPARATOR . 'scenarios';

function scenario_sort_key(string $file): array
{
    $basename = preg_replace('/\.[^.]+$/', '', $file);

    if (!is_string($basename) || !preg_match('/^(\d+)-(.+)$/', $basename, $matches)) {
        return [PHP_INT_MAX, 0, $basename ?: $file];
    }

    $name = $matches[2];

    return [(int) $matches[1], substr_count($name, '-') + 1, $name];
}

function compare_scenarios(string $left, string $right): int
{
    $leftKey = scenario_sort_key($left);
    $rightKey = scenario_sort_key($right);

    return ($leftKey[0] <=> $rightKey[0])
        ?: ($leftKey[1] <=> $rightKey[1])
        ?: strcmp($leftKey[2], $rightKey[2]);
}

$files = scandir($scenarioDir);

if ($files === false) {
    fwrite(STDERR, "No se pudo leer el directorio de escenarios: {$scenarioDir}\n");
    exit(1);
}

$scenarios = array_values(array_filter(
    $files,
    static fn (string $file): bool => preg_match('/^[0-9][0-9].*\.php$/', $file) === 1
));

usort($scenarios, 'compare_scenarios');

if (!chdir($root)) {
    fwrite(STDERR, "No se pudo entrar a la suite: {$root}\n");
    exit(1);
}

$failed = 0;

foreach ($scenarios as $scenario) {
    echo "\n>>> {$scenario}\n";

    $command = escapeshellarg(PHP_BINARY) . ' ' . escapeshellarg('scenarios/' . $scenario);
    $status = 0;

    passthru($command, $status);

    if ($status !== 0) {
        $failed++;
    }
}

exit($failed > 0 ? 1 : 0);
