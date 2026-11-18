import { describe, expect, it } from "vitest";
import { childrenShown, counts, matches, visible } from "../../src/logic/filter";
import { counted, defaultState } from "../../src/logic/state";
import { load, pick } from "./helpers";

const single = load("single");
const matrix = load("matrix");
const withQ = (doc = single, q: string) => ({ ...defaultState(doc), q });

describe("matches", () => {
  it("digits match the qid exactly, not as a substring", () => {
    const s = withQ(single, "93");
    expect(matches(pick(single, (f) => f.qid === 93), s)).toBe(true);
    expect(matches(pick(single, (f) => f.qid === 96393 && !f.caused_by), s)).toBe(false);
  });
  it("matches title case-insensitively", () => {
    const f = pick(single, (f) => f.qid === 500);
    expect(matches(f, withQ(single, "GNOME trouble"))).toBe(true);
    expect(matches(f, withQ(single, "nonsense"))).toBe(false);
  });
  it("matches file:line", () => {
    const f = pick(single, (f) => f.qid === 500);
    expect(matches(f, withQ(single, "Dun_11_14.lua:300"))).toBe(true);
    expect(matches(f, withQ(single, "Dun_11_14.lua:301"))).toBe(false);
  });
  it("matches id", () => {
    const f = pick(single, (f) => f.qid === 500);
    expect(matches(f, withQ(single, f.id.toLowerCase()))).toBe(true);
  });
  it("a digit token in file:line matches", () => {
    const f = pick(single, (f) => f.qid === 500);
    expect(matches(f, withQ(single, "300"))).toBe(true);
  });
  it("respects the severity, file and kind sets", () => {
    const f = pick(single, (f) => f.qid === 500);
    const s = defaultState(single);
    expect(matches(f, { ...s, sev: new Set(["low"]) })).toBe(false);
    expect(matches(f, { ...s, file: new Set() })).toBe(false);
    expect(matches(f, { ...s, kind: new Set(["stuck"]) })).toBe(false);
  });
});

describe("visible", () => {
  it("lifts a matching follow-on whose cause does not match", () => {
    const cause = pick(single, (f) => f.qid === 96393 && !f.caused_by);
    const follow = pick(single, (f) => f.qid === 96393 && f.caused_by === cause.id);
    const v = visible(single, withQ(single, "doesn't advance"));
    expect(v.lifted.map((f) => f.id)).toContain(follow.id);
    expect(v.roots.map((f) => f.id)).not.toContain(cause.id);
  });
  it("keeps a follow-on nested when its cause matches too", () => {
    const cause = pick(single, (f) => f.qid === 96393 && !f.caused_by);
    const follow = pick(single, (f) => f.qid === 96393 && f.caused_by === cause.id);
    const v = visible(single, withQ(single, "96393"));
    expect(v.roots.map((f) => f.id)).toContain(cause.id);
    expect(v.lifted.map((f) => f.id)).not.toContain(follow.id);
    expect(childrenShown(cause, single, withQ(single, "96393")).map((f) => f.id)).toContain(follow.id);
  });
  const chain = () => {
    const root = pick(single, (f) => f.qid === 96393 && !f.caused_by);
    const middle = pick(single, (f) => f.qid === 93);
    const leaf = pick(single, (f) => f.qid === 94);
    return { root, middle, leaf };
  };
  it("does not lift a grandchild whose root matches, though the middle does not", () => {
    const { root, middle, leaf } = chain();
    const st = withQ(single, "the"); // root and leaf titles contain "the"; the middle's does not
    expect([root, middle, leaf].map((f) => matches(f, st))).toEqual([true, false, true]);
    const v = visible(single, st);
    expect(v.roots.map((f) => f.id)).toContain(root.id);
    expect(v.lifted.map((f) => f.id)).not.toContain(leaf.id);
    expect(childrenShown(root, single, st).map((f) => f.id)).toContain(middle.id);
    expect(childrenShown(middle, single, st).map((f) => f.id)).toEqual([leaf.id]);
  });
  it("lifts a grandchild when only it matches", () => {
    const { leaf } = chain();
    const v = visible(single, withQ(single, "warrior's path"));
    expect(v.lifted.map((f) => f.id)).toEqual([leaf.id]);
    expect(v.roots).toEqual([]);
  });
  it("childrenShown keeps a non-matching cause that has a matching descendant", () => {
    const root = pick(single, (f) => f.qid === 96393 && !f.caused_by);
    const s = withQ(single, "warrior's path");
    const kids = childrenShown(root, single, s);
    expect(kids.map((f) => f.qid)).toEqual([93]);
  });
  it("never shows harness or expected findings", () => {
    const ids = new Set(
      [...visible(single, defaultState(single)).roots, ...visible(single, defaultState(single)).lifted].map((f) => f.id),
    );
    for (const f of single.findings) if (!counted(f)) expect(ids.has(f.id)).toBe(false);
    const v = visible(single, withQ(single, "GetNumGroupMembers"));
    expect(v.roots).toEqual([]);
    expect(v.lifted).toEqual([]);
  });
  it("by default there are no lifted findings", () => {
    expect(visible(single, defaultState(single)).lifted).toEqual([]);
  });
});

describe("counts", () => {
  const total = single.findings.filter(counted).length;
  it("totals every counted finding, shown equals total by default", () => {
    const c = counts(single, defaultState(single));
    expect(c.total).toBe(total);
    expect(c.shown).toBe(total);
  });
  it("with only High on, shown is the High count and total is unchanged", () => {
    const high = single.findings.filter((f) => counted(f) && f.severity === "high").length;
    const c = counts(single, { ...defaultState(single), sev: new Set(["high"]) });
    expect(c.shown).toBe(high);
    expect(c.total).toBe(total);
  });
  it("sev option counts ignore the severity filter but respect the text query", () => {
    const s = { ...defaultState(single), sev: new Set(["high"]), q: "advance" };
    const c = counts(single, s);
    const expected = single.findings.filter((f) => counted(f) && f.signal === "did-not-advance");
    expect(c.options.sev.medium).toBe(expected.filter((f) => f.severity === "medium").length);
    expect(c.options.sev.high).toBe(0);
    expect(c.shown).toBe(0);
  });
  it("counts a follow-on under its own severity, not its cause's", () => {
    const cause = pick(single, (f) => f.qid === 96393 && !f.caused_by);
    const follow = pick(single, (f) => f.qid === 96393 && f.caused_by === cause.id);
    expect(cause.severity).not.toBe(follow.severity);
    const c = counts(single, defaultState(single));
    const med = single.findings.filter((f) => counted(f) && f.severity === follow.severity).length;
    expect(c.options.sev[follow.severity!]).toBe(med);
    const only = counts(single, { ...defaultState(single), sev: new Set([follow.severity!]) });
    expect(only.shown).toBe(med);
  });
  it("option counts sum consistently across groups", () => {
    const c = counts(single, defaultState(single));
    expect(Object.values(c.options.sev).reduce((a, b) => a + b, 0)).toBe(total);
    expect(Object.values(c.options.kind).reduce((a, b) => a + b, 0)).toBe(total);
    expect(Object.values(c.options.file).reduce((a, b) => a + b, 0)).toBe(total);
  });
});

describe("matrix", () => {
  it("filtering to one combo hides findings only other combos hit", () => {
    const only = "Gnome PRIEST baseline";
    const s = { ...defaultState(matrix), combo: new Set([only]) };
    const v = visible(matrix, s);
    const ids = [...v.roots, ...v.lifted].map((f) => f.id);
    for (const f of matrix.findings.filter(counted)) {
      const hit = (f.combos ?? []).includes(only);
      expect(ids.includes(f.id), f.id).toBe(hit);
    }
    expect(ids.length).toBeGreaterThan(0);
    const c = counts(matrix, s);
    expect(c.shown).toBe(ids.length);
    expect(c.options.combo[only]).toBe(ids.length);
    
  });
});

describe("every visible finding is rendered exactly once", () => {
  const states = (doc: typeof single) => {
    const d = defaultState(doc);
    const qs = ["", "the", "93", "94", "advance", "never", "offered", "lua", "Dun_1_5", "Dun_5_11.lua:99", "warrior", "300", "zzz"];
    const out = qs.map((q) => ({ ...d, q }));
    out.push({ ...d, sev: new Set(["high"]) }, { ...d, sev: new Set(["medium"]) }, { ...d, kind: new Set(["did-not-advance"]) });
    for (const c of doc.header.matrix.combos) out.push({ ...d, combo: new Set([c]) });
    out.push({ ...d, q: "advance", sev: new Set(["medium"]) });
    return out;
  };
  for (const [name, doc] of [["single", single], ["matrix", matrix]] as const) {
    it(`${name}: walking roots+lifted through childrenShown visits each matching counted finding once`, () => {
      for (const s of states(doc)) {
        const v = visible(doc, s);
        const seen = new Map<string, number>();
        const walk = (f: (typeof doc.findings)[number], path: Set<string>) => {
          seen.set(f.id, (seen.get(f.id) ?? 0) + 1);
          for (const c of childrenShown(f, doc, s)) if (!path.has(c.id)) walk(c, new Set(path).add(c.id));
        };
        for (const f of [...v.roots, ...v.lifted]) walk(f, new Set([f.id]));
        for (const f of doc.findings.filter((x) => counted(x) && matches(x, s))) {
          expect(seen.get(f.id), `${f.id} under ${JSON.stringify([s.q, [...s.sev]])}`).toBe(1);
        }
      }
    });
  }
});
