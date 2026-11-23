# Forever client table fixtures

These CSVs are trimmed test data (a header line plus a handful of rows each)
from the wago.tools DB2 exports of Forever build 1.60.1.70959. They are not
complete tables; do not treat them as game truth.

`installed/` holds these same CSVs run through `hwc.forever.convert` (the
installed store shape `{ columns, rows }`) plus a `.hwc-release.json`; its sha256
values are placeholders.
