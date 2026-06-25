/**
 * ESCENARIO 5: Error READONLY
 * ===========================
 *
 * OBJETIVO: Reproducir y comprender el error READONLY.
 *
 * CONCEPTOS CLAVE:
 * - Las replicas son solo lectura por defecto
 * - Si intentas escribir en una replica, obtienes READONLY o una redireccion
 * - Usar el endpoint master evita esto
 *
 * PREGUNTA DE REFLEXION:
 * Por que cambiar de clustercfg a master endpoint soluciono tu problema?
 * Respuesta: clustercfg puede conectar a cualquier nodo incluyendo replicas,
 * master endpoint solo conecta a masters.
 */

import {
    calculateSlot,
    cluster,
    clusterNodes,
    clusterSlots,
    directNode,
    disconnectAll,
    error,
    info,
    parseClusterNodes,
    section,
    sleep,
    slotOwner,
    success,
    warning,
} from "../lib/scenario-utils.mjs";

const directClients = [];
const testKey = "readonly-test-key";

function errorMessage(err) {
    return err instanceof Error ? err.message : String(err);
}

function nodeEndpoint(node) {
    return `${node.host}:${node.port}`;
}

function isMaster(node) {
    return node.flags.includes("master");
}

function isReplica(node) {
    return node.flags.includes("slave") || node.flags.includes("replica");
}

function findNodeByEndpoint(nodes, endpoint) {
    return nodes.find((node) => nodeEndpoint(node) === endpoint)
        || nodes.find((node) => String(node.port) === endpoint.split(":")[1]);
}

function redisInfoValue(rawInfo, key) {
    const line = rawInfo
        .split(/\r?\n/)
        .find((entry) => entry.startsWith(`${key}:`));

    if (!line) {
        return "unknown";
    }

    return line.slice(key.length + 1);
}

function createDirectClient(host, port) {
    const client = directNode(host, port);
    directClients.push(client);
    return client;
}

try {
    section("ERROR READONLY");

    console.log("Este es el error que puedes ver en produccion:");
    console.log("  READONLY You can't write against a read only replica.\n");

    console.log("Ocurre cuando intentas escribir en una replica de Redis.");
    console.log("Las replicas son solo lectura por diseno.\n");

    section("TEST 1: Topologia del Cluster");

    const nodes = parseClusterNodes(await clusterNodes());
    const slots = await clusterSlots();
    const masters = nodes.filter(isMaster);
    const replicas = nodes.filter(isReplica);

    console.log("Nodos del cluster:\n");

    for (const node of masters) {
        info("Master", nodeEndpoint(node));
    }

    for (const node of replicas) {
        info("Replica", `${nodeEndpoint(node)} -> ${node.masterId?.slice(0, 8) || "unknown"}`);
    }

    console.log("");
    success(`Identificados ${masters.length} masters y ${replicas.length} replicas asociadas`);

    const slot = calculateSlot(testKey);
    const correctOwner = slotOwner(slots, slot);

    if (!correctOwner) {
        throw new Error(`No se encontro nodo responsable para el slot ${slot}`);
    }

    const masterEndpoint = `${correctOwner.host}:${correctOwner.port}`;
    const targetMaster = findNodeByEndpoint(masters, masterEndpoint);
    const targetReplica = targetMaster
        ? replicas.find((node) => node.masterId === targetMaster.id)
        : null;

    if (!targetMaster) {
        throw new Error(`No se encontro el master ${masterEndpoint} en CLUSTER NODES`);
    }

    section("TEST 2: Provocar READONLY");

    if (!targetReplica) {
        warning("No se encontro replica para la key seleccionada");
    } else {
        info("Key de prueba", `${testKey} (Slot: ${slot})`);
        info("Conectando a replica responsable", nodeEndpoint(targetReplica));

        try {
            const replicaClient = createDirectClient(targetReplica.host, targetReplica.port);
            const replicationInfo = await replicaClient.info("replication");

            info("Rol", redisInfoValue(replicationInfo, "role"));

            console.log("\nIntentando escribir en la replica...");
            await replicaClient.set(testKey, "test-value");
            error("La escritura funciono. Esto no deberia pasar.");
        } catch (err) {
            info("Resultado temporal", errorMessage(err));

            console.log("\nDIFERENCIA CLAVE: OSS REDIS vs AWS ELASTICACHE");
            console.log("En Redis Open Source, si intentas escribir en una replica dentro");
            console.log("de Redis Cluster, normalmente Redis te redirige al master con MOVED.\n");

            console.log("En AWS ElastiCache, si te conectas al endpoint de una replica");
            console.log("o si el Configuration Endpoint resuelve a una replica, el proxy");
            console.log("puede bloquear la escritura directamente y devolver:");
            console.log("  'READONLY You can't write against a read only replica.'\n");

            success("En ambos casos, la leccion es la misma: NO puedes escribir en una replica.");
        }
    }

    section("TEST 3: Escribir en Master Funciona");

    info("Key de prueba", `${testKey} (Slot: ${slot})`);
    info("Conectando a master responsable", nodeEndpoint(targetMaster));

    try {
        const masterClient = createDirectClient(targetMaster.host, targetMaster.port);
        const replicationInfo = await masterClient.info("replication");

        info("Rol", redisInfoValue(replicationInfo, "role"));

        console.log("\nIntentando escribir en el master...");
        await masterClient.set(testKey, "test-value");

        success("Escritura exitosa en el master");

        const value = await masterClient.get(testKey);
        info("Valor leido", value);
    } catch (err) {
        error(`Error inesperado: ${errorMessage(err)}`);
    }

    section("TEST 4: Simulando el Problema de clustercfg");

    console.log("Hipotesis de lo que paso en tu sistema:\n");

    console.log("1. Usabas el endpoint clustercfg Configuration Endpoint");
    console.log("2. Este endpoint puede resolver a cualquier nodo del cluster");
    console.log("3. Si resolvio a una replica, tu conexion inicial fue a una replica");
    console.log("4. Cuando intentaste escribir, obtuviste READONLY\n");

    console.log("Solucion:");
    console.log("Cambiar al endpoint master, que SIEMPRE resuelve a un master.\n");

    section("TEST 5: Replicas y Replicacion");

    console.log("Las replicas si permiten lecturas cuando el cliente lo pide explicitamente:\n");

    if (!targetReplica) {
        warning("No se encontro replica para probar lectura replicada");
    } else {
        try {
            const replicaClient = createDirectClient(targetReplica.host, targetReplica.port);

            await cluster.set(testKey, "valor-desde-master");
            await sleep(100);

            await replicaClient.call("READONLY");
            const value = await replicaClient.get(testKey);

            if (value === "valor-desde-master") {
                success(`Replica tiene el valor replicado: ${value}`);
            } else {
                console.log("Replica no tiene el valor aun, la replicacion es asincrona");
            }
        } catch (err) {
            console.log(`Nota: ${errorMessage(err)}`);
        }
    }

    section("TEST 6: Configuracion de Replicas");

    console.log("Redis permite configurar replicas de diferentes maneras:\n");

    console.log("1. Replica solo lectura por defecto:");
    console.log("   - Rechaza escrituras");
    console.log("   - Usada para failover y read replicas\n");

    console.log("2. Replica con comando READONLY:");
    console.log("   - Cliente puede enviar READONLY");
    console.log("   - Permite lecturas desde replicas en Redis Cluster\n");

    console.log("3. Replica con replica-read-only no:");
    console.log("   - Permite escrituras, no recomendado");
    console.log("   - Las escrituras no se replican de vuelta\n");

    section("TEST 7: Mejores Practicas");

    console.log("Para evitar READONLY en produccion:\n");

    console.log("1. Usa endpoint master o routing cluster-aware para escrituras");
    console.log("2. Configura ioredis con Redis.Cluster");
    console.log("3. Usa scaleReads: 'master' para caminos que escriben");
    console.log("4. Implementa retry logic para READONLY o MOVED\n");

    console.log("Configuracion recomendada para ioredis:");
    console.log("  const redis = new Redis.Cluster([");
    console.log("    { host: 'master.tu-cluster.cache.amazonaws.com', port: 6379 }");
    console.log("  ], {");
    console.log("    scaleReads: 'master'");
    console.log("  });");

    section("CONCLUSIONES");

    console.log("OK READONLY ocurre al intentar escribir en una replica");
    console.log("OK Las replicas son solo lectura por diseno");
    console.log("OK clustercfg puede conectar a cualquier nodo, incluyendo replicas");
    console.log("OK master endpoint solo conecta a masters");
    console.log("OK Usar masters para escrituras fue la decision correcta");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si tienes muchas replicas y quieres distribuir lecturas,");
    console.log("como podrias hacerlo sin arriesgarte a escribir en una replica?");

    console.log("\nProximo escenario: make test node/ioredis/06-crossslot-error");
} finally {
    await disconnectAll(...directClients, cluster);
}
