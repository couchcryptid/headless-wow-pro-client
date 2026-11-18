// What every component reads: the document, the filter state and the page's
// navigation actions. Display helpers only; no filtering, counting or sorting.
import { createContext } from "preact";
import type { FilterState } from "../logic/state";
import type { Finding, ReportDoc } from "../types";

export type FoldKey = "harness" | "expected" | "about";

export interface Page {
  doc: ReportDoc;
  s: FilterState;
  /** The run has more than one character. */
  multi: boolean;
  /** Ids of follow-ons lifted to the top level because their cause is filtered out. */
  lifted: Set<string>;
  byId: Map<string, Finding>;
  /** Reset the filters, then scroll to a finding's card (or its fold entry). */
  goToCause: (f: Finding) => void;
}

export const PageContext = createContext<Page>(null as unknown as Page);

export const cardId = (id: string) => `card-${id}`;
export const foldId = (k: FoldKey) => `fold-${k}`;
/** Id of a guide file's section in Guide order. */
export const fileSecId = (file: string) => `file-${file.replace(/[^\w-]/g, "_")}`;

export { shortFile } from "../logic/state";

export function comboLabel(doc: ReportDoc, c: string): string {
  return doc.labels.combos[c] ?? c;
}

export function plural(n: number, one: string, many = `${one}s`): string {
  return `${n} ${n === 1 ? one : many}`;
}

/** Scroll smoothly unless the reader asked for reduced motion. */
export function scrollToEl(el: HTMLElement) {
  const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  el.scrollIntoView({ behavior: reduce ? "auto" : "smooth", block: "start" });
  el.focus({ preventScroll: true });
  el.classList.remove("flash");
  void el.offsetWidth;
  el.classList.add("flash");
}
