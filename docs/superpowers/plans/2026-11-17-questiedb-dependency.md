# QuestieDB as a Managed Dependency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `hwc init`, `hwc doctor` and `hwc sync questie` manage the QuestieDB
Forever release under `~/.hwc/`. The catalog reads quests, NPCs, items, objects
and XP from that release, loaded unmodified in a sandbox per character, so
QuestieDB's own corrections apply.

**Architecture:**
- A new `src/hwc/questie/` package holds the installed-release store (`home`),
  GitHub release selection and the contract rule (`release`), curl/unzip
  (`http`), install/sync (`install`), the C_EncodingUtil stand-ins
  (`encoding`), TOC metadata (`tocmeta`), the sandboxed QuestieDB load
  (`addon`), and the adapter the catalog reads (`source`).
- `src/hwc/doctor.lua` builds the health report.
- The catalog swaps its raw-file loader (`catalog/questie.lua`, deleted) for a
  `Source`.

**Tech Stack:** LuaJIT 2.1, busted 2.3, luafilesystem, dkjson, LibDeflate
1.0.2-release (vendored, zlib licence), curl, unzip.

**Spec:** `docs/superpowers/specs/2026-11-17-questiedb-dependency-design.md`

## Global Constraints

- No QuestieDB file and no code from QuestieDB's source repo (`emulator/*`, `generator/vendor/BlizzardCBOR.lua`) is ever committed. QuestieDB is GPL-3.0; this repo is MIT.
- QuestieDB's files are loaded unmodified. hwc never patches, re-implements or reformats its corrections or its baked decoder.
- The store root is `$HWC_HOME` if set, else `$HOME/.hwc`. QuestieDB lives at `<root>/questie/<tag>/` (holding `QuestieDB/QuestieDB_Forever.toc`) plus `<root>/questie/<tag>/.hwc-release.json`, and `<root>/questie/active` holds one line, the tag.
- Releases: `github.com/Questie/QuestieDB`. Skip `draft` and `prerelease` (a moving `preview` prerelease exists). The asset name comes from the release's `release.json` entry whose `metadata[].flavor == "forever"`, never guessed.
- hwc is built against contract `4`. A release is accepted when `minSupportedContract <= 4 <= contractVersion`.
- The verified TOC header must have `X-Flavor: Forever` and `X-Mode: baked`. Ignore `QuestieDB_Camelot.toc`.
- Dynamic corrections read the character: `UnitClassBase("player")` → `cfg.class`, `UnitFactionGroup("player")` → `cfg.faction` (`"Alliance"`). `C_Seasons.GetActiveSeason()` → `0` (QuestieDB `src/corrections/register.lua:68-70`: "Offline and in the emulator … returns 0").
- `C_EncodingUtil.DecompressString(data, method)`: `0` = raw deflate, `1` = zlib. It errors `"C_EncodingUtil.DecompressString: invalid compressed data"` when the output is nil or the leftover isn't 0.
- `doctor` is read-only, and a network failure is a **warn**. Exit codes: `0`, or `1` when any check is **fail**. CLI usage errors exit `2`, as elsewhere in `cli.lua`.
- Earlier installed versions are never deleted automatically.

## Review Focus

1. **Several classes in one process** (`hwc matrix`): a WARRIOR combo followed by a MAGE combo must see each class's own corrected data, not the first combo's cached instance. This is pinned in Task 7 (`QuestDB 8315 nextQuestInChain`: WARRIOR 8316, MAGE 8381, loaded back to back).
2. **A download or verify that fails or is interrupted** leaves the previously active version active and byte-identical, with no `<tag>` directory and no staging directory left behind. This is pinned in Task 5.
3. **GitHub unreachable or rate-limited** (curl exit 22 on a 403, or no network): `doctor` prints a warn and still prints every other check, and `sync` names the failing URL and exits 1. This is pinned in Tasks 5 and 9.
4. **`active` names a tag whose directory was deleted, or a TOC that's missing**: doctor reports **fail** with `hwc sync questie --tag <tag>`, and the catalog records `present = false` (no crash) with the hint. This is pinned in Tasks 4, 8 and 9.
5. **`HOME` unset and no `HWC_HOME`**: `init`, `sync` and `doctor` print `hwc: HOME is not set; set HWC_HOME` and exit 2, with no nil concatenation. This is pinned in Tasks 4 and 10.

---

### Task 1: Baseline before the switch

Captures what the old loader produces, so Task 11 can explain the difference.
No code changes.

**Files:**
- Create: `docs/superpowers/plans/2026-11-17-questiedb-dependency-carryover.md`

- [ ] **Step 1: Record timings and findings on the old loader**

From `~/Projects/WoW-Pro-Guides`:
```sh
/usr/bin/time -p hwc boot --race Dwarf --class WARRIOR > /dev/null
/usr/bin/time -p hwc matrix --races Dwarf --out /tmp/hwc-baseline   # then keep only the WARRIOR and MAGE findings files
```
Copy `/tmp/hwc-baseline` to the scratchpad. Don't commit it, since findings
embed third-party data.

- [ ] **Step 2: Write the carryover doc**

Headings: `## Baseline (old loader, pin d57637f)` with the two `real` times
and the findings file names and counts per category. Leave
`## After (v<tag>)` and `## Differences explained` empty.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/plans/2026-11-17-questiedb-dependency-carryover.md
git commit -m "Record the old QuestieDB loader baseline"
```

---

### Task 2: C_EncodingUtil stand-ins (base64, inflate, CBOR)

**Files:**
- Create: `src/hwc/vendor/LibDeflate.lua` (verbatim from `SafeteeWoW/LibDeflate` tag `1.0.2-release`, keeping its zlib licence header), `src/hwc/vendor/LibDeflate.LICENSE.txt`
- Create: `src/hwc/questie/encoding.lua`
- Test: `spec/questie/encoding_spec.lua`

**Interfaces:**
- Produces:
  - `encoding.decode_base64(s: string) -> string`: standard alphabet with `=` padding; raises `"hwc: base64: invalid input"` on any other character.
  - `encoding.decompress(data: string, method: 0|1) -> string`: raises the exact message in Global Constraints; any other method raises `"C_EncodingUtil.DecompressString: unsupported compression method <m>"`.
  - `encoding.deserialize_cbor(bytes: string) -> any`
  - `encoding.c_encoding_util() -> { DecodeBase64, DecompressString, DeserializeCBOR }`: plain functions with the WoW signatures (not methods).

- [ ] **Step 1: Vendor LibDeflate**

Download `LibDeflate.lua` and `LICENSE.txt` from the `1.0.2-release` tag.
Record the sha256 of `LibDeflate.lua` in a comment at the top of
`encoding.lua`. Load it with `require("hwc.vendor.LibDeflate")`. LibDeflate
falls back to standalone mode when `LibStub` is absent; confirm that by reading
its header.

- [ ] **Step 2: Write the failing tests**

```lua
local enc = require("hwc.questie.encoding")
local function hex(h) return (h:gsub("%x%x", function(c) return string.char(tonumber(c, 16)) end)) end

describe("base64", function()
  it("decodes padded and unpadded tails", function()
    assert.are.equal("foobar", enc.decode_base64("Zm9vYmFy"))
    assert.are.equal("fo", enc.decode_base64("Zm8="))
    assert.are.equal("f", enc.decode_base64("Zg=="))
  end)
  it("rejects characters outside the alphabet", function()
    assert.has_error(function() enc.decode_base64("Zm9v!") end, "hwc: base64: invalid input")
  end)
end)

describe("decompress", function()
  local LD = require("hwc.vendor.LibDeflate")
  it("inflates zlib (1) and raw deflate (0)", function()
    assert.are.equal("hello hello hello", enc.decompress(LD:CompressZlib("hello hello hello"), 1))
    assert.are.equal("hello hello hello", enc.decompress(LD:CompressDeflate("hello hello hello"), 0))
  end)
  it("rejects trailing garbage like the client", function()
    assert.has_error(function() enc.decompress(LD:CompressZlib("x") .. "junk", 1) end,
      "C_EncodingUtil.DecompressString: invalid compressed data")
  end)
end)

-- RFC 8949 Appendix A vectors
describe("cbor", function()
  local cases = {
    { "00", 0 }, { "17", 23 }, { "1818", 24 }, { "1903e8", 1000 }, { "1a000f4240", 1000000 },
    { "1b000000e8d4a51000", 1000000000000 }, { "20", -1 }, { "3903e7", -1000 },
    { "f93c00", 1.0 }, { "fa47c35000", 100000.0 }, { "fb3ff199999999999a", 1.1 },
    { "f4", false }, { "f5", true }, { "6449455446", "IETF" }, { "4401020304", "\1\2\3\4" },
  }
  for _, c in ipairs(cases) do
    it("decodes " .. c[1], function() assert.are.equal(c[2], enc.deserialize_cbor(hex(c[1]))) end)
  end
  it("decodes null as nil, arrays 1-based with holes, and maps", function()
    assert.is_nil(enc.deserialize_cbor(hex("f6")))
    assert.are.same({ 1, { 2, 3 }, { 4, 5 } }, enc.deserialize_cbor(hex("8301820203820405")))
    local t = enc.deserialize_cbor(hex("8301f603"))
    assert.are.equal(1, t[1]); assert.is_nil(t[2]); assert.are.equal(3, t[3])
    assert.are.same({ a = 1, b = { 2, 3 } }, enc.deserialize_cbor(hex("a26161016162820203")))
    assert.are.same({ [1] = "x", [7] = "y" }, enc.deserialize_cbor(hex("a2016178076179")))
  end)
  it("decodes indefinite-length arrays and maps", function()
    assert.are.same({ 1, 2 }, enc.deserialize_cbor(hex("9f0102ff")))
    assert.are.same({ a = 1 }, enc.deserialize_cbor(hex("bf616101ff")))
  end)
  it("unwraps tags", function()
    assert.are.equal(1363896240, enc.deserialize_cbor(hex("c11a514b67b0")))
  end)
end)
```

- [ ] **Step 3: Run the tests and verify they fail**

Run: `~/.luarocks/bin/busted spec/questie/encoding_spec.lua`
Expected: FAIL with `module 'hwc.questie.encoding' not found`.

- [ ] **Step 4: Implement `src/hwc/questie/encoding.lua`**

- Base64 uses a 256-entry lookup and builds the output 3 bytes at a time with
  `bit` (LuaJIT).
- CBOR is a recursive-descent reader over a position index:
  - major types 0–7;
  - 64-bit integers kept in doubles (exact to 2^53);
  - half floats by the RFC's Appendix D algorithm, single and double via byte assembly;
  - byte and text strings become Lua strings;
  - null and undefined become nil;
  - indefinite lengths for strings, arrays and maps (break `0xff`);
  - a tag skips its number and returns the inner item.

Trailing bytes after the top item raise `"hwc: cbor: trailing data"`.

- [ ] **Step 5: Run the tests and verify they pass**

Run: `~/.luarocks/bin/busted spec/questie/encoding_spec.lua`
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
git add src/hwc/vendor src/hwc/questie/encoding.lua spec/questie/encoding_spec.lua
git commit -m "Add C_EncodingUtil stand-ins: base64, inflate (vendored LibDeflate), CBOR"
```

---

### Task 3: TOC metadata

**Files:**
- Create: `src/hwc/questie/tocmeta.lua`
- Test: `spec/questie/tocmeta_spec.lua`

**Interfaces:**
- Produces:
  - `tocmeta.parse(path: string) -> table<string,string>`: every `## Key: value` line in the whole file; raises `"hwc: questie: cannot read <path>"`. Cached per process, keyed by `path .. size .. modification`, and returned as the same table on a cache hit (read-only by convention).
  - `tocmeta.header(path) -> table<string,string>`: the `##` lines only up to the first line that is neither `##`, `#` nor blank. Never cached and cheap, for doctor and verify.

- [ ] **Step 1: Write the failing tests**

```lua
describe("tocmeta", function()
  local toc = require("hwc.questie.tocmeta")
  local path -- tmp file with: "## Interface: 16001\r\n# comment\n## X-Flavor: Forever\n\nsrc\\a.lua\n## X-Quest-2-S: pw==\n## Notes: a: b\n"
  it("parses every ## line, keeps colons in values, strips CR", function()
    local m = toc.parse(path)
    assert.are.equal("16001", m["Interface"]); assert.are.equal("Forever", m["X-Flavor"])
    assert.are.equal("pw==", m["X-Quest-2-S"]); assert.are.equal("a: b", m["Notes"])
  end)
  it("returns the cached table for an unchanged file", function()
    assert.are.equal(toc.parse(path), toc.parse(path))
  end)
  it("header stops at the first file line", function()
    local h = toc.header(path)
    assert.are.equal("Forever", h["X-Flavor"]); assert.is_nil(h["X-Quest-2-S"])
  end)
end)
```

- [ ] **Step 2: Run and see it fail**, then **Step 3: implement**, then **Step 4: run and see it pass**

Run: `~/.luarocks/bin/busted spec/questie/tocmeta_spec.lua`

`parse` reads the file in one `f:read("*a")` and walks it with
`gmatch("[^\n]+")`. Avoid per-line `io.lines` for the 17 MB file.

- [ ] **Step 5: Commit**

```bash
git add src/hwc/questie/tocmeta.lua spec/questie/tocmeta_spec.lua
git commit -m "Parse TOC ## metadata with a per-process cache"
```

---

### Task 4: The store under `~/.hwc`

**Files:**
- Create: `src/hwc/questie/home.lua`
- Test: `spec/questie/home_spec.lua`

**Interfaces:**
- Produces:
  - `home.root(env?: {hwc_home?, home?}) -> string | nil, err`. env defaults to `os.getenv`. `HWC_HOME` wins, else `HOME .. "/.hwc"`. With neither (or empty strings): `nil, "hwc: HOME is not set; set HWC_HOME"`.
  - `home.version_dir(root, tag) -> string`: `root/questie/tag`. `tag` must match `^v%d+%.%d+%.%d+$`, else raises `"hwc: questie: bad tag <tag>"`.
  - `home.active(root) -> tag | nil`: nil when the file is absent or empty.
  - `home.set_active(root, tag)`: writes `active.tmp`, then `os.rename`s it over `active`.
  - `home.active_dir(root) -> dir | nil, reason`: nil with `"none installed"` when no `active`, or `"broken: <tag>"` when `active` names a tag without `QuestieDB/QuestieDB_Forever.toc`.
  - `home.installed(root) -> {tag...}`: version-sorted; only dirs holding the TOC.
  - `home.read_release(root, tag) -> table | nil`: `.hwc-release.json` with `{tag, asset, size, sha256, downloaded_at}`.

- [ ] **Step 1: Write the failing tests**

Cover these, using a tmp root:
- `root{hwc_home="/x"} == "/x"`
- `root{home="/h"} == "/h/.hwc"`
- `root{home=false}` returns `nil, "hwc: HOME is not set; set HWC_HOME"`
- `version_dir(r, "../x")` raises
- `active` is nil, then `set_active(r,"v1.1.2")` makes it `"v1.1.2"`
- `active_dir` is `nil,"broken: v1.1.2"` before the TOC exists, and the dir after
- `installed` sorts `v1.10.0` after `v1.9.0`

- [ ] **Step 2: Run and see it fail.** **Step 3: Implement.** **Step 4: Run and see it pass.**

Run: `~/.luarocks/bin/busted spec/questie/home_spec.lua`

- [ ] **Step 5: Commit**

```bash
git add src/hwc/questie/home.lua spec/questie/home_spec.lua
git commit -m "Add the ~/.hwc QuestieDB store with an active-version pointer"
```

---

### Task 5: Release selection, the contract rule, curl, and install/sync

**Files:**
- Create: `src/hwc/questie/release.lua`, `src/hwc/questie/http.lua`, `src/hwc/questie/install.lua`
- Test: `spec/questie/release_spec.lua`, `spec/questie/install_spec.lua`, `spec/fixtures/questie/releases.json` (canned API list: `v1.2.0` draft, `preview` prerelease, `v1.1.3` with no Forever entry in its `release.json`, `v1.1.2` good), `spec/fixtures/questie/release-*.json`

**Interfaces:**
- Consumes: `home.*` (Task 4), `tocmeta.header` (Task 3), `hwc.json`.
- Produces:
  - `release.API = "https://api.github.com/repos/Questie/QuestieDB"`, `release.SUPPORTED_CONTRACT = 4`
  - `release.select(get_json, opts: {tag?}) -> {tag, asset_name, asset_url, asset_size, build_commit, skipped = {tag...}} | nil, err`
    - Without a tag: `GET API.."/releases?per_page=30"`, newest first. Skip drafts and prereleases, then take the first release whose `release.json` (fetched from that release's `release.json` asset `browser_download_url`) has a Forever entry. `skipped` lists the newer releases that had none.
    - With a tag: `GET API.."/releases/tags/"..tag`; no Forever entry gives `nil, "hwc: questie: <tag> has no Forever build"`.
    - `build_commit` is the release's `target_commitish`.
  - `release.contract_range(version_dir) -> {min, max} | nil, err`. Read as text from `QuestieDB/src/config.lua`, matching `config%.contractVersion%s*=%s*(%d+)` and `config%.minSupportedContract%s*=%s*(%d+)`. If `minSupportedContract` is absent, `min = max`. If `config.lua` is unreadable, fall back to the TOC header `X-Contract-Version` for both.
  - `release.contract_ok(range) -> true | false, msg`. `msg` is `"QuestieDB contract <min>-<max> does not include 4 (hwc is built for 4)"`.
  - `http.get_json(url) -> table | nil, err`: `curl -fsSL --max-time 15 -H 'Accept: application/vnd.github+json'`, with the URL single-quote-escaped. `err` is `"hwc: GET <url> failed (curl exit <n>)"`.
  - `http.download(url, path) -> true | nil, err`, with `--max-time 300`.
  - `http.unzip(zip, dest) -> true | nil, err`: `unzip -q`.
  - `install.sync(root, opts: {tag?}, deps?: {get_json, download, unzip}) -> {from, to, build, already, skipped} | nil, err`. `deps` defaults to `http`.
  - `install.verify(stage_dir, asset_size, zip_path) -> header | nil, err`
  - `install.init(root, deps?) -> {already: bool, sync_result?} | nil, err`

`install.sync` steps (spec §4.3):
1. Run `select`.
2. If `version_dir(to)` is already installed and verifies, `set_active` and return `already=true`.
3. Otherwise download to `<root>/questie/.stage-<tag>-<pid-ish random>/asset.zip` and check the zip's byte size against `asset_size`.
4. Unzip into the same stage dir, then `verify`:
   - the TOC exists;
   - `X-Flavor` is `Forever` and `X-Mode` is `baked`;
   - `contract_ok(contract_range(stage))`.
5. Write `.hwc-release.json` with the sha256 of the zip (`shasum -a 256` via `io.popen`), then delete `asset.zip`.
6. `os.rename(stage, version_dir)`, then `set_active`.
7. Remove the stage dir on **every** failure path (a pcall-wrapped body), and never touch `active` before step 6.

- [ ] **Step 1: Write the failing release tests**

These use a `get_json` that serves the fixtures by URL and records the URLs
asked for:
- `select({})` gives `tag == "v1.1.2"`, `skipped == {"v1.1.3"}`, and the asset name `QuestieDB-1.1.2-Forever.zip`
- `select({tag="v1.1.3"})` gives `nil, "hwc: questie: v1.1.3 has no Forever build"`
- a failed `get_json` passes the error through
- `contract_range` on a tmp `src/config.lua` containing `config.contractVersion = 5` and `config.minSupportedContract = 4` gives `{min=4,max=5}`, and `contract_ok` is true
- `{min=5,max=6}` gives false with the exact message

- [ ] **Step 2: Write the failing install tests**

Use fake deps: `download` writes N bytes, and `unzip` copies a tmp tree with
a TOC whose header is given per test, plus `src/config.lua`.
- A fresh root syncs to `v1.1.2`, `active == "v1.1.2"`, and `.hwc-release.json` has `tag`, `size` and `sha256`.
- Syncing again gives `already == true` and makes no download call.
- **Review Focus 2:** after a good v1.1.2 install, a sync to a `v1.1.3` (fixture variant with a Forever entry) fails in each case below. Each time, `active` is still `"v1.1.2"`, `v1.1.3` doesn't exist, and no `.stage-*` dir remains:
  - `download` raising;
  - `unzip` returning nil;
  - an `X-Flavor: Vanilla` header;
  - a size mismatch;
  - contract 5–6.
- **Review Focus 3:** a `get_json` returning `nil, "hwc: GET … failed (curl exit 22)"` makes `sync` return that error unchanged.
- `init` on a root with a good active version returns `already=true` and makes no `get_json` call.

- [ ] **Step 3: Run the tests and see them fail.** **Step 4: Implement the three modules.** **Step 5: Run the tests and see them pass.**

Run: `~/.luarocks/bin/busted spec/questie/release_spec.lua spec/questie/install_spec.lua`

- [ ] **Step 6: Commit**

```bash
git add src/hwc/questie/{release,http,install}.lua spec/questie/{release,install}_spec.lua spec/fixtures/questie
git commit -m "Select QuestieDB Forever releases and install them atomically"
```

---

### Task 6: Install a real release by hand (manual check, no commit)

- [ ] **Step 1:** Run
`luajit -e 'package.path="src/?.lua;src/?/init.lua;"..package.path; local h=require("hwc.questie.home"); print(require("hwc.questie.install").sync(h.root(), {}))'`
with `bin/hwc`'s `LUA_PATH`.
Expected: `~/.hwc/questie/v1.1.2/QuestieDB/QuestieDB_Forever.toc` exists and `~/.hwc/questie/active` reads `v1.1.2`.

This gives Tasks 7, 8 and 11 a real install.

---

### Task 7: Load QuestieDB per character

**Files:**
- Create: `src/hwc/questie/addon.lua`, `src/hwc/questie/source.lua`
- Test: `spec/questie/source_spec.lua` (unit), `spec/integration/questie_release_spec.lua` (pending without an install)

**Interfaces:**
- Consumes: `hwc.sandbox.new(cfg)`, `sb:run_file(path, addon, private)`, `hwc.toc.files(root, toc_rel, game)`, `tocmeta.parse`, `encoding.c_encoding_util`, `release.SUPPORTED_CONTRACT`.
- Produces:
  - `addon.load(version_dir, character: {class, faction}) -> lib, sb`. `lib` is QuestieDB's private addon table (the second vararg every file receives). It raises `"hwc: questie: <rel>: <msg>"` on the first file error, and raises on `lib.RequireContract(4)` returning false, with `"hwc: questie: " .. msg .. "; run hwc sync questie --tag <tag>"`.
  - `source.from_lib(lib, info: {path, tag, build, sha256}) -> Source`
  - `source.open(questie_dir, character) -> Source | nil, reason`: nil with `home.active_dir`-style reasons (`"none installed"`, `"broken: <tag>"`) when the TOC is missing. It reads `.hwc-release.json` and the TOC header (`X-BUILD-COMMIT`) for `info`.
  - `Source` (all methods use colon calls, `src:quest(id)`; the fixture Source in Task 8 follows the same shape):
    - `quest(id)`, `npc(id)`, `item(id)`, `object(id)` each return `{id=, <QuestieDB key name>=value…} | nil`, built from `<Entity>DB.GetAll(id)`. Key names are QuestieDB's own (`questLevel`, `requiredLevel`, `startedBy`, `objectives`, `questRewards`, …), confirmed against `lib.Meta.<Entity>.keys`.
    - `xp(id) -> {level, xp} | nil`, from the `QuestXP` module's `db` (find where the release exposes `QuestieLoader`; read it, don't re-run the file).
    - `item_ids() -> {id...}` sorted, from `ItemDB.GetAllIds()`.
    - `info`.

`addon.load` details:
1. `cfg` for the sandbox is `{ class = character.class, faction = character.faction }`. Use a **fresh `hwc.sandbox` per call**, so per-character dynamic corrections are never shared (Review Focus 1). The 17 MB parse is shared through the `tocmeta.parse` cache.
2. Before any file runs, install in `sb.env`:
   - `C_AddOns = { GetAddOnMetadata = function(name, key) … }`, serving `tocmeta.parse(<dir>/QuestieDB/QuestieDB_Forever.toc)[key]` only when `name == "QuestieDB"`, else nil;
   - `C_EncodingUtil = encoding.c_encoding_util()`;
   - `C_Seasons = { GetActiveSeason = function() return 0 end }`;
   - `UnitClassBase = function(u) if u == "player" then return character.class, CLASS_ID[character.class] end end` (with the standard Classic class IDs);
   - `UnitFactionGroup = function(u) if u:lower() == "player" then return character.faction, character.faction end end`;
   - `GetLocale = function() return "enUS" end`.
3. Iterate `toc.files(version_dir, "QuestieDB/QuestieDB_Forever.toc", "Forever")`. Run each non-skipped file with addon name `"QuestieDB"` and one shared `private` table. Skipped entries are an error, since the release is expected to be complete.
4. After the last file: `sb.errors` must be empty, else raise. Any `sb.missing_order` name not in `ALLOWED_MISSING` (start empty) raises `"hwc: questie: missing global <name>"`. When the real release names more globals, add stand-ins in step 2, and allowlist only names it merely probes with `rawget`. Note each in a comment citing the QuestieDB file and line.

- [ ] **Step 1: Write the failing unit test for the adapter**

Build a fake `lib` table with `Meta.Quest.keys = {name=1, questLevel=5}`,
`QuestDB.GetAll = function(id) return id == 7 and {"Fake", nil, nil, nil, 12} or nil end`,
`ItemDB.GetAllIds = function() return {9, 3} end`, and an `xp_db = {[7]={2,170}}`
hook (the adapter accepts `lib` plus an `xp_db` field set by `addon.load`).
Assert:
- `s:quest(7)` is `{id=7, name="Fake", questLevel=12}`
- `s:quest(8)` is nil
- `s:item_ids()` is `{3,9}`
- `s:xp(7)` is `{2,170}`

- [ ] **Step 2: Write the failing integration spec**

It is pending with `"no QuestieDB installed: run hwc init"` when
`home.active_dir(home.root())` is nil.
- `source.open(dir, {class="WARRIOR", faction="Alliance"})`: `s:quest(179).name == "Dwarven Outfitters"` and `s:xp(179)` is non-nil.
- **Review Focus 1:** open WARRIOR, then MAGE, in the same process. `s:quest(8315).nextQuestInChain` is `8316` for WARRIOR and `8381` for MAGE (QuestieDB `src/corrections/Forever/legacy/classicQuestFixes.lua:103-114`). If 8315 turns out to be statically baked rather than dynamic, pick another `[playerClass]` entry from that file and cite it.
- Both loads leave no entries in `sb.errors`.
- Print the wall time of the first and second `open` to stderr, for the carryover.

- [ ] **Step 3: Run and see both fail**

Run: `~/.luarocks/bin/busted spec/questie/source_spec.lua spec/integration/questie_release_spec.lua`

- [ ] **Step 4: Implement `addon.lua` and `source.lua`, iterating on the real release until the integration spec passes**

- [ ] **Step 5: Run and see both pass**

- [ ] **Step 6: Commit**

```bash
git add src/hwc/questie/{addon,source}.lua spec/questie/source_spec.lua spec/integration/questie_release_spec.lua
git commit -m "Load the QuestieDB release unmodified per character"
```

---

### Task 8: The catalog reads a Source; the raw loader is removed

**Files:**
- Modify: `src/hwc/catalog/init.lua:90-110` (load), `:136-140` (`name_of`), `:205-215` (`build_quest`), `:364,380` (npc/item lookups), `:404-437` (`quest_rewards`, `item_id`)
- Modify: `src/hwc/config.lua` (delete `QUESTIE_PIN`; the default `questie_dir` is the version dir from `home.active_dir(home.root())`, or nil; the config also carries `cfg.faction`, already `"Alliance"`)
- Delete: `src/hwc/catalog/questie.lua`, `spec/catalog/questie_spec.lua`, `spec/fixtures/catalog/questie/`, `tools/fetch-questie.sh`
- Create: `spec/fixtures/catalog/questie_source.lua`: returns a `Source` (same interface as Task 7) built from plain tables, holding **the same invented rows** as the deleted raw fixture (quests 1001–1010, their NPCs, items, objects and XP rows), so the existing catalog assertions keep their values.
- Modify: `spec/catalog/catalog_spec.lua`, `spec/helpers/driver_fixtures.lua`, `spec/config_spec.lua:61`, `spec/cli_spec.lua:184`, `spec/helpers/world_engine_flow.lua:24`, `spec/integration/anchors_spec.lua:44`

**Interfaces:**
- Consumes: `source.open`, `home.*`.
- Produces:
  - `cfg.catalog.questie_source` (optional `Source`) bypasses loading; specs use it.
  - Otherwise `Catalog.load(cfg)` calls `source.open(c.questie_dir, {class=cfg.class, faction=cfg.faction})`.
  - `catalog.sources.questie = {path, present, tag?, build?, sha256?, reason?}`. `present` is `true` or `false`; `"partial"` no longer exists. `reason` is the nil-reason from `source.open`.
  - When the source is absent, `boot.run` writes one line to stderr: `hwc: no QuestieDB installed (<reason>); run hwc init`.

- [ ] **Step 1: Update the catalog specs to the fixture Source**

`fixture_cfg` sets `questie_source = dofile(FIX .. "/questie_source.lua")`.
Replace the `commit`/`PIN` assertions (`catalog_spec.lua:273-323`) with:
- an absent install gives `present == false`, and a `reason` of `"none installed"` when `questie_dir` is nil;
- **Review Focus 4:** `questie_dir` pointing at a dir without the TOC gives `present == false` and a `reason` starting with `"broken"`, without raising.

Everything else in `catalog_spec.lua` must pass unchanged in its expected values.

- [ ] **Step 2: Run them and see them fail**

Run: `~/.luarocks/bin/busted spec/catalog spec/config_spec.lua`

- [ ] **Step 3: Implement the catalog changes**

- `qd.quests[id]` becomes `src:quest(id)` (likewise for npcs, items and objects).
- `qd.xp[id]` becomes `src:xp(id)`.
- `quest_rewards` and `item_id` iterate `src:item_ids()` with `src:item(id).questRewards` and `.name`.
- No positional `rows`/`keys` access remains (check with `grep -n 'rows\|keys' src/hwc/catalog/init.lua`).

- [ ] **Step 4: Point the other specs at the store**

- `driver_fixtures` uses the fixture Source.
- `config_spec:61` asserts that the default `questie_dir` equals `home.active_dir(home.root())`.
- `cli_spec:184`, `world_engine_flow:24` and `anchors_spec:44` become pending on `home.active_dir(home.root()) == nil`, with `"no QuestieDB installed: run hwc init"`.

- [ ] **Step 5: Run the full suite, including slow specs, against the Task 6 install**

Run: `~/.luarocks/bin/busted && ~/.luarocks/bin/busted --tags=slow`
Expected:
- all unit specs pass;
- integration specs run (not pending) and pass, **except** expected-findings assertions that move because of the new data. Record each of those, its old and new value, in the carryover under `## Differences explained` before updating it.

- [ ] **Step 6: Commit**

```bash
git add -A src/hwc/catalog src/hwc/config.lua spec tools
git commit -m "Read QuestieDB through the installed release; drop the raw-file loader"
```

---

### Task 9: `hwc doctor`

**Files:**
- Create: `src/hwc/doctor.lua`
- Test: `spec/doctor_spec.lua`

**Interfaces:**
- Consumes: `home.*`, `tocmeta.header`, `release.select`, `release.contract_range/contract_ok`, `hwc.source.find/start_dir`, `hwc.addon_info.read`, `config.load().catalog.supplement`.
- Produces:
  - `doctor.run(env: {pwd, cwd, home, hwc_home}, deps?: {get_json, has_tool(name)->bool, require_ok(mod)->bool}) -> {checks = {{id, status: "ok"|"warn"|"fail", detail, fix?}...}, failed: bool}`
  - `doctor.text(report) -> string`: one line per check, `ok   <id>: <detail>` / `warn <id>: <detail> → <fix>` / `FAIL <id>: …`.
  - `doctor.json(report) -> string`

Checks, in this order, with these ids (spec §4.4 table):

| id | ok | warn | fail |
|---|---|---|---|
| `luajit` | `jit.version` starts with `LuaJIT 2.1` | | otherwise |
| `rocks` | `lfs`, `dkjson`, `busted` all load | `busted` missing → `luarocks --lua-version 5.1 install busted` | `lfs` or `dkjson` missing |
| `tools` | `curl` and `unzip` found (`command -v`) | | either missing (init/sync need them) |
| `wowpro` | folder found; `branch @ short-commit (dirty)` when git | not in a WoW-Pro folder → `cd into your WoW-Pro folder for run/matrix` | |
| `questie` | active tag, build commit (7 characters), path | | `none installed` → `hwc init`; `broken: <tag>` → `hwc sync questie --tag <tag>` |
| `questie-toc` | flavor Forever, mode baked | | other flavor or mode → `hwc sync questie --tag <tag>` |
| `questie-contract` | `contract <min>-<max> includes 4` | | `contract_ok` message |
| `questie-upstream` | `up to date (<tag>)` | `<tag> → <new> available` → `hwc sync questie`; any `select` error → `could not check upstream: <err>` | |
| `supplement` | present, valid JSON, every entry has `source` | absent (optional) | invalid JSON or an entry without `source` |

`questie-toc`, `questie-contract` and `questie-upstream` are skipped (not
printed) when `questie` fails. `failed` is true if any check fails.

- [ ] **Step 1: Write the failing tests**

All run with fake deps and a tmp `HWC_HOME`:
- a healthy install with upstream equal: every check is ok or warn; `failed == false`
- **Review Focus 3:** `get_json` errors: `questie-upstream` is warn with `could not check upstream`, and all 9 ids except the skipped ones are still present
- **Review Focus 4:** `active = v1.1.2` with no dir: `questie` is fail with fix `hwc sync questie --tag v1.1.2`, `questie-toc` is absent, and `failed == true`
- upstream `v1.1.3` available gives a warn whose detail is `v1.1.2 → v1.1.3 available`
- `has_tool("unzip") == false` gives `tools` fail
- a supplement entry without `source` gives fail

- [ ] **Step 2: Run and see them fail.** **Step 3: Implement.** **Step 4: Run and see them pass.**

Run: `~/.luarocks/bin/busted spec/doctor_spec.lua`

- [ ] **Step 5: Commit**

```bash
git add src/hwc/doctor.lua spec/doctor_spec.lua
git commit -m "Add the doctor health report"
```

---

### Task 10: CLI wiring, findings line, docs

**Files:**
- Modify: `src/hwc/cli.lua` (USAGE, and dispatch in `M.main` next to `boot`/`quest`; `env` gains `hwc_home = os.getenv("HWC_HOME")`)
- Modify: `src/hwc/findings/render.lua:490-505` (questie source line)
- Modify: `spec/cli_spec.lua`, `spec/findings/render_spec.lua:269-290`
- Modify: `README.md` (Requirements: `curl`, `unzip` are now required, and `python3` stays optional; Quick start / World and catalog: `hwc init` replaces `fetch-questie.sh`; new short sections `### Health check` and `### Updating QuestieDB`; licence section: QuestieDB is downloaded to `~/.hwc`, GPL-3.0; LibDeflate is vendored under zlib), `CONTRIBUTING.md` (drop the fetch-script steps)

**Interfaces:**
- Consumes: `install.init/sync`, `doctor.run/text/json`, `home.root`.
- Produces: these USAGE lines, verbatim:
  ```
         hwc init
         hwc doctor [--json]
         hwc sync questie [--tag TAG]
  ...
    init          Download QuestieDB (latest Forever release) into ~/.hwc and check the setup
    doctor        Check LuaJIT, rocks, tools, the WoW-Pro folder, QuestieDB and the supplement
    sync questie  Install the newest QuestieDB Forever release (or --tag TAG) and make it active
  ```
  `init`, `doctor` and `sync` run from any directory (no `locate`).

Output:
- **`sync`** prints `QuestieDB <from or "none"> → <to> (build <7>)`, or `QuestieDB <to> already installed; active`. Then one line per skipped release: `skipped <tag>: no Forever build`.
- **`init`** prints the sync line (or `QuestieDB <tag> already installed`), then `doctor.text`.
- **Exit codes:** `init`/`sync` failure exits 1 with the error. `doctor` exits 1 when `failed`. Unknown subcommands (`sync foo`) and bad flags exit 2 with USAGE.
- **Findings render:** `` - `questie`: present · `v1.1.2` · build `e1652ce` · sha256 `<12>` · `<path>` ``, or `` - `questie`: absent (<reason>) · `<path or "-">` ``.

- [ ] **Step 1: Write the failing CLI and render tests**

- `main({"sync","foo"})` returns 2
- `main({"doctor","--bogus"})` returns 2
- **Review Focus 5:** `main({"init"}, out, err, {home=false})` returns 2, and `err` contains `hwc: HOME is not set; set HWC_HOME`. Same for `doctor` and `sync questie`.
- `main({"sync","questie"})` with `install.sync` stubbed (the same replace-and-restore pattern `cli_spec` uses for `runner.character`) prints `QuestieDB none → v1.1.2 (build e1652ce)` and returns 0
- `doctor` with a stubbed `failed=true` report returns 1
- In the render spec, the two questie line formats above, replacing the old `commit d57637f` expectations

- [ ] **Step 2: Run and see them fail.** **Step 3: Implement.** **Step 4: Run and see them pass.**

Run: `~/.luarocks/bin/busted spec/cli_spec.lua spec/findings/render_spec.lua`

- [ ] **Step 5: Update the README and CONTRIBUTING**

Check with `grep -rn 'fetch-questie\|d57637f\|local/questie' README.md CONTRIBUTING.md src spec tools`.
Expected: no matches.

- [ ] **Step 6: Commit**

```bash
git add src/hwc/cli.lua src/hwc/findings/render.lua spec README.md CONTRIBUTING.md
git commit -m "Add hwc init, doctor and sync questie; record the QuestieDB release in findings"
```

---

### Task 11: End-to-end check and carryover

- [ ] **Step 1: Fresh-machine path**

```sh
HWC_HOME=$(mktemp -d) hwc doctor; echo $?   # questie FAIL → hwc init; exit 1
HWC_HOME=<same> hwc init                     # installs latest; prints doctor
HWC_HOME=<same> hwc sync questie             # "already installed; active"
HWC_HOME=<same> hwc sync questie --tag v1.1.1 && HWC_HOME=<same> hwc doctor   # active v1.1.1, upstream warn
```
Expected: as the comments say. Then switch back with
`hwc sync questie --tag v1.1.2`.

- [ ] **Step 2: Timings and findings on the new loader**

Repeat Task 1 Step 1 against `~/.hwc` (v1.1.2). Fill `## After (v1.1.2)` with
the times and the counts. Under `## Differences explained`, for each findings
category whose count changed, take one example and say whether it comes from
a correction (cite the QuestieDB fix file and quest id) or from the
66-commit data update.

- [ ] **Step 3: Full suite**

Run: `~/.luarocks/bin/busted && ~/.luarocks/bin/busted --tags=slow`
Expected: all pass; nothing pending except the specs that need the WoW-Pro checkout, if it's absent.

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/plans/2026-11-17-questiedb-dependency-carryover.md
git commit -m "Record QuestieDB v1.1.2 findings differences and timings"
```
