import { describe, expect, it } from "vitest";
import { MIN_GAP, gapFor, scaleTicks, tracks } from "../../src/logic/map";
import { counted, defaultState } from "../../src/logic/state";
import type { Finding, ReportDoc } from "../../src/types";
import { load } from "./helpers";

const single = load("single");
const matrix = load("matrix");
const s0 = defaultState(single);

// single.json's longest guide holds the two close pins (lines 300 and 303).
const longGuide = single.header.guides.reduce((a, b) => (b.last_line > a.last_line ? b : a));
const trackOf = (doc: ReportDoc, file: string, s = defaultState(doc), minGap?: number) =>
  tracks(doc, s, minGap).find((t) => t.file === file)!;
const lines = (fs: Finding[]) => fs.map((f) => f.line);

describe("tracks", () => {
  it("follow header.guides order, one per guide", () => {
    expect(tracks(single, s0).map((t) => t.file)).toEqual(single.header.guides.map((g) => g.file));
    expect(tracks(matrix, defaultState(matrix)).map((t) => t.file)).toEqual(matrix.header.guides.map((g) => g.file));
  });

  it("label the track with the short file name", () => {
    const t = trackOf(single, longGuide.file);
    expect(t.label).toBe(longGuide.file.split("/").pop()!.replace(/\.lua$/, ""));
  });

  it("hold one pin per matching counted finding in the file", () => {
    for (const t of tracks(single, s0)) {
      const want = single.findings.filter((f) => counted(f) && f.file === t.file).map((f) => f.id).sort();
      expect(t.groups.flatMap((g) => g.findings.map((f) => f.id)).sort()).toEqual(want);
      expect(t.count).toBe(want.length);
    }
  });

  it("leave out uncounted findings (expected, harness)", () => {
    const exp = single.findings.find((f) => f.expected && f.file)!;
    const t = trackOf(single, exp.file!);
    expect(t.groups.flatMap((g) => g.findings).some((f) => f.id === exp.id)).toBe(false);
  });

  it("place pins at line / last_line", () => {
    for (const t of tracks(single, s0, 0)) {
      const g = single.header.guides.find((x) => x.file === t.file)!;
      for (const p of t.groups) expect(p.at).toBeCloseTo(p.findings[0]!.line! / g.last_line, 10);
    }
  });
});

describe("pin groups", () => {
  it("group the close pins in single.json and leave the others alone", () => {
    const t = trackOf(single, longGuide.file);
    const big = t.groups.filter((g) => g.findings.length > 1);
    expect(big).toHaveLength(1);
    expect(lines(big[0]!.findings)).toEqual([300, 303]);
    expect(big[0]!.at).toBeGreaterThanOrEqual(300 / longGuide.last_line);
    expect(big[0]!.at).toBeLessThanOrEqual(303 / longGuide.last_line);
    for (const g of t.groups.filter((x) => x !== big[0])) expect(g.findings).toHaveLength(1);
    // Groups run in line order.
    const ats = t.groups.map((g) => g.at);
    expect(ats).toEqual([...ats].sort((a, b) => a - b));
  });

  it("minGap = 0 gives one pin per group", () => {
    for (const t of tracks(single, s0, 0)) for (const g of t.groups) expect(g.findings).toHaveLength(1);
  });

  it("a wide minGap chains neighbours into one group", () => {
    const t = trackOf(single, longGuide.file, s0, 1);
    expect(t.groups).toHaveLength(1);
    expect(lines(t.groups[0]!.findings)).toEqual([...lines(t.groups[0]!.findings)].sort((a, b) => a! - b!));
  });

  it("a filter that excludes a finding removes its pin", () => {
    // Drop the severity of the line-303 pin: the line-300 pin stands alone.
    const at303 = single.findings.find((f) => f.file === longGuide.file && f.line === 303)!;
    const sev = new Set([...s0.sev].filter((x) => x !== at303.severity));
    const t = trackOf(single, longGuide.file, { ...s0, sev });
    const all = t.groups.flatMap((g) => g.findings);
    expect(all.some((f) => f.id === at303.id)).toBe(false);
    expect(t.groups.every((g) => g.findings.length === 1)).toBe(true);
    expect(t.count).toBe(all.length);
  });
});

describe("levelText", () => {
  it("one combo: declared range, entered, left", () => {
    const g = single.header.guides.find((x) => x.flags.some((f) => f.rule === "enter-under"))!;
    const lv = Object.values(g.levels)[0]!;
    expect(trackOf(single, g.file).levelText).toBe(
      `${g.start_level}–${g.end_level} · entered ${lv.enter}, left ${lv.leave}`,
    );
    expect(trackOf(single, single.header.guides[0]!.file).levelText).toBe("1–5 · entered 1, left 5");
  });

  it("several combos: the min–max of enter and of leave", () => {
    const sm = defaultState(matrix);
    const byFile = (pred: (n: number) => boolean) =>
      matrix.header.guides.find((g) => pred(Object.keys(g.levels).length))!;
    // Combos entering a guide at different levels, one of them cut short.
    const wes = matrix.header.guides.find((g) => g.flags.some((f) => f.rule === "enter-over"))!;
    expect(trackOf(matrix, wes.file, sm).levelText).toBe("12–15 · entered 12–16, left 14–16");
    // Every combo entered and left at the same level: no range.
    const three = byFile((n) => n === 3);
    expect(trackOf(matrix, three.file, sm).levelText).toBe("1–5 · entered 1, left 5");
    const mid = matrix.header.guides.find((g) => new Set(Object.values(g.levels).map((l) => l.enter)).size > 1 && g !== wes)!;
    expect(trackOf(matrix, mid.file, sm).levelText).toBe("5–11 · entered 5–7, left 11");
  });

  it("no declared range: only entered and left", () => {
    const doc = structuredClone(single);
    const g = doc.header.guides[1]!;
    delete g.start_level;
    delete g.end_level;
    const lv = Object.values(g.levels)[0]!;
    expect(trackOf(doc, g.file).levelText).toBe(`entered ${lv.enter}, left ${lv.leave}`);
  });

  it("perCombo lists each character's levels by display name", () => {
    const wes = matrix.header.guides.find((g) => g.flags.some((f) => f.rule === "enter-over"))!;
    const t = trackOf(matrix, wes.file, defaultState(matrix));
    expect(t.perCombo).toEqual(
      Object.entries(wes.levels).map(([c, l]) => ({ combo: matrix.labels.combos[c] ?? c, enter: l.enter, leave: l.leave })),
    );
  });
});

describe("flags", () => {
  it("group combos by rule, named through labels.combos", () => {
    const wes = matrix.header.guides.find((g) => g.flags.some((f) => f.rule === "enter-over"))!;
    const t = trackOf(matrix, wes.file, defaultState(matrix));
    const over = wes.flags.filter((f) => f.rule === "enter-over").map((f) => matrix.labels.combos[f.combo]);
    expect(t.flags).toEqual([{ rule: "enter-over", combos: over }]);
    expect(over).toEqual(["Gnome Priest"]);
  });

  it("merge several combos under one rule", () => {
    const doc = structuredClone(matrix);
    const g = doc.header.guides[0]!;
    g.flags = [
      { combo: "Gnome MAGE none", rule: "leave-under" },
      { combo: "Dwarf WARRIOR none", rule: "enter-under" },
      { combo: "Gnome PRIEST none", rule: "leave-under" },
    ];
    expect(trackOf(doc, g.file, defaultState(doc)).flags).toEqual([
      { rule: "leave-under", combos: ["Gnome Mage", "Gnome Priest"] },
      { rule: "enter-under", combos: ["Dwarf Warrior"] },
    ]);
  });

  it("a guide without flags has none", () => {
    expect(trackOf(single, single.header.guides[0]!.file).flags).toEqual([]);
  });
});

describe("scaleTicks", () => {
  it("round steps from 0, at most max ticks, within last_line", () => {
    expect(scaleTicks(600)).toEqual([0, 100, 200, 300, 400, 500, 600]);
    expect(scaleTicks(220)).toEqual([0, 50, 100, 150, 200]);
    expect(scaleTicks(180, 4)).toEqual([0, 50, 100, 150]);
    expect(scaleTicks(7)).toEqual([0, 2, 4, 6]);
  });
  it("never more than max + 1 ticks", () => {
    for (const n of [1, 9, 33, 101, 999, 1234, 5000]) expect(scaleTicks(n, 5).length).toBeLessThanOrEqual(6);
  });
});

describe("gapFor: a minGap from the rail's rendered width", () => {
  it("is the widest marker plus 2px over the rail width", () => {
    expect(gapFor(320)).toBeCloseTo(24 / 320, 10);
    expect(gapFor(400, 16)).toBeCloseTo(18 / 400, 10);
  });
  it("falls back to MIN_GAP when no width is known", () => {
    expect(gapFor(0)).toBe(MIN_GAP);
    expect(gapFor(Number.NaN)).toBe(MIN_GAP);
  });

  it("a narrow rail groups the 300/303 pins, and pins the default keeps apart", () => {
    const narrow = gapFor(320);
    const big = trackOf(single, longGuide.file, s0, narrow).groups.find((g) => g.findings.length > 1)!;
    expect(lines(big.findings)).toEqual(expect.arrayContaining([300, 303]));
    // Some pair of pins sits in separate groups at the default but one group on a narrow rail.
    const sizes = (gap: number) => tracks(single, s0, gap).flatMap((t) => t.groups.map((g) => g.findings.length));
    expect(sizes(narrow).length).toBeLessThan(sizes(MIN_GAP).length);
    const apart = tracks(single, s0).flatMap((t) => t.groups);
    const together = tracks(single, s0, narrow).flatMap((t) => t.groups).filter((g) => g.findings.length > 1);
    const merged = together.some((g) => new Set(g.findings.map((f) => apart.find((a) => a.findings.includes(f)))).size > 1);
    expect(merged).toBe(true);
  });

  it("no two groups on a track are closer than the minGap passed in", () => {
    for (const gap of [0, MIN_GAP, gapFor(680), gapFor(320), gapFor(120)])
      for (const doc of [single, matrix])
        for (const t of tracks(doc, defaultState(doc), gap))
          for (let i = 1; i < t.groups.length; i++)
            expect(t.groups[i]!.at - t.groups[i - 1]!.at).toBeGreaterThanOrEqual(gap);
  });
});

describe("track target (ruling R12)", () => {
  it("a file with its own section in Guide order jumps to the section", () => {
    for (const t of tracks(single, s0)) expect(t.target).toEqual({ kind: "section", file: t.file });
  });

  it("a file with no matching findings has no target", () => {
    const file = new Set([...s0.file].filter((x) => x !== longGuide.file));
    expect(trackOf(single, longGuide.file, { ...s0, file }).target).toBeNull();
  });

  it("a file whose matching findings all nest under another file's card jumps to the first of them", () => {
    const doc = structuredClone(single);
    const child = doc.findings.find((f) => f.caused_by && f.file !== undefined && counted(doc.findings.find((c) => c.id === f.caused_by)!))!;
    const root = doc.findings.find((f) => f.id === child.caused_by)!;
    const other = doc.header.guides.find((g) => g.file !== root.file)!.file;
    // Move the follow-on into another guide that has nothing else.
    doc.findings = doc.findings.filter((f) => f === child || f.file !== other);
    child.file = other;
    const t = trackOf(doc, other, defaultState(doc));
    expect(t.count).toBe(1);
    expect(t.target).toEqual({ kind: "card", id: child.id });
  });
});
