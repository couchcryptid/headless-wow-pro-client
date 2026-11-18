// The folded sections below the cards (spec §4.7): harness notices, expected
// manual clicks and About this run. Left out of every count and filter above.
import type { ComponentChildren } from "preact";
import { useContext } from "preact/hooks";
import type { Finding, NoteKey, ReportDoc } from "../types";
import { Card } from "./Card";
import { PageContext, comboLabel, foldId, type FoldKey } from "./context";

function Fold(props: {
  k: FoldKey;
  title: string;
  n?: number;
  phrase?: string;
  open: boolean;
  onToggle: () => void;
  children: ComponentChildren;
}) {
  const { k, title, n, phrase, open, onToggle, children } = props;
  return (
    <section class={open ? "fold open" : "fold"} id={foldId(k)} tabIndex={-1} aria-labelledby={`${foldId(k)}-btn`}>
      <h2 class="fold-head">
        <button type="button" id={`${foldId(k)}-btn`} aria-expanded={open} aria-controls={`${foldId(k)}-body`} onClick={onToggle}>
          <span class="twist" aria-hidden="true">
            {open ? "▾" : "▸"}
          </span>
          <span class="fold-title">{title}</span>
          {n !== undefined && <span class="n">{n}</span>}
          {phrase && <span class="fold-phrase">{phrase}</span>}
        </button>
      </h2>
      {open && (
        <div class="fold-body" id={`${foldId(k)}-body`}>
          {children}
        </div>
      )}
    </section>
  );
}

function Entries({ list }: { list: Finding[] }) {
  if (list.length === 0) return <p class="muted">None in this run.</p>;
  return (
    <>
      {list.map((f) => (
        <Card key={f.id} f={f} />
      ))}
    </>
  );
}

function state(dirty: boolean | undefined): string | undefined {
  if (dirty === true) return "uncommitted changes";
  if (dirty === false) return "clean";
  return undefined;
}

function Row({ k, children }: { k: string; children: ComponentChildren }) {
  return (
    <div class="about-row">
      <dt>{k}</dt>
      <dd>{children}</dd>
    </div>
  );
}

function Catalog({ doc }: { doc: ReportDoc }) {
  const cat = doc.header.catalog ?? {};
  const names = Object.keys(cat).sort();
  if (names.length === 0) return null;
  return (
    <Row k="Catalog">
      <ul class="plain">
        {names.map((name) => {
          const c = cat[name];
          const parts: string[] = [];
          if (c.present === false) {
            parts.push(`absent${c.reason ? ` (${c.reason})` : ""}`);
            parts.push(c.path ?? "-");
          } else {
            parts.push("present");
            if (c.tag) parts.push(c.tag);
            if (c.build) parts.push(`build ${String(c.build).slice(0, 7)}`);
            if (c.commit) parts.push(`commit ${c.commit}`);
            if (typeof c.sha256 === "string") parts.push(`sha256 ${c.sha256.slice(0, 12)}`);
            if (c.path) parts.push(c.path);
          }
          const files = c.sha256 && typeof c.sha256 === "object" ? Object.keys(c.sha256).sort() : [];
          return (
            <li key={name}>
              <code>{name}</code>: {parts.join(" · ")}
              {files.length > 0 && (
                <ul class="plain hashes">
                  {files.map((file) => (
                    <li key={file}>
                      <code>{file}</code> <code>{String((c.sha256 as Record<string, string>)[file]).slice(0, 12)}</code>
                    </li>
                  ))}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
    </Row>
  );
}

function About({ doc }: { doc: ReportDoc }) {
  const h = doc.header;
  const a = h.addon;
  const addon: string[] = [];
  if (a.path) addon.push(a.path);
  if (a.git === false) {
    if (a.version) addon.push(`version ${a.version}`);
    addon.push("not a git folder");
  } else {
    if (a.branch) addon.push(a.branch === "HEAD" ? "detached" : `branch ${a.branch}`);
    if (a.commit) addon.push(`commit ${a.commit}`);
    const st = state(a.dirty);
    if (st) addon.push(st);
  }
  const client: string[] = [];
  if (h.client.commit) client.push(`commit ${h.client.commit}`);
  const cst = state(h.client.dirty);
  if (cst) client.push(cst);
  const keys: NoteKey[] = ["filters", "played", "unreached", "skipped_races", "rank", "dungeons", "jumped", "carried"];
  const notes = keys
    .map((k) => h.notes[k])
    .filter((n): n is string => typeof n === "string" && n !== "");

  return (
    <dl class="about">
      {addon.length > 0 && <Row k="WoW-Pro">{addon.join(" · ")}</Row>}
      {client.length > 0 && <Row k="Client">{client.join(" · ")}</Row>}
      {h.matrix.combos.length > 0 && <Row k="Characters">{h.matrix.combos.map((c) => comboLabel(doc, c)).join(", ")}</Row>}
      {notes.length > 0 && (
        <Row k="Run">
          <ul class="plain">
            {notes.map((n) => (
              <li key={n}>{n}</li>
            ))}
          </ul>
        </Row>
      )}
      <Catalog doc={doc} />
      {h.gaps.length > 0 && (
        <Row k="Not modelled">
          <ul class="gaps">
            {h.gaps.map((g) => (
              <li key={g}>{g}</li>
            ))}
          </ul>
        </Row>
      )}
      {h.paths_relative_to && (
        <Row k="Paths relative to">
          <code>{h.paths_relative_to}</code>
        </Row>
      )}
    </dl>
  );
}

export function Folds({
  harness,
  expected,
  open,
  onToggle,
}: {
  harness: Finding[];
  expected: Finding[];
  open: Set<FoldKey>;
  onToggle: (k: FoldKey) => void;
}) {
  const { doc } = useContext(PageContext);
  return (
    <div class="folds">
      <Fold
        k="harness"
        title="Harness notices"
        n={harness.length}
        phrase={doc.labels.folds.harness}
        open={open.has("harness")}
        onToggle={() => onToggle("harness")}
      >
        <Entries list={harness} />
      </Fold>
      <Fold
        k="expected"
        title="Expected manual clicks"
        n={expected.length}
        phrase={doc.labels.folds.expected}
        open={open.has("expected")}
        onToggle={() => onToggle("expected")}
      >
        <Entries list={expected} />
      </Fold>
      <Fold k="about" title="About this run" open={open.has("about")} onToggle={() => onToggle("about")}>
        <About doc={doc} />
      </Fold>
    </div>
  );
}
