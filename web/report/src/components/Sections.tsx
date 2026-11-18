// The Order switch and the cards in Priority or Guide order (spec §4.5).
import { useContext } from "preact/hooks";
import { guideSections, prioritySections } from "../logic/order";
import type { Order } from "../logic/state";
import { Card } from "./Card";
import { PageContext, fileSecId, shortFile } from "./context";

export function OrderSwitch({ onOrder }: { onOrder: (o: Order) => void }) {
  const { s } = useContext(PageContext);
  const opt = (o: Order, label: string) => (
    <button type="button" class="seg" aria-pressed={s.order === o} onClick={() => onOrder(o)}>
      {label}
    </button>
  );
  return (
    <div class="order" role="group" aria-label="Order">
      <span class="order-label">Order</span>
      <span class="segs">
        {opt("prio", "Priority")}
        {opt("guide", "Guide order")}
      </span>
    </div>
  );
}

function PriorityView() {
  const { doc, s } = useContext(PageContext);
  return (
    <>
      {prioritySections(doc, s).map((sec) => (
        <section class="section" key={sec.severity} aria-labelledby={`sec-${sec.severity}`}>
          <h2 class="section-head" id={`sec-${sec.severity}`}>
            <span class={`dot sev-${sec.severity}`} aria-hidden="true" />
            <span class="section-name">{doc.labels.severities[sec.severity] ?? sec.severity}</span>
            <span class="section-count">
              {sec.primary} primary · {sec.follow} follow-on
            </span>
          </h2>
          {sec.cards.map((f) => (
            <Card key={f.id} f={f} showFile />
          ))}
        </section>
      ))}
    </>
  );
}

function GuideView() {
  const { doc, s } = useContext(PageContext);
  return (
    <>
      {guideSections(doc, s).map((sec) => (
        <section
          class="section file"
          key={sec.file ?? ""}
          id={sec.file ? fileSecId(sec.file) : undefined}
          tabIndex={-1}
          aria-label={sec.file ? shortFile(sec.file) : "Addon code"}
        >
          <h2 class="section-head sticky">
            <span class="section-name">{sec.file ? shortFile(sec.file) : "Addon code"}</span>
            {sec.file && <span class="section-path mono">{sec.file}</span>}
          </h2>
          {sec.cards.map((f) => (
            <Card key={f.id} f={f} showFile={false} />
          ))}
        </section>
      ))}
    </>
  );
}

export function Sections() {
  const { s } = useContext(PageContext);
  return <div class="sections">{s.order === "guide" ? <GuideView /> : <PriorityView />}</div>;
}
