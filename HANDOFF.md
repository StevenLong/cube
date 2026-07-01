# Handoff

## Session 16 (2026-07-01): ENEMY NAV ROBUSTNESS built end to end (a+b+c); SEEK ratified; button feel-check CONFIRMED
Grilled the nav cluster, then built it as one slice. All headless-verified; in-editor feel-check owed.
Commits: cube (this), game-dev task list. SEEK is now [settled]; the button + tut_08 feel-checks the dev
owed from S15 are CONFIRMED ("buttons work well", likes tut_08).

KEY REFRAME (from the grill): this was NOT a nav-grid rebuild. `enemy_sphere._cell_blocked()` is already
queried live per A* expansion and already carries a dynamic term (the player-hiding block). So corralling =
ADD a live gate term there. Gates already track `_covered` + `_open`; they just needed a group.

(a) SHUT GATES CORRAL ENEMIES.
- Gates join group "gates" (extend_lock_gate `_ready`); new `blocked_cells()` returns `_covered` while shut,
  [] while open. enemy_sphere `_refresh_gate_blocked()` snapshots those cells once per frame into
  `_gate_blocked_now`; `_cell_blocked` + the `_move_toward` backstop read it. Sight-blocking was already free
  (raised gate = mask-1 StaticBody). UNIFORM (all gates, no per-gate flag).
- `_move_toward` backstop now also refuses a gate-blocked next cell -> a guard stops at the gate FACE instead
  of clipping through during the ~0.3s repath window.
- EJECT on close: `_maybe_eject()` (top of `_process`) -> if a shut gate covers our cell, slide to the
  nearest OPEN neighbour (`_nearest_open_cell`, nearest to actual sub-cell pos = the "past midpoint through,
  else back" fairness rule for free). Slide = a ~0.15s ease (EJECT_TIME) applied AFTER the state match so it
  overrides normal locomotion; overlaps the 0.25s gate rise. No open neighbour -> stays put, start-snap gets it.

(b) GRACEFUL RE-NAV + CONFUSION.
- START-SNAP in `_find_path`: symmetric to the existing goal-snap -- a blocked START plans from its nearest
  open neighbour toward the goal instead of returning [] and freezing.
- PATROL rewrite: a PATROL_REPATH_INTERVAL (0.5s) timer re-plans mid-leg (not just on arrival), so a gate
  shutting across the current leg is noticed. Empty re-plan = leg severed -> CONFUSION. A detour keeps a
  non-empty path -> quietly reroute (confusion is severance-ONLY).
- CONFUSION = a PATROL sub-FLAG (`_confused_t`), deliberately NOT a State enum entry (that grows the
  [_state]-indexed hum/colour arrays -> the SEEK crash d6684cd). ~1.5s erratic look-around (`_confused_glance`
  snaps a fresh random yaw every 0.4s), grey, no alert glyph, vision still live. Trigger fires for a gate
  shut OR a player BLEND in a chokepoint (the hiding block already lives in _cell_blocked -> emergent: blend
  in a chokepoint and a confused guard mills next to you). Then `_resettle_patrol` -> reachable remainder or
  lighthouse.

(c) LIGHTHOUSE = `_lighthouse` flag. `waypoints < 2` or fully-sealed -> slow STEADY yaw sweep
(`_lighthouse_scan`, LIGHTHOUSE_SWEEP_RATE), grey cone, vision live (contrast: confusion is erratic). Re-checks
reachability every LIGHTHOUSE_RECHECK_INTERVAL (1.5s) so a sealed guard RESUMES patrol when a gate reopens.
`_enter_state(PATROL)` now clears both sub-flags and routes a node-less guard to lighthouse (was an
empty-waypoint crash risk).

VERIFIED HEADLESS (throwaway tests in scratchpad, not committed):
- Grid truth table (11/11): gate-block, detour-reroute, full-severance -> [], start-snap (non-empty, reaches
  goal, excludes the blocked start), eject nearest-side (2.4 -> forward (3,0); 1.6 -> back (1,0)), isolated
  cell -> no eject.
- Integration smoke on level_01 + tut_07 (the two shipped gates+enemies levels): load clean, gates in group,
  gates shut-at-load blocking cells, guards survive 40 pumped frames of the new patrol/eject/refresh code.

OWED IN-EDITOR FEEL-CHECK (none headless-able): corralling feel (run into a lock-gate room, gate shuts behind
you, guard can't follow); the eject bump when a gate closes on a guard; the confusion glance ("huh?") when you
blend in a chokepoint on a patrol route; the lighthouse sweep (node-less guard, and a fully-sealed one); and
SPECIFICALLY re-check level_01 + tut_07 -- their gates now corral, so a guard whose beat crossed a
(shut-at-load) gate will confuse->lighthouse until the player opens it. Confirm that reads sensibly, not broken.
Build a 1-guard + 1-lock-gate room to exercise it. KNOBS to tune on feel: EJECT_TIME, CONFUSION_TIME +
CONFUSION_GLANCE_INTERVAL, LIGHTHOUSE_SWEEP_RATE, LIGHTHOUSE_RECHECK_INTERVAL, PATROL_REPATH_INTERVAL.
POSSIBLE ADD (deferred): confusion currently look-only; the dev floated a small WANDER (a step or two) -- add
on feel-check if the stationary glance reads too static. Terms pinned in GLOSSARY: Corral, Confusion, Lighthouse.

NEXT (obvious): feel-check the nav slice in-editor. Then still owed: remaining per-object grills (closing gate,
remote-noise, cylinder); parked feel-checks (glass-blend 30s; pitfall amber telegraph + 5-cell ping radius).
The closing/airlock gate is now a natural next prop -- corralling makes it meaningful (a gate that shuts on a
TIMER or trigger, not just a lock/button, to seal guards).

## Session 15 (2026-06-29): FLOOR BUTTON built end to end (object + gate refactor + Button Puzzle wizard); headless-verified, feel-check owed
Built the floor button per the Session-14 SPEC, in the pinned build order. All logic verified headless;
in-editor feel-check is the only thing owed. GLOSSARY + task list updated.

PHASE 1 -- BUTTON OBJECT + LATCH (floor_button.gd/.tscn, registry entry, loader). Single-cell LATCHING
one-shot pressure plate: latches when the cube comes to REST on its cell (gated on not is_moving(), like the
lock zone -- grid_pos jumps to a tumble's destination at its START, so without the guard it fired mid-anim;
feel-check fix). Stays on for the run (restart resets), PLAYER-ONLY. Plain Node3D (not Wall*, stays out of nav). `is_active()` = latched. Loader
_build_button + a `floor_button` case in _add_object_floor (the cube must stand on it, so the cell is floor).
Visual = a flat plate (grey unpressed -> green + sinks when latched).

PHASE 2 -- GATE OPENER-POLL REFACTOR (extend_lock_gate.gd, extend_lock_zone.gd, loader _wire_lock_links).
The gate no longer polls `_player.active_lock_id()`; it polls each opener OBJECT's `is_active()` and opens per
a new per-gate `require_all` flag (ANY default / ALL). Added `lock.is_active()` (= am-I-the-active-lock) so
locks and buttons are interchangeable openers; the loader resolves an `opens` edge's `from` id to the actual
lock OR button object and calls `gate.add_opener(obj)`. BEHAVIOR-PRESERVING for existing lock levels:
require_all defaults false => ANY => the old `opener_ids.has(active_lock)` semantics; a single lock opener
under ANY is identical. Mixed lock+button openers on one gate work as a free bonus.

PHASE 3 -- BUTTON PUZZLE WIZARD (editor.gd). New "Button Puzzle (wizard)" tool entry PARALLEL to the lock
wizard, driven by a stage-sequence map (WIZARD_STAGES: lock=lock/gate/unlock, button=button/gate). Reuses ALL
the existing plumbing -- grouping, id minting (added a "button" counter -> button1/button2...), and
_emit_group_links (buttons emit the same `opens` kind to every gate in the group; groups stay independent).
Per-gate ANY/ALL: `T` toggles `require_all` on the gate whose fence covers the cursor cell (only button-wizard
gates carry the flag; lock gates omit it, so their look is unchanged); a billboard Label3D "ANY"/"ALL" tag
floats over the gate ghost. Lint wording updated ("Gate has no opener (lock or button)").

GUIDE LINES (added on dev request after the first pass): a button->gate guide line now draws too, matching the
lock system. TEAL path (distinct from orange lock->gate / green lock->unlock), routed along the grid; stays
visible but GRAYS OUT once the button latches (feel-check: dev wanted it dimmed, not hidden -- the connection
still reads, just spent; one-shot so it dims once via guide_line `_gray_out`). guide_line.gd gained an `opener`
mode that polls the button's is_active() directly (bypasses the lock-state branches); level_loader `_build_lock_links` now
takes `buttons` and anchors an `opens` edge's line on a lock OR a button (`_new_button_link_holder`,
`_button_cell`, BUTTON_LINE_COLOR). Headless-verified the line draws + disables on latch, and that shipped
LOCK levels still draw their lines (tut_07 = 4, unchanged).

VERIFIED HEADLESS (parse-clean; throwaway tests stashed in scratchpad, removed from repo per convention):
- Gate combinator truth table (ANY/ALL/empty), button latch + one-shot, full LevelLoader load pipeline.
- Wizard emission: mint button1/gate1 + lock regression (lock->gate opens, lock->unlock released_by), groups
  independent (no cross-bleed), ALL gate keeps require_all.
- END-TO-END ALL gate: a JSON level with 2 buttons + a require_all gate loads, opens ONLY when both latched.
  NOTE: the `-s` SceneTree harness does NOT auto-tick node _process on `await process_frame`; the tests pump
  button/gate `_process` explicitly (exercises the real bodies). Keep that in mind for future load tests.

OWED IN-EDITOR FEEL-CHECK (none headless-able, all this session): button plate look (unpressed grey -> latched
green sink); the teal button->gate guide line graying out (staying visible) on press; the ANY/ALL Label3D tag + the
`T` toggle UX (stand on a button gate, press T); the Button Puzzle wizard flow (place buttons -> gate(s) ->
finish; readout shows "BUTTON PUZZLE n [stage] nB nG ... T ANY/ALL").
Build a quick 2-button ALL-gate room in the editor to exercise it. CAVEAT (unchanged, by design): gates are
ENEMY-TRANSPARENT -- a button-gated room blocks the cube but NOT guards (see "### Enemy nav robustness").

BUTTON TUTORIAL (tut_08_buttons.json, registered in tutorials_menu.gd as #8 "Buttons"). Hand-authored (dev
out of time to author; levels are JSON so I built it directly + smoke-verified, not editor-drawn). Two beats,
3 rooms L->R, NO enemies (pure mechanic): (1) one button opens an ANY gate into room B; (2) two SPACED
buttons on an ALL gate to the exit -- spaced so a 1x1 cube can't cover both, so the LATCHING one-shot is what
solves it (press one, it stays latched, walk to the other). The gray-out-on-latch guide lines do the teaching
for free: a pressed button's teal line grays, the unpressed one stays lit, gate opens when both are gray --
no in-game ALL label needed (the ANY/ALL tag is EDITOR-only; revisit only if playtesters are confused).
Smoke-verified headless: loads, exit reachable, 3 links, ANY/ALL gates wired (1 + 2 openers).

NEXT (obvious): feel-check the button + tut_08 in-editor/in-game. Still owed
from before: ratify the SEEK name (still [proposed]); remaining per-object grills (closing gate, remote-noise,
cylinder); parked feel-checks (glass-blend 30s; pitfall amber telegraph + 5-cell ping radius). The Enemy nav
robustness cluster (dynamic gate blocking / re-nav / lighthouse) is the unlock for guard-proof button rooms.

## Session 14 (2026-06-29): Pyramid beams/detection/REVEALED finished + feel-checked; Windows export de-risked; floor button GRILLED
Tight, productive session. ALL feel-checks CONFIRMED by the dev in-editor this session. Commits: cube
87cf5a0, c5d5a18, 7e3a86c, ba27fbe, 35c4eca + game-dev task list baf0b0b, ccbd18d. All pushed.

ECHO PYRAMID BEAMS + DETECTION (87cf5a0, c5d5a18) -- finished the Session-13 deferred beam work.
- DIRECTION FIX: comms beams traced the wrong path (player->straight-up + player->guard). Now
  pyramid->floor (emit) -> player->PYRAMID (return) -> PYRAMID->each guard (broadcast). The "stray beam to
  random positions" was NOT a separate bug -- it was the player-origin broadcast with an invisible source;
  re-anchoring to the pyramid fixed both at once.
- DETECTION (real bug): the catch tested the cube's CENTRE point vs radius, so an extended cube partway
  into the zone wasn't caught. Now `_nearest_footprint_dist` walks the footprint extent (footprint_covers/
  get_footprint_min) + clamps to the nearest occupied cell -> caught by the overlapping edge. Dev confirmed.
- BEAM VISUAL PASS: beams track the live guard (recomputed each tick via _orient_flash), stop at the sphere
  SURFACE (inset by GUARD_BODY_RADIUS 0.4 -- centre-aim showed through the alpha-blended body), thinner
  (r 0.015), translucent (alpha 0.55), fade in+out (sin envelope). Return beam originates at + tracks the
  CUBE, not the floor tile.

REVEALED DEBUFF (7e3a86c) -- closed the dodge/walk/corner escape after a catch. GRILLED + settled: a catch
now also tags the player REVEALED, a SIBLING flag to EXPOSED on the SAME shared overheat timer
(DODGE_COOLDOWN 1.5s, re-maxed per catch). While revealed, each pyramid re-feeds in-range guards the LIVE
cell (throttled REVEAL_FEED_INTERVAL 0.2s via enemy_pyramid `_feed_revealed`), so guards track THROUGH
cover. Kept as a separate flag so it can later be SPLIT off the timer into a "clears only when you leave the
zone" version (the revisit lever) if same-timer feels weak. DEV VERDICT: "aggressive but still outsmartable
with calm skill" = the target -> KEEP same-timer, DON'T pull the leave-zone lever. Shares EXPOSED's red wash
(always co-occur). player.is_revealed(); GLOSSARY: Revealed [settled], Exposed trimmed, Catch updated.

THROWAWAY WINDOWS EXPORT (ba27fbe, 35c4eca; task baf0b0b) -- DONE, distribution de-risked. export_presets.cfg
(Windows Desktop, tracked; /build/ gitignored). Ran CLEAN on native 4.7: menu, built-in levels, editor save
to user://, a pyramid level. FINDING: Godot 4.7 `export_filter=all_resources` already packs the raw
res://levels/data/*.json (read via FileAccess by string path) -- the editor cleared the belt-and-suspenders
`*.json` include filter and it still worked. Only re-add *.json if a future export ever 404s a level.
Templates already installed; no signing friction.

FLOOR BUTTON GRILLED (task ccbd18d, "### Floor button" SPEC) -- NOT built. LATCHING one-shot pressure plate
(the latching complement to the momentary lock; OR-only was rejected as too close to a shape-less lock).
button--opens-->gate (same kind as locks); per-GATE `require_all` flag for ANY/ALL (multi-button AND);
all-to-all within a group, no per-edge/blending. Runtime = refactor the gate to poll each opener OBJECT's
is_active() (lock=active-lock, button=latched) then open = require_all?all:any (~30-40 lines, allows mixed
openers). Exit gating = a gate on the EndTile (no new mechanism). Editor = a NEW "Button Puzzle" wizard
parallel to the lock wizard (buttons->gates->finish, per-gate ANY/ALL toggle), reuses grouping +
_build_links. BUILD ORDER: (1) button object + latch runtime, (2) gate opener-poll refactor + require_all,
(3) wizard; verify (1)+(2) headless before the editor.

DEFERRED / FILED (task ccbd18d, "### Enemy nav robustness") -- a cluster the dev leans "moderately strongly"
toward but OUT of the button build (own grill): (a) shut gates BLOCK/corral enemies (DYNAMIC nav -- grid is
built once at load), (b) graceful RE-NAV when the next patrol node is unreachable, (c) no-nodes default =
"LIGHTHOUSE" (node-less sphere rotates+scans in place instead of sitting dead; also a sound-test default).
PARKED note: gates opening visually for enemies / circular holes only non-cubic enemies fit through (cute,
sneak-through unresolved, left as is). NOTE: gates are ENEMY-TRANSPARENT today (a shut gate blocks the CUBE
via StaticBody colliders but not enemies -- out of the nav grid + kinematic sphere movement); a button-gated
room is NOT guard-proof until this cluster lands.

NEXT (obvious first move): BUILD the floor button per the SPEC. Still owed: ratify the SEEK name (still
[proposed] in GLOSSARY -- SEEK/ALERT/TAGGED?); remote-noise button (own grill); cylinder enemy (grill);
parked feel-checks (glass-blend 30s; pitfall amber telegraph + 5-cell ping radius likely lowered).

## Session 13 (2026-06-28): Catch overheat/exposed BUILT; pyramid feel pass; SEEK enemy state; pursuit stickiness; beams (BUG open)
Big iterative session on the echo pyramid + the guard it feeds. Nine commits (4e1dd33..b2d9e7e), all pushed.

CATCH -> OVERHEAT + EXPOSED (BUILT, the Session-12 grilled spec). A pyramid catch now sticks instead of
being shrugged off by re-blending. The real dodge gate is `_dodge_cooldown_t` (not the `is_dodge_available`
helper -- my first attempt gated the wrong thing, 4e1dd33, fixed in e551908): a catch sets the FULL dodge
cooldown (= a max-length dodge, so the existing trigger bars dodge) AND sets `_exposed` (force-breaks blend +
blocks re-entry via the `wants_blend` condition). One window: `_exposed` clears exactly when the cooldown hits
0, so both indicators (edge-heat + red wash) show and end together. Tell: a strong pulsing red whole-face wash
(cube.gdshader `exposed` uniform). player.gd `apply_catch_overheat()`; enemy_pyramid `_on_catch` calls it.

PYRAMID READABILITY/FEEL PASS (4929ced, e551908): filled danger zone (was a bare ring); charge wind-up now
LIFTS the pyramid mesh then it FALLS back under gravity with a damped bounce (DROP_GRAVITY/BOUNCE consts) --
no more teleport-snap; an emit beam at sweep start; procedural audio via `_make_ping(f0,f1,dur,peak,decay,
glide_k)` -- sonar "boing" (high + long ring) at sweep start, sharp short sting on catch; strengthened red wash.

ZONE SHAPE -- final = TWO-TIER PER-TILE (8885ca7). Iterated: hard per-cell cutoff (7fb7f5a) read "square" at
r=5; tried a round continuous circle (d3f072d) but dev wanted per-tile back. FINAL: per-tile (round() to cell
centre), FULL colour where the tile centre is within radius (exactly the catchable cells, matches the d<=radius
catch test), a DIMMER wash (0.6) on tiles the radius only clips -> rounds the silhouette while staying honest.
In shaders/grid_ground.gdshader.

SEEK ENEMY STATE (be7c913, GRILLED first). New 5th `State.SEEK` so a pyramid catch makes guards AGGRESSIVE
instead of the gentle INVESTIGATE (stepping behind a wall no longer shakes the combo). reveal_player_at routes
here for every guard in range (PURSUIT guards keep their own lock). Beelines to the EXACT revealed cell at a
~4.0 u/s floor (SEEK_SPEED/MULT; above walk, below pursuit) via pursuit's hybrid locomotion (extracted to
`_chase`); cone aimed ahead -> escalates to real PURSUIT on sight; each ping refreshes target + resets the
give-up timer; on reaching a stale cell -> INVESTIGATE. Ignores noise like pursuit. Tell: electric cyan body +
cyan "!" + hum 1.35. GLOSSARY: `Seek [proposed]` (NAME NOT RATIFIED -- SEEK/ALERT/TAGGED?), Zone/Catch refreshed.
CRASH FIX d6684cd: `_update_hum` indexes TWO arrays by `_state` (HUM_PITCH + HUM_VOL); I added the 5th entry to
HUM_PITCH but missed HUM_VOL -> out-of-bounds the instant a guard entered SEEK. (Lesson in auto-memory
feedback_godot_runtime_gotchas: grep EVERY `[_state]` when growing an enum; also const/enum edits need a FULL
Godot restart, hot-reload leaves them stale.)

PURSUIT STICKINESS (3eb0f22): two fixes so the chase isn't shaken trivially. (1) PURSUIT_GRACE (1.2s): after
LoS breaks (ducking a corner right in front) the guard keeps tracking the player's cell briefly instead of
freezing/staring -> one corner isn't a free escape; re-seeing refreshes it. (2) reveal_player_at during PURSUIT
now ACTS on the fresh intel at once (retarget, refresh detection lock + grace, repath) instead of early-returning.

BEAMS (b2d9e7e) -- BUILT but WRONG + has a BUG. Emit shaft now stays attached to the falling cone tip (unit
cylinder stretched via scale.y), thinner (r 0.025). On a catch it spawns transient comms beams (_spawn_flash/
_tick_flashes; beam stretch uses Basis(right, up*len, fwd) NOT Basis.scaled -- scaled scales rows not the axis).
   *** TWO THINGS TO FIX NEXT (deferred this session, dev out of time): ***
   1. WRONG DIRECTION. Intended signal trail (dev-confirmed): pyramid->floor (emit, DONE) -> ping hits player ->
      player->PYRAMID (return) -> PYRAMID->each reachable guard (broadcast). Current code does player->straight-UP
      and player->guard. FIX in enemy_pyramid `_on_catch`: aim the return beam from the player tile to the
      pyramid's mesh position; change the broadcast ORIGIN from the player to the pyramid position.
   2. BUG: on a ping/catch there's a stray "second beam that goes to random positions," hard to read. Investigate
      the broadcast _spawn_flash -- candidate causes: a guard position read, a degenerate orientation, or beams
      stacking across repeated catches while the player lingers in the zone. Diagnose before re-aiming.

OWED FEEL-CHECKS (none verifiable headless; all this session's work): catch overheat dodge-block + both
indicators together; sonar boing / catch sting; pyramid descent bounce; two-tier zone; SEEK (cyan, beeline,
escalate on sight, unshakeable-by-a-single-wall); pursuit corner grace; ping-during-pursuit; beams. NOTE: dev on
NATIVE Windows Godot over \\wsl$ -- after any const/enum push, FULL editor restart (hot-reload leaves stale).

KEY TUNABLES: CATCH lockout = DODGE_COOLDOWN (1.5); SEEK_SPEED 4.0 / SEEK_SPEED_MULT 1.3 / SEEK_ARRIVE_DIST 0.6
/ SEEK_TIMEOUT 8.0; PURSUIT_GRACE 1.2; COLOR_SEEK cyan; HUM_PITCH/HUM_VOL[4]; zone fringe dim 0.6 (grid_ground);
beam radius/timing + _make_ping params (enemy_pyramid). NEXT: fix the beams (redirect + the stray-beam bug), then
the owed feel-checks; ratify the SEEK name.

## Session 12 (2026-06-27): Glass fix + PITFALL tiles + ECHO PYRAMID enemy built; Exposed/overheat GRILLED (not built)
Stage 1 toolkit work. Four things shipped, one design fully settled and queued.

GLASS-BLEND FIX (commit c1322b4) -- the filed exploit. `_extend_cell_clear` gained `ignore_glass`; the
cover probes `_column_walled`/`_row_walled` (player.gd) pass it so a glass-only cell reads CLEAR (can't hide
behind a window), while extension-collision callers keep glass solid. Glass already in group "glass". Headless
branch test green. Feel-check still owed (30s: cube flanked by glass = no blend; by real walls = still blends).

PITFALL TILES (commits 3631cdf, 37e81da, 2c75602) -- BUILT + dev-driven, "good for now". New `pitfall`
BASE_TILE (glyph p): walkable floor that breaks when the cube's WHOLE footprint vacates it -> ordinary void.
ONE mechanism: footprint-before/after diff on every settle (tumble/collapse/extend/dodge); a dodge also breaks
pitfalls it sweeps OVER (dev's call). Player-only trigger; a broken cell blocks enemies free via live is_floor.
Each break = a moderate ~5-cell noise ping with the player-step wave ring + a low crumble (own _crumble_player,
since a tumble plays a step the same frame). Loader tags tiles group "pitfall_tiles"; level.gd break_pitfall()
erases floor + frees tile. Verified headless (unit + full-pipeline smoke). OPEN: amber telegraph visual needs
work (-> UI/UX pass); the 5-cell ping radius "feels a bit much", first knob to lower after more play.

ECHO PYRAMID enemy (commits 24ae5ca, 43447c7, 2184843) -- BUILT, design grilled first. Stationary FLOATING
sonar pylon that DEFEATS COVER (the sphere's opposite: non-visual, immobile, no LoS). Fixed-beat pulse: charge
tell, then a detection FRONT expands centre->R; caught the instant it reaches your cell inside R (edge =
dodge out ahead, centre = near-instant). On a CATCH, every guard CURRENTLY inside the radius gets your exact
position (enemy_sphere.reveal_player_at() -> reuses ungated _on_sound_heard -> _last_seen_pos + INVESTIGATE,
bypassing LoS/walls). No standalone fail, no global alert, no links; lone pyramid = inert. Recoverable: leave
the field. Registry OBJECT (per-instance radius+interval, editor auto-lists). Readout is drawn on the FLOOR
TILES via the ground shader (pyr_* uniforms, per-slot like cones; loader wipes slots each load): persistent
outer ring + a per-tile step-wave SCAN (after two visual reworks -- first floating meshes overhung void + the
TorusMesh was a glitchy diamond). DEMO LEVEL: user://levels/echo_pyramid_demo.json. KEY TUNABLE: front_speed
vs dodge distance. Verified headless (parse + smoke: proximity gate reveals in-range guard only). Feel-check
of the per-tile scan + an audio cue on catch still owed.

EXPOSED / OVERHEAT ON A CATCH -- GRILLED + FULLY SETTLED 2026-06-27, NOT BUILT (the obvious NEXT). Fixes:
blending currently shrugs off a catch (re-blend and vanish). Settled spec (full version + build hooks in the
task list "PYRAMID CATCH -> OVERHEAT + EXPOSED" item, and terms in GLOSSARY.md): a catch ALSO (a) OVERHEATS
(max dodge cooldown, no dodge) and (b) applies EXPOSED (force-break blend + block re-entry, no hide), both on
ONE shared timer = a new CATCH_OVERHEAT const (default DODGE_COOLDOWN 1.5s, tunable up), re-maxed per catch.
Only dodge+blend lock; walk/tumble/extend free (walk out exposed = the escape). Pyramid-SPECIFIC (not all
overheat). TELL: distinct red "Exposed" cube-display look. Build is small (apply_catch_overheat() + one
`wants_blend` condition + cube-display red state + the _on_catch call). I asked "green light to build?" -- not
yet answered; START HERE next session.

NEW THIS SESSION: GLOSSARY.md (repo root) -- a Domain-Driven-Design ubiquitous-language doc (dev's request).
Pins ambiguous/coined gameplay terms ([settled]/[proposed]/[contested]) before they drive a build; CLAUDE.md
points at it. Already settled: Blend, Cover, Catch (vs guard Detection), Echo Pyramid/Zone/Pulse/Scan, Dodge
cooldown, Overheat, Exposed, Worming. Keep it updated when coining/disambiguating terms (auto-memory
feedback_glossary_ubiquitous_language).

PARKED/OWED FEEL-CHECKS: glass-blend (30s), pitfall amber visual + ping radius, pyramid per-tile scan +
catch audio cue. Per-object grills still owed for: cylinder, floor button, closing gate, remote-noise, laser.

## Session 11 (2026-06-26): Link layer SLICE 6 (editor lint) DONE + endgame REPLANNED
Link layer is now COMPLETE end to end (all 6 slices + backfill retired).

SLICE 6 -- EDITOR LINT PANEL (committed 3cf82ca, marker tweak b0e0c07). Top-right ⚠ warnings Label in
editor.gd (`_compute_warnings`/`_update_warnings`, recomputed on a 0.5s timer so it never serializes/
BFSs on the per-frame readout path). Findings: no start, no end, orphan gate (no `opens`), orphan unlock
(no `released_by`), unlock shape not a permutation of its lock's, and end unreachable from start.
Reachability REUSES the loader's real router (LevelLoader._parse_base -> _walkable_cells/_blocked_cells
-> _route), so floor steps + void jumps + wall/edge blocking all count (no false "unreachable"). Orphan
checks iterate `_objects`, so a manually-placed id-less gate/unlock is flagged too. Verified headless
(4-case reachability test + parse-clean). USER feel-checked the panel: reads well; only change was the
warn marker `!` -> `⚠`. NOT in v1 (cheap to add): "floating overlay" (ink/water over void) -- loader
auto-floors overlay cells so it's harmless. Slice 6 marked done in the task list.

GODOT 4.7 BUMP (committed f4cbb1e). User opened the project in Godot 4.7 (was 4.6). One-line conversion:
config/features "4.6"->"4.7"; config_version stays 5, no scenes touched. NOTE: the WSL headless binary
`~/.local/bin/godot` is still 4.6 -- it opens the 4.7 project fine for parse/headless checks but prints a
version warning. Bump it to 4.7 only if a clean headless run is wanted.

ENDGAME REPLANNED (grill 2026-06-26) -- full plan is in the task list under "## Stage 1 - Alpha demo"
(CURRENT WORKSTREAM). Summary: engine/editor/link-layer/save/tutorials are all DONE, so the remaining
work is a 2-stage CONTENT plan, not a systems gap. STAGE 1 = expand the toolkit (2 enemy candidates
pyramid+cylinder, design-spec-then-build; 3+ props -- floor button, closing/airlock gate, remote-noise
button, laser/tripwire, PITFALL TILES) + a gizmo tutorial each, then ship an EXPORTED Windows build to an
alpha squad with a level-making + best-capstone-time contest (sharing/voting low-tech/external via the
existing user://levels menu + Discord; NO export_presets.cfg yet -- de-risk with a throwaway export EARLY).
STAGE 2 = fold in alpha feedback, amass content, polish to a price tag (this is the priced-release goal;
the 15-20 level grind + composites + cosmetics + new enemies all live here). An editor-usability pass
(readable control hints + sane bindings) gates the demo since strangers will author levels.

PITFALL TILES decided this session (collapsing floor; full SPEC in the task list): new BASE_TILE, breaks
when the cube's WHOLE footprint vacates it -> becomes ordinary void (impassable gap, not a death-fall).
PLAYER-only trigger (broken void blocks enemies for free via enemy_sphere's live is_floor check). Visibly
fragile from the start, breaks INSTANTLY on vacate. OPEN EDGE CASE flagged by the dev: does an extend-then-
collapse (shape-change) vacate count, or only a tumble? -> resolve in the pitfall spec pass.

EVENING NOTES (2026-06-26, triaged into the task list, NOT implemented):
- UI/UX not user-friendly -> widened the pre-demo polish item to a "UI/UX + accessibility pass
  (ALPHA-BLOCKING)": general UI cleanup + a SETTINGS menu (accessibility + user-facing control REMAPPING;
  collect the squad's remaps as feedback) + fold in the deferred control-scheme overhaul.
- WORMING: dev's emergent movement tech (extend-then-collapse repeatedly = silent fast travel). Exploitable
  but maybe a feature -- WATCH in alpha, don't preemptively nerf; reserve lever is an extend OVERHEAT reusing
  the dodge cooldown (single timer). Replaces the vague "movement tech" parked thread.
- BLEND between mismatched walls: ANSWERED (working-as-designed, no partial blend). _is_in_cover needs an
  opposite pair of sides walled to EXACTLY the cube's top height per-cell; mismatched heights can't both
  match so it just doesn't blend. Logged as a design note, no action.
- BLEND in GLASS: DECIDED no -- glass must NOT count as cover (it's see-through, so blending against it =
  invisible-behind-a-window, an exploit). Today it DOES (glass is a layer-1 Wall* solid). Fix filed in the
  task list: cover probe ignores group "glass", glass stays solid for movement. Small (~5-10 lines), do
  before alpha. NOT yet implemented.

PARKED THREADS: (1) WORMING (see evening notes) -- decide after alpha. (2) Per-object design grills owed
before building each enemy/prop (pyramid, cylinder, floor button, closing gate, remote-noise, laser/
tripwire, pitfall).

NEXT (obvious first move): the throwaway Windows export to de-risk distribution, or kick off the first
per-object design grill (pyramid or pitfall). Optional voice setup still pending the user's `sudo apt
install sox pulseaudio-utils` (WSL mic for the native voice skill; WSLg PulseServer is live).

## Session 10 (2026-06-23): Link layer SLICE 4 (wizard) BUILT + SLICE 5 (dogfood) DONE
Built the wizard end to end in `editor.gd`. The big remaining link-layer piece is now in.

SLICE 5 DOGFOOD + PROMOTE (2026-06-23): user drove the actual wizard on a stripped tut_07 base I
dropped in their user:// (full level minus the 6 lock components), authored both puzzles, playtested,
and tweaked unlock2 to (36,14)[1,1,3] (a permutation of lock2's [1,3,1], reachable, no softlock).
Wizard emitted byte-correct independent links (loader keeps 4/4; lock1 wired to gate1+unlock1 only,
no cross-talk). PROMOTED to res://levels/data/tut_07_convergence.json (name restored to "Convergence";
parse-clean). The wizard now authors SHIPPED content. NOTE: user runs NATIVE WINDOWS Godot, so user://
is at /mnt/c/Users/steve/AppData/Roaming/Godot/app_userdata/Cube/ -- NOT the WSL path (see auto-memory
project_windows_userdata_path). The dogfood file tut07_wizard_dogfood.json is still in their user://.

BACKFILL RETIRED (2026-06-23, user approved): removed `_backfill_global_coupling` + `_has_lock_edges`
(level_loader) and the `lock_id==""` legacy mode (guide_line); `_wire_lock_links`/`_build_lock_links`
run the explicit path unconditionally. A no-edge lock level now wires nothing + draws no guide lines
(+ warns per id-less lock). Verified: parse clean, no shipped level affected (all 3 carry links), and
_wire_lock_links on real tut_07 nodes injects each gate/unlock to its own lock, no cross-talk. The
runtime is purely explicit-links-only now. COLLATERAL (accepted): 4 pre-wizard user:// scratch levels
went inert (convergence, extension, fun_game_1, my_level_2) -- re-author via the wizard if wanted.

POST-PLAYTEST FIXES (2026-06-23, user drove the wizard; "it passes for now")
- Wizard back rebound off pad-X (clashed with sprint) to **L3** (button 7, free). Keyboard Shift+Tab
  unchanged. project.godot + editor.gd labels updated.
- LOCK attention fix (extend_lock_zone.gd + guide_line.gd), a GAMEPLAY bug surfaced while testing:
  arming a lock used to HIDE every lock's telegraph (its own shape-ghost, the floor tile, and all
  OTHER locks) because the telegraph keyed off the global `is_extend_locked()`. Now while any lock is
  engaged, every lock drops to a quiet DISABLED state (dim grey unlit tile, no icon, no expand ghost)
  instead of vanishing; the live unlock + its guide line keep attention. Guide-line cross-puzzle bleed
  also fixed: a lock->gate line shows only while NOTHING is engaged (was visible for a different
  puzzle while you were committed elsewhere). Single-lock shipped levels unchanged (truth-table
  verified). User picked "dim ALL locks" (not just the active one). See task list N15. NEEDS a visual
  feel-check on a multi-lock level (e.g. tut_07 or a 2-puzzle wizard playtest).
- Deferred (task list): holistic control-scheme rebind + more readable editor on-screen control hints.

WHAT IT DOES
- New tool-menu entry "Lock Puzzle (wizard)". Grouped-sequence flow: place lock(s) -> gate(s) ->
  unlock(s) -> finish; finishing loops to a fresh independent puzzle.
- CONTROLS (tunable on feel-check), keyboard / controller:
  - next stage: **Tab / Y** -- past the unlock stage this finishes the puzzle and starts the next one.
  - previous stage: **Shift+Tab / L3** (`editor_wizard_back`, NEW action in project.godot) -- steps
    back within the SAME puzzle to add more of an earlier role; stops at lock, never crosses into the
    prior puzzle. Safe because wiring is all-to-all / order-independent. Checked BEFORE editor_menu in
    `_unhandled_input` (and guarded by `_wizard_active`) because Shift+Tab also matches plain-Tab
    editor_menu; handling back first + returning shadows that. Verified by an InputMap-match test.
    (Originally pad-X, but X=sprint in gameplay; moved to L3/button 7, free. A holistic control-scheme
    rebind is deferred -- see task list Deferred.)
  - finish & exit: **` / View(Back) button**.
  - erase a placed object (drops it + its group): **X-key or Backspace / B**.
  Placement itself is the EXISTING zone (BE-the-shape) / gate (node-path) tooling, untouched.
- Each placed lock/gate/unlock gets an in-memory `group` tag (sibling to id/params in `_objects`,
  NOT serialized). On save, `_serialize` -> `_build_links`:
  - `_mint_link_ids` gives every grouped object a scan-unique id (lock1/gate1/unlock1...), written
    into `params` so it's stable + idempotent (re-saving never renames).
  - `_emit_group_links` emits all-to-all OR within a group (every lock `opens` every gate, every
    lock `released_by` every unlock). Separate groups = independent puzzles.
  - Unions those with the level's LOADED links (now stashed in `_load_data` as `_loaded_links`),
    pruning edges whose endpoints were deleted. This fixes a latent bug: serialize used to hardcode
    `"links": []`, so editing+saving ANY linked level silently dropped its relationships. Now links
    round-trip (object ids already rode in params).
- Readout shows the active puzzle number, stage, and L/G/U counts.

VERIFIED (headless, ~/.local/bin/godot v4.6)
- Parse clean (no SCRIPT/SHADER errors).
- 19 link-logic checks pass: single all-to-all puzzle, two-puzzle independence (no cross-talk),
  lock-only commit-to-shape (id minted, no edges), round-trip + dangling-edge prune, mint-uniqueness
  vs loaded ids, idempotent re-build.
- Serialize->loader e2e: a wizard puzzle's emitted edges parse via `LevelLoader._parse_links` with
  zero dropped, and all objects carry ids. Emitted format is byte-identical to the migrated levels
  (level_01/tut_03/tut_07) the user already confirmed behaviorally.
- InputMap match: plain Tab matches editor_menu but NOT editor_wizard_back; Shift+Tab matches the
  back action. So forward/back never collide.

NOT VERIFIED (needs the user, can't drive the editor GUI headless)
- The interactive feel: Tab/stage flow, per-stage placement, the readout, the wizard controls.
  Drive it on a real playtest. Controls are explicitly "tunable on feel-check".

OPEN / NEXT (pick ONE) -- link layer is now COMPLETE (slices 1-5 done + backfill retired)
1. **Slice 6** editor warnings panel (gate with no opener, unlock with no lock, missing start/end,
   end unreachable, unlock dims not a permutation, floating overlay). Now that the runtime is
   explicit-links-only, "id-less lock / unlinked gate" are real authoring mistakes worth surfacing.
2. **Closing/airlock gate** candidate (new `closes` link kind) -- see task list Link layer Candidates.
3. **N5c then N5d** guide-line polish (jump cost scales with void width; line origin at tile edge).
4. Optional: re-author the 4 now-inert user:// scratch levels (convergence, extension, fun_game_1,
   my_level_2) via the wizard, or delete them.

---

## Session 9 (2026-06-22): OFF-PROJECT tooling, NO cube code changed
Side/tooling work only:
- Built the user-level `/idea` capture skill (`~/.claude/skills/idea/SKILL.md`): near-frictionless
  game-idea capture into the game-dev vault.
- Fixed the status-line script (`~/.claude/statusline.py`): it read the wrong rate-limit fields
  (`utilization`, ISO reset) vs the real schema (`used_percentage`, epoch `resets_at`). Now correct,
  shows percent-remaining plus a live countdown; `settings.json` got `refreshInterval: 60`.
- Dogfooded `/idea` by capturing a new game idea, "Quiet Town" (music-first owl game), into game-dev
  (committed + pushed). USER HAS NOT YET REVIEWED that capture or the skill's output quality.
- Skill 2 (idea EXPANSION, grill+teach style) is DESIGNED in conversation but NOT built. Details in
  auto-memory: project_idea_pipeline.

The cube link-layer state below is UNCHANGED and remains the cube NEXT (slice 4 wizard, etc.).

---

# Handoff, 2026-06-22 (session 8)

## Headline
Link layer LARGELY BUILT (runtime + content), the editor wizard FULLY DESIGNED (not built),
two guide-line polish notes triaged, plus a status-line side quest.
1. **Link layer slices 1, 2, 3 DONE + slice 5 CONTENT** (tut_07 hand-authored). All three shipped
   lock levels run on explicit links; per-lock guide lines; tut_07 has two independent puzzles.
   Behavioral feel-check CONFIRMED by user (all working as expected).
2. **Wizard (slice 4) fully designed via a grill** (grouped-sequence, OR all-to-all within a group).
   NOT built. Full buildable spec is in the task list "Link layer" slice 4.
3. **N5c + N5d** guide-line notes triaged (see task list "Lock/gate guide lines").
4. Status line now shows ctx% + 5h rate-limit% + reset countdown (`~/.claude/statusline.py`; user
   config, NOT a repo file).

## Link layer -- what's BUILT (level_loader.gd, player.gd, extend_lock_zone.gd, extend_lock_gate.gd, guide_line.gd)
- **Slice 1 (schema):** `_parse_links` / `_object_ids` parse + validate the generic `{from,to,kind}`
  edge list (structure + endpoints), drop malformed/dangling with a warning, store `data["links"]`.
  Object `id` is the per-instance key (distinct from `type`). `kind` is opaque (generic plumbing).
- **Slice 2 (runtime):** player holds `_active_lock_id` (ONE at a time, since the cube is one shape)
  + `set_active_lock`/`clear_active_lock`/`active_lock_id`; `is_extend_locked()` == id != "". Loader
  `_wire_lock_links` injects `gate.opener_ids` / `unlock.release_lock_ids` (ARRAYS -> many-to-many
  capable) / `lock.link_id`; objects react per-id, EXPLICIT-LINKS-ONLY. `is_extend_locked()` still
  gates the global concerns (extend/collapse barred, locked colour).
- **TRANSITIONAL `_backfill_global_coupling`:** any level with locks but no links gets the OLD global
  behaviour reproduced (all-to-all, minted `__lockN` ids) through the explicit machinery. KEEP IT
  until the wizard authors links everywhere -- it protects user-made lock levels with no links.
- **Slice 3 (migration + guide lines):** level_01 + tut_03 carry real links now. `guide_line.gd` is
  per-lock (a `lock_id` tag tracks that lock; `lock_id == ""` is the legacy global mode for backfill
  levels). `_build_lock_links` draws per-edge for linked levels, the old locks[0] anchor for backfill.
- **Slice 5 content:** tut_07 hand-authored -- puzzle A `lock_a`[8,27] 3x3x3 -> gate_a -> unlock_a;
  puzzle B `lock_b`[27,9] 1x3x1 -> gate_b -> unlock_b. Headless 7/7: each gate opens for its OWN lock
  only. STILL OPEN: dogfood the WIZARD on tut_07 (slice 5 proper) and retire the backfill afterward.

## Wizard (slice 4) -- DESIGNED, ready to build. FULL SPEC: task list "Link layer" slice 4.
Grouped-sequence wizard: a "Lock Puzzle" tool, explicit-advance stages (1+ locks -> 0+ gates -> 0+
unlocks -> finish group, loop per puzzle), all-to-all OR wiring within a group. Reuses existing
zone/gate placement. Hook points: `_objects` entry gains a `group` tag; `_serialize` (~L939) mints
ids + emits the links; tool menu adds the mode + stage counter; round-trip stashes loaded links and
unions new ones (object ids already ride in params). All logic is data/serialize side, so the future
editor overhaul (WYSIWYG inert objects + shared LevelBuilder) won't disturb it. Boundaries: no
in-place re-wire, no sub-pairing within a group, no AND, no generic link tool.

## OPEN / NEXT (pick ONE)
1. **Slice 4 (wizard)** -- fully designed, ready to build. The big remaining link-layer piece.
2. **N5c then N5d** guide-line polish (jump cost should scale with void width; line origin at the
   tile edge not centre). Small, contained, independent of the wizard.
3. **Slice 6** editor warnings panel. After the wizard.

## Verify recipe (unchanged; ~/.local/bin/godot v4.6; FROM cube dir; exit 0 even on errors)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|SHADOWED"`
- Logic test: throwaway `extends SceneTree`; `LevelLoader.new()` then call _parse_links/_wire_lock_links/_route directly.
- Smoke-load: throwaway SceneTree sets `LevelLoader.requested_file`, instantiates painted_level.tscn
  into root, awaits ~30 process_frame, finds nodes (LockZone%d/Gate%d) and asserts. Clean up .gd + .uid after.
