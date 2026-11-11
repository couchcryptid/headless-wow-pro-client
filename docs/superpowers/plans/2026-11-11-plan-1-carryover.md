# Plan 1 carry-over: rulings and deferred items

Generated from the Plan 1 SDD ledger at merge time (2026-11-11). Plan 2 starts by reading this.

## Rulings
- Ruling: T1 step 1 is satisfied by setup (repo init + docs commit d40d7d6); T1 extends the existing .gitignore — the setup needed a branch before any implementer ran — costs nothing if wrong.
- Ruling: T7 implements `C_Timer.NewTimer(d,f)` as a cancellable one-shot via `Clock:after` and `C_Timer.NewTicker(d,f,n)` as a re-arming `after` chain with `:Cancel()` — matches the WoW contract; spec lists only After as required — if wrong, one stub to adjust.
- Ruling: T7 sets `CreateFrame = function(...) return frames:create(...) end` — WoW's CreateFrame is not a method — trivially reversible.
- Ruling: `Sandbox.new` initialises `chat = {}` and `standin_calls = {}` alongside `errors`/`missing` (T5), so T7/T8 only append — avoids nil fields across tasks — trivially reversible.
- Ruling: `.busted` omits `lua=` (my dispatch ruling reversed) — the ~/.luarocks/bin/busted wrapper already execs /opt/homebrew/bin/luajit (verified in discovery); setting lua= re-execs without the rock path — costs nothing if wrong (specs fail loudly).
- Ruling: config defaults race=Human, class=WARRIOR are acceptable placeholders — every boot/CLI call passes race/class explicitly — if wrong, a default changes, no behaviour depends on it.
- Ruling: commit trailer stays "Claude Opus 5.5" — the session attribution rule names it; subagent model differs but attribution follows the session rule — cosmetic.
- Ruling: frame __index fallback returns the chainable function only for string keys starting with an uppercase letter (WoW API methods are PascalCase); every other missing key returns nil — my earlier "unknown methods/getters return the frame" decision did not consider data fields like rows[i].index, which real WoW leaves nil — if wrong, an addon call on a lowercase method errors loudly (visible in Task 8).
- Ruling: env.loadstring must compile chunks into the sandbox env (wrap: loadstring then setfenv(fn, env)) — CallbackHandler-1.0 and other Ace libs build code with loadstring, and real-_G chunks would bypass stubs and the trap — carried into Task 7's dispatch as an extra item — if wrong, a generated chunk reads the wrong globals (visible as boot errors in Task 8).
- Ruling: Forever stubs expose the modern C_QuestLog family and NOT GetQuestLogTitle/GetNumQuestLogEntries globals, so CompatUtil takes its C_QuestLog path — evidence: WoWPro_Trade.lua:359/433/528 groups FOREVER with RETAIL for C_TradeSkillUI/GetProfessions, and the user's Forever install writes Logs/EditMode.log (Edit Mode exists only on modern clients, where GetQuestLogTitle was removed) — if wrong, the quest-log compat branch differs from the real client; confirm with an in-game `/dump GetQuestLogTitle` when convenient (cheap human check, not blocking).
- Ruling: GetCurrentRegion/GetCurrentRegionName stay, cited to AceDB-3.0.lua:263 (a real load-time caller the reviewer missed); GetMinimapZoneText is dropped — no addon or library caller, and the missing-global trap will reveal it if one appears — costs one stub if wrong.
- Ruling: C_* namespace tables built by the stubs (C_QuestLog, C_Map, C_Timer, C_AddOns, C_ChatInfo) get an __index that records "<ns>.<field>" in sb.missing/missing_order and returns nil — calls to unstubbed namespaced APIs would otherwise surface only as "attempt to call nil" with no trap record, slowing Task 8 diagnosis — cheap and reversible.
- Ruling: chat frame is created as "ChatFrame1" with DEFAULT_CHAT_FRAME aliasing it (client naming) — folded into this fix round because it is a one-line change in the same block.
- Ruling: WoWPro_Widgets.lua and WoWPro_CurrentGuide.lua are loaded (removed from the skip list) — Frames.lua:1767 builds every row from Widgets constructors and Broker.lua:1880 reads CurrentGuideFrame:IsVisible() on every update; loading the real files is more faithful than ~20 hand-written stand-ins, matching spec §5.3's intent that row state is engine behaviour — spec §4.2's skip list is amended — if wrong, more UI code runs headless (visible as errors), never less fidelity.
- Ruling: settle uses `busy = fn` (keep settling while the lockdown OnUpdate handler is pending) in place of the brief's literal max_virtual-only call — the lockdown release is an OnUpdate, not a timer (Broker:4840-4874), so queue-empty stopped before LoadGuide; boot only reads LockdownTimer — if wrong, a run settles longer than needed (bounded by max_virtual).
- Ruling: "harness error" = an error whose message location or innermost frame is under src/hwc — the brief's "stack runs through src/hwc" matched every error since all calls enter via the harness — if wrong, an addon error could be misclassified as harness (visible in the error list either way).
- Ruling: accept typed-in C_Map entries (1426 Dun Morogh, 1415 Eastern Kingdoms), C_SuperTrack stub (addon calls it unguarded; modern Forever client per the EditMode.log evidence), GetBindLocation absent until Plan 2 player state, Pets.lua functions unreached for now — each is a Plan 2 follow-up, recorded here.
- Ruling: final fix wave = Important 1 + 2, the hit_limit assertion, plus Minor print→sb.chat, getfenv(0)→env, and a spec pinning the tail-call error classification — all small, in Plan 1 modules, and either binding-constraint or isolation fixes — if wrong, a few lines to revert.
- Ruling: Important 3 (ADDON_LOADED interleaving + SavedVariables timing) moves to Plan 2's first task with a spec amendment — reviewer found no current behavioural effect (baseName unread, RegisterGuide reads no DB), and it touches boot ordering that Plan 2 restructures anyway — if wrong, findings produced before Plan 2 could differ (none are produced in Plan 1).
- Ruling: addon-side pairs() order across processes (LuaJIT hash seed) is a Plan 3 requirement: findings must be canonicalised (sorted) before writing, and Plan 3 adds a cross-process byte-identical findings spec — Plan 1 only fixes its own JSON — if wrong, findings files could differ in order between runs.
- Final: parked — getfenv(2)/getfenv(fn) still return real _G; real setfenv passthrough — Ruling: unreached by the addon today (only LibSharedMedia uses getfenv(0), now env); fix in Plan 2 task 1 — cost if wrong: a future addon path sees real _G.
- Final: parked — polyfills.lua:67 dead real-clock date/time line (overridden by sandbox) — Ruling: delete in Plan 2 task 1 — cost if wrong: determinism hazard if install order flips.
- Final: parked — vdate non-string fmt errors; boot_spec chat-stamp check vacuous if no stamped lines — Ruling: minor, Plan 2.

## Deferred minors (triaged by the final review)
- Task 1: minor (deferred): addon_info git failures silent — non-repo reads as clean tree with empty commit (addon_info.lua:164,172-174); consider error when rev-parse HEAD empty. NOTE for Task 8: boot result must not accept an empty commit.
- Task 1: minor (deferred): single-quote path interpolation in addon_info io.popen.
- Task 1: minor (deferred): config HOME unset → concat-nil error.
- Task 1: minor (deferred): cli.lua calls os.exit at require time — not requirable from specs; Task 8 adds `boot` subcommand, fix there.
- Task 1: minor (deferred): config_spec temp-dir cleanup not in after_each; os.execute results unasserted.
- Task 2: minor (deferred): add strsplit edge specs — pieces > count, pieces == 1, limit with adjacent delimiters ("a&&b",2 → "a","&b"), empty input, leading delimiter.
- Task 2: minor (deferred): strsplit rebuilds delimiter set per call (perf only).
- Task 3: minor (deferred): cancel spec lacks lower bound (clock_spec:84).
- Task 3: minor (deferred): timer due exactly at start+max_virtual left queued; unpinned boundary.
- Task 3: minor (deferred): float residual can cause near-zero extra ticker call.
- Task 3: minor (deferred): O(n) earliest scan + per-step allocation (perf only).
- Task 4: minor (deferred): cancel spec doesn't prove cancellation (frames_spec:89-92); one-ticker-per-frame weakly tested (:77-78).
- Task 4: minor (deferred): SetText(nil) → GetText nil (WoW returns ""); IsEventRegistered true for RegisterAllEvents frames.
- Task 5: minor (deferred): string/table/math are shared process tables — isolation is top-level only (acceptable: runs that need hard isolation can use separate processes).
- Task 5: minor (deferred): unpack drops trailing nil returns in sb:call; handler-recorded errors have generic where="call"; no spec for swallowed error end-to-end or error({}).
- Task 6: minor (deferred): Include/Script patterns are case-sensitive and require double-quoted file= first (fine for the real addon; comment it).
- Task 6: minor (deferred): fix round wrote spec+fix together (no separate RED); unterminated <!-- left in place.
- Task 7: minor (deferred): GetBuildInfo reads sb.cfg vs cfg param; "1.16.1" hard-coded.
- Task 7: minor (deferred): NewTicker delay 0 unbounded relies on settle's max_virtual.
- Task 7: minor (deferred): HBD spec uses a hand-rolled LibStub mock; dead line stubs_spec.lua:125.
- Task 7: minor (deferred): standins.install nil-WoWPro error message.
- Task 8: minor (deferred): error-handler guard can stick if sb:record throws; failing custom handler unrecorded (sandbox.lua:1133-1138).
- Task 8: minor (deferred): script/timer errors recorded where="call", per-tick OnUpdate error floods — tag origin + dedupe in printout.
- Task 8: minor (deferred): GetValue nil vs client 0; invented GetTextColor/GetMinMaxValues defaults.
- Task 8: minor (deferred): standins.lua:1350 citation :145-146 → :144-145.
- Task 8: minor (deferred): integration specs don't assert settle.hit_limit == false.
- Task 8: minor (deferred): redundant files_failed condition boot.lua:601.

## Parked at final review
- Final: parked — getfenv(2)/getfenv(fn) still return real _G; real setfenv passthrough — Ruling: unreached by the addon today (only LibSharedMedia uses getfenv(0), now env); fix in Plan 2 task 1 — cost if wrong: a future addon path sees real _G.
- Final: parked — polyfills.lua:67 dead real-clock date/time line (overridden by sandbox) — Ruling: delete in Plan 2 task 1 — cost if wrong: determinism hazard if install order flips.
- Final: parked — vdate non-string fmt errors; boot_spec chat-stamp check vacuous if no stamped lines — Ruling: minor, Plan 2.

## Plan 2 must start with
- ADDON_LOADED interleaving per addon (load WoWPro TOC → ADDON_LOADED(WoWPro) → load Leveling TOC → ADDON_LOADED(WoWPro_Leveling)) and SavedVariables timing; amend spec §4.3.
- Keep the player/world state on `sb` (stubs read it per call).
- getfenv/setfenv leaks; delete polyfills.lua:67 date/time line; strsplit edge specs; error-handler guard reset if sb:record throws.
- Findings must be canonicalised (sorted) before writing; add a cross-process byte-identical findings spec (LuaJIT per-process hash seed).
