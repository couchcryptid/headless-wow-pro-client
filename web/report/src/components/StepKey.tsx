// The key to WoWPro's step letters, one click away from every step strip.
import { useContext, useEffect, useRef, useState } from "preact/hooks";
import { PageContext } from "./context";

export function StepKey() {
  const { doc } = useContext(PageContext);
  const [open, setOpen] = useState(false);
  const root = useRef<HTMLSpanElement>(null);

  useEffect(() => {
    if (!open) return;
    const away = (e: Event) => {
      if (root.current && !root.current.contains(e.target as Node)) setOpen(false);
    };
    const esc = (e: KeyboardEvent) => {
      if (e.key === "Escape") {
        setOpen(false);
        root.current?.querySelector("button")?.focus();
      }
    };
    document.addEventListener("click", away);
    document.addEventListener("focusin", away);
    document.addEventListener("keydown", esc);
    return () => {
      document.removeEventListener("click", away);
      document.removeEventListener("focusin", away);
      document.removeEventListener("keydown", esc);
    };
  }, [open]);

  const entries = Object.entries(doc.labels.actions).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return (
    <span class="stepkey" ref={root}>
      <button
        type="button"
        class="stepkey-btn"
        aria-expanded={open}
        aria-label="Step key"
        title="Step key"
        onClick={() => setOpen(!open)}
      >
        ?
      </button>
      {open && (
        <div class="stepkey-pop" role="group" aria-label="Step key">
          <dl>
            {entries.map(([letter, verb]) => (
              <div key={letter}>
                <dt>
                  <kbd class="cap">{letter}</kbd>
                </dt>
                <dd>{verb.replace(/:$/, "")}</dd>
              </div>
            ))}
          </dl>
        </div>
      )}
    </span>
  );
}
