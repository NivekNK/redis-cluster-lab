# Conceptos Fundamentales de Redis Cluster

## ¿Qué es Redis Cluster?

Redis Cluster es una implementación de Redis que permite distribuir datos entre múltiples nodos, proporcionando:

- **Sharding automático**: Distribución de datos entre nodos
- **Alta disponibilidad**: Failover automático cuando un nodo cae
- **Escalabilidad horizontal**: Agregar más nodos para aumentar capacidad

## Arquitectura Básica

```
┌─────────────────────────────────────────────────────────┐
│                    Redis Cluster                         │
│                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────┐  │
│  │  Master 1    │    │  Master 2    │    │ Master 3 │  │
│  │  Slots 0-5k  │    │  Slots 5k-10k│    │Slots 10k+│  │
│  │  [Primary]   │    │  [Primary]   │    │ [Primary]│  │
│  └──────┬───────┘    └──────┬───────┘    └────┬─────┘  │
│         │                   │                  │        │
│  ┌──────▼───────┐    ┌──────▼───────┐    ┌────▼─────┐  │
│  │  Replica 1   │    │  Replica 2   │    │ Replica 3│  │
│  │  [Backup]    │    │  [Backup]    │    │ [Backup] │  │
│  └──────────────┘    └──────────────┘    └──────────┘  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Slots: El Corazón del Sharding

### ¿Qué son los Slots?

Redis Cluster divide el espacio de keys en **16384 slots** (numerados del 0 al 16383).

```
Slot 0 ────────────────────────────────────────────────────┐
Slot 1 ────────────────────────────────────────────────────┤
Slot 2 ────────────────────────────────────────────────────┤
  ...                                                      ├── 16384 slots
Slot 16382 ────────────────────────────────────────────────┤
Slot 16383 ────────────────────────────────────────────────┘
```

### ¿Cómo se asigna una key a un slot?

Redis usa el algoritmo **CRC16** para calcular el slot:

```php
$slot = crc16($key) % 16384;
```

Ejemplo:
- Key: `"user:123"`
- CRC16: `12345`
- Slot: `12345 % 16384 = 12345`

### Distribución de Slots

Los slots se distribuyen entre los masters:

| Nodo | Rango de Slots | Cantidad |
|------|----------------|----------|
| Master 1 | 0 - 5460 | 5461 slots |
| Master 2 | 5461 - 10922 | 5462 slots |
| Master 3 | 10923 - 16383 | 5461 slots |

## Hash Tags: El Secreto de la Atomicidad

### El Problema

En Redis Cluster, las operaciones multi-key (MGET, pipelines, Lua scripts) requieren que **todas las keys estén en el mismo slot**.

```
❌ MGET key1 key2  # Falla si key1 y key2 están en slots diferentes
```

### La Solución

Los **hash tags** permiten forzar que múltiples keys vayan al mismo slot:

```
✓ MGET {user}:profile {user}:settings  # Ambas keys usan "user" para el hash
```

### Regla del Hash Tag

Solo el contenido entre `{` y `}` se usa para calcular el slot:

| Key | Usado para hash | Slot |
|-----|-----------------|------|
| `user:123` | `user:123` | 12345 |
| `user:{123}` | `123` | 6789 |
| `a{123}b` | `123` | 6789 |
| `a{123}b{456}` | `123` | 6789 (solo el primero) |

## Tipos de Nodos

### Master (Primario)

- Recibe operaciones de escritura
- Es dueño de un rango de slots
- Puede tener múltiples réplicas

### Replica (Secundario)

- Copia de un master
- Solo lectura por defecto
- Se promociona a master si el original falla

## Comunicación entre Nodos

### Cluster Bus

Los nodos se comunican mediante un bus de cluster en puertos especiales:

- Puerto de datos: `7000`
- Puerto de cluster bus: `17000` (puerto de datos + 10000)

### Protocolo de Intercambio

Los nodos intercambian información sobre:
- Estado de los nodos
- Distribución de slots
- Fallos detectados

## Redirecciones

### MOVED

Cuando una key no está en el nodo consultado:

```
CLIENTE → Nodo 1: GET mykey
Nodo 1  → CLIENTE: MOVED 12345 192.168.1.2:7001
CLIENTE → Nodo 2: GET mykey
Nodo 2  → CLIENTE: "value"
```

### ASK

Durante la migración de un slot:

```
CLIENTE → Nodo 1: GET mykey
Nodo 1  → CLIENTE: ASK 12345 192.168.1.3:7002
CLIENTE → Nodo 3: ASKING + GET mykey
Nodo 3  → CLIENTE: "value"
```

## Failover

### Detección de Fallo

1. Las réplicas detectan que el master no responde
2. Basado en `cluster-node-timeout` (default: 15s)
3. Se inicia una elección

### Promoción

1. La réplica con más datos se promociona
2. El cluster actualiza el mapa de slots
3. Los clientes reciben MOVED y actualizan su mapa

## Comparación: Single Instance vs Cluster

| Característica | Single Instance | Cluster |
|----------------|-----------------|---------|
| Sharding | No | Sí |
| Alta disponibilidad | No (sin Sentinel) | Sí |
| Operaciones multi-key | Sin restricciones | Mismo slot |
| Escalabilidad | Vertical | Horizontal |
| Complejidad | Baja | Media |

## Preguntas Frecuentes

### ¿Por qué 16384 slots?

Es un balance entre:
- **Granularidad suficiente**: Permite distribución uniforme
- **Eficiencia de memoria**: El mapa de slots cabe en pocos KB
- **Velocidad de transferencia**: CLUSTER SLOTS es rápido

### ¿Puedo tener más de 16384 slots?

No, es una constante en Redis. Pero 16384 es suficiente para la mayoría de casos.

### ¿Qué pasa si un slot no tiene dueño?

El cluster entra en estado `fail` y rechaza operaciones en ese slot.

### ¿Puedo mover slots entre nodos?

Sí, usando `redis-cli --cluster reshard`.

## Recursos Adicionales

- [Documentación oficial de Redis Cluster](https://redis.io/topics/cluster-spec)
- [Redis Cluster Tutorial](https://redis.io/topics/cluster-tutorial)
