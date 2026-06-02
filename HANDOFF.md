# Handoff, 2026-06-02

## Headline: level authoring is now DATA-DRIVEN (paint via a text grid)
The big shift this session: levels are no longer hand-authored `.tscn`. A level is a text
grid in `levels/data/*.txt` plus a loader that builds the playable scene. This was a
deliberate pivot - the user found iterating on level design *through the agent* too slow and
error-prone, and wants to author levels directly (and eventually let players make levels).
Step 1 (format + loader) is done and verified; Step 2 (an in-game mouse painter) is next.

## What changed this session
1. **`level.gd` multi-enemy wiring.** Connects every sibling exposing `entered_pursuit`
   (was a single node named `Enemy`) so the Spotted readout reflects all guards. Backward
   compatible with single-enemy scenes and the no-enemy tutorials.
2. **`enemy_sphere.gd` nav-grid footprint fix.** `_build_nav_grid` now blocks EVERY cell a
   wall's `BoxShape3D` footprint covers (was only the centre cell), still keyed off the
   `Wall*` name prefix. This fixed an "enemies walk through walls" bug whose root cause was
   walls NOT named `Wall*` being invisible to nav. **CONVENTION: any wall the sphere must
   path around MUST be named `Wall*`.** (The loader names them `Wall0, Wall1, ...`.)
3. **Data-driven level loader (the pivot):**
   - `level_loader.gd` - parses a grid + enemy lines, builds the world from a template
     DETACHED, positions everything, then attaches in ONE `add_child`. Race-free: every
     `_ready` fires with the full tree present, so Player<->Level circular sibling refs
     resolve, the sphere nav sees the walls, and floor tiles are in-group before `level.gd`
     scans. Mirrors loading a hand-authored scene.
   - `level_template.tscn` - reusable scaffold (WorldEnvironment, Camera, Light, Player,
     Level, UI, StartTile, EndTile). No floor/walls/enemies.
   - `painted_level.tscn` - trivial host: just the loader; `level_file` export points at the
     `.txt` (default `levels/data/level_01.txt`). Set it in the inspector to load another file.
   - `enemy_sphere.tscn` - extracted Enemy subtree the loader instantiates per enemy.
   - `levels/data/level_01.txt` - a THROWAWAY demo proving the loader (a weave-maze + two
     vertical patrollers). NOT a designed level - repaint it (see NEXT).
4. **Menu.** Main menu gained a Levels submenu (`levels_menu.gd/.tscn`); "1: Crossing" now
   loads `painted_level.tscn` (the loader).
5. **Deleted.** Orphan `levels/level_01_movement.tscn`; and `levels/level_01.tscn` - a
   hand-authored hallway+loop level I built mid-session, then superseded by the data loader.

## Level data format (`levels/data/*.txt`)
Grid chars: `.` floor | `#` tall wall (cover, blocks sight, blend-able) | `=` low rail
(safe edge you see over; blocks the cube + nav, NO blend since the cube overtops it) |
` ` (space) void/fall | `S` start | `E` end. Top row = far side; cols = x, rows = z, 0-based
top-left origin. Enemies: `@ col,row col,row ... [speed=N]` - first cell = spawn, rest =
patrol path; waypoint cells must be floor. Keep rows non-empty (blank lines are skipped);
one `S`, one `E`. Verified headless: demo parses to floor=66 tall=24 rails=50 enemies=2.

## EDGE / PERIMETER lesson (carry into level design)
Tall `#` walls block visibility and the floating-in-void look - do NOT ring a level in them.
Platform edges should be open void (fall, see across) or low `=` rails (safe, see over).
Tall walls are for INTERIOR cover only. (This was a user correction; baked into the format.)

## NEXT (order the user picked)
- **Step 2: in-game mouse painter** - palette + click-to-paint floor/wall/rail/start/end +
  save to the `.txt` format. Multi-level selection lands here too: planned seam is an autoload
  (e.g. `level_select` holding the chosen path) the menu sets and the loader reads; right now
  the loader just defaults to `level_01.txt`.
- Step 3: enemies + patrol paths in the painter (ordered waypoints - the fiddly part).
- Near-term: repaint `level_01.txt` into the user's requested patterns - a long hallway with
  alcoves, then a loop around a central block with a circuit patrol - to feel the real gameloop.

## Carry-over from the prior session (still true)
- Sphere is freshly hardened (blend = flush height MATCH, pursuit chases the visible end,
  knock + search-and-clear investigate, wall-clip gate). See memory `project_blend_flush_height_match`.
- **Debug aids STILL ON:** `DEBUG_DETECTION` readout (`enemy_sphere.gd` ~line 52) + the V
  reveal x-ray. With 2+ enemies the readouts overlap on screen. Remove when done tuning (the
  separate "tidy & verify" task). The last-known ghost graduated to gameplay - keep it.

## Outstanding / not done
- `game-dev/Cube Game Tasks.md` (separate repo) still has stale Phase 8C/9 boxes and no entry
  for the level loader / data-driven authoring. Reconcile next session.
- Tutorials + sandbox (`main.tscn`) are still hand-authored `.tscn` (not ported to data). Fine
  for now; could port later once the format settles.

## Verify recipe (`~/.local/bin/godot` v4.6; exit code is 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR"`
- Smoke: `godot --headless --quit-after 120 res://painted_level.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/driver/display noise)

## Memory notes
- Read HANDOFF.md first at session start.
- Levels are data-driven now (memory `project_data_driven_levels`).
- Walls must be named `Wall*` for sphere nav (memory `project_wall_naming_nav`).
- Active verbs cube-only; ink/water binary; Transform3D row-major; no Co-Authored-By; no
  em/en dashes; commit at session end or on request.
