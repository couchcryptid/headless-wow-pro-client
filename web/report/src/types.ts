// The format-2 findings document written by the Lua CLI (spec §5).
// Every other module imports the shape from here.

export type Severity = "high" | "medium-high" | "medium" | "low";

export interface StepRef {
  action: string;
  name: string;
}

export interface Finding {
  id: string;
  signal: string;
  title: string;
  sentence: string;
  /** Absent on expected findings. */
  severity?: Severity;
  confidence?: "verified" | "unverified";
  action?: string;
  name?: string;
  step?: StepRef;
  before?: StepRef;
  after?: StepRef;
  gid?: string;
  file?: string;
  line?: number;
  qid?: number;
  qname?: string;
  level?: number;
  log?: number[];
  combos?: string[];
  reasons?: string[];
  why?: string;
  use?: string;
  /** Item id (as a string) to quantity. */
  loot?: Record<string, number>;
  grind?: { kills: number; to: number };
  message?: string;
  stack?: string;
  /** Id of the finding this one follows from. */
  caused_by?: string;
  /** Ids of findings that follow from this one. */
  causes?: string[];
  /** Count of counted descendants (primary findings only). */
  explains?: number;
  expected?: boolean;
  /** Set on a lua-error raised in harness code rather than the addon. */
  harness?: boolean;
}

export interface GuideLevels {
  enter: number;
  leave: number;
  finished: boolean;
}

export type FlagRule = "enter-under" | "leave-under" | "enter-over";

export interface GuideFlag {
  combo: string;
  rule: FlagRule;
}

export interface GuideEntry {
  file: string;
  gid: string;
  last_line: number;
  /** The guide's declared range; absent when the guide declares none. */
  start_level?: number;
  end_level?: number;
  levels: Record<string, GuideLevels>;
  flags: GuideFlag[];
}

/** One catalog source's provenance, as the run recorded it. */
export interface CatalogSource {
  present?: boolean;
  reason?: string;
  path?: string;
  tag?: string;
  build?: string;
  commit?: string;
  /** One hash, or one per file (questie). */
  sha256?: string | Record<string, string>;
}

export interface Header {
  addon: {
    branch: string | null;
    commit: string | null;
    dirty: boolean;
    git: boolean;
    path: string;
    version: string;
  };
  client: { commit: string; dirty: boolean };
  /** Absent when the run recorded no catalog sources. */
  catalog?: Record<string, CatalogSource>;
  date: string;
  gaps: string[];
  guides: GuideEntry[];
  matrix: { combos: string[] };
  notes: Record<string, string>;
  paths_relative_to: string;
  rank: number;
  scope: string;
  stop?: { combo: string; reason: string }[];
  warnings: string[];
}

export type SeverityCounts = Record<string, { primary: number; follow: number }>;

export interface Summary {
  findings: number;
  roots: number;
  by_severity: Record<string, number>;
  by_signal: Record<string, number>;
  by_file: Record<string, SeverityCounts>;
  by_combo: Record<string, SeverityCounts>;
}

export interface Labels {
  signals: Record<string, string>;
  actions: Record<string, string>;
  combos: Record<string, string>;
  severities: Record<string, string>;
  folds: Record<string, string>;
  stops: Record<string, string>;
  /** Level-flag rule to its wording (the map's flag tooltips). */
  flags: Record<string, string>;
}

export interface ReportDoc {
  format: 2;
  header: Header;
  summary: Summary;
  labels: Labels;
  findings: Finding[];
}
