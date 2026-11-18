import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";
import type { ReportDoc } from "../src/types";

const dir = join(__dirname, "../../../spec/fixtures/findings");

describe("shared fixtures", () => {
  it("every shared fixture parses as a format-2 ReportDoc", () => {
    const names = readdirSync(dir).filter((n) => n.endsWith(".json"));
    expect(names.length).toBeGreaterThan(0);
    let withoutSeverity = 0;
    for (const name of names) {
      const doc = JSON.parse(readFileSync(join(dir, name), "utf8")) as ReportDoc;
      expect(doc.format, name).toBe(2);
      const ids = new Set(doc.findings.map((f) => f.id));
      for (const f of doc.findings) {
        expect(f.id, name).toBeTruthy();
        expect(f.signal, name).toBeTruthy();
        expect(f.title, name).toBeTruthy();
        expect(Object.keys(doc.labels.signals), `${name}: ${f.id} signal`).toContain(f.signal);
        if (f.severity === undefined) withoutSeverity++;
        else expect(Object.keys(doc.labels.severities), `${name}: ${f.id} severity`).toContain(f.severity);
        if (f.caused_by) expect(ids.has(f.caused_by), `${name}: ${f.id} caused_by`).toBe(true);
      }
    }
    // Expected findings carry no severity; keep that optionality exercised.
    expect(withoutSeverity).toBeGreaterThan(0);
  });
});
