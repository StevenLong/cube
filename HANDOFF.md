# Handoff, 2026-06-15

## Headline: visual-coherence + lock-puzzle-readability pass from a partner playtest. Perfect vision is now the DEFAULT (LoS kept behind a flag for a future debuff); gate redesigned as raised/lowered floor tiles; lock guide lines route along the grid; end screens have buttons; AA on; playtest has Back to Editor. Loop validated; iterating on feel/clarity.

## What happened this session (all tested headless; gate visuals + AA need the user's eyes)
- **Perfect vision is the default (LoS removed for base play).** The partner playtest with LoS off
  read better, so floor fog and enemy silhouette-fade are OFF by default and gated behind flags for
  a future "blinded" debuff: shader `player_los_enabled` (false) and enemy_sphere `ENEMY_LOS_FADE`
  (false). The temporary DEBUG_XRAY hack from the live session is gone, folded into these.
- **Cones clip on walls from the ENEMY's viewpoint** (shader), so a danger sector stops at a wall
  instead of bleeding through. This was the real cause of "vision through walls on big levels."
  Enemy ACTUAL sight was always a physics raycast (accurate); only the cone visual lied.
- **Wall buffer 16 -> 64** (player.gd MAX_WALLS + shader arrays) so large levels (the 736-tile one)
  don't overflow the cone-occlusion list.
- **Extend through safety edges fixed**: extension now probes at y=0.2 (below the 0.4u edge top), so
  a safety edge blocks extension, not just full-height walls (EXTEND_PROBE_Y).
- **Gate redesigned as raised/lowered floor tiles** (extend_lock_gate.gd): the bright ghost fence is
  gone. Doorway cells are red-grid tiles (same wall shader, red lines) that rise into a 1u blocking
  wall while shut and sink flush into the floor (walkable) when the player commits. Fixes from the
  first cut: red GRID material (not flat black), BOX_H=1.9 so a lowered tile tucks to the floor
  bottom (no poking out below the level), and the loader floors EVERY gate cell (not just the first
  node) so the others aren't fall-through gaps.
- **Lock guide lines route along the grid** (level_loader `_grid_path` BFS over walkable floor),
  not crow-flies. lock->gate line shows while shut, hides when open; lock->unlock line hidden until
  open (guide_line.gd, `visible_when_locked`).
- **End screens (death/finish) have buttons**: Restart / Quit to Menu (+ Back to Editor in playtest),
  controller-navigable, focus on Restart. The old press-any-key auto-loop is gone.
- **Anti-aliasing on**: MSAA 4x + FXAA (project.godot [rendering]). MSAA for geometry edges, FXAA for
  the shader-drawn thin grid lines. If still rough, deeper fix is fwidth analytic AA in the line shader.
- **Playtest exit**: "Quit to Menu" now goes to the MAIN MENU everywhere (consistent). Added a
  **Back to Editor** button (pause menu + results), shown only during a playtest, restoring the
  autosaved editor session. Editor > Continue also still works.

## NEXT (priority order)
1. Right-stick extend precision / drift (carried; dial deadzone WITH the user, see prior handoff).
2. Continue partner playtest notes.
3. Planned but not built (from playtest): extend-lock telegraph rework (single tile + lock icon ->
   ghost of YOUR cube expanding to the required dims on landing; behavior is easy, the icon waits on
   the icon system); floor extending downward to "infinity" (exploratory; pairs with the gate work).
4. Deferred systems: per-face ink + cube-as-display (faces show state/expressions/timers); icon set
   (padlock/key/droplet); save/progression (unblocks the level-intro/par/highscore screen); these
   are the bigger design chunks.

## Tuning dials
- shader `player_los_enabled` (false) / enemy_sphere `ENEMY_LOS_FADE` (false): the future debuff.
- player.gd STEP_RADIUS_* , INPUT_BUFFER_TIME, EXTEND_PROBE_Y, MAX_WALLS(64).
- enemy_sphere NOISE_WALL_MUFFLE, DETECT_* (still untuned).
- extend_lock_gate RAISE_TIME / RAISED_TOP / BOX_H / RED_* colors.
- project.godot msaa_3d(2=4x) + screen_space_aa(1=FXAA).

## Open / loose (carried)
- **Tutorials**: the old hand-authored tutorial scenes' end/results screen is left behind: it predates
  the pause/results-button + controller rework, so it does not work on controller. NOT a problem now
  (tutorials get rebuilt as data levels in Phase 9); noted so it is not lost. Also Cube Game Tasks Phase 9.
- Editor gate preview still draws the OLD ghost fence (in-game gate is now red tiles): preview != play
  for gates until the editor preview is updated. Editor/loader drift (shared LevelBuilder) general issue.
- Cones clip on `Wall*` only, so a raised gate (named "Gate") does NOT clip the cone visual (enemy
  real sight IS blocked by it, via raycast). Add gates to the shader wall list if it reads wrong.
- HIDAPI "gamepad index N" warning on launch = harmless engine/Steam-build phantom-device noise.
- DEBUG_DETECTION still true in enemy_sphere.gd (remove when detection tuning starts).
- One global extend-lock per level (link layer pending); editor warns, loader syncs stale unlocks.

## Verify recipe (`~/.local/bin/godot` v4.6; exit 0 even on errors, so grep)
- Parse: `godot --headless --editor --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|SHADER ERROR|Busy"`
- Smoke: `godot --headless --quit-after 90 res://<scene>.tscn 2>&1 | grep -iE "ERROR|nil|invalid|cannot|failed"` (filter vulkan/audio/display/leaked)
- Logic: throwaway `extends SceneTree` run with `-s`; `await process_frame` after add_child (refs Nil
  otherwise); physics point/ray queries need ~6-8 frames for static bodies; PackedFloat32 compare with
  tolerance. Delete the script + `.uid` after.

## Memory
- No new memory this session; durable design intents live as code comments (perfect-vision flags,
  dodge-escape-by-geography). Standing cube memories unchanged.
