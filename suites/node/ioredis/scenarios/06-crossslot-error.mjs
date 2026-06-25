/**
 * ESCENARIO 6: Error CROSSSLOT
 * ============================
 *
 * OBJETIVO: Comprender el error CROSSSLOT y por que ocurre.
 *
 * CONCEPTOS CLAVE:
 * - CROSSSLOT ocurre cuando operas sobre keys en slots diferentes
 * - Redis Cluster requiere que operaciones multi-key usen el mismo slot
 * - Los hash tags solucionan esto
 *
 * PREGUNTA DE REFLEXION:
 * Por que Redis Cluster tiene esta limitacion?
 * Respuesta: Las operaciones atomicas no pueden cruzar nodos.
 * Redis no tiene transacciones distribuidas.
 */

import { calculateSlot, cluster, disconnectAll, error, info, section, success } from "../lib/scenario-utils.mjs";

function errorMessage(err) {
    return err instanceof Error ? err.message : String(err);
}

function isCrossSlotOrClientBlock(message) {
    return message.includes("CROSSSLOT")
        || message.includes("same slot")
        || message.includes("different slots")
        || message.includes("All keys in the pipeline");
}

function infoKey(label, key) {
    info(label, `${key} -> Slot ${calculateSlot(key)}`);
}

async function assertPipelineResult(results) {
    const failed = results.find(([err]) => err);

    if (failed) {
        throw failed[0];
    }
}

try {
    section("ERROR CROSSSLOT");

    console.log("CROSSSLOT ocurre cuando intentas operar sobre keys");
    console.log("que estan en slots diferentes.\n");

    console.log("Mensaje tipico:");
    console.log("  CROSSSLOT Keys in request don't hash to the same slot\n");

    section("TEST 1: CROSSSLOT con MGET");

    const key1 = "key-alpha";
    const key2 = "key-beta";

    infoKey("Key 1", key1);
    infoKey("Key 2", key2);

    if (calculateSlot(key1) !== calculateSlot(key2)) {
        console.log("\nLas keys estan en slots diferentes. Intentando MGET...\n");

        try {
            await cluster.mget(key1, key2);
            success("MGET funciono, sorpresa");
        } catch (err) {
            const message = errorMessage(err);

            if (isCrossSlotOrClientBlock(message)) {
                error("CROSSSLOT ERROR o bloqueado por ioredis");
                info("Mensaje", message);

                console.log("\nEsto es el comportamiento esperado.");
                console.log("ioredis intercepta o Redis rechaza operaciones multi-key entre slots.");
            } else {
                console.log(`Error diferente: ${message}`);
            }
        }
    } else {
        console.log("\nLas keys coinciden en el mismo slot por casualidad.");
        console.log("Prueba con diferentes keys.");
    }

    section("TEST 2: Solucion con Hash Tags");

    const taggedKey1 = "a{same-slot}";
    const taggedKey2 = "b{same-slot}";
    const taggedKey3 = "c{same-slot}";

    infoKey("Key 1", taggedKey1);
    infoKey("Key 2", taggedKey2);
    infoKey("Key 3", taggedKey3);

    if (
        calculateSlot(taggedKey1) === calculateSlot(taggedKey2)
        && calculateSlot(taggedKey2) === calculateSlot(taggedKey3)
    ) {
        console.log("\nTodas las keys van al mismo slot.\n");

        await cluster.set(taggedKey1, "valor-1");
        await cluster.set(taggedKey2, "valor-2");
        await cluster.set(taggedKey3, "valor-3");

        try {
            const values = await cluster.mget(taggedKey1, taggedKey2, taggedKey3);
            success(`MGET exitoso: ${values.join(", ")}`);
        } catch (err) {
            error(`Error inesperado: ${errorMessage(err)}`);
        }
    }

    section("TEST 3: Pipeline con Slots Diferentes");

    console.log("Los pipelines de ioredis Cluster tambien esperan un slot compatible.\n");

    const keyA = "pipeline-a";
    const keyB = "pipeline-b";

    infoKey("Key A", keyA);
    infoKey("Key B", keyB);

    if (calculateSlot(keyA) !== calculateSlot(keyB)) {
        console.log("\nIntentando pipeline con slots diferentes...");

        try {
            const results = await cluster
                .pipeline()
                .set(keyA, "1")
                .set(keyB, "2")
                .exec();

            await assertPipelineResult(results);
            success("Pipeline funciono, sorpresa");
        } catch (err) {
            const message = errorMessage(err);

            if (isCrossSlotOrClientBlock(message)) {
                error("CROSSSLOT o validacion de ioredis en pipeline");
                info("Mensaje", message);
            } else {
                console.log(`Error: ${message}`);
            }
        }
    }

    section("TEST 4: Pipeline con Hash Tags");

    console.log("Pipeline con mismo hash tag:\n");

    try {
        const results = await cluster
            .pipeline()
            .set("x{pipeline}", "1")
            .set("y{pipeline}", "2")
            .set("z{pipeline}", "3")
            .exec();

        await assertPipelineResult(results);
        success("Pipeline con hash tags exitoso");
    } catch (err) {
        error(`Error: ${errorMessage(err)}`);
    }

    section("TEST 5: RPOPLPUSH y Colas");

    console.log("RPOPLPUSH mueve un elemento entre dos listas atomicamente.");
    console.log("Requiere que ambas listas esten en el mismo slot.\n");

    const source = "queue:source";
    const dest = "queue:destination";

    infoKey("Source", source);
    infoKey("Dest", dest);

    if (calculateSlot(source) !== calculateSlot(dest)) {
        console.log("\nIntentando RPOPLPUSH con slots diferentes...");

        await cluster.del(source);
        await cluster.rpush(source, "job1");

        try {
            await cluster.rpoplpush(source, dest);
            success("RPOPLPUSH funciono, sorpresa");
        } catch (err) {
            const message = errorMessage(err);

            if (isCrossSlotOrClientBlock(message)) {
                error("CROSSSLOT ERROR o bloqueado por ioredis");
                console.log("Comportamiento esperado: operacion multi-key entre slots.");
            } else {
                console.log(`Error: ${message}`);
            }
        }
    }

    section("TEST 6: RPOPLPUSH con Hash Tags");

    const taggedSource = "queue:{default}";
    const taggedDest = "queue:{default}:processing";

    infoKey("Source", taggedSource);
    infoKey("Dest", taggedDest);

    if (calculateSlot(taggedSource) === calculateSlot(taggedDest)) {
        console.log("\nAmbas listas estan en el mismo slot.\n");

        await cluster.del(taggedSource, taggedDest);
        await cluster.rpush(taggedSource, "job1", "job2", "job3");

        const job = await cluster.rpoplpush(taggedSource, taggedDest);
        success(`Job movido atomicamente: ${job}`);

        const sourceLen = await cluster.llen(taggedSource);
        const destLen = await cluster.llen(taggedDest);

        info("Items en source", sourceLen);
        info("Items en dest", destLen);
    }

    section("TEST 7: Por que existe CROSSSLOT?");

    console.log("La razon fundamental:\n");

    console.log("Redis Cluster NO tiene transacciones distribuidas.");
    console.log("Una operacion solo puede ejecutarse en UN nodo.\n");

    console.log("Si tuvieras:");
    console.log("  - Key A en Nodo 1");
    console.log("  - Key B en Nodo 2\n");

    console.log("Un MGET tendria que:");
    console.log("  1. Pedir valor de A a Nodo 1");
    console.log("  2. Pedir valor de B a Nodo 2");
    console.log("  3. Combinar resultados\n");

    console.log("Esto NO es atomico y agrega complejidad.");
    console.log("Redis prefiere rechazar la operacion.\n");

    console.log("Solucion: Hash Tags");
    console.log("Fuerza que las keys vayan al mismo nodo.");

    section("CONCLUSIONES");

    console.log("OK CROSSSLOT ocurre con operaciones multi-key en slots diferentes");
    console.log("OK Redis Cluster no soporta operaciones atomicas cross-node");
    console.log("OK Los hash tags fuerzan keys al mismo slot");
    console.log("OK Laravel usa {default} para evitar CROSSSLOT en colas");
    console.log("OK Es una limitacion de diseno, no un bug");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si necesitas hacer MGET de 100 keys y todas usan hash tags");
    console.log("diferentes, que estrategia podrias usar?");

    console.log("\nProximo escenario: make test node/ioredis/06-crossslot-error-raw");
} finally {
    await disconnectAll(cluster);
}
