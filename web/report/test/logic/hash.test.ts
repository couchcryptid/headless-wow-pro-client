import { describe, expect, it } from "vitest";
import { fromHash, toHash } from "../../src/logic/hash";
import { defaultState } from "../../src/logic/state";
import { load } from "./helpers";

describe("hash", () => {
  const doc = load("matrix");
  it("empty hash is the default state", () => {
    expect(fromHash("", doc)).toEqual(defaultState(doc));
    expect(fromHash("#", doc)).toEqual(defaultState(doc));
    expect(toHash(defaultState(doc), doc)).toBe("");
  });
  it("round-trips a state with every field set", () => {
    const d = defaultState(doc);
    const s = {
      q: "a b&c=d,é",
      sev: new Set(["high", "low"]),
      file: new Set([doc.header.guides[0]!.file]),
      kind: new Set(["did-not-advance"]),
      combo: new Set(["Gnome MAGE baseline"]),
      order: "guide" as const,
    };
    expect(s.sev.size).toBeLessThan(d.sev.size);
    const h = toHash(s, doc);
    expect(h).toContain("char=");
    expect(h).toContain("order=guide");
    expect(fromHash(h, doc)).toEqual(s);
  });
  it("round-trips an empty set and writes only differing parts", () => {
    const s = { ...defaultState(doc), sev: new Set<string>() };
    expect(toHash(s, doc)).toBe("sev=");
    expect(fromHash("sev=", doc)).toEqual(s);
    expect(toHash({ ...defaultState(doc), q: "x y" }, doc)).toBe("q=x%20y");
  });
});
