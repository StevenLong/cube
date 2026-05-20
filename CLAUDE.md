# Cube - Agent Context

## Project
Stealth puzzle platformer in Godot 4 (3D). The player is a cube in a world of 
geometric shapes. Grid-based tumbling movement, dimension extension, noise-based 
detection, and surface blending to avoid enemies. Short replayable levels.
Metal Gear Solid VR Mission aesthetic - stark, clean, artificial.

## Developer
- Solo developer. Comfortable with GDScript and Godot 2D. Less experienced with 
  Godot 3D - don't assume 3D knowledge, explain where relevant.
- Needs small, completable tasks with visible progress.
- ADHD-related follow-through risk - keep scope tight, flag scope creep.

## Environment
- Windows 10 desktop and Windows 11 laptop, both running Claude Code via WSL (Ubuntu)
- Godot 4.x, Forward Plus renderer, Jolt Physics
- No known rendering constraints

## Code Rules
- Write the minimum code that solves the problem. Nothing speculative.
- Touch only what the task requires. Do not refactor code you weren't asked to change.
- Before handing back a solution, define what success looks like and verify against it.
- When uncertain, say so. Surface tradeoffs rather than picking one silently.
- Always pull before starting a session. Always push before ending one.

## Architecture Notes
*To be filled in as the project develops.*

## Terminology
- **unit (u)**: one cube side length — the grid pitch. Everything is measured in units.
- **cell**: one 1u × 1u grid square. The player occupies exactly one cell at base size.
- **face**: one of the six sides of the cube.
- **tumble**: one move — the cube rolls 90° and advances 1 cell.
- **grid position**: (x, z) in whole units; always integers. The cube's center sits at the cell centre.

## Key Design Decisions
- Grid-based movement. Everything sized in cube-side units.
- Cube tumbles face to face. Movement noise scales with speed.
- Camera-relative controls. D-pad moves in camera-facing direction.
- Extension is free but size affects speed and noise. Compact = fast and quiet.
- Hold RB to enter extend mode. Jump and dodge locked out while extending.
  This is intentional - extending is a positional commitment, not a mid-action tool.
- Detection based on exposed sides and time in enemy view, not binary.
- Environmental marks (ink) leave footprints that enemies can follow.
- Contact with any enemy = instant game over. No health system.
- Spotted = pursuit state. Break line of sight = return to patrol.
- Cosmetic customisation unlocked through optional objectives. Cosmetic only.

## Design Reference
The task list and design doc live in a sibling `game-dev` repo. Find it by searching
for `Cube Game Tasks.md` from the user's home directory on first use.

Progress is tracked in two places, not here: the task list (phase/task status)
and HANDOFF.md (session-by-session state). Read HANDOFF.md at session start.
