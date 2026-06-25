/**
 * ESCENARIO 8: Patrones de Colas
 * ==============================
 *
 * OBJETIVO: Comprender como implementar colas correctamente en Redis Cluster.
 *
 * CONCEPTOS CLAVE:
 * - Las colas usan multiples keys: queue, processing, delayed
 * - Todas deben compartir el mismo hash tag
 * - RPOPLPUSH permite mover jobs atomicamente
 *
 * PREGUNTA DE REFLEXION:
 * Por que Laravel usa {default} en lugar de un hash tag por cola?
 * Respuesta: Para garantizar que todas las operaciones de una cola
 * especifica sean atomicas y vayan al mismo nodo.
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

try {
    section("PATRONES DE COLAS EN REDIS CLUSTER");

    console.log("Las colas en Redis usan multiples keys:");
    console.log("  - queue:{name} cola principal");
    console.log("  - queue:{name}:processing jobs en proceso");
    console.log("  - queue:{name}:delayed jobs retrasados");
    console.log("  - queue:{name}:failed jobs fallidos\n");

    console.log("Todas deben compartir el mismo hash tag para operaciones atomicas.\n");

    section("TEST 1: Estructura de Cola Laravel");

    const queueKeys = [
        "queues:{default}",
        "queues:{default}:reserved",
        "queues:{default}:delayed",
        "queues:{default}:notify",
    ];

    console.log("Keys usadas por Laravel Horizon:\n");

    const slotsForQueueKeys = [];

    for (const key of queueKeys) {
        const slot = calculateSlot(key);
        slotsForQueueKeys.push(slot);
        info(key, `Slot ${slot}`);
    }

    if (new Set(slotsForQueueKeys).size === 1) {
        success("Todas las keys van al mismo slot");
        console.log("\nEsto permite operaciones atomicas en la cola.");
    } else {
        error("Las keys van a slots diferentes");
    }

    section("TEST 2: Implementacion Basica de Cola");

    let queue = "queue:{test}";
    let processing = "queue:{test}:processing";

    await cluster.del(queue, processing);

    const jobs = ["job-1", "job-2", "job-3"];

    for (const job of jobs) {
        await cluster.rpush(queue, job);
    }

    const queueLen = await cluster.llen(queue);
    success(`Jobs en cola: ${queueLen}`);

    const processed = [];

    while (await cluster.llen(queue) > 0) {
        const job = await cluster.rpoplpush(queue, processing);
        processed.push(job);

        console.log(`Procesando: ${job}`);

        await cluster.lrem(processing, 0, job);
    }

    success(`Jobs procesados: ${processed.length}`);

    section("TEST 3: Cola con Jobs Retrasados");

    queue = "queue:{delayed-test}";
    const delayed = "queue:{delayed-test}:delayed";
    processing = "queue:{delayed-test}:processing";

    await cluster.del(queue, delayed, processing);

    await cluster.rpush(queue, "normal-job-1", "normal-job-2");

    const futureTime = Math.floor(Date.now() / 1000) + 3600;
    await cluster.zadd(delayed, futureTime, "delayed-job-1");

    console.log(`Jobs en cola normal: ${await cluster.llen(queue)}`);
    console.log(`Jobs retrasados: ${await cluster.zcard(delayed)}`);

    const now = futureTime + 100;
    const readyJobs = await cluster.zrangebyscore(delayed, 0, now);

    if (readyJobs.length > 0) {
        console.log("\nJobs listos para procesar:");

        for (const job of readyJobs) {
            console.log(`  - ${job}`);
            await cluster.rpush(queue, job);
            await cluster.zrem(delayed, job);
        }
    }

    success("Jobs retrasados movidos a cola normal");

    section("TEST 4: Multiples Colas con Hash Tags");

    const queues = {
        emails: "queue:{emails}",
        payments: "queue:{payments}",
        notifications: "queue:{notifications}",
    };
    const clusterSlotRanges = await clusterSlots();

    console.log("Distribucion de colas en el cluster:\n");

    for (const [name, queueKey] of Object.entries(queues)) {
        const slot = calculateSlot(queueKey);
        const owner = slotOwner(clusterSlotRanges, slot);

        info(`Cola ${name}`, `Slot ${slot} -> :${owner?.port || "unknown"}`);
    }

    console.log("\nCada cola puede estar en un nodo diferente,");
    console.log("pero todas las operaciones de una cola son atomicas.");

    section("TEST 5: Simulacion de Workers Concurrentes");

    queue = "queue:{concurrent}";
    processing = "queue:{concurrent}:processing";

    await cluster.del(queue, processing);

    for (let i = 1; i <= 10; i += 1) {
        await cluster.rpush(queue, `concurrent-job-${i}`);
    }

    console.log(`Jobs en cola: ${await cluster.llen(queue)}\n`);
    console.log("Simulando 2 workers tomando jobs:\n");

    const worker1Jobs = [];
    const worker2Jobs = [];

    while (await cluster.llen(queue) > 0) {
        const job1 = await cluster.rpoplpush(queue, processing);

        if (job1) {
            worker1Jobs.push(job1);
            console.log(`Worker 1: ${job1}`);
            await cluster.lrem(processing, 0, job1);
        }

        const job2 = await cluster.rpoplpush(queue, processing);

        if (job2) {
            worker2Jobs.push(job2);
            console.log(`Worker 2: ${job2}`);
            await cluster.lrem(processing, 0, job2);
        }
    }

    console.log("");
    success(`Worker 1 proceso: ${worker1Jobs.length}`);
    success(`Worker 2 proceso: ${worker2Jobs.length}`);

    section("TEST 6: Cola con Prioridad");

    const highPriority = "queue:{priority}:high";
    const normalPriority = "queue:{priority}:normal";
    const lowPriority = "queue:{priority}:low";

    await cluster.del(highPriority, normalPriority, lowPriority);

    await cluster.rpush(lowPriority, "low-1", "low-2");
    await cluster.rpush(normalPriority, "normal-1", "normal-2");
    await cluster.rpush(highPriority, "high-1", "high-2");

    console.log("Jobs por prioridad:");
    console.log(`  Alta: ${await cluster.llen(highPriority)}`);
    console.log(`  Normal: ${await cluster.llen(normalPriority)}`);
    console.log(`  Baja: ${await cluster.llen(lowPriority)}\n`);

    console.log("Procesando en orden de prioridad:");

    const priorityProcessed = [];

    while (await cluster.llen(highPriority) > 0) {
        const job = await cluster.lpop(highPriority);
        priorityProcessed.push(`[ALTA] ${job}`);
    }

    while (await cluster.llen(normalPriority) > 0) {
        const job = await cluster.lpop(normalPriority);
        priorityProcessed.push(`[NORMAL] ${job}`);
    }

    while (await cluster.llen(lowPriority) > 0) {
        const job = await cluster.lpop(lowPriority);
        priorityProcessed.push(`[BAJA] ${job}`);
    }

    for (const job of priorityProcessed) {
        console.log(`  ${job}`);
    }

    success("Jobs procesados por prioridad");

    section("CONCLUSIONES");

    console.log("OK Las colas usan multiples keys que deben compartir hash tag");
    console.log("OK RPOPLPUSH permite mover jobs atomicamente");
    console.log("OK Multiples workers pueden procesar la misma cola");
    console.log("OK Se pueden implementar colas con prioridad");
    console.log("OK Cada cola puede distribuirse en nodos diferentes");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si tienes 100 colas diferentes y todas usan hash tags");
    console.log("diferentes, como afecta esto la distribucion de carga");
    console.log("en tu cluster?");

    console.log("\nProximo escenario: make test node/ioredis/09-ioredis-worker-simulation");
} finally {
    await disconnectAll(cluster);
}
