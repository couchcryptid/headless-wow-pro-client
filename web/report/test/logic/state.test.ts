import { describe, expect, it } from "vitest";
import { childrenShown } from "../../src/logic/filter";
import { guideSections } from "../../src/logic/order";
import { counted, defaultState, isHarness, location } from "../../src/logic/state";
import { load, pick } from "./helpers";

describe("state", () => {
  it("isHarness holds arrival data gaps, out of the counts", () => {
    expect(isHarness({ signal: "arrival-data-gap" } as never)).toBe(true);
    expect(counted({ signal: "arrival-data-gap", severity: "low" } as never)).toBe(false);
    expect(isHarness({ signal: "emulation-gap" } as never)).toBe(true);
    expect(counted({ signal: "emulation-gap", severity: "low" } as never)).toBe(false);
  });

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

  it("location names the file unless the finding is in its Guide-order section's own file", () => {
    const doc = load("single");
    const cause = pick(doc, (f) => f.qid === 96393 && !f.caused_by);
    const same = pick(doc, (f) => f.qid === 93);
    const other = pick(doc, (f) => f.qid === 95);
    expect(other.caused_by).toBe(cause.id);
    expect(other.file).not.toBe(cause.file);
    // In Guide order the cross-file follow-on nests under its cause in the cause's section.
    const s = { ...defaultState(doc), order: "guide" as const };
    const sec = guideSections(doc, s).find((x) => x.cards.some((c) => c.id === cause.id))!;
    expect(sec.file).toBe(cause.file);
    expect(childrenShown(cause, doc, s).map((f) => f.id)).toEqual(expect.arrayContaining([same.id, other.id]));
    expect(location(same, sec.file!)).toBe("line 30");
    expect(location(other, sec.file!)).toBe("Dun_5_11:25");
    // Priority order and the folds pass no section file: always file:line.
    expect(location(same)).toBe("Dun_1_5:30");
    expect(location(pick(doc, (f) => f.signal === "missing-global"))).toBeUndefined();
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
