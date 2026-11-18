import { describe, expect, it } from "vitest";
import { visible } from "../../src/logic/filter";
import { guideSections, prioritySections } from "../../src/logic/order";
import { defaultState } from "../../src/logic/state";
import { load } from "./helpers";

const single = load("single");
const s0 = defaultState(single);

describe("prioritySections", () => {
  const secs = prioritySections(single, s0);
  const high = secs.find((x) => x.severity === "high")!;
  const ids = (xs: { id: string }[]) => xs.map((f) => f.id);
  const idOf = (pred: (f: (typeof single.findings)[number]) => boolean) => single.findings.find(pred)!.id;

  it("lists severities in order", () => {
    expect(secs.map((x) => x.severity)).toEqual(["high", "medium-high", "medium", "low"]);
  });
  it("follow-ons are not top-level cards unless lifted", () => {
    // single.json's one lifted finding (qid 530) follows from an uncounted harness notice.
    const lifted = new Set(visible(single, s0).lifted.map((f) => f.id));
    expect(lifted.size).toBe(1);
    for (const sec of secs) for (const c of sec.cards) if (!lifted.has(c.id)) expect(c.caused_by).toBeUndefined();
    expect(high.primary).toBe(8);
    expect(high.follow).toBe(3); // 93, 94 and the cross-file 95, all under the 96393 refusal
  });
  it("orders by explains, verified, guide order, line, id", () => {
    const q = (n: number) => idOf((f) => f.qid === n && !f.caused_by);
    expect(ids(high.cards)).toEqual([
      q(96393), // explains 3
      q(200), // explains 1, verified, Dun_1_5 line 100
      q(430), // explains 1, verified, Dun_5_11
      q(310), // explains 0, verified, Dun_1_5 line 170
      q(420), // verified, Dun_5_11 line 51
      q(500), // verified, Dun_11_14
      idOf((f) => f.signal === "lua-error" && f.file !== undefined), // unverified, Dun_5_11 line 99
      idOf((f) => f.signal === "lua-error" && f.file === undefined), // no file: last
    ]);
  });
  it("the file-less lua-error sorts last in its severity", () => {
    expect(high.cards[high.cards.length - 1]!.signal).toBe("lua-error");
    expect(high.cards[high.cards.length - 1]!.file).toBeUndefined();
  });
  it("a lifted follow-on becomes a card", () => {
    const s = { ...s0, q: "doesn't advance" };
    const med = prioritySections(single, s).find((x) => x.severity === "medium")!;
    expect(med.cards.some((c) => c.caused_by)).toBe(true);
    expect(med.follow).toBeGreaterThan(0);
  });
});

describe("guideSections", () => {
  const secs = guideSections(single, s0);
  it("follows header.guides order then Addon code last", () => {
    expect(secs.map((x) => x.file)).toEqual([...single.header.guides.map((g) => g.file), null]);
  });
  it("sorts each section by line", () => {
    for (const sec of secs) {
      const lines = sec.cards.map((c) => c.line ?? Infinity);
      expect(lines).toEqual([...lines].sort((a, b) => a - b));
    }
  });
  it("the last section holds the file-less lua-error", () => {
    const last = secs[secs.length - 1]!;
    expect(last.file).toBeNull();
    expect(last.cards.map((c) => c.signal)).toEqual(["lua-error"]);
  });
  it("holds exactly the visible cards", () => {
    const v = visible(single, s0);
    expect(secs.flatMap((x) => x.cards).length).toBe(v.roots.length + v.lifted.length);
  });
});
