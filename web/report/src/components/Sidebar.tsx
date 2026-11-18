// Search, filter groups and the "Also in this run" links (spec §4.3).
import type { ComponentChildren } from "preact";
import { useContext, useState } from "preact/hooks";
import type { Counts, Group } from "../logic/filter";
import type { FilterState } from "../logic/state";
import { PageContext, comboLabel, foldId, shortFile, type FoldKey } from "./context";

interface Props {
  counts: Counts;
  /** Option counts with no filter on: an option that is 0 here can never match, so it is not offered. */
  base: Counts["options"];
  filterOn: boolean;
  folds: { harness: number; expected: number };
  onState: (s: FilterState) => void;
  onReset: () => void;
  onFold: (k: FoldKey) => void;
}

function FilterGroup({ title, children }: { title: string; children: ComponentChildren }) {
  return (
    <fieldset class="group">
      <legend>{title}</legend>
      {children}
    </fieldset>
  );
}

export function Sidebar({ counts, base, filterOn, folds, onState, onReset, onFold }: Props) {
  const { doc, s, multi } = useContext(PageContext);
  const [open, setOpen] = useState(false);

  const toggle = (key: Group, v: string) => {
    const next = new Set(s[key]);
    if (next.has(v)) next.delete(v);
    else next.add(v);
    onState({ ...s, [key]: next });
  };

  const options = (key: Group, label: (v: string) => ComponentChildren) =>
    Object.keys(counts.options[key])
      .filter((v) => (base[key][v] ?? 0) > 0)
      .map((v) => {
        const n = counts.options[key][v];
        return (
          <label class={n === 0 ? "opt zero" : "opt"} key={v}>
            <input type="checkbox" checked={s[key].has(v)} onChange={() => toggle(key, v)} />
            <span class="opt-label">{label(v)}</span>
            <span class="n">{n}</span>
          </label>
        );
      });

  const foldLink = (k: FoldKey, label: string, n?: number) => (
    <li>
      <a
        href={`#${foldId(k)}`}
        onClick={(e) => {
          // The hash holds the filters, so the link must not replace it.
          e.preventDefault();
          onFold(k);
        }}
      >
        {label}
      </a>
      {n !== undefined && <span class="n">{n}</span>}
    </li>
  );

  const sev = options("sev", (v) => (
    <>
      <span class={`dot sev-${v}`} aria-hidden="true" />
      {doc.labels.severities[v] ?? v}
    </>
  ));
  const combo = options("combo", (v) => comboLabel(doc, v));
  const file = options("file", (v) => <span title={v}>{shortFile(v)}</span>);
  const kind = options("kind", (v) => doc.labels.signals[v] ?? v);

  return (
    <aside class={open ? "side open" : "side"} aria-label="Filters">
      <button type="button" class="side-toggle" aria-expanded={open} aria-controls="side-body" onClick={() => setOpen(!open)}>
        <span aria-hidden="true">{open ? "▾" : "▸"}</span> Filters
        {filterOn && <span class="side-toggle-n">{counts.shown} of {counts.total}</span>}
      </button>
      <div class="side-body" id="side-body">
        {counts.total > 0 && (
        <label class="search">
          <span class="search-label">Search</span>
          <input
            type="search"
            value={s.q}
            placeholder="Title, quest, file:line or F- id"
            onInput={(e) => onState({ ...s, q: (e.target as HTMLInputElement).value })}
          />
        </label>
        )}
        {filterOn && (
          <button type="button" class="reset" onClick={onReset}>
            Clear filters
          </button>
        )}
        {sev.length > 0 && <FilterGroup title="Severity">{sev}</FilterGroup>}
        {multi && combo.length > 0 && <FilterGroup title="Character">{combo}</FilterGroup>}
        {file.length > 0 && <FilterGroup title="Guide file">{file}</FilterGroup>}
        {kind.length > 0 && <FilterGroup title="Kind">{kind}</FilterGroup>}
        <nav class="also" aria-label="Also in this run">
          <h2>Also in this run</h2>
          <ul>
            {foldLink("harness", "Harness notices", folds.harness)}
            {foldLink("expected", "Expected manual clicks", folds.expected)}
            {foldLink("about", "About this run")}
          </ul>
        </nav>
      </div>
    </aside>
  );
}
