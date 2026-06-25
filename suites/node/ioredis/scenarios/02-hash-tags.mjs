/**
 * ESCENARIO 2: Hash Tags {}
 * ========================
 *
 * OBJETIVO: Comprender por que los hash tags son CRITICOS en Redis Cluster.
 *
 * CONCEPTOS CLAVE:
 * - Solo el contenido entre {} se usa para calcular el slot
 * - Keys con el mismo hash tag van al mismo slot
 * - Esto permite operaciones atomicas como MGET, pipelines y Lua
 *
 * PREGUNTA DE REFLEXION:
 * Por que Laravel usa {default} en las colas?
 * Respuesta: Para garantizar que todas las operaciones de la cola sean
 * atomicas, ya que usan multiples keys.
 */

import {
    calculateSlot,
    cluster,
    disconnectAll,
    error,
    info,
    section,
    success,
} from "../lib/scenario-utils.mjs";

function errorMessage(err) {
    return err instanceof Error ? err.message : String(err);
}

try {
    section("HASH TAGS: EL SECRETO DE LAS OPERACIONES ATOMICAS");

    console.log("En Redis Cluster, solo el contenido entre {} se usa para calcular el slot.");
    console.log("Esto permite forzar que multiples keys vayan al mismo slot.\n");

    section("TEST 1: Con vs Sin Hash Tag");

    const comparisons = [
        ["queue:default", "queue:{default}"],
        ["user:123:profile", "user:{123}:profile"],
        ["session:abc:data", "session:{abc}:data"],
        ["api-tee_queues:default", "api-tee_queues:{default}"],
    ];

    for (const [withoutTag, withTag] of comparisons) {
        const slotWithout = calculateSlot(withoutTag);
        const slotWith = calculateSlot(withTag);

        console.log(`Sin tag: '${withoutTag}' -> Slot ${slotWithout}`);
        console.log(`Con tag: '${withTag}' -> Slot ${slotWith}`);

        if (slotWithout !== slotWith) {
            success("Los slots son diferentes, comportamiento esperado");
        } else {
            console.log("  Coincidencia casual");
        }

        console.log("");
    }

    section("TEST 2: Multiples Keys, Mismo Hash Tag");

    const keysWithSameTag = [
        "queue:{default}",
        "queue:{default}:processing",
        "queue:{default}:delayed",
        "queue:{default}:failed",
        "queue:{default}:reserved",
    ];

    console.log("Todas estas keys usan el hash tag {default}:\n");

    const slots = [];

    for (const key of keysWithSameTag) {
        const slot = calculateSlot(key);
        slots.push(slot);
        info(key, `Slot ${slot}`);
    }

    const uniqueSlots = new Set(slots);

    if (uniqueSlots.size === 1) {
        success(`TODAS las keys van al mismo slot (${slots[0]})`);
        console.log("\nEsto permite operaciones atomicas entre estas keys");
    } else {
        error("Las keys van a slots diferentes. Esto no deberia pasar.");
    }

    section("TEST 3: Operacion MGET Multi-Get");

    console.log("MGET requiere que todas las keys esten en el mismo slot.\n");

    console.log("Intentando MGET sin hash tags:");
    try {
        await cluster.mget("key1", "key2", "key3");
        success("MGET funciono porque las keys coincidieron en el mismo slot por casualidad");
    } catch (err) {
        error(`MGET fallo: ${errorMessage(err)}`);
        console.log("Esto es esperado si las keys estan en slots diferentes");
    }

    console.log("\nIntentando MGET con hash tags:");
    try {
        await cluster.mget("key1{test}", "key2{test}", "key3{test}");
        success("MGET con hash tags funciono correctamente");
    } catch (err) {
        error(`Error inesperado: ${errorMessage(err)}`);
    }

    section("TEST 4: Pipeline con Hash Tags");

    console.log("Los pipelines tambien requieren que las keys esten en el mismo slot.\n");

    console.log("Pipeline con mismo hash tag:");
    try {
        await cluster
            .pipeline()
            .set("a{pipeline}", "1")
            .set("b{pipeline}", "2")
            .set("c{pipeline}", "3")
            .incr("counter{pipeline}")
            .exec();

        success("Pipeline ejecutado exitosamente");
    } catch (err) {
        error(`Error: ${errorMessage(err)}`);
    }

    section("TEST 5: Simulacion de Cola Laravel");

    console.log("Laravel Horizon usa multiples keys para cada cola:");
    console.log("- queues:{default} cola principal");
    console.log("- queues:{default}:reserved jobs en proceso");
    console.log("- queues:{default}:delayed jobs retrasados\n");

    const laravelKeys = ["queues:{default}", "queues:{default}:reserved", "queues:{default}:delayed"];

    for (const key of laravelKeys) {
        info(key, `Slot ${calculateSlot(key)}`);
    }

    const queue = "queues:{default}";
    const processing = "queues:{default}:processing";

    console.log("\nSimulando operacion de cola RPUSH + RPOPLPUSH:");

    await cluster.del(queue, processing);
    await cluster.rpush(queue, "job1", "job2", "job3");
    const job = await cluster.rpoplpush(queue, processing);

    success(`Job movido atomicamente: ${job}`);

    section("TEST 6: Hash Tags Anidados");

    console.log("Que pasa si hay multiples {} en una key?");
    console.log("Redis usa SOLO el primero.\n");

    const nestedKeys = ["a{tag1}b{tag2}c", "a{tag2}b{tag1}c", "{tag1}resto{tag2}"];

    for (const key of nestedKeys) {
        info(key, `Slot ${calculateSlot(key)} (usa solo el primer {})`);
    }

    const slot1 = calculateSlot("{tag1}");
    const slot2 = calculateSlot("{tag2}");

    if (slot1 !== slot2) {
        success("Confirmado: {tag1} y {tag2} dan slots diferentes");
    }

    section("TEST 7: Casos Especiales");

    console.log("Hash tag vacio '{}':");
    info("key{}", `Slot ${calculateSlot("key{}")}`);

    console.log("\nSin hash tag:");
    info("key", `Slot ${calculateSlot("key")}`);

    console.log("\nHash tag con espacios:");
    info("key{my tag}", `Slot ${calculateSlot("key{my tag}")}`);

    section("CONCLUSIONES");

    console.log("OK Los hash tags fuerzan que multiples keys vayan al mismo slot");
    console.log("OK Esto permite operaciones atomicas como MGET, pipelines y Lua scripts");
    console.log("OK Laravel usa {default} para garantizar atomicidad en colas");
    console.log("OK El trade-off: sacrificas sharding horizontal por consistencia");

    console.log("\nPREGUNTA CRITICA:");
    console.log("Si usas '{api-tee}' como prefix para TODAS tus keys,");
    console.log("cuantos slots de los 16384 estaras usando?");
    console.log("Que implica esto para escalar tu cluster?");

    console.log("\nProximo escenario: make test node/ioredis/03-routing");
} finally {
    await disconnectAll(cluster);
}
