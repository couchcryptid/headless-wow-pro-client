// Section ordering for the two views. Pure; no DOM.
import type { Finding, ReportDoc } from "../types";
import { matches, visible } from "./filter";
import { counted, universe, type FilterState } from "./state";

export interface PrioritySection {
  severity: string;
  primary: number;
  follow: number;
  cards: Finding[];
}

export interface GuideSection {
  file: string | null;
  cards: Finding[];
}

function cmp(a: number, b: number): number {
  return a === b ? 0 : a < b ? -1 : 1;
}

export function prioritySections(doc: ReportDoc, s: FilterState): PrioritySection[] {
  const guideIndex = new Map(doc.header.guides.map((g, i) => [g.file, i]));
  const rank = (f: Finding) => (f.file !== undefined && guideIndex.has(f.file) ? guideIndex.get(f.file)! : Infinity);
  const v = visible(doc, s);
  const cards = [...v.roots, ...v.lifted];
  const shown = doc.findings.filter((f) => counted(f) && matches(f, s));
  return universe(doc)
    .sev.map((severity) => {
      const mine = cards
        .filter((f) => f.severity === severity)
        .sort(
          (a, b) =>
            cmp(b.explains ?? 0, a.explains ?? 0) ||
            cmp(a.confidence === "verified" ? 0 : 1, b.confidence === "verified" ? 0 : 1) ||
            cmp(rank(a), rank(b)) ||
            cmp(a.line ?? Infinity, b.line ?? Infinity) ||
            cmp(a.id < b.id ? -1 : a.id > b.id ? 1 : 0, 0),
        );
      const same = shown.filter((f) => f.severity === severity);
      return {
        severity,
        primary: same.filter((f) => !f.caused_by).length,
        follow: same.filter((f) => f.caused_by).length,
        cards: mine,
      };
    })
    .filter((x) => x.cards.length > 0 || x.primary + x.follow > 0);
}

export function guideSections(doc: ReportDoc, s: FilterState): GuideSection[] {
  const v = visible(doc, s);
  const cards = [...v.roots, ...v.lifted];
  const known = new Set(doc.header.guides.map((g) => g.file));
  const byLine = (a: Finding, b: Finding) =>
    cmp(a.line ?? Infinity, b.line ?? Infinity) || cmp(a.id < b.id ? -1 : a.id > b.id ? 1 : 0, 0);
  const out: GuideSection[] = doc.header.guides.map((g) => ({
    file: g.file as string | null,
    cards: cards.filter((f) => f.file === g.file).sort(byLine),
  }));
  out.push({ file: null, cards: cards.filter((f) => f.file === undefined || !known.has(f.file)).sort(byLine) });
  return out.filter((x) => x.cards.length > 0);
}
