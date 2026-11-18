// The page: holds the FilterState (mirrored in the URL hash) and the open folds,
// and hands everything else to the logic in ./logic.
import { useEffect, useMemo, useState } from "preact/hooks";
import { PageContext, cardId, foldId, scrollToEl, type FoldKey, type Page } from "./components/context";
import { Folds } from "./components/Folds";
import { Header } from "./components/Header";
import { OrderSwitch, Sections } from "./components/Sections";
import { Sidebar } from "./components/Sidebar";
import { counts, visible } from "./logic/filter";
import { fromHash, toHash } from "./logic/hash";
import { prioritySections } from "./logic/order";
import { counted, defaultState, isHarness, universe, type FilterState } from "./logic/state";
import "./styles.css";
import type { Finding, ReportDoc } from "./types";

export function App({ doc }: { doc: ReportDoc }) {
  const [s, setS] = useState<FilterState>(() => fromHash(location.hash, doc));
  const [open, setOpen] = useState<Set<FoldKey>>(() => new Set());
  // Element id to scroll to once the next render has put it on the page.
  const [pending, setPending] = useState<string | null>(null);

  useEffect(() => {
    const h = toHash(s, doc);
    const url = h === "" ? location.pathname + location.search : `#${h}`;
    history.replaceState(null, "", url);
  }, [s, doc]);

  useEffect(() => {
    const onHash = () => setS(fromHash(location.hash, doc));
    window.addEventListener("hashchange", onHash);
    return () => window.removeEventListener("hashchange", onHash);
  }, [doc]);

  useEffect(() => {
    if (!pending) return;
    const el = document.getElementById(pending);
    if (el) scrollToEl(el);
    setPending(null);
  }, [pending]);

  const byId = useMemo(() => new Map(doc.findings.map((f) => [f.id, f])), [doc]);
  const multi = useMemo(() => universe(doc).combo.length > 1, [doc]);
  const base = useMemo(() => counts(doc, defaultState(doc)).options, [doc]);
  const harness = useMemo(() => doc.findings.filter((f) => isHarness(f) && !f.expected), [doc]);
  const expected = useMemo(() => doc.findings.filter((f) => f.expected === true), [doc]);

  const c = counts(doc, s);
  const v = visible(doc, s);
  const follow = prioritySections(doc, s).reduce((n, sec) => n + sec.follow, 0);
  const filterOn = toHash({ ...s, order: "prio" }, doc) !== "";

  const openFold = (k: FoldKey) => {
    setOpen((o) => new Set(o).add(k));
    setPending(foldId(k));
  };
  const toggleFold = (k: FoldKey) =>
    setOpen((o) => {
      const n = new Set(o);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });

  const goToCause = (cause: Finding) => {
    if (counted(cause)) setS(defaultState(doc));
    else setOpen((o) => new Set(o).add(isHarness(cause) ? "harness" : "expected"));
    setPending(cardId(cause.id));
  };

  const reset = () => setS({ ...defaultState(doc), order: s.order });

  const page: Page = {
    doc,
    s,
    multi,
    lifted: new Set(v.lifted.map((f) => f.id)),
    byId,
    goToCause,
  };

  return (
    <PageContext.Provider value={page}>
      <div class="layout">
        <Sidebar
          counts={c}
          base={base}
          filterOn={filterOn}
          folds={{ harness: harness.length, expected: expected.length }}
          onState={setS}
          onReset={reset}
          onFold={openFold}
        />
        <main class="main">
          <Header shown={c.shown} total={c.total} follow={follow} filterOn={filterOn} />
          {c.total === 0 ? (
            <p class="empty">No findings</p>
          ) : (
            <>
              {/* Guide map (spec §4.4) goes here. */}
              <div class="map-slot" />
              <OrderSwitch onOrder={(order) => setS({ ...s, order })} />
              {c.shown === 0 ? (
                <div class="empty">
                  <p>No findings match these filters.</p>
                  <button type="button" class="reset" onClick={reset}>
                    Clear filters
                  </button>
                </div>
              ) : (
                <Sections />
              )}
            </>
          )}
          <Folds harness={harness} expected={expected} open={open} onToggle={toggleFold} />
        </main>
      </div>
    </PageContext.Provider>
  );
}
