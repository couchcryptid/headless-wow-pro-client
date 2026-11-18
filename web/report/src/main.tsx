import { render } from "preact";
import { App } from "./App";
import type { ReportDoc } from "./types";

const doc = JSON.parse(document.getElementById("report")!.textContent!) as ReportDoc;
render(<App doc={doc} />, document.getElementById("app")!);
