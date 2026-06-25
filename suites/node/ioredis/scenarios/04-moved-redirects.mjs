/**
 * ESCENARIO 4: Redirecciones MOVED
 * ================================
 *
 * OBJETIVO: Comprender que es MOVED y como ioredis lo maneja.
 *
 * CONCEPTOS CLAVE:
 * - MOVED significa: "esta key no esta en este nodo, ve a este otro"
 * - Ocurre cuando el mapa del cliente esta desactualizado
 * - ioredis actualiza automaticamente su mapa al recibir MOVED
 *
 * PREGUNTA DE REFLEXION:
 * Cuando ocurre MOVED en produccion?
 * Respuesta: Despues de resharding, failover, o si el cliente se conecto
 * inicialmente a un nodo diferente.
 */

import {
    calculateSlot,
    cluster,
    clusterSlots,
    directNode,
    disconnectAll,
    error,
    info,
    section,
    slotOwner,
    success,
    warning,
} from "../lib/scenario-utils.mjs";

const directClients = [];

function errorMessage(err) {
    return err instanceof Error ? err.message : String(err);
}

function parseMoved(message) {
    const match = message.match(/MOVED\s+(\d+)\s+([^:]+):(\d+)/);

    if (!match) {
        return null;
    }

    return {
        slot: match[1],
        host: match[2],
        port: match[3],
    };
}

function masterEndpoints(slots) {
    const endpoints = new Map();

    for (const [, , master] of slots) {
        const endpoint = {
            host: master[0],
            port: Number(master[1]),
        };

        endpoints.set(`${endpoint.host}:${endpoint.port}`, endpoint);
    }

    return [...endpoints.values()];
}

function wrongEndpointFor(slots, owner) {
    const wrong = masterEndpoints(slots).find((endpoint) => endpoint.port !== Number(owner.port));

    if (!wrong) {
        throw new Error("No se encontro un nodo incorrecto para provocar MOVED");
    }

    return wrong;
}

function createDirectClient(endpoint) {
    const client = directNode(endpoint.host, endpoint.port);
    directClients.push(client);
    return client;
}

try {
    section("REDIRECCIONES MOVED");

    console.log("MOVED es la forma que tiene Redis de decir:");
    console.log("  'Esta key no esta aqui, ve a este otro nodo'\n");
    console.log("ioredis maneja MOVED automaticamente actualizando su mapa.\n");

    section("TEST 1: Provocar MOVED Manualmente");

    console.log("Vamos a conectarnos directamente a un nodo especifico");
    console.log("y pedirle una key que no le corresponde.\n");

    const slots = await clusterSlots();
    const key = "test-moved-key";
    const slot = calculateSlot(key);
    const correctNode = slotOwner(slots, slot);

    if (!correctNode) {
        throw new Error(`No se encontro nodo responsable para el slot ${slot}`);
    }

    const wrongNode = wrongEndpointFor(slots, correctNode);

    info("Key de prueba", key);
    info("Slot calculado", slot);
    info("Nodo correcto", `${correctNode.host}:${correctNode.port}`);
    info("Nodo incorrecto", `${wrongNode.host}:${wrongNode.port}`);

    console.log("\nConectando al nodo incorrecto y pidiendo la key...");

    try {
        const wrongClient = createDirectClient(wrongNode);
        const result = await wrongClient.get(key);

        console.log(`Resultado: ${result}`);
        success("El nodo respondio, posiblemente redirigio internamente");
    } catch (err) {
        const message = errorMessage(err);

        if (message.includes("MOVED")) {
            warning("Recibimos MOVED");
            info("Respuesta", message);

            const moved = parseMoved(message);
            if (moved) {
                info("Slot en MOVED", moved.slot);
                info("Nodo correcto", `${moved.host}:${moved.port}`);
            }
        } else {
            console.log(`Error diferente: ${message}`);
        }
    }

    section("TEST 2: ioredis Maneja MOVED Automaticamente");

    console.log("Cuando usas el cliente cluster de ioredis, MOVED se maneja");
    console.log("automaticamente sin que la aplicacion lo note.\n");

    const testKey = `moved-test-${Date.now()}`;

    await cluster.set(testKey, "valor-prueba");
    const value = await cluster.get(testKey);

    success(`Key guardada y recuperada: ${value}`);

    console.log("\nQue paso detras de escenas?");
    console.log(`  1. ioredis calculo el slot de '${testKey}'`);
    console.log("  2. Consulto su mapa para encontrar el nodo");
    console.log("  3. Envio el comando al nodo correcto");
    console.log("  4. Si el nodo respondiera MOVED, ioredis actualizaria el mapa");
    console.log("     y reintentaria automaticamente");

    section("TEST 3: Mapa Interno de ioredis");

    console.log("ioredis descarga el mapa de slots al iniciar:\n");
    console.log("Rangos de slots:");

    for (const range of slots) {
        const [start, end, master] = range;
        info(`Slots ${start}-${end}`, `${master[0]}:${master[1]}`);
    }

    console.log("\nioredis mantiene este mapa en memoria para enrutar comandos.");

    section("TEST 4: Simular Cambio de Topologia");

    console.log("En produccion, la topologia cambia cuando:");
    console.log("  - Un master falla y una replica toma su lugar");
    console.log("  - Se hace resharding de slots");
    console.log("  - Se agregan o eliminan nodos\n");

    console.log("Para simular esto, necesitariamos hacer failover manual.");
    console.log("Lo haremos en el escenario 7 (make test node/ioredis/07-failover).");

    section("TEST 5: MOVED vs ASK");

    console.log("Hay dos tipos de redirecciones:\n");

    console.log("MOVED:");
    console.log("  - El slot ha sido permanentemente movido a otro nodo");
    console.log("  - El cliente debe actualizar su mapa");
    console.log("  - ioredis lo maneja automaticamente\n");

    console.log("ASK:");
    console.log("  - El slot esta en proceso de migracion");
    console.log("  - El cliente debe enviar ASKING antes del comando");
    console.log("  - Es temporal, durante resharding\n");

    section("TEST 6: Impacto de Redirecciones");

    console.log("Las redirecciones tienen un costo de rendimiento:\n");

    console.log("  1. RTT adicional para el reintento");
    console.log("  2. Actualizacion del mapa de slots");
    console.log("  3. Posible reconexion a otro nodo\n");

    console.log("ioredis optimiza esto cacheando el mapa y actualizandolo");
    console.log("solo cuando es necesario.");

    section("TEST 7: Verificacion de Comportamiento");

    console.log("Vamos a verificar que ioredis enruta correctamente:\n");

    const keys = [];

    for (let i = 0; i < 10; i += 1) {
        const verifyKey = `verify-${i}`;
        await cluster.set(verifyKey, `value-${i}`);
        keys.push(verifyKey);
    }

    let allOk = true;

    for (const verifyKey of keys) {
        const index = verifyKey.split("-")[1];
        const expected = `value-${index}`;
        const actual = await cluster.get(verifyKey);

        if (expected !== actual) {
            error(`Error en ${verifyKey}: esperado '${expected}', obtenido '${actual}'`);
            allOk = false;
        }
    }

    if (allOk) {
        success("Todas las keys fueron enrutadas correctamente");
    }

    section("CONCLUSIONES");

    console.log("OK MOVED indica que una key esta en otro nodo");
    console.log("OK ioredis maneja MOVED automaticamente");
    console.log("OK El cliente actualiza su mapa de slots cuando recibe MOVED");
    console.log("OK ASK es similar pero para migraciones temporales");
    console.log("OK Las redirecciones tienen costo de rendimiento");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si tu aplicacion empieza a ver muchos errores MOVED,");
    console.log("que podria estar pasando en el cluster?");

    console.log("\nProximo escenario: make test node/ioredis/05-readonly-error");
} finally {
    await disconnectAll(...directClients, cluster);
}
