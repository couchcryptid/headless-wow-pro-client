// One finding (spec §4.6), with its shown follow-ons nested below it.
import { useContext, useState } from "preact/hooks";
import { cardChildren } from "../logic/filter";
import { counted, location } from "../logic/state";
import type { Finding, StepRef } from "../types";
import { PageContext, cardId, comboLabel } from "./context";
import { StepKey } from "./StepKey";

function Step({ step, me }: { step?: StepRef; me?: boolean }) {
  const { doc } = useContext(PageContext);
  if (!step) return null;
  const verb = step.action ? doc.labels.actions[step.action] : undefined;
  return (
    <li class={me ? "step me" : "step"} aria-current={me ? "step" : undefined}>
      {step.action && (
        <kbd class="cap" title={verb}>
          {step.action}
        </kbd>
      )}
      <span class="step-text">
        {verb && <span class="verb">{verb} </span>}
        {step.name}
      </span>
    </li>
  );
}

function Steps({ f }: { f: Finding }) {
  if (!f.before && !f.after && !f.step?.action) return null;
  return (
    <div class="steps">
      <ol aria-label="Where in the guide">
        <Step step={f.before} />
        <Step step={f.step} me />
        <Step step={f.after} />
      </ol>
      <StepKey />
    </div>
  );
}

function Detail({ f }: { f: Finding }) {
  const reasons = f.reasons ?? [];
  const empty = !f.why && reasons.length === 0 && !f.message && !f.stack;
  return (
    <div class="detail" id={`detail-${f.id}`}>
      {empty && <p class="muted">No engine detail recorded.</p>}
      {f.why && (
        <div>
          <span class="dlabel">why</span>
          <code>{f.why}</code>
        </div>
      )}
      {reasons.length > 0 && (
        <div>
          <span class="dlabel">reasons</span>
          <code>{reasons.join(", ")}</code>
        </div>
      )}
      {f.message && (
        <div>
          <span class="dlabel">message</span>
          <code>{f.message}</code>
        </div>
      )}
      {f.stack && (
        <div>
          <span class="dlabel">stack</span>
          <pre>{f.stack}</pre>
        </div>
      )}
    </div>
  );
}

function FollowsFrom({ f }: { f: Finding }) {
  const { byId, goToCause } = useContext(PageContext);
  const cause = f.caused_by ? byId.get(f.caused_by) : undefined;
  if (!cause) return null;
  // An uncounted cause (harness or expected) lives in a fold, which filters never hide.
  const filtered = counted(cause);
  return (
    <p class="follows">
      <button type="button" class="linkish" onClick={() => goToCause(cause)}>
        Follows from {cause.title}
        {filtered ? " (hidden by filters)" : ""}
      </button>
    </p>
  );
}

/** sectionFile: the file of the Guide-order section the card sits in; omitted elsewhere. */
export function Card({ f, sectionFile }: { f: Finding; sectionFile?: string }) {
  const page = useContext(PageContext);
  const { doc, s, multi, lifted } = page;
  const [open, setOpen] = useState(false);
  const kids = cardChildren(f, doc, s);
  // Expected findings carry no severity: no dot, a neutral edge.
  const sev = f.severity ?? "none";
  const sevLabel = f.severity ? (doc.labels.severities[f.severity] ?? f.severity) : undefined;

  const meta: string[] = [];
  const loc = location(f, sectionFile);
  if (loc !== undefined) meta.push(loc);
  if (f.qid !== undefined) meta.push(`quest ${f.qid}`);
  if (f.level !== undefined) meta.push(`level ${f.level}`);

  return (
    <article class={`card sev-${sev}`} id={cardId(f.id)} tabIndex={-1} aria-label={f.title}>
      <header class="card-top">
        {sevLabel && (
          <span class={`dot sev-${sev}`} title={sevLabel}>
            <span class="sr">{sevLabel}</span>
          </span>
        )}
        <h3 class="card-title">{f.title}</h3>
        {(f.explains ?? 0) > 0 && <span class="chip">explains {f.explains} more</span>}
      </header>
      <p class="meta">
        {meta.map((m) => (
          <span class="mono" key={m}>
            {m}
          </span>
        ))}
        <span class="kind">{doc.labels.signals[f.signal] ?? f.signal}</span>
      </p>
      {multi && f.combos && f.combos.length > 0 && (
        <p class="combos">{f.combos.map((c) => comboLabel(doc, c)).join(", ")}</p>
      )}
      {lifted.has(f.id) && <FollowsFrom f={f} />}
      {f.sentence && <p class="sentence">{f.sentence}</p>}
      <Steps f={f} />
      {f.grind && (
        <p class="grind">
          Grind: {f.grind.kills} kills to level {f.grind.to}
        </p>
      )}
      <footer class="card-foot">
        <button
          type="button"
          class="fid"
          aria-expanded={open}
          aria-controls={`detail-${f.id}`}
          onClick={() => setOpen(!open)}
        >
          <span class="twist" aria-hidden="true">
            {open ? "▾" : "▸"}
          </span>
          {f.id} · {f.signal}
        </button>
        {open && <Detail f={f} />}
      </footer>
      {kids.length > 0 && (
        <div class="kids">
          {kids.map((k) => (
            <Card key={k.id} f={k} sectionFile={sectionFile} />
          ))}
        </div>
      )}
    </article>
  );
}
