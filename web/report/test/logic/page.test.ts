// The page's card walk: top-level cards (roots + lifted) and the fold entries
// (harness notices, expected clicks), each expanded through cardChildren as Card does.
import { describe, expect, it } from "vitest";
import { cardChildren, visible } from "../../src/logic/filter";
import { counted, defaultState, isHarness, type FilterState } from "../../src/logic/state";
import type { Finding, ReportDoc } from "../../src/types";
import { load, pick } from "./helpers";

const single = load("single");

/** Rendered-card count per id, as the page renders them. */
function rendered(doc: ReportDoc, s: FilterState): Map<string, number> {
  const seen = new Map<string, number>();
  const walk = (f: Finding) => {
    seen.set(f.id, (seen.get(f.id) ?? 0) + 1);
    for (const k of cardChildren(f, doc, s)) walk(k);
  };
  const v = visible(doc, s);
  for (const f of [...v.roots, ...v.lifted]) walk(f);
  for (const f of doc.findings.filter((x) => (isHarness(x) && !x.expected) || x.expected === true)) walk(f);
  return seen;
}

describe("the page renders each finding at most once", () => {
  const d = defaultState(single);
  const states: [string, FilterState][] = [
    ["default", d],
    ["low only", { ...d, sev: new Set(["low"]) }],
    ["search tunnel", { ...d, q: "tunnel" }],
  ];

  it("single.json has a counted finding whose cause is uncounted", () => {
    const child = pick(single, (f) => f.qid === 530);
    const cause = pick(single, (f) => f.id === child.caused_by);
    expect(counted(child)).toBe(true);
    expect(counted(cause)).toBe(false);
  });

  for (const [name, s] of states) {
    it(`${name}: every id at most once, fold entries nest nothing`, () => {
      for (const [id, n] of rendered(single, s)) expect(n, id).toBe(1);
      for (const f of single.findings.filter((x) => !counted(x))) expect(cardChildren(f, single, s)).toEqual([]);
    });
  }

  it("the follow-on of an uncounted cause is a top-level card, not a fold child", () => {
    const child = pick(single, (f) => f.qid === 530);
    expect(rendered(single, d).get(child.id)).toBe(1);
    expect(visible(single, d).lifted.map((f) => f.id)).toContain(child.id);
  });
});

describe("the tab title", () => {
  it("names the character(s) and the run date from the header", async () => {
    const { pageTitle } = await import("../../src/components/Header");
    expect(pageTitle(single)).toBe("Dwarf Warrior · 2026-01-01 · hwc findings");
    expect(pageTitle(load("matrix"))).toBe("3 characters (Dwarf, Gnome) · 2026-01-01 · hwc findings");
  });
});
