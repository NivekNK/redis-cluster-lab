/**
 * ESCENARIO 6 RAW: Error CROSSSLOT
 * =================================
 *
 * OBJETIVO: Ver el error CROSSSLOT lo mas cerca posible de Redis.
 *
 * Esta variante fuerza comandos crudos contra un nodo Redis para separar
 * lo que valida ioredis de lo que rechaza Redis Cluster directamente.
 */

import { spawnSync } from "child_process";
import {
    calculateSlot,
    cluster,
    directNode,
    disconnectAll,
    error,
    info,
    section,
    success,
    warning,
} from "../lib/scenario-utils.mjs";

const rawClient = directNode("redis-node-1", 7000);

function errorMessage(err) {
    return err instanceof Error ? err.message : String(err);
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

async function rawCall(command, ...args) {
    return rawClient.call(command, ...args);
}

try {
    section("ERROR CROSSSLOT RAW");

    console.log("CROSSSLOT ocurre cuando intentas operar sobre keys");
    console.log("que estan en slots diferentes.\n");

    section("TEST 1: CROSSSLOT con MGET");

    const crossKey1 = "key-alpha";
    const crossKey2 = "key-beta";

    infoKey("Key 1", crossKey1);
    infoKey("Key 2", crossKey2);

    if (calculateSlot(crossKey1) !== calculateSlot(crossKey2)) {
        console.log("\nLas keys estan en slots diferentes. Intentando MGET crudo...\n");

        try {
            await rawCall("MGET", crossKey1, crossKey2);
            success("MGET funciono, sorpresa");
        } catch (err) {
            const message = errorMessage(err);

            if (message.includes("CROSSSLOT")) {
                error("CROSSSLOT ERROR");
                info("Mensaje", message);
                console.log("\nEsto es el comportamiento esperado.");
            } else {
                console.log(`Error diferente: ${message}`);
            }
        }
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

    console.log("Un pipeline de comandos separados no es una operacion multi-key atomica.");
    console.log("Con ioredis Cluster, un pipeline cross-slot puede ser bloqueado por el cliente.\n");

    const keyA = "pipeline-a";
    const keyB = "pipeline-b";

    infoKey("Key A", keyA);
    infoKey("Key B", keyB);

    if (calculateSlot(keyA) !== calculateSlot(keyB)) {
        try {
            const results = await cluster
                .pipeline()
                .set(keyA, "1")
                .set(keyB, "2")
                .exec();

            await assertPipelineResult(results);
            success("Pipeline funciono correctamente");
        } catch (err) {
            warning(`ioredis bloqueo o rechazo el pipeline: ${errorMessage(err)}`);
            console.log("Esto no es el CROSSSLOT crudo de Redis; es validacion/routing del cliente.");
        }

        await cluster.set(keyA, "1");
        await cluster.set(keyB, "2");
        success("Los mismos SET por separado funcionan porque cada comando se enruta a su nodo");
    }

    section("TEST 4: Pipeline con Hash Tags");

    console.log("Pipeline con mismo hash tag, garantiza mismo nodo:\n");

    try {
        const results = await cluster
            .pipeline()
            .set("x{pipeline}", "1")
            .set("y{pipeline}", "2")
            .set("z{pipeline}", "3")
            .exec();

        await assertPipelineResult(results);
        success("Pipeline con hash tags exitoso");

        const values = await cluster.mget("x{pipeline}", "y{pipeline}", "z{pipeline}");
        success(`MGET posterior tambien funciona: ${values.join(", ")}`);
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
        console.log("\nIntentando RPOPLPUSH crudo con slots diferentes...");

        await cluster.del(source);
        await cluster.rpush(source, "job1");

        try {
            await rawCall("RPOPLPUSH", source, dest);
            success("RPOPLPUSH funciono, sorpresa");
        } catch (err) {
            const message = errorMessage(err);

            if (message.includes("CROSSSLOT")) {
                error("CROSSSLOT. No se puede mover entre slots");
                info("Mensaje", message);
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

    section("TEST 7: Ver CROSSSLOT real con redis-cli");

    console.log("Para ver el error CROSSSLOT directamente de Redis:\n");

    const args = ["-h", "redis-node-1", "-p", "7000", "MGET", crossKey1, crossKey2];
    console.log(`$ redis-cli ${args.join(" ")}`);

    const result = spawnSync("redis-cli", args, {
        encoding: "utf8",
    });

    const output = `${result.stdout || ""}${result.stderr || ""}`.trim();

    if (result.status !== 0 || output.includes("CROSSSLOT")) {
        error("Error CROSSSLOT confirmado:");
        console.log(`  ${output.replace(/\n/g, "\n  ")}`);
    } else {
        console.log(`  ${output.replace(/\n/g, "\n  ")}`);
    }

    section("TEST 8: Por que existe CROSSSLOT?");

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
    console.log("OK ioredis protege enviando solo comandos validos al cluster");
    console.log("OK Los hash tags fuerzan keys al mismo slot");
    console.log("OK Laravel usa {default} para evitar CROSSSLOT en colas");
    console.log("OK Es una limitacion de diseno, no un bug");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si necesitas hacer MGET de 100 keys y todas usan hash tags");
    console.log("diferentes, que estrategia podrias usar?");

    console.log("\nProximo escenario: make test node/ioredis/07-failover");
} finally {
    await disconnectAll(rawClient, cluster);
}
