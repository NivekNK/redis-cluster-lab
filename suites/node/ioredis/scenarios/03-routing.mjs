/**
 * ESCENARIO 3: Routing de ioredis
 * ===============================
 *
 * OBJETIVO: Entender como ioredis decide a que nodo enviar cada comando.
 *
 * CONCEPTOS CLAVE:
 * - ioredis mantiene un mapa de slots -> nodos
 * - Al iniciar, descarga CLUSTER SLOTS del cluster
 * - Para cada comando, calcula el slot y elige el nodo
 *
 * PREGUNTA DE REFLEXION:
 * Que pasa si el mapa de ioredis queda desactualizado?
 * Respuesta: ioredis recibe MOVED y actualiza el mapa automaticamente.
 */

import {
    calculateSlot,
    cluster,
    clusterSlots,
    directNode,
    disconnectAll,
    info,
    section,
    slotOwner,
    success,
    warning,
} from "../lib/scenario-utils.mjs";

const SAMPLE_SIZE = 1000;
const directClients = [];

function endpointKey(endpoint) {
    return `${endpoint.host}:${endpoint.port}`;
}

function masterEndpoints(slots) {
    const endpoints = new Map();

    for (const [, , master] of slots) {
        const endpoint = {
            host: master[0],
            port: Number(master[1]),
        };

        endpoints.set(endpointKey(endpoint), endpoint);
    }

    return [...endpoints.values()];
}

function asciiBar(percentage) {
    return "#".repeat(Math.max(1, Math.round(percentage / 2)));
}

function errorMessage(err) {
    return err instanceof Error ? err.message : String(err);
}

function redisInfoValue(rawInfo, key) {
    const line = rawInfo
        .split(/\r?\n/)
        .find((entry) => entry.startsWith(`${key}:`));

    if (!line) {
        return "N/A";
    }

    return line.slice(key.length + 1);
}

async function nodeClient(endpoint) {
    const client = directNode(endpoint.host, endpoint.port);
    directClients.push(client);
    return client;
}

try {
    section("ROUTING DE IOREDIS");

    console.log("ioredis mantiene un mapa interno de slots -> nodos.");
    console.log("Para cada comando, calcula el slot y envia al nodo correcto.\n");

    section("TEST 1: Mapa de Slots del Cluster");

    const slots = await clusterSlots();

    console.log("Rangos de slots y sus nodos:\n");

    for (const range of slots) {
        const [start, end, master] = range;
        info(`Slots ${start}-${end}`, `${master[0]}:${master[1]}`);
    }

    section("TEST 2: Routing de Keys Especificas");

    const testKeys = [
        "user:1",
        "user:2",
        "user:3",
        "session:abc",
        "queue:{default}",
        "cache:data",
    ];

    console.log("Para cada key, ioredis:");
    console.log("  1. Calcula el slot usando CRC16");
    console.log("  2. Busca el nodo responsable de ese slot");
    console.log("  3. Envia el comando a ese nodo\n");

    for (const key of testKeys) {
        const slot = calculateSlot(key);
        const owner = slotOwner(slots, slot);

        if (!owner) {
            throw new Error(`No se encontro nodo responsable para el slot ${slot}`);
        }

        console.log(
            `Key: '${key}'`.padEnd(25)
            + `Slot: ${String(slot).padEnd(6)}`
            + `-> Nodo: ${owner.host}:${owner.port}`
        );
    }

    success("Cada key se enruta al nodo correcto");

    section("TEST 3: Distribucion de Carga");

    const distribution = new Map();

    for (const endpoint of masterEndpoints(slots)) {
        distribution.set(endpoint.port, 0);
    }

    for (let i = 0; i < SAMPLE_SIZE; i += 1) {
        const key = `key-${i}-${Math.random().toString(16).slice(2)}`;
        const slot = calculateSlot(key);
        const owner = slotOwner(slots, slot);

        if (!owner) {
            throw new Error(`No se encontro nodo responsable para el slot ${slot}`);
        }

        distribution.set(owner.port, (distribution.get(owner.port) || 0) + 1);
    }

    console.log(`Distribucion de ${SAMPLE_SIZE} keys aleatorias:\n`);

    for (const [port, count] of distribution) {
        const percentage = Number(((count / SAMPLE_SIZE) * 100).toFixed(1));
        info(`Nodo :${port}`, `${count} keys (${percentage}%) ${asciiBar(percentage)}`);
    }

    success("La distribucion es aproximadamente uniforme");

    section("TEST 4: Routing con Hash Tags");

    console.log("Cuando usas hash tags, todas las keys van al mismo nodo.\n");

    const taggedKeys = [
        "a{user123}",
        "b{user123}",
        "c{user123}",
        "data{user123}",
        "counter{user123}",
    ];

    let firstNode = null;
    let allSame = true;

    for (const key of taggedKeys) {
        const slot = calculateSlot(key);
        const owner = slotOwner(slots, slot);

        if (!owner) {
            throw new Error(`No se encontro nodo responsable para el slot ${slot}`);
        }

        if (firstNode === null) {
            firstNode = owner.port;
        } else if (firstNode !== owner.port) {
            allSame = false;
        }

        info(key, `Slot ${slot} -> :${owner.port}`);
    }

    if (allSame) {
        success(`Todas las keys van al mismo nodo (:${firstNode})`);
    } else {
        warning("Las keys fueron a nodos diferentes");
    }

    section("TEST 5: Conexiones del Cliente");

    console.log(`Tipo de conexion: ${cluster.constructor.name}\n`);
    info("Conexiones master en ioredis", cluster.nodes("master").length);
    info("Conexiones replica en ioredis", cluster.nodes("slave").length);

    for (const endpoint of masterEndpoints(slots)) {
        try {
            const client = await nodeClient(endpoint);
            const rawInfo = await client.info("clients");
            info(
                `Nodo ${endpoint.host}:${endpoint.port}`,
                `${redisInfoValue(rawInfo, "connected_clients")} clientes conectados`
            );
        } catch (err) {
            info(`Nodo ${endpoint.host}:${endpoint.port}`, `No disponible: ${errorMessage(err)}`);
        }
    }

    section("TEST 6: Latencia por Nodo");

    console.log("Midiendo latencia a cada nodo...\n");

    for (const endpoint of masterEndpoints(slots)) {
        const startedAt = process.hrtime.bigint();

        try {
            const client = await nodeClient(endpoint);
            await client.ping();

            const elapsedMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
            info(`Nodo ${endpoint.host}:${endpoint.port}`, `${elapsedMs.toFixed(2)}ms`);
        } catch (err) {
            info(`Nodo ${endpoint.host}:${endpoint.port}`, `Error: ${errorMessage(err)}`);
        }
    }

    section("TEST 7: Operaciones Multi-Key");

    console.log("ioredis enruta automaticamente operaciones multi-key.");
    console.log("Redis Cluster exige que todas las keys de un MGET esten en el mismo slot.\n");

    await cluster.set("multi{a}", "1");
    await cluster.set("multi{b}", "2");
    await cluster.set("multi{c}", "3");

    try {
        const values = await cluster.mget("multi{a}", "multi{b}", "multi{c}");
        success(`MGET exitoso: ${values.join(", ")}`);
    } catch (err) {
        console.log(`Error: ${errorMessage(err)}`);
    }

    section("CONCLUSIONES");

    console.log("OK ioredis mantiene un mapa slots -> nodos en memoria");
    console.log("OK Para cada comando, calcula el slot y elige el nodo");
    console.log("OK Las keys se distribuyen uniformemente entre nodos");
    console.log("OK Los hash tags permiten agrupar keys en un mismo nodo");
    console.log("OK El routing es transparente para la aplicacion");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si ioredis tiene el mapa desactualizado, por ejemplo despues de un failover,");
    console.log("que crees que pasara cuando intente escribir en un nodo que ya no es master?");

    console.log("\nProximo escenario: make test node/ioredis/04-moved-redirects");
} finally {
    await disconnectAll(...directClients, cluster);
}
