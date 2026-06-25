/**
 * ESCENARIO 7: Failover
 * =====================
 *
 * OBJETIVO: Simular y comprender el comportamiento durante failover.
 */

import {
    cluster,
    clusterNodes,
    disconnectAll,
    error,
    info,
    parseClusterNodes,
    section,
    sleep,
    success,
    warning,
} from "../lib/scenario-utils.mjs";

function isMaster(node) {
    return node.flags.includes("master");
}

function isReplica(node) {
    return node.flags.includes("slave") || node.flags.includes("replica");
}

function nodeEndpoint(node) {
    return `${node.host}:${node.port}`;
}

function parseClusterInfo(raw) {
    return Object.fromEntries(
        raw
            .trim()
            .split(/\r?\n/)
            .filter((line) => line.includes(":"))
            .map((line) => {
                const [key, ...valueParts] = line.split(":");
                return [key, valueParts.join(":")];
            })
    );
}

function shardCount() {
    return Number(process.env.SHARDS || 3);
}

try {
    section("FAILOVER EN REDIS CLUSTER");

    console.log("El failover ocurre cuando un master falla");
    console.log("y una replica toma su lugar automaticamente.\n");

    section("TEST 1: Estado Inicial del Cluster");

    const nodes = parseClusterNodes(await clusterNodes());
    const masters = nodes.filter(isMaster);
    const replicas = nodes.filter(isReplica);

    for (const node of masters) {
        info("Master", nodeEndpoint(node));
    }

    for (const node of replicas) {
        info("Replica", `${nodeEndpoint(node)} -> ${node.masterId?.slice(0, 8) || "unknown"}`);
    }

    section("TEST 2: Informacion del Cluster");

    const clusterInfo = parseClusterInfo(await cluster.call("CLUSTER", "INFO"));
    const interestingKeys = [
        "cluster_state",
        "cluster_slots_assigned",
        "cluster_known_nodes",
        "cluster_size",
    ];

    for (const key of interestingKeys) {
        if (clusterInfo[key] !== undefined) {
            info(key, clusterInfo[key]);
        }
    }

    section("TEST 3: Simulando Carga Continua");

    console.log("Vamos a simular un worker de cola escribiendo constantemente.");
    console.log("Esto nos permitira ver que pasa durante el failover.\n");

    const testKey = `failover-test-${Date.now()}`;
    let operations = 0;
    const errors = [];

    info("Key de prueba", testKey);

    console.log("\nEjecutando 20 operaciones de escritura...\n");

    for (let i = 0; i < 20; i += 1) {
        try {
            await cluster.set(testKey, `value-${i}`);
            process.stdout.write(".");
            operations += 1;
            await sleep(100);
        } catch (err) {
            process.stdout.write("X");
            errors.push(err instanceof Error ? err.message : String(err));
        }
    }

    console.log("\n");
    success(`Operaciones exitosas: ${operations}/20`);

    if (errors.length > 0) {
        warning(`Errores: ${errors.length}`);
        info("Ultimo error", errors[errors.length - 1]);
    }

    section("TEST 4: Verificar Replicacion");

    console.log("Las replicas replican datos de sus masters.\n");

    const testValue = `replication-test-${Date.now()}`;
    await cluster.set("replication-key", testValue);

    console.log(`Valor escrito en cluster: ${testValue}`);
    console.log("Esperando replicacion...");

    await sleep(500);

    try {
        const replicatedValue = await cluster.get("replication-key");

        if (replicatedValue === testValue) {
            success("Valor recuperado correctamente desde el cluster");
            info("Valor leido", replicatedValue);
        } else {
            warning("Valor diferente, replicacion asincrona");
        }
    } catch (err) {
        const message = err instanceof Error ? err.message : String(err);
        error(`Error: ${message}`);
    }

    section("TEST 5: Instrucciones para Failover Manual");

    console.log("Para simular un failover real, ejecuta estos comandos:\n");

    console.log("1. Identifica un master y su replica:");
    console.log("   redis-cli -h redis-node-1 -p 7000 CLUSTER NODES\n");

    console.log("2. Conecta a la replica:");

    const firstReplica = replicas[0];
    const fallbackReplicaNode = shardCount() + 1;
    const fallbackReplicaPort = 6999 + fallbackReplicaNode;

    if (firstReplica) {
        console.log(`   redis-cli -h ${firstReplica.host} -p ${firstReplica.port}\n`);
    } else {
        console.log(`   redis-cli -h redis-node-${fallbackReplicaNode} -p ${fallbackReplicaPort}\n`);
    }

    console.log("3. Ejecuta failover manual:");
    console.log("   CLUSTER FAILOVER\n");

    console.log("4. Verifica el cambio:");
    console.log("   redis-cli -h redis-node-1 -p 7000 CLUSTER NODES\n");

    console.log("Observa como los puertos de master y replica se intercambian.");

    section("TEST 6: Comportamiento de ioredis");

    console.log("Cuando ocurre un failover:\n");

    console.log("1. Master cae");
    console.log("   - Las conexiones existentes fallan");
    console.log("   - Nuevas escrituras reciben errores\n");

    console.log("2. Replica detecta el fallo");
    console.log("   - Basado en cluster-node-timeout, 5s en nuestro lab");
    console.log("   - Inicia eleccion de nuevo master\n");

    console.log("3. Nuevo master elegido");
    console.log("   - La replica se promociona");
    console.log("   - El mapa de slots se actualiza\n");

    console.log("4. ioredis se recupera");
    console.log("   - Recibe MOVED/ASK o errores de conexion temporales");
    console.log("   - Actualiza su mapa de slots");
    console.log("   - Reintenta operaciones segun su configuracion\n");

    section("TEST 7: Metricas de Failover");

    console.log("Metricas a monitorear en produccion:\n");

    console.log("Tiempo de deteccion:");
    console.log("  - cluster-node-timeout, default: 15s");
    console.log("  - Cuanto tarda en detectar que un nodo cayo\n");

    console.log("Tiempo de failover:");
    console.log("  - Tiempo desde deteccion hasta nuevo master");
    console.log("  - Generalmente menor a 1 segundo despues de deteccion\n");

    console.log("Tiempo de recuperacion del cliente:");
    console.log("  - Depende de la implementacion");
    console.log("  - ioredis refresca slots y reintenta segun retryStrategy/clusterRetryStrategy\n");

    section("CONCLUSIONES");

    console.log("OK El failover es automatico en Redis Cluster");
    console.log("OK Las replicas se promocionan cuando el master falla");
    console.log("OK El cluster sigue operativo con nodos restantes");
    console.log("OK ioredis maneja el cambio de topologia");
    console.log("OK Hay un periodo de indisponibilidad durante el failover");

    console.log("\nPREGUNTA PARA REFLEXIONAR:");
    console.log("Si tienes un sistema de pagos y ocurre un failover,");
    console.log("que estrategia usarias para manejar las operaciones");
    console.log("que fallan durante el cambio de master?");

    console.log("\nProximo escenario: make test node/ioredis/08-queue-patterns");
} finally {
    await disconnectAll(cluster);
}
