import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { build } from "vite";
import { describe, expect, it } from "vitest";

const committed = join(__dirname, "../../../src/hwc/findings/report.html");
const PLACEHOLDER = "__HWC_REPORT_JSON__";

describe("bundle", () => {
  it("the committed report.html matches a fresh build", async () => {
    // Vitest sets NODE_ENV=test, which makes Vite bundle Preact's dev build.
    const previousEnv = process.env.NODE_ENV;
    process.env.NODE_ENV = "production";
    const out = mkdtempSync(join(tmpdir(), "hwc-report-"));
    try {
      await build({ root: join(__dirname, ".."), logLevel: "silent", mode: "production", build: { outDir: out, emptyOutDir: true } });
      const fresh = readFileSync(join(out, "index.html"));
      const have = readFileSync(committed);
      expect(
        fresh.equals(have),
        "src/hwc/findings/report.html is stale: run `npm run build` in web/report and commit it",
      ).toBe(true);
    } finally {
      process.env.NODE_ENV = previousEnv;
      rmSync(out, { recursive: true, force: true });
    }
  }, 60_000);

  it("the bundle is self-contained", () => {
    const html = readFileSync(committed, "utf8");
    expect(html.split(PLACEHOLDER).length - 1).toBe(1);
    expect(html).not.toMatch(/<script[^>]*\ssrc=/);
    expect(html).not.toMatch(/<link/);
    expect(html).not.toMatch(/\b(src|href)\s*=\s*["']?https?:/);
    expect(html).not.toMatch(/url\(\s*["']?https?:/);
    expect(html).not.toContain("@import");
  });
});
