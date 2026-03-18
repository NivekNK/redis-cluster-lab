# Guía de Errores en Redis Cluster

## Índice de Errores

1. [MOVED](#moved)
2. [ASK](#ask)
3. [CROSSSLOT](#crossslot)
4. [READONLY](#readonly)
5. [CLUSTERDOWN](#clusterdown)
6. [TRYAGAIN](#tryagain)

---

## MOVED

### Descripción

El slot de la key ha sido movido permanentemente a otro nodo.

### Mensaje

```
MOVED 12345 192.168.1.2:7001
```

### Significado

- `12345`: El slot de la key
- `192.168.1.2:7001`: El nodo que ahora tiene ese slot

### Cuándo Ocurre

- Después de un resharding de slots
- Después de un failover (master cambió)
- Cuando el cliente se conectó al nodo incorrecto inicialmente

### Solución

**Predis lo maneja automáticamente:**

1. Recibe MOVED
2. Actualiza el mapa de slots
3. Reintenta en el nodo correcto

### Prevención

- Usa `cluster => 'redis'` en Predis
- Mantén los clientes actualizados
- Monitorea redirecciones excesivas

---

## ASK

### Descripción

El slot está en proceso de migración.

### Mensaje

```
ASK 12345 192.168.1.3:7002
```

### Significado

El slot `12345` se está moviendo al nodo `192.168.1.3:7002`.

### Cuándo Ocurre

- Durante un resharding de slots
- Mientras el cluster está reequilibrando datos

### Solución

**Predis lo maneja automáticamente:**

1. Recibe ASK
2. Envía comando `ASKING`
3. Reintenta el comando original

### Diferencia con MOVED

| ASK | MOVED |
|-----|-------|
| Temporal | Permanente |
| Durante migración | Después de migración |
| Requiere ASKING | Actualiza mapa |

---

## CROSSSLOT

### Descripción

Operación multi-key con keys en slots diferentes.

### Mensaje

```
CROSSSLOT Keys in request don't hash to the same slot
```

### Cuándo Ocurre

```php
// ❌ Esto falla si las keys están en slots diferentes
$client->mget(['key1', 'key2', 'key3']);

// ❌ Pipeline con slots diferentes
$client->pipeline(function ($pipe) {
    $pipe->set('key1', '1');  // Slot 100
    $pipe->set('key2', '2');  // Slot 200
});

// ❌ RPOPLPUSH con slots diferentes
$client->rpoplpush('queue:source', 'queue:dest');
```

### Solución

**Usar hash tags:**

```php
// ✓ Todas las keys van al mismo slot
$client->mget(['{user}:profile', '{user}:settings']);

// ✓ Pipeline con mismo hash tag
$client->pipeline(function ($pipe) {
    $pipe->set('{session}:data', '1');
    $pipe->set('{session}:meta', '2');
});

// ✓ RPOPLPUSH con hash tag
$client->rpoplpush('{queue}:pending', '{queue}:processing');
```

### Caso Real: Laravel Queues

Laravel usa `{default}` para todas las keys de una cola:

```
queues:{default}
queues:{default}:reserved
queues:{default}:delayed
queues:{default}:notify
```

---

## READONLY

### Descripción

Intento de escritura en una réplica.

### Mensaje

```
READONLY You can't write against a read only replica.
```

### Cuándo Ocurre

1. **Conexión directa a réplica:**
   ```php
   $client = new Client('tcp://replica:7003');
   $client->set('key', 'value');  // ❌ READONLY
   ```

2. **Endpoint clustercfg resolvió a réplica:**
   ```php
   // Si clustercfg resuelve a una réplica
   $client = new Client([
       'tcp://clustercfg.endpoint:6379'
   ], ['cluster' => 'redis']);
   
   // La conexión inicial puede ser a una réplica
   // Las escrituras fallarán
   ```

### Solución

**Opción 1: Usar endpoint master**

```php
$client = new Client([
    'tcp://master.endpoint:6379'
], ['cluster' => 'redis']);
```

**Opción 2: Múltiples seeds con Predis cluster:**

```php
$client = new Client([
    'tcp://node1:7000',
    'tcp://node2:7001',
    'tcp://node3:7002',
], ['cluster' => 'redis']);
```

### Tu Caso

Cambiaste de `clustercfg` a `master` endpoint porque:
- `clustercfg` puede resolver a cualquier nodo
- `master` solo resuelve a masters

---

## CLUSTERDOWN

### Descripción

El cluster no tiene suficientes nodos para operar.

### Mensaje

```
CLUSTERDOWN The cluster is down
```

### Cuándo Ocurre

- Más de la mitad de los masters están caídos
- Un slot no tiene dueño
- El cluster está en estado de fallo

### Estados del Cluster

```
cluster_state:ok        # Todo bien
cluster_state:fail      # Algo está mal
```

### Solución

1. Verificar nodos:
   ```bash
   redis-cli CLUSTER NODES
   ```

2. Verificar slots:
   ```bash
   redis-cli CLUSTER SLOTS
   ```

3. Recuperar nodos caídos

4. Forzar recuperación (último recurso):
   ```bash
   redis-cli CLUSTER RESET HARD
   ```

---

## TRYAGAIN

### Descripción

El slot está migrando y no está listo para operaciones.

### Mensaje

```
TRYAGAIN Multiple keys request during rehashing of slot
```

### Cuándo Ocurre

- Durante resharding
- El slot está en estado intermedio

### Solución

**Predis reintenta automáticamente.**

Si persiste:
1. Esperar a que termine la migración
2. Reducir la velocidad de resharding

---

## Matriz de Errores y Soluciones

| Error | Causa | Solución | Predis lo Maneja |
|-------|-------|----------|------------------|
| MOVED | Slot movido | Actualizar mapa | ✅ Sí |
| ASK | Migración en progreso | Enviar ASKING | ✅ Sí |
| CROSSSLOT | Keys en slots diferentes | Usar hash tags | ❌ No |
| READONLY | Escribir en réplica | Usar master | ❌ No |
| CLUSTERDOWN | Cluster fallando | Recuperar nodos | ❌ No |
| TRYAGAIN | Slot migrando | Reintentar | ✅ Sí |

---

## Monitoreo de Errores

### Métricas Importantes

```bash
# Contar MOVED por segundo
redis-cli INFO stats | grep moved

# Ver errores de cluster
redis-cli INFO cluster

# Monitorear en tiempo real
redis-cli MONITOR | grep -E "MOVED|ASK|CROSSSLOT|READONLY"
```

### Alertas Recomendadas

- **MOVED > 100/min**: Posible resharding o failover
- **CROSSSLOT > 0**: Revisar uso de hash tags
- **READONLY > 0**: Revisar configuración de endpoints
- **CLUSTERDOWN**: CRÍTICO - Cluster caído

---

## Debugging

### Habilitar Logs en Predis

```php
$client = new Client($nodes, [
    'cluster' => 'redis',
    'exceptions' => true,
]);

// Capturar excepciones
try {
    $client->set('key', 'value');
} catch (\Predis\Response\ServerException $e) {
    echo "Error: " . $e->getMessage();
}
```

### Verificar Slots de Keys

```bash
# Calcular slot de una key
redis-cli CLUSTER KEYSLOT mykey

# Ver en qué nodo está
redis-cli CLUSTER SLOTS | grep -A 2 <slot>
```

### Simular Errores

```bash
# Provocar READONLY
redis-cli -p 7003  # Conectar a réplica
SET foo bar        # Error READONLY

# Provocar CROSSSLOT
redis-cli MGET key1 key2  # Si están en slots diferentes
```
