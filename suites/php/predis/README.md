# suites/php/predis

Suite pedagogica de Redis Cluster usando Predis.

## Comandos

Desde el root del repo:

```bash
make up
make scenarios php/predis
make test php/predis
make test php/predis/01-slots-basics
make lab php/predis
```

Los escenarios viven en `scenarios/` y se ejecutan por numero de escenario, dejando variantes como `-raw` despues del escenario base.
El runner local de la suite es `scripts/run-all.php`.

## Desarrollo Local Opcional

```bash
nix develop .#predis
cd suites/php/predis
composer install
composer test
php scenarios/01-slots-basics.php
```

Para ejecutar localmente sin Docker, el cluster debe estar activo y los hosts `redis-node-N` deben resolver desde la maquina host.
