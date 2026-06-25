import Redis from "ioredis";
import dotenv from "dotenv";

dotenv.config();

const REDIS_MODE = process.env.REDIS_MODE || "cluster";
const REDIS_HOST = process.env.REDIS_HOST || "clustercfg.local";
const REDIS_PORT = Number(process.env.REDIS_PORT) || 6381;
const REDIS_PASSWORD = process.env.REDIS_PASSWORD || undefined;
const REDIS_USERNAME = process.env.REDIS_USERNAME || undefined;
const REDIS_SCHEME = process.env.REDIS_SCHEME || "tcp";

const redisCommonOptions = {
    password: REDIS_PASSWORD,
    username: REDIS_USERNAME,
    tls: REDIS_SCHEME === "tls" ? {} : undefined,
};

let redisClient;

if (REDIS_MODE === "cluster") {
    console.log(`🚀 [Redis Client] Conectando en modo CLUSTER -> ${REDIS_HOST}:${REDIS_PORT}`);
    redisClient = new Redis.Cluster(
        [{ host: REDIS_HOST, port: REDIS_PORT }],
        {
            redisOptions: {
                ...redisCommonOptions,
                connectTimeout: 5000,
            },
            clusterRetryStrategy: (times) => Math.min(times * 100, 2000),
            dnsLookup: (hostname, options, callback) => {
                import("dns").then((dns) => dns.lookup(hostname, options, callback));
            },
            scaleReads: "master",
        }
    );
} else {
    console.log(`🔌 [Redis Client] Conectando en modo SINGLE -> ${REDIS_HOST}:${REDIS_PORT}`);
    redisClient = new Redis({
        host: REDIS_HOST,
        port: REDIS_PORT,
        ...redisCommonOptions,
        db: 0,
        retryStrategy: (times) => Math.min(times * 50, 2000),
    });
}

redisClient.on("error", (err) => console.error("[Redis Error]:", err.message));

export default redisClient;
