import { readdirSync } from "fs";
import { spawnSync } from "child_process";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const scenarioDir = join(root, "scenarios");

function scenarioSortKey(file) {
    const basename = file.replace(/\.[^.]+$/, "");
    const match = basename.match(/^(\d+)-(.+)$/);

    if (!match) {
        return [Number.POSITIVE_INFINITY, 0, basename];
    }

    const [, number, name] = match;

    return [Number(number), name.split("-").length, name];
}

function compareScenarios(left, right) {
    const leftKey = scenarioSortKey(left);
    const rightKey = scenarioSortKey(right);

    return leftKey[0] - rightKey[0]
        || leftKey[1] - rightKey[1]
        || leftKey[2].localeCompare(rightKey[2]);
}

const scenarios = readdirSync(scenarioDir)
    .filter((file) => /^[0-9][0-9].*\.(mjs|js)$/.test(file))
    .sort(compareScenarios);

let failed = 0;

for (const scenario of scenarios) {
    console.log(`\n>>> ${scenario}`);
    const result = spawnSync(process.execPath, [join("scenarios", scenario)], {
        cwd: root,
        stdio: "inherit",
        env: process.env,
    });

    if (result.status !== 0) {
        failed += 1;
    }
}

process.exit(failed > 0 ? 1 : 0);
