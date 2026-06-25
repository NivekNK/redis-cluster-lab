/**
 * ESCENARIO 1: Fundamentos de Slots
 * =================================
 *
 * OBJETIVO: Comprender como Redis Cluster distribuye datos usando slots.
 *
 * CONCEPTOS CLAVE:
 * - Redis Cluster tiene 16384 slots (0-16383)
 * - Cada key se asigna a un slot usando CRC16
 * - Los slots se distribuyen entre los masters
 *
 * PREGUNTA DE REFLEXION:
 * Por que 16384 slots y no mas o menos?
 * Respuesta: Es un balance entre granularidad y eficiencia de memoria.
 */

import {
    calculateSlot,
    cluster,
    clusterSlots,
    disconnectAll,
    info,
    section,
    slotOwner,
    success,
    warning,
} from "../lib/scenario-utils.mjs";

const TOTAL_REDIS_SLOTS = 16384;

try {
    section("FUNDAMENTOS DE SLOTS");

    console.log("Redis Cluster divide el espacio de keys en 16384 slots (0-16383).");
    console.log("Cada key se asigna a un slot usando el algoritmo CRC16.\n");

    section("TEST 1: Calculo de Slots");

    const testKeys = [
        "simple-key",
        "user:123",
        "session:abc123",
        "queue:default",
        "cache:data",
        "a",
        "una-key-muy-larga-para-probar-el-algoritmo-de-hash",
    ];

    for (const key of testKeys) {
        info(`Key '${key}'`, `Slot: ${calculateSlot(key)}`);
    }

    success("Todas las keys tienen un slot asignado (0-16383)");

    section("TEST 2: Distribucion en el Cluster");

    const slots = await clusterSlots();

    console.log(`El cluster tiene ${slots.length} rangos de slots:\n`);

    for (const range of slots) {
        const [start, end, master] = range;
        const slotCount = end - start + 1;

        info(`Slots ${start}-${end}`, `${slotCount} slots -> ${master[0]}:${master[1]}`);
    }

    success("Slots distribuidos entre los masters");

    section("TEST 3: Ubicacion de Keys");

    const key = "mi-key-de-prueba";
    const slot = calculateSlot(key);
    const owner = slotOwner(slots, slot);

    if (!owner) {
        throw new Error(`No se encontro nodo responsable para el slot ${slot}`);
    }

    info("Key", key);
    info("Slot calculado", slot);
    info("Nodo responsable", `${owner.host}:${owner.port}`);

    await cluster.set(key, "valor-de-prueba");
    const value = await cluster.get(key);

    success("Key guardada y recuperada exitosamente");
    info("Valor", value);

    section("TEST 4: Colision de Slots");

    console.log("Dos keys diferentes pueden caer en el mismo slot.");
    console.log("Esto NO es un problema, es comportamiento normal.\n");

    const keysBySlot = new Map();

    for (let i = 0; i < 100; i += 1) {
        const candidateKey = `key-${i}`;
        const candidateSlot = calculateSlot(candidateKey);
        const keys = keysBySlot.get(candidateSlot) || [];

        keys.push(candidateKey);
        keysBySlot.set(candidateSlot, keys);
    }

    let foundCollision = false;

    for (const [candidateSlot, keys] of keysBySlot) {
        if (keys.length > 1) {
            info(`Slot ${candidateSlot}`, `${keys.slice(0, 3).join(", ")}...`);
            foundCollision = true;
            break;
        }
    }

    if (!foundCollision) {
        warning("No se encontraron colisiones en la muestra, raro pero posible");
    }

    success("Las colisiones son normales y no causan problemas");

    section("TEST 5: Rango Completo de Slots");

    const totalSlots = slots.reduce((total, [start, end]) => total + (end - start + 1), 0);

    info("Total de slots cubiertos", totalSlots);
    info("Slots esperados", TOTAL_REDIS_SLOTS);

    if (totalSlots === TOTAL_REDIS_SLOTS) {
        success("Todos los slots estan cubiertos");
    } else {
        warning("Algunos slots no estan asignados");
    }

    section("CONCLUSIONES");

    console.log("OK Redis Cluster usa 16384 slots para distribuir datos");
    console.log("OK Cada key se asigna a un slot usando CRC16");
    console.log("OK Los slots se distribuyen entre los nodos master");
    console.log("OK Multiples keys pueden compartir el mismo slot, lo que llamamos colision");
    console.log("OK ioredis calcula el slot y envia el comando al nodo correcto");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si todas tus keys usan el mismo hash tag, por ejemplo {default},");
    console.log("en cuantos slots caeran? Que implica esto para el sharding?");

    console.log("\nProximo escenario: make test node/ioredis/02-hash-tags");
} finally {
    await disconnectAll(cluster);
}
