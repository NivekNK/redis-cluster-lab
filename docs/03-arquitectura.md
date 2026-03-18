# Decisiones Arquitectónicas en Redis Cluster

## Tu Arquitectura Actual

```
┌─────────────────────────────────────────────────────────────┐
│                      Tu Sistema                              │
│                                                              │
│  ┌──────────────┐         ┌──────────────────────────────┐  │
│  │   Laravel    │────────▶│  AWS ElastiCache Redis       │  │
│  │   Workers    │         │                              │  │
│  │              │         │  ┌────────────────────────┐  │  │
│  └──────────────┘         │  │  Master (7000)         │  │  │
│                           │  │  - Slots 0-16383       │  │  │
│  Configuración:           │  │  - Todos los datos     │  │  │
│  - Endpoint: master       │  └────────────────────────┘  │  │
│  - Prefix: {api-tee}      │              │               │  │
│  - Cluster: redis         │  ┌───────────▼───────────┐  │  │
│                           │  │  Replica (7001)       │  │  │
│                           │  │  - Solo lectura       │  │  │
│                           │  │  - Failover           │  │  │
│                           │  └───────────────────────┘  │  │
│                           │                              │  │
│                           └──────────────────────────────┘  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Decisiones Clave

### 1. Endpoint: master vs clustercfg

| Aspecto | clustercfg | master |
|---------|------------|--------|
| Resuelve a | Cualquier nodo | Solo masters |
| Uso principal | Descubrimiento | Operaciones |
| Riesgo READONLY | Alto | Ninguno |
| Routing por slots | Sí | No (con 1 shard) |

**Tu decisión:** Usar `master` endpoint ✅

**Razón:** Evitar errores READONLY en workers.

### 2. Prefix: {api-tee}

**Efecto:** Todas las keys van al mismo slot.

```
api-tee_queues:{default}        → Slot X
api-tee_queues:{default}:reserved → Slot X
api-tee_cache:data              → Slot X
api-tee_session:abc             → Slot X
```

**Ventajas:**
- ✅ Operaciones atómicas garantizadas
- ✅ No hay CROSSSLOT
- ✅ Lua scripts funcionan siempre

**Desventajas:**
- ❌ No hay sharding horizontal
- ❌ Todo el tráfico va a un nodo
- ❌ No escala con más shards

### 3. Cluster Mode: redis vs predis

```php
// Opción 1: Client-side sharding (legacy)
'cluster' => 'predis'

// Opción 2: Protocolo nativo Redis Cluster (recomendado)
'cluster' => 'redis'
```

**Tu configuración:** `'cluster' => 'redis'` ✅

## Comparativa de Arquitecturas

### Opción A: Tu Configuración Actual

```php
'redis' => [
    'client' => 'predis',
    'clusters' => [
        'default' => [
            'host' => 'master.xxx.cache.amazonaws.com',
            'port' => 6379,
            'parameters' => [
                'prefix' => '{api-tee}',
            ],
        ],
    ],
],
```

**Características:**
- 1 shard con réplica
- Todo en un slot
- Failover automático
- No escala horizontalmente

**Para:** Sistemas medianos, simplicidad operativa

### Opción B: Multi-Shard Real

```php
'redis' => [
    'client' => 'predis',
    'clusters' => [
        'default' => [
            'host' => 'clustercfg.xxx.cache.amazonaws.com',
            'port' => 6379,
        ],
    ],
],

// En código: diferentes hash tags por funcionalidad
$cache->set('{cache}:user:123', $data);
$queue->push('{queue}:emails', $job);
$session->set('{session}:abc', $data);
```

**Características:**
- Múltiples shards
- Distribución real de carga
- Más complejo de operar
- Requiere diseño de hash tags

**Para:** Sistemas grandes, alta escala

### Opción C: Redis + SQS Híbrido

```php
// Colas críticas → SQS
$sqs->sendMessage([
    'QueueUrl' => $paymentsQueue,
    'MessageBody' => json_encode($payment),
]);

// Cache, rate limit, locks → Redis
$redis->set('{cache}:user:123', $data, 'EX', 3600);
$redis->incr('{ratelimit}:api:ip:1.2.3.4');
```

**Características:**
- Colas: SQS (fiabilidad, escalabilidad)
- Cache: Redis (velocidad)
- Mejor de ambos mundos
- Más costo operativo

**Para:** Sistemas de pagos, alta fiabilidad

## Trade-offs

### Atomicidad vs Escalabilidad

```
┌─────────────────────────────────────────────────────────┐
│                                                         │
│   Atomicidad ◄────────────────────────────► Escalabilidad│
│                                                         │
│   {api-tee} prefix              Hash tags específicos   │
│   └── Todo en 1 slot            └── Distribuido         │
│                                                         │
│   ✓ Operaciones atómicas      ✓ Carga distribuida      │
│   ✓ Simple                    ✓ Escalable              │
│   ✗ No escala                 ✗ Más complejo           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Tu Sistema en la Curva

```
Tráfico
   ▲
   │              ┌─────────────┐
   │              │  Multi-Shard │
   │         ┌────┤  con SQS    │
   │    ┌────┘    └─────────────┘
   │    │    Tu Sistema Actual
   │────┼─────────────────────────
   │    │    (1 shard, {api-tee})
   │    │
   │    │
   └────┴──────────────────────────► Tiempo
        Ahora   Futuro
```

## Recomendaciones por Escenario

### Escenario 1: Sistema Pequeño (< 10K ops/seg)

**Recomendación:** Tu configuración actual ✅

- 1 shard con réplica
- Prefix {api-tee}
- Master endpoint

### Escenario 2: Sistema Mediano (10K-50K ops/seg)

**Recomendación:** Multi-shard con hash tags

```php
// Diferentes hash tags por funcionalidad
'{cache}:data'     // Cache distribuido
'{queue}:default'  // Cola específica
'{session}:user'   // Sesiones
```

### Escenario 3: Sistema Grande (> 50K ops/seg)

**Recomendación:** Redis + SQS híbrido

- SQS para colas críticas
- Redis para cache y rate limiting
- Considerar Redis Streams

### Escenario 4: Sistema de Pagos (cualquier tamaño)

**Recomendación:** SQS para colas

- Fiabilidad > Latencia
- Dead letter queues
- Retries nativos
- Observabilidad

## Métricas para Decidir

### Cuándo Escalar

| Métrica | Umbral | Acción |
|---------|--------|--------|
| CPU Redis | > 70% | Considerar más shards |
| Memoria | > 80% | Aumentar tamaño o sharding |
| Latencia p99 | > 10ms | Revisar arquitectura |
| Errores | > 0.1% | Investigar causas |

### Cuándo Migrar a SQS

- Jobs críticos que no pueden perderse
- Necesitas dead letter queues
- Múltiples consumers complejos
- Requieres observabilidad avanzada

## Conclusión

Tu arquitectura actual es **correcta para tu escala**:

- ✅ Simplicidad operativa
- ✅ Atomicidad garantizada
- ✅ Failover automático
- ✅ Sin CROSSSLOT

**Para escalar en el futuro:**

1. **Opción conservadora:** Múltiples colas con diferentes hash tags
2. **Opción agresiva:** SQS para colas, Redis para cache
3. **Opción híbrida:** Redis Streams para colas complejas

La clave es que ahora **entiendes las implicaciones** de cada decisión.
