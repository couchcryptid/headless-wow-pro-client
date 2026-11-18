import { readFileSync } from "node:fs";
import { join } from "node:path";
import type { Finding, ReportDoc } from "../../src/types";

const dir = join(__dirname, "../../../../spec/fixtures/findings");

export function load(name: "single" | "matrix" | "empty"): ReportDoc {
  return JSON.parse(readFileSync(join(dir, `${name}.json`), "utf8")) as ReportDoc;
}

/** The one finding matching the predicate; throws unless exactly one does. */
export function pick(doc: ReportDoc, pred: (f: Finding) => boolean): Finding {
  const hits = doc.findings.filter(pred);
  if (hits.length !== 1) throw new Error(`expected one finding, got ${hits.length}`);
  return hits[0]!;
}
