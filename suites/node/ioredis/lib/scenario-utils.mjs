import Redis from "ioredis";
import calculateSlot from "cluster-key-slot";
import clusterClient from "../client.js";

export const cluster = clusterClient;
export { Redis, calculateSlot };

const colors = {
    blue: "\x1b[34m",
    green: "\x1b[32m",
    yellow: "\x1b[33m",
    red: "\x1b[31m",
    cyan: "\x1b[36m",
    reset: "\x1b[0m",
};

export function section(title) {
    console.log(`\n${colors.blue}${"=".repeat(60)}${colors.reset}`);
    console.log(`${colors.blue}${title}${colors.reset}`);
    console.log(`${colors.blue}${"=".repeat(60)}${colors.reset}\n`);
}

export function info(label, value) {
    console.log(`${colors.cyan}${label}:${colors.reset} ${value}`);
}

export function success(message) {
    console.log(`${colors.green}OK${colors.reset} ${message}`);
}

export function warning(message) {
    console.log(`${colors.yellow}WARN${colors.reset} ${message}`);
}

export function error(message) {
    console.log(`${colors.red}ERROR${colors.reset} ${message}`);
}

export function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function clusterSlots(client = cluster) {
    return client.call("CLUSTER", "SLOTS");
}

export async function clusterNodes(client = cluster) {
    return client.call("CLUSTER", "NODES");
}

export function slotOwner(slots, slot) {
    for (const range of slots) {
        const [start, end, master] = range;
        if (slot >= start && slot <= end) {
            return {
                start,
                end,
                host: master[0],
                port: master[1],
                id: master[2],
            };
        }
    }

    return null;
}

export function parseClusterNodes(raw) {
    return raw
        .trim()
        .split("\n")
        .filter(Boolean)
        .map((line) => {
            const parts = line.split(" ");
            const addressParts = parts[1].split("@")[0].split(":");
            const flags = parts[2].split(",");

            return {
                id: parts[0],
                host: addressParts[0],
                port: Number(addressParts[1]),
                flags,
                masterId: parts[3] === "-" ? null : parts[3],
                slots: parts.slice(8),
                raw: line,
            };
        });
}

export function directNode(host, port) {
    return new Redis({
        host,
        port,
        connectTimeout: 5000,
        lazyConnect: false,
        maxRetriesPerRequest: 1,
    });
}

export async function disconnectAll(...clients) {
    for (const client of clients) {
        if (client) {
            client.disconnect();
        }
    }
}
