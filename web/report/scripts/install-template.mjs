// Copies the built single-file page to where the Lua CLI reads it.
import { copyFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
copyFileSync(join(here, "../dist/index.html"), join(here, "../../../src/hwc/findings/report.html"));
