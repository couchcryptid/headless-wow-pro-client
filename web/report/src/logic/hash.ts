// URL-hash state: q=…&sev=a,b&file=…&kind=…&char=…&order=guide
import type { ReportDoc } from "../types";
import { defaultState, type FilterState } from "./state";

type SetKey = "sev" | "file" | "kind" | "combo";
const SET_KEYS: [SetKey, string][] = [
  ["sev", "sev"],
  ["file", "file"],
  ["kind", "kind"],
  ["combo", "char"],
];

function sameSet(a: Set<string>, b: Set<string>): boolean {
  return a.size === b.size && [...a].every((x) => b.has(x));
}

export function toHash(s: FilterState, doc: ReportDoc): string {
  const d = defaultState(doc);
  const parts: string[] = [];
  if (s.q !== "") parts.push(`q=${encodeURIComponent(s.q)}`);
  for (const [key, name] of SET_KEYS) {
    if (sameSet(s[key], d[key])) continue;
    parts.push(`${name}=${[...s[key]].map(encodeURIComponent).join(",")}`);
  }
  if (s.order !== "prio") parts.push(`order=${s.order}`);
  return parts.join("&");
}

export function fromHash(h: string, doc: ReportDoc): FilterState {
  const s = defaultState(doc);
  const raw = h.replace(/^#/, "");
  if (raw === "") return s;
  for (const part of raw.split("&")) {
    const eq = part.indexOf("=");
    if (eq < 0) continue;
    const name = part.slice(0, eq);
    const val = part.slice(eq + 1);
    if (name === "q") s.q = decodeURIComponent(val);
    else if (name === "order") s.order = val === "guide" ? "guide" : "prio";
    else {
      const key = SET_KEYS.find(([, n]) => n === name)?.[0];
      if (key) s[key] = new Set(val === "" ? [] : val.split(",").map(decodeURIComponent));
    }
  }
  return s;
}
