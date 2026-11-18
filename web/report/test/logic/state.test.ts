import { describe, expect, it } from "vitest";
import { counted, defaultState } from "../../src/logic/state";
import { load, pick } from "./helpers";

describe("state", () => {
  it("defaultState turns every option on", () => {
    const doc = load("matrix");
    const s = defaultState(doc);
    expect(s.q).toBe("");
    expect(s.order).toBe("prio");
    expect([...s.combo].sort()).toEqual([...doc.header.matrix.combos].sort());
    expect(s.sev.has("high")).toBe(true);
    for (const f of doc.findings) {
      expect(s.kind.has(f.signal)).toBe(true);
      expect(s.file.has(f.file ?? "(no file)")).toBe(true);
    }
  });

  it("counted excludes expected, severity-less and harness findings", () => {
    const doc = load("single");
    expect(counted(pick(doc, (f) => f.signal === "missing-global"))).toBe(false);
    expect(counted(pick(doc, (f) => f.expected === true))).toBe(false);
    expect(counted(pick(doc, (f) => f.qid === 93))).toBe(true);
    const err = pick(doc, (f) => f.signal === "lua-error" && !f.file);
    expect(counted(err)).toBe(true);
    expect(counted({ ...err, harness: true })).toBe(false);
    expect(counted({ ...err, severity: undefined })).toBe(false);
  });
});
