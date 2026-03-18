# 🧪 Redis Cluster Laboratory

> Laboratorio pedagógico interactivo para comprender Redis Cluster, Predis y los desafíos de arquitectura distribuida.

## 📚 ¿Qué aprenderás?

Este laboratorio te guiará paso a paso para comprender:

1. **Slots y Sharding** - Cómo Redis distribuye datos
2. **Hash Tags `{}`** - El secreto para operaciones atómicas
3. **MOVED y ASK** - Redirecciones en cluster
4. **READONLY** - Por qué ocurre y cómo evitarlo
5. **CROSSSLOT** - Por qué tus colas fallan
6. **Failover** - Qué pasa cuando un nodo cae, simulación y recuperación automática

## 🚀 Inicio Rápido

```bash
# 1. Clonar o descomprimir el laboratorio
cd redis-cluster-lab

# 2. Iniciar el cluster (por defecto 3 shards: 3 masters + 3 replicas)
make up

# 3. Iniciar con más shards (ej: 5 masters + 5 replicas)
make up SHARDS=5

# 4. Verificar que todo funciona
make test

# 5. Explorar los escenarios
make scenarios
```

## ⚙️ Configuración de Shards

La cantidad de shards (masters) se configura con la variable `SHARDS`:

```bash
# 3 shards (default): 3 masters + 3 replicas = 6 nodos
make up

# 5 shards: 5 masters + 5 replicas = 10 nodos
make up SHARDS=5
```

Cada shard crea:
- **1 nodo Master** (puertos 7000, 7001, ...)
- **1 nodo Replica** (puertos siguientes)
- **HAProxy** en puertos `6380` (masters) y `6381` (discovery)

> **Nota:** Los archivos `docker-compose.generated.yml` y `haproxy.generated.cfg` se generan automáticamente. No los edites manualmente.
>
> 🪟 **Usuarios de Windows:** El laboratorio es **100% compatible** con Windows de forma nativa. Si ejecutas `make up` desde PowerShell CMD, se detectará automáticamente tu sistema y se invocarán `.ps1` auto-generadores integrados.

## 📁 Estructura del Proyecto

```
redis-cluster-lab/
├── README.md                 # Este archivo
├── Makefile                  # Comandos simplificados
├── docker-compose.yml        # Compose de referencia (estático)
├── composer.json             # Dependencias PHP
├── haproxy.cfg               # Config HAProxy de referencia
│
├── scripts/                  # Scripts de utilidad
│   ├── setup.sh             # Setup inicial
│   ├── generate-compose.sh  # Genera docker-compose dinámico
│   ├── generate-haproxy.sh  # Genera haproxy.cfg dinámico
│   ├── cluster-init.sh      # Inicializa el cluster
│   ├── cluster-status.sh    # Estado del cluster
│   └── reset.sh             # Limpia todo
│
├── tests/                    # Tests pedagógicos
│   ├── 01-slots-basics.php          # Fundamentos de slots
│   ├── 02-hash-tags.php             # Hash tags explicados
│   ├── 03-routing.php               # Cómo Predis enruta
│   ├── 04-moved-redirects.php       # Redirecciones MOVED
│   ├── 05-readonly-error.php        # Error READONLY
│   ├── 06-crossslot-error.php       # Error CROSSSLOT
│   ├── 07-failover.php              # Simulación de failover
│   ├── 08-queue-patterns.php        # Patrones de colas
│   └── 09-laravel-simulation.php    # Simula Laravel Horizon
│
├── docs/                     # Documentación
│   ├── 01-conceptos.md      # Conceptos fundamentales
│   ├── 02-errores.md        # Guía de errores
│   └── 03-arquitectura.md   # Decisiones arquitectónicas
│
└── Archivos generados (en .gitignore):
    ├── docker-compose.generated.yml  # Compose dinámico
    └── haproxy.generated.cfg         # HAProxy dinámico
```

## 🎮 Comandos Make

| Comando | Descripción |
|---------|-------------|
| `make help` | Muestra la ayuda con todos los comandos |
| `make up` | Inicia el cluster Redis (default: 3 shards) |
| `make up SHARDS=N` | Inicia el cluster con N shards (mínimo: 3) |
| `make down` | Detiene el cluster, HAProxy y restaura `/etc/hosts` |
| `make status` | Muestra estado del cluster |
| `make generate SHARDS=N` | Solo genera los archivos de configuración |
| `make test` | Ejecuta todos los tests |
| `make scenarios` | Muestra escenarios disponibles |
| `make scenario-NN` | Ejecuta un escenario específico (ej: `make scenario-01`) |
| `make lab` | Entra a la consola interactiva bash de `redis-lab` (Contenedor PHP PHP 8.2 cli) ideal para testear comandos aislados |
| `make shell` | Accede a redis-node-1 via redis-cli (ejecutado por docker exec) |
| `make shell-N` | Accede al nodo N (ej: `make shell-2`) |
| `make monitor` | Monitorea comandos en tiempo real (nodo 1) |
| `make monitor-N` | Monitorea un nodo específico (ej: `make monitor-3`) |
| `make monitor-all` | TTY Multiventana monitoreando TODOS los nodos simultáneamente |
| `make reset SHARDS=N` | Limpia todo y reinicia con N shards |
| `make logs` | Muestra logs de todos los nodos |
| `make logs-N` | Muestra logs de un nodo específico (ej: `make logs-2`) |
| `make install` | Instala dependencias PHP localmente (Solo si deseas ejecutar tests locales sin usar docker) |
| `make setup` | Ejecuta el setup inicial completo |
| `make info` | Muestra slots y nodos del cluster |

## 🎯 Escenarios Disponibles

### Escenario 1: Slots y Hash Tags
```bash
make scenario-01
```
Aprende cómo Redis calcula slots y por qué los hash tags son críticos.

### Escenario 2: Error READONLY
```bash
make scenario-05
```
Reproduce y comprende el error que te llevó a cambiar de `clustercfg` a `master`.

### Escenario 3: Failover
```bash
make scenario-07
```
Simula la caída de un master y observa cómo el cluster se recupera.

### Escenario 4: Colas Laravel
```bash
make scenario-09
```
Comprende por qué Laravel usa `{default}` en las colas.

## 📖 Documentación

- [Conceptos Fundamentales](docs/01-conceptos.md)
- [Guía de Errores](docs/02-errores.md)
- [Decisiones Arquitectónicas](docs/03-arquitectura.md)

## 🔧 Requisitos

- Docker y Docker Compose
- **No se requiere Node.js, PHP ni `redis-cli` en tu máquina anfitriona** (TODO corre en sus propios Dockers de forma transparente para las directivas interactivas - `make shell`, `monitor`, `lab`, etc).
- Make (opcional, para comandos simplificados)
- (Windows) Si te encuentras en ambiente Windows, los comandos `make` levantarán las implementaciones `.ps1` en PowerShell integradas.

## 📝 Licencia

Laboratorio educativo para comprender Redis Cluster.
