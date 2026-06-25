/**
 * ESCENARIO 9: Simulacion de Worker Node con ioredis
 * ==================================================
 *
 * OBJETIVO: Simular como un worker Node puede usar ioredis con Redis Cluster.
 *
 * CONCEPTOS CLAVE:
 * - Un worker de colas usa multiples keys: queue, reserved, delayed, notify
 * - Todas las keys operadas atomicamente deben compartir hash tag
 * - ioredis puede ejecutar scripts Lua siempre que las keys esten en el mismo slot
 *
 * PREGUNTA DE REFLEXION:
 * Por que un worker Node usaria scripts Lua en lugar de comandos simples?
 * Respuesta: Para garantizar atomicidad y evitar race conditions entre
 * multiples workers concurrentes.
 */

import {
    calculateSlot,
    cluster,
    clusterSlots,
    disconnectAll,
    error,
    info,
    section,
    slotOwner,
    success,
} from "../lib/scenario-utils.mjs";

function metric(label, value) {
    info(label, value);
}

try {
    section("SIMULACION DE WORKER NODE CON IOREDIS");

    console.log("Un worker Node puede usar Redis Cluster para colas distribuidas.");
    console.log("Vamos a simular su comportamiento interno con ioredis.\n");

    const prefix = "{ioredis-lab}";
    const queueName = "default";

    section("TEST 1: Estructura de Keys del Worker");

    const workerKeys = [
        `${prefix}:queues:${queueName}`,
        `${prefix}:queues:${queueName}:reserved`,
        `${prefix}:queues:${queueName}:delayed`,
        `${prefix}:queues:${queueName}:notify`,
        `${prefix}:queues:${queueName}:failed`,
    ];

    console.log(`Keys que el worker usa para la cola '${queueName}':\n`);

    const slots = [];

    for (const key of workerKeys) {
        const slot = calculateSlot(key);
        slots.push(slot);
        info(key, `Slot ${slot}`);
    }

    const uniqueSlots = new Set(slots);

    if (uniqueSlots.size === 1) {
        success(`Todas las keys van al mismo slot (${slots[0]})`);
        console.log("\nEsto garantiza atomicidad en todas las operaciones.");
    } else {
        error("Las keys van a slots diferentes");
    }

    section("TEST 2: Simular Push de Job");

    const queueKey = `${prefix}:queues:${queueName}`;
    const jobPayload = JSON.stringify({
        id: `job_${Date.now()}`,
        name: "ProcessPayment",
        handler: "workers/payments/process-payment",
        data: { orderId: 12345 },
        attempts: 0,
    });

    await cluster.del(queueKey);
    await cluster.rpush(queueKey, jobPayload);

    const queueLen = await cluster.llen(queueKey);
    success("Job agregado a la cola");
    info("Jobs en cola", queueLen);
    info("Payload", `${jobPayload.slice(0, 80)}...`);

    section("TEST 3: Simular Worker Tomando Job");

    const reservedKey = `${prefix}:queues:${queueName}:reserved`;

    await cluster.del(reservedKey);

    const job = await cluster.rpoplpush(queueKey, reservedKey);

    if (job) {
        const jobData = JSON.parse(job);

        success("Job tomado atomicamente");
        info("Job ID", jobData.id || "N/A");
        info("Handler", jobData.handler || "N/A");
        info("Queue length", await cluster.llen(queueKey));
        info("Reserved length", await cluster.llen(reservedKey));
    }

    section("TEST 4: Simular Procesamiento y Release");

    console.log("Si el job falla, el worker puede devolverlo a la cola");
    console.log("o moverlo a delayed para retry.\n");

    await cluster.lrem(reservedKey, 0, job);
    await cluster.rpush(queueKey, job);

    success("Job devuelto a la cola para reintento");
    info("Queue length", await cluster.llen(queueKey));
    info("Reserved length", await cluster.llen(reservedKey));

    section("TEST 5: Simular Delayed Jobs");

    const delayedKey = `${prefix}:queues:${queueName}:delayed`;

    await cluster.del(delayedKey);

    const delay = 60;
    const availableAt = Math.floor(Date.now() / 1000) + delay;
    const delayedJob = JSON.stringify({
        id: `delayed_job_${Date.now()}`,
        name: "SendEmail",
        payload: { email: "user@example.com" },
        availableAt,
    });

    await cluster.zadd(delayedKey, availableAt, delayedJob);

    success(`Job agregado con delay de ${delay} segundos`);
    info("Available at", new Date(availableAt * 1000).toISOString());
    info("Delayed jobs", await cluster.zcard(delayedKey));

    section("TEST 6: Metricas que el Worker Monitorea");

    console.log("Un worker Node suele monitorear estas metricas:\n");

    for (let i = 0; i < 5; i += 1) {
        await cluster.rpush(queueKey, JSON.stringify({ id: i }));
    }

    const failedKey = `${prefix}:queues:${queueName}:failed`;
    const metrics = {
        "Queue size": await cluster.llen(queueKey),
        "Reserved jobs": await cluster.llen(reservedKey),
        "Delayed jobs": await cluster.zcard(delayedKey),
        "Failed jobs": await cluster.llen(failedKey),
    };

    for (const [name, value] of Object.entries(metrics)) {
        metric(name, value);
    }

    section("TEST 7: Script Lua con ioredis");

    console.log("ioredis permite ejecutar scripts Lua en Redis Cluster.");
    console.log("Las keys del script deben pertenecer al mismo slot.\n");

    const luaScript = `
local delayed = KEYS[1]
local queue = KEYS[2]
local now = tonumber(ARGV[1])

local jobs = redis.call('zrangebyscore', delayed, 0, now)

for i, job in ipairs(jobs) do
    redis.call('rpush', queue, job)
    redis.call('zrem', delayed, job)
end

return #jobs
`;

    const scriptDelayedKey = `${prefix}:script:delayed`;
    const scriptQueueKey = `${prefix}:script:queue`;
    const now = Math.floor(Date.now() / 1000);

    await cluster.del(scriptDelayedKey, scriptQueueKey);
    await cluster.zadd(scriptDelayedKey, now - 10, "job-past-1");
    await cluster.zadd(scriptDelayedKey, now - 5, "job-past-2");
    await cluster.zadd(scriptDelayedKey, now + 100, "job-future");

    const moved = await cluster.eval(luaScript, 2, scriptDelayedKey, scriptQueueKey, now);

    success("Script Lua ejecutado");
    info("Jobs movidos", moved);
    info("Jobs en queue", await cluster.llen(scriptQueueKey));
    info("Jobs restantes en delayed", await cluster.zcard(scriptDelayedKey));

    section("TEST 8: Analisis de Configuracion ioredis");

    console.log("En esta simulacion usamos:\n");

    console.log(`Prefix: ${prefix}`);
    console.log("  -> Todas las keys usan el mismo hash tag");
    console.log("  -> Todas caen en el mismo slot");
    console.log("  -> Operaciones atomicas garantizadas\n");

    const prefixSlot = calculateSlot(prefix);
    const owner = slotOwner(await clusterSlots(), prefixSlot);

    info(`Slot de ${prefix}`, prefixSlot);
    info("Nodo responsable", owner ? `${owner.host}:${owner.port}` : "unknown");

    console.log("\nImplicacion:");
    console.log(`Con prefix '${prefix}', TODO el trafico de esa cola va a un solo nodo.`);
    console.log("El cluster no distribuye esa cola, solo proporciona failover para ella.");

    section("CONCLUSIONES");

    console.log("OK Un worker Node con ioredis usa multiples keys por cola");
    console.log("OK Todas las keys atomicas deben compartir hash tag");
    console.log("OK Los scripts Lua garantizan atomicidad");
    console.log("OK RPOPLPUSH permite mover jobs sin race conditions");
    console.log("OK Un hash tag global es seguro, pero concentra carga en un slot");

    console.log("\nPREGUNTA FINAL:");
    console.log("Si tu sistema crece y necesitas distribuir carga,");
    console.log("que estrategias podrias usar manteniendo atomicidad?");
    console.log("\nOpciones:");
    console.log("  1. Multiples colas con diferentes hash tags");
    console.log("  2. Un broker dedicado para colas, Redis para cache");
    console.log("  3. Redis Streams con una estrategia de particion explicita");

    console.log("\nLaboratorio node/ioredis completado.");
    console.log("\nComandos utiles:");
    console.log("  make status    - Ver estado del cluster");
    console.log("  make monitor   - Monitorear comandos");
    console.log("  make reset     - Reiniciar el laboratorio");
} finally {
    await disconnectAll(cluster);
}
