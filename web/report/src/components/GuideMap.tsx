// The guide map (spec §4.4): one track per guide, pins per finding, level text
// and flags. A compact copy stays pinned to the top of the main column once the
// full map scrolls away. Layout comes from logic/map; this file only renders.
import type { ComponentChildren } from "preact";
import { useContext, useEffect, useRef, useState } from "preact/hooks";
import { SEVERITY_ORDER } from "../logic/state";
import { scaleTicks, tracks, type PinGroup, type Track } from "../logic/map";
import type { Finding } from "../types";
import { PageContext, plural, scrollToEl, shortFile } from "./context";

interface Actions {
  /** Scroll to a finding's card and highlight it. */
  onPin: (f: Finding) => void;
  /** Switch to Guide order and jump to the file's section. */
  onFile: (file: string) => void;
}

/** Group key: the file and its first finding (stable while the group exists). */
const groupKey = (t: Track, g: PinGroup) => `${t.file}|${g.findings[0]!.id}`;

/** The group's colour: its most severe finding. */
function worst(g: PinGroup): string {
  const rank = (f: Finding) => {
    const i = SEVERITY_ORDER.indexOf(f.severity ?? "");
    return i < 0 ? SEVERITY_ORDER.length : i;
  };
  return g.findings.reduce((a, b) => (rank(b) < rank(a) ? b : a)).severity ?? "none";
}

/** Tooltip box; shown by CSS on the parent's hover or keyboard focus, with no delay. */
function Tip({ at, children }: { at: number; children: ComponentChildren }) {
  const edge = at < 0.18 ? " tip-l" : at > 0.82 ? " tip-r" : "";
  return (
    <span class={`tip${edge}`} aria-hidden="true">
      {children}
    </span>
  );
}

function Pin({ f, at, mini, actions }: { f: Finding; at: number; mini: boolean; actions: Actions }) {
  const { doc } = useContext(PageContext);
  const sev = f.severity ?? "none";
  const sevWord = doc.labels.severities[sev] ?? sev;
  const loc = `${shortFile(f.file!)}:${f.line}`;
  return (
    <button
      type="button"
      class={`pin sev-${sev}${f.caused_by ? " follow" : ""}`}
      style={{ left: `${at * 100}%` }}
      tabIndex={mini ? -1 : undefined}
      aria-label={`${f.title}, ${loc}, ${sevWord}`}
      onClick={() => actions.onPin(f)}
    >
      <Tip at={at}>
        <span class="tip-title">{f.title}</span>
        <span class="tip-meta">
          <span class="mono">{loc}</span>
          <span class={`tip-sev sev-${sev}`}>
            <span class={`dot sev-${sev}`} />
            {sevWord}
          </span>
        </span>
      </Tip>
    </button>
  );
}

function Group({
  t,
  g,
  open,
  mini,
  onToggle,
}: {
  t: Track;
  g: PinGroup;
  open: boolean;
  mini: boolean;
  onToggle: () => void;
}) {
  const first = g.findings[0]!.line;
  const last = g.findings[g.findings.length - 1]!.line;
  const where = first === last ? `line ${first}` : `lines ${first}–${last}`;
  const sev = worst(g);
  return (
    <button
      type="button"
      class={`pin grp sev-${sev}`}
      style={{ left: `${g.at * 100}%` }}
      tabIndex={mini ? -1 : undefined}
      aria-expanded={open}
      aria-label={`${plural(g.findings.length, "finding")}, ${t.label} ${where}`}
      onClick={onToggle}
    >
      <span class="grp-n" aria-hidden="true">
        {g.findings.length}
      </span>
      <Tip at={g.at}>
        <span class="tip-meta">
          <span>{plural(g.findings.length, "finding")}</span>
          <span class="mono">
            {t.label} {where}
          </span>
        </span>
        <span class="tip-list">
          {g.findings.map((f) => (
            <span class="tip-row" key={f.id}>
              <span class={`dot sev-${f.severity ?? "none"}`} />
              <span>{f.title}</span>
            </span>
          ))}
        </span>
        {!open && <span class="tip-hint">Click to spread out</span>}
      </Tip>
    </button>
  );
}

/** An open group, spread out under its track: one button per finding. */
function Spread({ g, actions, mini }: { g: PinGroup; actions: Actions; mini: boolean }) {
  return (
    <ul class="spread" style={{ "--at": `${g.at * 100}%` }}>
      {g.findings.map((f) => (
        <li key={f.id}>
          <button
            type="button"
            class={`spread-pin${f.caused_by ? " follow" : ""}`}
            tabIndex={mini ? -1 : undefined}
            onClick={() => actions.onPin(f)}
          >
            <span class={`dot sev-${f.severity ?? "none"}`} aria-hidden="true" />
            <span class="mono">{f.line}</span>
            <span class="spread-title">{f.title}</span>
          </button>
        </li>
      ))}
    </ul>
  );
}

function Flags({ t }: { t: Track }) {
  const { doc } = useContext(PageContext);
  if (t.flags.length === 0) return null;
  const lines = t.flags.map((fl) => `${doc.labels.flags[fl.rule] ?? fl.rule}: ${fl.combos.join(", ")}`);
  return (
    <span class="flag" tabIndex={0} role="img" aria-label={lines.join(". ")}>
      <span class="flag-mark" aria-hidden="true">
        ▲{t.flags.length > 1 ? t.flags.length : ""}
      </span>
      <Tip at={0}>
        {t.flags.map((fl) => (
          <span class="tip-row" key={fl.rule}>
            <span class="tip-title">{doc.labels.flags[fl.rule] ?? fl.rule}</span>
            <span>{fl.combos.join(", ")}</span>
          </span>
        ))}
      </Tip>
    </span>
  );
}

/** The level text; for several characters a hover lists each one's levels. */
function Levels({ t }: { t: Track }) {
  if (t.levelText === "") return null;
  if (t.perCombo.length < 2) return <span class="lv">{t.levelText}</span>;
  const each = t.perCombo.map((p) => `${p.combo}: entered ${p.enter}, left ${p.leave}`);
  return (
    <span class="lv has-tip" tabIndex={0} aria-label={`${t.levelText}. ${each.join(". ")}`}>
      {t.levelText}
      <Tip at={0}>
        {t.perCombo.map((p) => (
          <span class="tip-row" key={p.combo}>
            <span class="tip-title">{p.combo}</span>
            <span class="mono">
              entered {p.enter}, left {p.leave}
            </span>
          </span>
        ))}
      </Tip>
    </span>
  );
}

function TrackRow({
  t,
  mini,
  open,
  setOpen,
  actions,
}: {
  t: Track;
  mini: boolean;
  open: string | null;
  setOpen: (k: string | null) => void;
  actions: Actions;
}) {
  const { doc } = useContext(PageContext);
  const last = doc.header.guides.find((g) => g.file === t.file)?.last_line ?? 1;
  const spread = t.groups.find((g) => g.findings.length > 1 && groupKey(t, g) === open);
  return (
    <li class={`trk${t.flags.length ? " flagged" : ""}`}>
      <div class="trk-name">
        <span class="trk-line">
          <button type="button" class="trk-file" tabIndex={mini ? -1 : undefined} onClick={() => actions.onFile(t.file)}>
            {t.label}
          </button>
          {!mini && <Flags t={t} />}
          {mini && t.flags.length > 0 && <span class="flag-mark" aria-hidden="true">▲</span>}
          {mini && <span class="trk-n">{t.count}</span>}
        </span>
        {!mini && (
          <span class="trk-sub">
            <span>{plural(t.count, "finding")}</span>
            <Levels t={t} />
          </span>
        )}
      </div>
      <div class="rail-wrap">
        <div class="rail">
          {t.groups.map((g) =>
            g.findings.length === 1 ? (
              <Pin key={g.findings[0]!.id} f={g.findings[0]!} at={g.at} mini={mini} actions={actions} />
            ) : (
              <Group
                key={groupKey(t, g)}
                t={t}
                g={g}
                mini={mini}
                open={groupKey(t, g) === open}
                onToggle={() => setOpen(groupKey(t, g) === open ? null : groupKey(t, g))}
              />
            ),
          )}
        </div>
        {!mini && (
          <div class="scale" aria-hidden="true">
            {scaleTicks(last).map((n) => (
              <span key={n} style={{ left: `${(n / Math.max(1, last)) * 100}%` }}>
                {n}
              </span>
            ))}
          </div>
        )}
        {spread && <Spread g={spread} actions={actions} mini={mini} />}
      </div>
    </li>
  );
}

export function GuideMap({ onPin, onFile }: Actions) {
  const { doc, s } = useContext(PageContext);
  const ts = tracks(doc, s);
  const [open, setOpen] = useState<string | null>(null);
  const [away, setAway] = useState(false);
  const full = useRef<HTMLElement>(null);
  // Jumping to a card closes any spread-out group, so the pinned copy doesn't cover the card.
  const actions = {
    onPin: (f: Finding) => {
      setOpen(null);
      onPin(f);
    },
    onFile,
  };

  // The compact copy shows once the full map has scrolled up out of view.
  useEffect(() => {
    const el = full.current;
    if (!el || typeof IntersectionObserver === "undefined") return;
    const io = new IntersectionObserver(([e]) => setAway(!e!.isIntersecting && e!.boundingClientRect.top < 0));
    io.observe(el);
    return () => io.disconnect();
  }, []);

  // The main column reserves room for the compact copy so sticky heads and
  // scrolled-to cards sit below it.
  useEffect(() => {
    const main = full.current?.closest<HTMLElement>(".main");
    main?.style.setProperty("--stick", away ? "var(--mini-h)" : "0px");
    main?.style.setProperty("--mini-h", `${ts.length * 22 + 14}px`);
  }, [away, ts.length]);

  if (ts.length === 0) return null;
  const rows = (mini: boolean) =>
    ts.map((t) => <TrackRow key={t.file} t={t} mini={mini} open={open} setOpen={setOpen} actions={actions} />);

  return (
    <>
      <div class="mini-anchor">
        {away && (
          <nav class="map mini" aria-label="Guide map, compact">
            <ol class="tracks">{rows(true)}</ol>
            <button type="button" class="mini-back" onClick={() => full.current && scrollToEl(full.current)}>
              Back to map
            </button>
          </nav>
        )}
      </div>
      <section class="map full" ref={full} tabIndex={-1} aria-label="Guide map">
        <ol class="tracks">{rows(false)}</ol>
      </section>
    </>
  );
}
