# Handoff, 2026-06-17

## Headline: started the level-set spine by replacing the tutorial plumbing. Reworked the tutorials menu to data-driven (empty until levels are authored) and parked the stale .tscn tutorials in an Old Tutorials submenu. Then built a new object the observation tutorials need: the glass_wall (solid to bodies, transparent to enemy vision), end to end and verified. Agreed a 6-tutorial set and the editor->tutorial promotion pipeline.

## Tutorials menu rework (the spine for this session) -- Phase 9 plumbing
The old system hard-coded three .tscn scene launchers; the new one mirrors the levels
menu (data-driven). DONE + smoke-verified:
- `tutorials_menu.gd` / `.tscn`: a `TUTORIALS` registry array (currently EMPTY -> shows
  "No tutorials yet"), dynamic rows, launches JSON via `LevelLoader.requested_file` +
  painted_level.tscn. Displayed number = array position (reorder = automatic).
- `old_tutorials_menu.gd` / `.tscn`: NEW submenu reachable from Tutorials, launches the
  three stale `levels/tutorial_*.tscn` for reference. Untouched and removable once their
  content is rebuilt as data levels.
- Nothing deleted; the .tscn tutorials still exist.

## glass_wall object (enabler for observation tutorials) -- new base tile
A 1u wall the body can't pass but enemy VISION sees through: a risk-free window to teach
guard behaviour. DONE + verified (parse, default-level regression, and a built glass level
asserting all wiring). Approach chosen for minimal blast radius: glass is a normal layer-1
`Wall*` solid in EVERY system (player tumble-block, nav routing, noise, blend all free),
and the ONLY detection change is that `enemy_sphere` excludes glass RIDs from its 3 LoS rays.
- `object_registry.gd`: `glass_wall` base tile, glyph `g`. Auto-appears in the editor palette.
- `level_loader.gd`: parses `g`, `_make_glass_rect` (merged panes, group "glass", mesh NOT
  named "MeshInstance3D" so the floor cone reads through it), gives each glass cell a floor
  tile (no void under a clear pane), keeps guide paths off glass.
- `enemy_sphere.gd`: gathers group "glass" RIDs at _ready; `query.exclude = _vision_exclude`
  on `_is_seeing_player`, `_visible_footprint_pos`, `_visible_to_player`.
- `editor.gd`: glass preview mesh (cyan pane, not a grey box).
- `SPEC_object_anatomy.md`: glass added to the base-tile catalog (anti-drift).
- **v1 choices to remember**: glass BLOCKS sound (noise ray still treats it as a wall);
  and because it is a layer-1 wall, the blend-cover test counts it, so DON'T flank the
  player with glass on two opposite sides at their height or they would hide from a guard
  looking through it. A normal one-sided window is unaffected. Both easy to special-case later.

## Agreed tutorial set (signature situation each, not bare mechanic)
1 Movement; 2 First guard (sprint + noise, guard introduced here); 3 Extension (lock gate);
4 Blend (flush-height hide); 5 Ink + water; 6 Detection + pursuit capstone (folds in dodge;
full graduated-detection model lives here). Glass unblocks #2 and #6 (watch the guard safely).

## Promotion pipeline (memory: project_tutorial_pipeline)
Dev builds + names + saves in the editor -> file lands at
`~/.local/share/godot/app_userdata/Cube/levels/<slug>.json`. Dev says "level X is tutorial N".
I copy it into `res://levels/data/tut_0N_<slug>.json`, set `meta.name`, register it in the
`TUTORIALS` array. Shipped = read-only in the editor.

## NEXT (parking list; pick ONE as the next spine)
1. **add-obj skill** (the agreed follow-on). Now that glass is a worked vision-interacting
   example alongside enemy/zone/gate, codify the add-an-object path: registry entry, scene,
   loader builder case, editor palette/preview, PLUS a cross-cutting checklist (nav `Wall*`
   naming, vision mask/RID-exclude, noise, shader occlusion, the .name / .tres gotchas).
2. **Author the tutorial levels** -- dev builds them in the editor (start with 1 Movement,
   which needs nothing new), I promote via the pipeline. TUTORIALS is empty until then.
3. **Broader save vision** (still deferred until a level set exists): unlock chain, cosmetics.
4. **Right-stick extend drift** (carried) -- needs the dev's hands to dial deadzone.

## Open / loose (carried from prior sessions)
- safety_edge still blocks enemy LoS (it is a `Wall*` body); design wants "see over". Untouched.
- DEBUG_DETECTION still true in enemy_sphere.gd. One global extend-lock per level (link layer pending).
- Editor previews for gate + lock zone still draw OLD ghosts (preview != play).
- Results panel covers the cube on level complete (start/end-of-level screen pass still pending).

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep). RUN FROM cube DIR.
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Scene smoke: `godot --headless --quit-after 30 res://painted_level.tscn 2>&1 | grep -i "SHADER ERROR"`.
- Logic: throwaway `extends SceneTree` with `-s`; add a LevelLoader, set
  `LevelLoader.requested_file`, await ~8 frames (loader builds via call_deferred), inspect via
  `find_child`. Clean user://*.json between/after; delete the script + `.uid` when done.

## Memory
- Added `project_tutorial_pipeline` (the promotion workflow + agreed tutorial set).
- glass_wall details live in SPEC_object_anatomy.md + code (not memory, to avoid duplication).
