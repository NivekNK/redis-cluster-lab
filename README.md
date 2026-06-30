# Redis Cluster Laboratory

Laboratorio pedagogico para levantar un Redis Cluster local y probar como se comporta cualquier cliente, libreria o framework frente a slots, hash tags, MOVED, READONLY, CROSSSLOT, failover y patrones de colas.

La infraestructura vive en root. Las pruebas viven bajo una convencion extensible:

```text
suites/<language>/<library>/
├── Dockerfile
├── docker-compose.lab.yml
├── scenarios/
│   ├── 01-slots-basics.<ext>
│   ├── 02-hash-tags.<ext>
│   └── ...
└── lib/ or scripts/
```

## Inicio Rapido

```bash
make up
make scenarios
make test <language>/<library>/<scenario>
```

Ejecutar una suite completa:

```bash
make test <language>/<library>
```

Ejecutar todo:

```bash
make test-all
make test-all <language>
make test-all <language>/<library>
```

## Comandos Genericos

Listar lo disponible:

```bash
make scenarios
make scenarios <language>
make scenarios <language>/<library>
```

Instalar dependencias:

```bash
make install <language>/<library>
make install-all
```

Ejecutar escenarios:

```bash
make test <language>/<library>
make test <language>/<library>/<scenario>
make test-all [<language>[/<library>]]
```

Si el lenguaje no existe, se reporta el lenguaje. Si existe el lenguaje pero no la libreria, se reporta la libreria. Si existe la suite pero no el escenario, se muestran los escenarios disponibles.

## Infraestructura

```bash
make generate
make up
make down
make status
make info
make reset
```

`make up` combina:

```text
docker-compose.generated.yml
suites/*/*/docker-compose.lab.yml
```

Puedes exponer públicamente los nodos pasando la variable `IP`:

```bash
make up IP=204.0.123.11
```

Esto configurará `--cluster-announce-ip` y `--cluster-preferred-endpoint-type ip` en cada nodo del cluster para que los clientes externos puedan ser redirigidos de forma transparente a tu IP pública.

Los runners se nombran de forma derivable:

```text
redis-lab-<language>-<library>
```

## Redis

```bash
make shell
make shell-2
make monitor
make monitor-3
make monitor-all
make queues
```

Endpoints:

- Masters por HAProxy: `master.local:6380`
- Discovery por HAProxy: `clustercfg.local:6381`
- Nodo seed dentro de Docker: `redis-node-1:7000`

## Agregar Una Suite

Crear:

```text
suites/<language>/<library>/Dockerfile
suites/<language>/<library>/docker-compose.lab.yml
suites/<language>/<library>/scenarios/01-slots-basics.<ext>
```

El dispatcher soporta por defecto escenarios `.php`, `.mjs`, `.js` y `.sh`. Para otra tecnologia, agrega scripts opcionales:

```text
suites/<language>/<library>/bin/install
suites/<language>/<library>/bin/run-scenario
```

`bin/run-scenario` recibe la ruta relativa del escenario, por ejemplo `scenarios/01-slots-basics.java`.

## Nix Opcional

Docker es el camino principal para ejecutar labs. Nix queda como ayuda para desarrollo local:

```bash
nix develop .#predis
nix develop .#ioredis
nix develop .#all
```

Tambien puedes entrar a una suite directamente:

```bash
cd suites/php/predis && nix develop
cd suites/node/ioredis && nix develop
```
