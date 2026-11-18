// Matching, lifting and counts. A filter must never hide a finding silently:
// a matching follow-on whose ancestor does not match is lifted to the top level.
import type { Finding, ReportDoc } from "../types";
import { counted, defaultState, fileKey, type FilterState } from "./state";

export type Group = "sev" | "file" | "kind" | "combo";
const GROUPS: Group[] = ["sev", "file", "kind", "combo"];

function textMatches(f: Finding, q: string): boolean {
  const needle = q.trim().toLowerCase();
  if (needle === "") return true;
  const loc = f.file !== undefined ? `${f.file}:${f.line}` : "";
  if (/^\d+$/.test(needle)) {
    if (f.qid === Number(needle)) return true;
    const token = new RegExp(`(?<!\\d)${needle}(?!\\d)`);
    return [f.title, loc, f.id].some((t) => token.test(t));
  }
  return [f.title, f.qname ?? "", loc, f.id].some((t) => t.toLowerCase().includes(needle));
}

function inGroup(f: Finding, s: FilterState, g: Group): boolean {
  switch (g) {
    case "sev":
      return f.severity !== undefined && s.sev.has(f.severity);
    case "file":
      return s.file.has(fileKey(f));
    case "kind":
      return s.kind.has(f.signal);
    case "combo":
      // A finding that records no combos cannot be excluded by a combo filter.
      return !f.combos || f.combos.length === 0 || f.combos.some((c) => s.combo.has(c));
  }
}

function matchesExcept(f: Finding, s: FilterState, skip?: Group): boolean {
  return textMatches(f, s.q) && GROUPS.every((g) => g === skip || inGroup(f, s, g));
}

export function matches(f: Finding, s: FilterState): boolean {
  return matchesExcept(f, s);
}

function byId(doc: ReportDoc): Map<string, Finding> {
  return new Map(doc.findings.map((f) => [f.id, f]));
}

function ancestors(f: Finding, ids: Map<string, Finding>): Finding[] {
  const out: Finding[] = [];
  const seen = new Set<string>([f.id]);
  let cur = f.caused_by ? ids.get(f.caused_by) : undefined;
  // Stop at the first uncounted ancestor: childrenShown never walks through one,
  // so a finding below it must be lifted rather than left unreachable.
  while (cur && counted(cur) && !seen.has(cur.id)) {
    out.push(cur);
    seen.add(cur.id);
    cur = cur.caused_by ? ids.get(cur.caused_by) : undefined;
  }
  return out;
}

export function visible(doc: ReportDoc, s: FilterState): { roots: Finding[]; lifted: Finding[] } {
  const ids = byId(doc);
  const roots: Finding[] = [];
  const lifted: Finding[] = [];
  for (const f of doc.findings) {
    if (!counted(f) || !matches(f, s)) continue;
    if (!f.caused_by) roots.push(f);
    // Lifted only when no counted ancestor matches; otherwise childrenShown nests it.
    else if (!ancestors(f, ids).some((a) => matches(a, s))) lifted.push(f);
  }
  return { roots, lifted };
}

function hasMatchingDescendant(f: Finding, ids: Map<string, Finding>, s: FilterState, seen: Set<string>): boolean {
  for (const id of f.causes ?? []) {
    const c = ids.get(id);
    if (!c || !counted(c) || seen.has(c.id)) continue;
    seen.add(c.id);
    if (matches(c, s) || hasMatchingDescendant(c, ids, s, seen)) return true;
  }
  return false;
}

export function childrenShown(f: Finding, doc: ReportDoc, s: FilterState): Finding[] {
  const ids = byId(doc);
  const out: Finding[] = [];
  for (const id of f.causes ?? []) {
    const c = ids.get(id);
    if (!c || !counted(c)) continue;
    if (matches(c, s) || hasMatchingDescendant(c, ids, s, new Set([f.id, c.id]))) out.push(c);
  }
  return out;
}

export interface Counts {
  shown: number;
  total: number;
  options: Record<Group, Record<string, number>>;
}

function optionValues(f: Finding, g: Group): string[] {
  switch (g) {
    case "sev":
      return f.severity ? [f.severity] : [];
    case "file":
      return [fileKey(f)];
    case "kind":
      return [f.signal];
    case "combo":
      return f.combos ?? [];
  }
}

export function counts(doc: ReportDoc, s: FilterState): Counts {
  const all = doc.findings.filter(counted);
  const d = defaultState(doc);
  const options = { sev: {}, file: {}, kind: {}, combo: {} } as Counts["options"];
  for (const g of GROUPS) {
    const tally: Record<string, number> = {};
    for (const v of d[g]) tally[v] = 0;
    for (const f of all) {
      if (!matchesExcept(f, s, g)) continue;
      for (const v of optionValues(f, g)) tally[v] = (tally[v] ?? 0) + 1;
    }
    options[g] = tally;
  }
  return { shown: all.filter((f) => matches(f, s)).length, total: all.length, options };
}

/**
 * The follow-ons a card nests. An uncounted card (a harness or expected fold entry)
 * nests none: visible() already lifts its counted follow-ons to the top level, so
 * nesting them too would show them twice.
 */
export function cardChildren(f: Finding, doc: ReportDoc, s: FilterState): Finding[] {
  return counted(f) ? childrenShown(f, doc, s) : [];
}
