# Handoff, 2026-06-16

## Headline: cube-as-display built and proven as a system. The cube's faces now show state: per-face ink, the dodge cooldown as edge heat (distance-scaled), and fail/success "screen" expressions. Plus left-stick menu nav, wedged as its own fail, and a longer fall. Loop validated; still in feel/clarity iteration.

## State of the build
Core loop validated. Editor is a full tool. Controls reworked. Recent work = playtest-driven
polish, now centered on the cube-as-display system. Everything below is committed and pushed.

## Cube-as-display system (the throughline this session)
The player cube uses a custom shaded shader (shaders/cube.gdshader) whose faces are info
"screens". The player pushes state to it each visual frame via `_push_cube_material()`:
- **Per-face ink** (commit f811c37): inked faces show on the cube, mapped from logical face
  marks to mesh faces via orientation so an inked face rolls with the cube. Replaced the old
  whole-cube tint. Re-pushed at tumble-settle so it doesn't blink one frame stale.
- **Dodge cooldown as heat** (commit 14f7755): a dodge heats the edges (glow builds over the
  slide), dissipates from the corners inward to each edge's middle, then a green edge blink +
  soft chime when ready. PEAK HEAT (and so cooldown TIME) scales with dodge distance, so a
  short/blocked dodge is cheap + quiet -> a movement tech. Replaced the HUD dodge bar. Hot edge
  darkens into a groove so it reads on a white cube, not just the inked one.
- **Fail/success expressions** (commits 301b1a4, latest): on a fail the faces become a random
  "broken screen" (0..3: missing-texture checker, red X, glitch bars, sad/frown face); on a
  clear, a happy face (4..6: smiley, check, sunglasses smiley); a perfect stealth clear (guards
  present, never spotted) shows a rainbow (7). Indices partitioned, named in shader + player.gd
  (FAIL_EXPR_COUNT / SUCCESS_EXPR_START / SUCCESS_EXPR_COUNT / PERFECT_EXPR).
  **Extend the system**: add a branch in expr_color + bump the relevant range; the player picks
  and pushes via `_trigger_fail_face()` (player-side) or `show_success(perfect)` (level-side).

## Also this session
- **Left stick navigates menus** (d08a4ab): re-added the analog ui_* events the WASD override
  had dropped.
- **Wedged is its own fail** (301b1a4): distinct `wedged` signal -> WEDGED state + "Wedged"
  results title, not counted as a fall.
- **Longer fall** (301b1a4): FALL_END_Y -6 -> -25, so a fall plunges into the void (showing its
  fail face) before the results, instead of freezing almost immediately.

## NEXT
1. **Start/end-of-level screen pass** (user flagged): right now the results panel covers the cube,
   so the happy/fail face is barely seen. A proper intro/outro (camera + timing) should show the
   cube's expression, the goal/par, etc. Ties to Cube Game Tasks Phase 8 "Level intro/outro".
2. **`/add-obj` skill** — documented in SPEC_object_anatomy.md, prerequisite (stable registry/
   loader/editor pattern) now MET, so it's unblocked. High leverage before producing objects/a
   level set. (A fail-screen skill was considered and rejected: boilerplate is trivial, the
   creative GLSL isn't automatable.)
3. **Save / progression** — needed for the level set and unlocks the PB/high-score expression
   variants (more success indices, gated on saved data).
4. **Right-stick extend drift** (carried) — needs the user's hands to dial deadzone.
5. More cube-display channels if wanted (debuff readouts — but no debuff system yet).

## Tuning dials (cube display)
- cube.gdshader: edge_band / edge_darken / glow_strength / heat_color / ready_color (dodge heat);
  expr_color patterns; cube_half/dodge_heat/dodge_flash/expression are pushed by the player.
- player.gd: DODGE_FLASH_TIME, _ready_player.volume_db (-15), DODGE_COOLDOWN, FALL_END_Y (-25),
  FAIL_EXPR_COUNT / SUCCESS_EXPR_* / PERFECT_EXPR.

## Open / loose (carried)
- Infinite floor: deep columns + side fade to void (fade_start/fade_end shader uniforms; FLOOR_DEPTH
  must exceed fade_end). Lock-puzzle telegraphs reworked (lock = tile+icon+expand ghost; unlock =
  placement ghost shown only when gate open). Gate = raised/lowered red floor tiles.
- Results panel covers the cube (the start/end pass above).
- Editor previews for gate + lock zone still draw OLD ghosts (preview != play).
- Tutorials: old hand-authored scenes; end screen predates the controller/results rework; rebuild
  as data levels (Phase 9) fixes it.
- DEBUG_DETECTION still true in enemy_sphere.gd. One global extend-lock per level (link layer pending).

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep). RUN FROM THE cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- SHADER runtime errors (e.g. `return` in fragment) are NOT caught by the parse check above; only
  the smoke run catches them: `godot --headless --quit-after 60 res://painted_level.tscn 2>&1 | grep -i "SHADER ERROR"`.
- Logic: throwaway `extends SceneTree` run with `-s`; `await process_frame` after add_child; physics
  queries need ~6-8 frames; `paused = false` if you need the player to _process; annotate test var
  types (untyped dynamic access fails inference); don't assign untyped literals to typed Array[T]
  properties; PackedFloat32 compare with tolerance. Delete the script + `.uid` after.

## Memory
- New `project_cube_display` (the cube-as-display system + how to extend expressions). Standing
  cube memories unchanged.
