// Title, run line, warnings and early stops (spec §4.2, §4.8).
import { useContext } from "preact/hooks";
import type { ReportDoc } from "../types";
import { PageContext, comboLabel, plural } from "./context";

/** One character's label, or "N characters (races)" for a matrix run. */
function who(doc: ReportDoc): string {
  const combos = doc.header.matrix.combos;
  if (combos.length === 0) return "Findings";
  if (combos.length === 1) return comboLabel(doc, combos[0]);
  // A label is "<race> <class>" with an optional "(professions)": the race is all but the last word.
  const races = combos.map((c) => {
    const l = comboLabel(doc, c).replace(/ \([^)]*\)$/, "");
    return l.replace(/ \S+$/, "") || l;
  });
  return `${combos.length} characters (${[...new Set(races)].sort().join(", ")})`;
}

/** The browser tab's title: who, the run date, and what the page is. */
export function pageTitle(doc: ReportDoc): string {
  return [who(doc), doc.header.date, "hwc findings"].filter((p) => p).join(" · ");
}

function runLine(doc: ReportDoc): string[] {
  const h = doc.header;
  const parts: string[] = [];
  if (h.date) parts.push(h.date);
  const a = h.addon;
  if (a.git === false) parts.push(`WoW-Pro ${a.version ? `${a.version} ` : ""}(not a git folder)`);
  else if (a.branch || a.commit) {
    let s = "WoW-Pro";
    if (a.branch) s += ` ${a.branch === "HEAD" ? "detached" : a.branch}`;
    if (a.commit) s += ` @ ${a.commit.slice(0, 7)}`;
    parts.push(s);
  }
  const n = h.matrix.combos.length;
  if (n > 0) parts.push(plural(n, "character"));
  if (h.scope) parts.push(h.scope);
  return parts;
}

export function Header({ shown, total, follow, filterOn }: { shown: number; total: number; follow: number; filterOn: boolean }) {
  const { doc } = useContext(PageContext);
  const h = doc.header;
  let count: string;
  if (total === 0) count = "no findings";
  else if (filterOn) count = `${shown} of ${plural(total, "finding")}`;
  else count = plural(total, "finding");
  if (total > 0 && follow > 0) count += `, ${follow} ${follow === 1 ? "follows" : "follow"} from others`;

  return (
    <header class="top">
      <h1 class="title">
        <span class="who">{who(doc)}:</span> <span class="count">{count}</span>
      </h1>
      <p class="runline">
        {runLine(doc).map((p) => (
          <span key={p}>{p}</span>
        ))}
      </p>
      {(h.warnings.length > 0 || (h.stop ?? []).length > 0) && (
        <ul class="warnings">
          {(h.stop ?? []).map((st) => (
            <li class="stop" key={`${st.combo}-${st.reason}`}>
              {comboLabel(doc, st.combo)}: {doc.labels.stops[st.reason] ?? st.reason}
            </li>
          ))}
          {h.warnings.map((w) => (
            <li key={w}>{w}</li>
          ))}
        </ul>
      )}
    </header>
  );
}
