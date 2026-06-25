# suites/node/ioredis

Suite pedagogica de Redis Cluster usando ioredis.

## Comandos

Desde el root del repo:

```bash
make up
make scenarios node/ioredis
make test node/ioredis
make test node/ioredis/06-crossslot-error
make lab node/ioredis
```

Los escenarios siguen la misma progresion conceptual que `php/predis`, adaptados a ioredis:

```text
01-slots-basics
02-hash-tags
03-routing
04-moved-redirects
05-readonly-error
06-crossslot-error
06-crossslot-error-raw
07-failover
08-queue-patterns
09-ioredis-worker-simulation
```

## Desarrollo Local Opcional

```bash
nix develop .#ioredis
cd suites/node/ioredis
npm ci
npm test
```

Defaults del cliente:

```env
REDIS_MODE=cluster
REDIS_HOST=redis-node-1
REDIS_PORT=7000
REDIS_SCHEME=tcp
```
