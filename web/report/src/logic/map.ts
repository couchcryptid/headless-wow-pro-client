// The guide map (spec §4.4): one track per guide, pins at line / last_line,
// close pins grouped so none hides another, level text and flags. Pure; no DOM.
import type { Finding, GuideEntry, ReportDoc } from "../types";
import { matches } from "./filter";
import { guideSections } from "./order";
import { counted, shortFile, type FilterState } from "./state";

export interface PinGroup {
  /** Position on the track, 0..1. */
  at: number;
  /** In line order. */
  findings: Finding[];
}

export interface TrackFlag {
  rule: string;
  /** Display names, through labels.combos. */
  combos: string[];
}

export interface ComboLevels {
  /** Display name, through labels.combos. */
  combo: string;
  enter: number;
  leave: number;
}

export interface Track {
  file: string;
  label: string;
  /** Pins on this track: the matching counted findings in the file. */
  count: number;
  levelText: string;
  flags: TrackFlag[];
  perCombo: ComboLevels[];
  groups: PinGroup[];
  /**
   * The file's own Guide-order section; else, when its matching findings all
   * nest under another file's cards, the first of them by line; else null (no
   * jump: the name is drawn disabled).
   */
  target: TrackTarget | null;
}

/**
 * Fallback grouping gap (a share of the track) for when the rail's rendered
 * width isn't known, e.g. before the first layout. It is not tied to any
 * marker size: the page always passes gapFor(measured width) once it can.
 */
export const MIN_GAP = 0.012;

/** Widest marker on the full map: the group pill's min-width (styles.css `.pin.grp`). */
export const PILL_PX = 22;

/**
 * The grouping gap for a rail `railPx` wide: the widest marker plus 2px, as a
 * share of the rail. Groups whose centres are at least this far apart can't
 * overlap. Falls back to MIN_GAP when the width is unknown (0 or NaN).
 */
export function gapFor(railPx: number, markerPx = PILL_PX): number {
  return railPx > 0 ? (markerPx + 2) / railPx : MIN_GAP;
}

/** Where a track name's click goes in Guide order (ruling R12). */
export type TrackTarget = { kind: "section"; file: string } | { kind: "card"; id: string };

/** "7", or "5–7" when the values differ. */
function span(xs: number[]): string {
  const lo = Math.min(...xs);
  const hi = Math.max(...xs);
  return lo === hi ? `${lo}` : `${lo}–${hi}`;
}

function levelText(g: GuideEntry, per: ComboLevels[]): string {
  const run = per.length > 0 ? `entered ${span(per.map((p) => p.enter))}, left ${span(per.map((p) => p.leave))}` : "";
  const declared = g.start_level !== undefined && g.end_level !== undefined ? `${g.start_level}–${g.end_level}` : "";
  return [declared, run].filter((x) => x !== "").join(" · ");
}

function groupPins(pins: { at: number; f: Finding }[], minGap: number): PinGroup[] {
  const out: { first: number; last: number; findings: Finding[] }[] = [];
  for (const p of pins) {
    const cur = out[out.length - 1];
    // Chained: each pin is compared with the previous pin in the current group.
    if (cur && p.at - cur.last < minGap) {
      cur.findings.push(p.f);
      cur.last = p.at;
    } else out.push({ first: p.at, last: p.at, findings: [p.f] });
  }
  return out.map((g) => ({ at: (g.first + g.last) / 2, findings: g.findings }));
}

export function tracks(doc: ReportDoc, s: FilterState, minGap = MIN_GAP): Track[] {
  const name = (c: string) => doc.labels.combos[c] ?? c;
  const sections = new Set(guideSections(doc, s).map((x) => x.file));
  return doc.header.guides.map((g) => {
    const pins = doc.findings
      .filter((f) => f.file === g.file && f.line !== undefined && counted(f) && matches(f, s))
      .map((f) => ({ at: Math.min(1, Math.max(0, f.line! / Math.max(1, g.last_line))), f }))
      .sort((a, b) => a.at - b.at || a.f.line! - b.f.line! || (a.f.id < b.f.id ? -1 : a.f.id > b.f.id ? 1 : 0));

    const perCombo = Object.entries(g.levels).map(([c, l]) => ({ combo: name(c), enter: l.enter, leave: l.leave }));

    // Grouped by rule, in order of first appearance.
    const byRule = new Map<string, string[]>();
    for (const fl of g.flags) {
      const list = byRule.get(fl.rule) ?? [];
      if (!list.includes(name(fl.combo))) list.push(name(fl.combo));
      byRule.set(fl.rule, list);
    }

    return {
      file: g.file,
      label: shortFile(g.file),
      count: pins.length,
      levelText: levelText(g, perCombo),
      flags: [...byRule].map(([rule, combos]) => ({ rule, combos })),
      perCombo,
      groups: groupPins(pins, minGap),
      target: sections.has(g.file)
        ? { kind: "section", file: g.file }
        : pins.length > 0
          ? { kind: "card", id: pins[0]!.f.id }
          : null,
    };
  });
}

/** Line-number scale: 0 and multiples of a round step (1, 2, 5 × 10^k), at most `max` steps. */
export function scaleTicks(lastLine: number, max = 6): number[] {
  const last = Math.max(1, lastLine);
  let step = 1;
  for (let k = 1; ; k *= 10) {
    const s = [1, 2, 5].map((m) => m * k).find((x) => last / x <= max);
    if (s !== undefined) {
      step = s;
      break;
    }
  }
  const out: number[] = [];
  for (let v = 0; v <= last; v += step) out.push(v);
  return out;
}
