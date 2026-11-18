// Filter state and the "counted" rule. Pure; no DOM.
import type { Finding, ReportDoc } from "../types";

export type Order = "prio" | "guide";

export interface FilterState {
  q: string;
  sev: Set<string>;
  file: Set<string>;
  kind: Set<string>;
  combo: Set<string>;
  order: Order;
}

/** File option for findings that carry no file (shown under "Addon code"). */
export const NO_FILE = "(no file)";

export const SEVERITY_ORDER = ["high", "medium-high", "medium", "low"];

/** The guide file's short name: its basename without ".lua". */
export function shortFile(p: string): string {
  if (p === NO_FILE) return "Addon code";
  return (p.split("/").pop() ?? p).replace(/\.lua$/, "");
}

/** The file option a finding belongs to. */
export function fileKey(f: Finding): string {
  return f.file ?? NO_FILE;
}

/** Mirrors Lua's report.is_harness. */
export function isHarness(f: Finding): boolean {
  return f.signal === "missing-global" || (f.signal === "lua-error" && f.harness === true);
}

/** Only counted findings are shown, listed or tallied. */
export function counted(f: Finding): boolean {
  return f.severity !== undefined && !f.expected && !isHarness(f);
}

/** Every option the page can offer, in a stable order. */
export function universe(doc: ReportDoc) {
  const sev = [...SEVERITY_ORDER, ...Object.keys(doc.labels.severities).filter((k) => !SEVERITY_ORDER.includes(k))];
  const uniq = (xs: string[]) => [...new Set(xs)];
  return {
    sev: uniq(sev),
    file: uniq([...doc.header.guides.map((g) => g.file), ...doc.findings.map(fileKey), NO_FILE]),
    kind: uniq([...Object.keys(doc.labels.signals), ...doc.findings.map((f) => f.signal)]),
    combo: uniq([...doc.header.matrix.combos, ...doc.findings.flatMap((f) => f.combos ?? [])]),
  };
}

export function defaultState(doc: ReportDoc): FilterState {
  const u = universe(doc);
  return {
    q: "",
    sev: new Set(u.sev),
    file: new Set(u.file),
    kind: new Set(u.kind),
    combo: new Set(u.combo),
    order: "prio",
  };
}
