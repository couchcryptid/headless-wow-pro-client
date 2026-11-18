import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import preact from "@preact/preset-vite";
import { defineConfig, type Plugin } from "vite";
import { viteSingleFile } from "vite-plugin-singlefile";

const here = dirname(fileURLToPath(import.meta.url));
const PLACEHOLDER = "__HWC_REPORT_JSON__";

// Dev server only: fills the placeholder from a shared fixture, chosen with
// ?fixture=<name> (default "single"). The build leaves the placeholder alone.
function devFixture(): Plugin {
  return {
    name: "hwc-dev-fixture",
    apply: "serve",
    transformIndexHtml: {
      order: "pre",
      handler(html, ctx) {
        const query = new URL(ctx.originalUrl ?? "/", "http://localhost").searchParams;
        const name = (query.get("fixture") ?? "single").replace(/[^\w-]/g, "");
        const json = readFileSync(join(here, "../../spec/fixtures/findings", `${name}.json`), "utf8");
        // "<" is escaped so the JSON can't close the script element.
        return html.replace(PLACEHOLDER, () => json.replace(/</g, "\\u003c"));
      },
    },
  };
}

export default defineConfig({
  plugins: [preact(), viteSingleFile(), devFixture()],
});
