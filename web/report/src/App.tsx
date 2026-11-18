import type { ReportDoc } from "./types";

export function App({ doc }: { doc: ReportDoc }) {
  return (
    <main>
      <h1>hwc findings report</h1>
      <p>{doc.summary.findings} findings</p>
    </main>
  );
}
