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

## 🐘 Guía para implementar Redis Cluster en Laravel

Si quieres utilizar un clúster de Redis desde tu propia aplicación Laravel, sigue estas importantes reglas y configuraciones:

### 1. Variables de Entorno (`.env`)

- **Cola con Hash Tags:** Tu variable `REDIS_QUEUE` (o la que uses para nombrar la cola) **sí o sí debe tener corchetes**. Esto garantiza que todos los metadatos de la cola se dirijan al mismo hash slot (evitando el error `CROSSSLOT`).
  ```env
  REDIS_QUEUE="{default}"
  ```
- **Punto de conexión:** `REDIS_HOST` se debe configurar apuntando al Configuration Endpoint (por ejemplo, en AWS ElastiCache) o al entrypoint del cluster, **no a un nodo master directamente** para que pueda descubrir el resto de los nodos automáticamente.
- **Prefijo:** El `REDIS_PREFIX` debe quedar vacío (`""`) o utilizar un prefijo que *no* tenga corchetes, para evitar que interfiera con los hash tags de las colas.

### 2. Configuración en `config/database.php`

En Laravel, es fundamental indicar en tu configuración que estás utilizando un clúster de Redis. Asegúrate de tener configurado `'client' => env('REDIS_CLIENT', 'predis')` y de especificar la opción `'cluster'` dentro del bloque `options`:

```php
    'redis' => [
        'client' => env('REDIS_CLIENT', 'predis'),

        'options' => [
            'cluster' => env('REDIS_CLUSTER', 'redis'),
            'prefix' => env('REDIS_PREFIX', ''),
            'parameters' => [
                'scheme'   => env('REDIS_SCHEME', 'tcp'),
                'username' => env('REDIS_USERNAME', null),
                'password' => env('REDIS_PASSWORD', null),
            ],
            'ssl' => [
                'verify_peer' => env('REDIS_SSL_VERIFY', false),
            ]
        ],

        // Configuración en modo clúster
        'clusters' => (env('REDIS_CLUSTER') == 'redis') ? [
            'default' => [
                [
                    'host'     => env('REDIS_HOST', '127.0.0.1'),
                    'port'     => env('REDIS_PORT', '6379'),
                    'database' => env('REDIS_DB', '0'),
                    'scheme'   => env('REDIS_SCHEME', 'tcp'),
                    'password' => env('REDIS_PASSWORD', null),
                    'username' => env('REDIS_USERNAME', null),
                ],
            ],
            'cache' => [
                [
                    'host'     => env('REDIS_HOST', '127.0.0.1'),
                    'port'     => env('REDIS_PORT', '6379'),
                    'database' => env('REDIS_DB', '0'),
                    'scheme'   => env('REDIS_SCHEME', 'tcp'),
                    'password' => env('REDIS_PASSWORD', null),
                    'username' => env('REDIS_USERNAME', null),
                ],
            ],
            'queue' => [
                [
                    'host'     => env('REDIS_QUEUE_HOST', env('REDIS_HOST', '127.0.0.1')),
                    'port'     => env('REDIS_PORT', '6379'),
                    'database' => env('REDIS_DB', '0'),
                    'scheme'   => env('REDIS_SCHEME', 'tcp'),
                    'password' => env('REDIS_PASSWORD', null),
                    'username' => env('REDIS_USERNAME', null),
                ],
            ],
        ] : null,
    ],
```

### 3. Prueba rápida usando Tinker

Para interactuar con la Caché y enviar tu primer valor al Clúster:
```bash
# Ingresar valores a la caché general
> Cache::store()->put('TESTING', 'value');

# Obtenerlos para verificar que existan
> Cache::store('redis')->get('TESTING');
```

**Verificando en el clúster con `redis-cli`:**
```bash
# Conectarte con soporte de redirecciones de clúster (-c)
make shell

# Luego ejecutar:
127.0.0.1:7000> GET TESTING
# (Nota: Es muy probable que Laravel le agregue automáticamente el prefijo "laravel_cache_" 
# a las llaves de caché. Si GET TESTING devuelve nulo, intenta con: GET laravel_cache_:TESTING)
```

### 4. Uso de Colas (Jobs) en Redis Cluster

Si usas el driver de colas de Redis, para mandar trabajos asegúrate de especificar la conexión a redis:
```php
Bus::dispatch((new App\Jobs\TestRedisJob())->onConnection('redis'));
```

**Ejemplos de Jobs (`App\Jobs\TestRedisJob` y `App\Jobs\DummyJob`):**

```php
<?php
namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;

class TestRedisJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function handle()
    {
        Log::info('¡El TestRedisJob se ejecutó correctamente desde la cola!');
    }
}
```

```php
<?php
namespace App\Jobs;

use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Storage;

class DummyJob implements ShouldQueue 
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    protected string $identificador;

    public function __construct(string $identificador = 'Anonimo')
    {
        $this->identificador = $identificador;
    }

     public function handle(): void
     {
        Log::info("Contexto de Laboratorio - Job ejecutado exitosamente para: {$this->identificador}");

        $contenido = "Registro de Laboratorio\n" . "Estado: Completado\n" . "Sujeto: {$this->identificador}\n" . "Timestamp: " . now()->toDateTimeString();

        Storage::disk('local')->put("resultado_job_{$this->identificador}.txt", $contenido);
    }
}
```

### 5. Verificando las colas en el Clúster

Con el clúster activo, puedes usar el comando integrado `make queues` que rastreará todos los nodos maestros y sus réplicas, indicándote visualmente en qué nodo se encuentran las llaves de tus trabajos (garantizando que el Hash Tag `{default}` las agrupa todas en un mismo nodo maestro):

```bash
make queues
🔍 Escaneando colas en el cluster Redis...

📦 Colas encontradas por nodo:
--------------------------------------------------------
[MASTER] redis-node-2
  ↳ queues:{default}:notify
  ↳ queues:{default}

✅ Escaneo completado.
```
*Puedes ver cómo las colas respetan el Hash Tag para mantenerse en un solo slot.*

### 6. Ejecutar los trabajos

Por último, simplemente enciende tu worker como de costumbre especificando la cola con corchetes (si no es la por defecto):
```bash
php artisan queue:work --queue {default}
```

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
