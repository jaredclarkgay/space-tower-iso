# CLAUDE.md — Space Tower Iso

## What this repo is

A Godot 4 game built around a single **isometric** view: a controllable character, a pan/zoom/rotate orthographic camera, and a stack of building floors the player brings online and grows.

It began as a throwaway vertical slice testing whether iso should replace Space Tower's old 3D-exterior + 2D-sim split. **That experiment succeeded.** The operator has committed to this direction — iso *is* the baseline, and this repo is now where the game is actively built and expanded, not a slice to be archived. Treat scope-creep guidance from the original brief as superseded; new floors and mechanics are expected here.

The sibling repo `space-tower/` (full game, original two-mode rendering) still exists and is referenced for autoload shape and idioms, but this iso repo is the live direction going forward.

## Current scope (what actually exists)

This is **multi-floor** and has real mechanics. **Canonical floor order** (as the game lays it out — verified against the elevator destination graph + stairs), listed bottom → top:

| # | Floor | Dir / scene | What it is |
|---|---|---|---|
| **1** | **Utility** | `scenes/floor_1/` | Bottom floor / infrastructure. Pull the master breaker, then connect + activate 6 utility sources (water, power, atmosphere, data, waste, cargo). Its spine pipes glow on every floor they pass through. |
| **2** | **Garden** | `scenes/floor_2/floor_2.tscn` *(main scene)* | The mechanically richest floor: 30×30 plot grid with a ROYGBV value gradient, player-driven seed planting (south-wall dispenser, 6-cell HUD seed selector with stock gauges, `P` plant verb), Cody GX-5 helper robot with arrival ceremony + dialogue tree + Schematics modal, food economy, three camera modes (ISO / PROFILE / OTS). |
| **3** | **Arboretum (ground)** | `scenes/floor_3/` | Edge tree plots, `P` to plant a sapling, two tree varieties, 60 s continuous growth persisted in `GameState.floor_3.trees`. Straight stairs up to Floor 4. |
| **4** | **Canopy deck** | `scenes/floor_4/` | Upper half of the Arboretum. Slab built tile-by-tile with pre-cut holes (elevator shaft, stair aperture, tree holes). **No elevator stop** — reachable only on foot via the stairs. Renders the crowns of trees grown on Floor 3 once growth crosses a threshold. |

> **Numbering note:** the numbers above are the *in-game* floor numbers and are canonical; directory names now match (`scenes/floor_1` … `floor_4`). The Garden's dir was renamed from the historical `iso_prototype/` to `scenes/floor_2/` so the layout is self-documenting (the `iso_*.gd` script names inside were kept — they describe the iso renderer, not the floor). The original brief called the Garden "Floor 3"; that is **stale** — Floor 3 is the Arboretum. Floors 3 + 4 together are one double-height Arboretum (ground + canopy).

Floors connect via a **multi-destination elevator chooser** (`scenes/shared/elevator_handler.gd`); the elevator serves Floors 1–3. Floors **3 ↔ 4** connect by **straight stairs** only (`scenes/shared/stairs.gd`) — the Canopy has no elevator stop.

Still genuinely absent (rooms for growth, not constraints): save/load, audio/music, skill-tree unlock logic (visual-only today), a win condition / progression goal, camera-follow on player movement, water/sunlight gating for tree growth (Phase 2B).

## House style (carried over from the slice)

- **Feel a moment.** State transitions get ceremony, not a bare visibility toggle (Cody's arrival, Schematics bounce-in, chat camera close-up).
- **Programmatic visuals.** Placeholder geometry built in code; no imported art pipeline yet.
- **Details make it special.** When something feels off, fix the principle being violated rather than band-aiding it.

## How to run

```sh
godot --path . --editor      # open in editor
godot --path . --debug       # run main scene (after Phase 3 lands one)
```

Main scene: `res://scenes/floor_2/floor_2.tscn` (the Garden), wired in `project.godot` as `run/main_scene`. From there the elevator/stairs reach the other floors.

The Godot editor app is installed at `/Applications/Godot.app`. The CLI (`godot`) may not be on `$PATH`; alias it or invoke via `/Applications/Godot.app/Contents/MacOS/Godot --path . ...` if needed.

## Constraints (locked)

- Godot 4.x (4.6 targeted), GDScript only.
- **GL Compatibility renderer.** Web export must remain possible.
- No C#, no GDExtension, no plugins beyond what ships with Godot.
- Game code lives under `scenes/`: one dir per floor (`scenes/floor_1/` … `scenes/floor_4/`) plus reusable cross-floor modules in `scenes/shared/`. **New floors get their own `scenes/floor_N/` dir and inherit `scenes/shared/floor_chrome.gd`** + the rules in `docs/floor_design_system.md`.
- The four autoloads (`Constants`, `GameState`, `SaveManager`, `AudioManager`) are the only globals. Tunable game-feel knobs live in `autoloads/constants.gd`; per-floor and cross-floor state lives in `autoloads/game_state.gd` (the single source of truth that the iso scene renders).

## The Builder Agent loop

Persistent self-knowledge lives in `agent/`:

| File | Purpose |
|---|---|
| `project_knowledge.json` | Facts about this prototype that don't change session-to-session. Synthesized from `docs/`. |
| `competency_map.json` | What the agent can and can't do confidently. Updated when evidence accrues. |
| `failure_log.json` | Append-only log of what didn't work and why. Append at the moment of failure, not later. |
| `request_queue.json` | Prioritized asks for the operator. Use `request_types` from the queue file. |
| `session_log.md` | Append-only narrative of work. Headed by date and goal. |
| `rules/` | Self-authored skill files. Empty until Phase 4 produces something worth keeping. |

When in doubt, **append rather than guess**. Surfacing an unresolved decision in `request_queue.json` beats picking blindly.

### Consulting `agent/rules/` before non-trivial work

Each rule is ~50–100 lines and captures a pattern that took real effort to discover. Reading the matching rule first is a 30-second tax that prevents repeating a failure that's already in the log.

| If you're working on... | Read first |
|---|---|
| Walk/run/locomotion in `iso_player.gd` | `rules/godot_locomotion_cycle.md` |
| Animation poses (kneel / charge / tuck / land) | `rules/animation_pose_alignment.md` |
| Adding a new `.gd` file referenced by a `.tscn` | `rules/godot_script_uid.md` |
| Fading 3D meshes (alpha tween, etc.) | `rules/godot_3d_fade.md` |
| HUD Buttons that might conflict with `ui_accept` (Space/Enter) | `rules/godot_button_focus.md` |
| `.tscn` fixes "not taking effect" in the editor | `rules/godot_editor_cache.md` |
| `class_name` with the `--headless --import` harness | `rules/gdscript_class_name_caveats.md` |
| Building shared geometry across multiple floors / scenes | `rules/godot_shared_module_pattern.md` |
| GDScript reload warnings about shadowed identifiers (`tan`, `scale`, etc.) | `rules/gdscript_builtin_shadow.md` |
| Label3D / 3D prompts that vanish or shrink as the camera zooms | `rules/godot_label3d_orthographic_zoom.md` (use `scenes/shared/label_scaler.gd`) |
| Number-key / single-key input that works on some machines but not macOS | `rules/godot_input_keynum_macos.md` |
| Stairs between Floors 3 ↔ 4 | `scenes/shared/stairs.gd` (the spiral staircase was deleted — see F-019; straight stairs replaced it) |
| Tiled slab with holes (elevator + stair aperture + tree holes) | `scenes/floor_4/floor_4.gd` `_build_tiled_slab_with_holes` |
| Multi-destination elevator / floor chooser | `scenes/shared/elevator_handler.gd` |
| Cross-floor entities (tree crown on the floor above, glowing spine pipes) | `scenes/floor_3/floor_3.gd` + `scenes/shared/floor_chrome.gd` `build_passive_spine_pipes` |

For specialized work, dispatch to the `godot-iso-builder` subagent (defined in `.claude/agents/`) — it pre-loads project conventions and the rule index.

### Auto-capture on session end

`agent/capture_session.sh` is wired up as a `SessionEnd:clear` and
`PreCompact:auto` hook in `.claude/settings.json`. When the operator runs
`/clear` (or context auto-compacts), the script backgrounds a Claude
headless run that distills new takeaways into `agent/` and commits
them as `chore(agent): capture session takeaways` (no push — operator
reviews + pushes). The hook returns in milliseconds so `/clear` isn't
blocked behind the capture.

The script no-ops if there have been no commits since the last `agent/`
update, so empty-session clears don't spam.

## Decisions log

- **Camera rotate keys: Q (left) / R (right).** Brief proposed Q/E, but `interact` already binds E. Q+R keeps both verbs available without a modifier.
- **Movement: WASD + arrow keys for `move_left`, `move_right`, `move_up`, `move_down`.** Iso projection means screen-space input is mapped to world-space vectors inside `iso_player.gd` (Phase 3).
- **Camera pan: middle-click drag** (handled in `iso_camera.gd`); also bind Shift+arrows in Phase 3 if useful. No InputMap action for raw drag — Godot models that as a mouse motion event handled in `_unhandled_input`.
- **Iso demo source: GitHub clone, not AssetLib.** Phase 1 will clone `godotengine/godot-demo-projects` and copy the iso demo into `references/godot_iso_demo/` with its license.
- **Architecture (Phase 2, locked 2026-04-26): Path B realized as `Camera3D` orthographic on a 3D scene graph**, rotated -30° X / 45° Y, parented to a CameraPivot for 90° rotation. `GameState` is the single source of truth for player position and camera state; the iso scene is one renderer of that world. Rationale: full write-up in `references/iso_research.md` and `agent/session_log.md` Phase 2 entry.

## References to docs/

| File | What's in it |
|---|---|
| `docs/space-tower-project-knowledge-v3.md` | The canonical brief. Constants, design principles, faction vocab, floor signatures, the Reckoning. |
| `docs/space-tower-mvp-spec-v2.md` | MVP scope for the full game (out of scope here, but anchors expectations). |
| `docs/rgb-floor5-design-brief.md` | The RGB experience — describes what the slice must NOT erode. |
| `docs/builder-agent-design-v1.md` | Agent loop, request types, session log shape. |
| `docs/player-journey-map-v3-final.html` | Step 07 "The Garden of Eden" — the visual reference for Floor 3. |
| `docs/floor_design_system.md` | **Universal floor rules.** Footprint, walls, camera, lighting, HUD, and interaction grammar every floor inherits. Read before adding a new floor. |

## History — the original slice (all done)

The five-phase vertical-slice brief that started this repo is **complete**, and its STOP-at-scope guidance is retired now that the operator has committed to the direction:

1. **Phase 0** — Bootstrap. Done (`a8317b1`).
2. **Phase 1** — Setup + research (`references/iso_research.md`). Done (`d8e3cb8`).
3. **Phase 2** — Architecture decision: Path B + 3D-orthographic. Done (`16fe1d9`).
4. **Phase 3** — Build the slice (the Garden, now `scenes/floor_2/`). Done — runnable.
5. **Phase 4/5** — Self-eval + handoff. The slice answered "yes, iso works"; the repo continued past handoff into active development.

## How work proceeds now

This is an ongoing build, driven by the operator's screenshot-and-iterate loop. Still **surface a decision rather than guess** — log open questions to `agent/request_queue.json`, append failures to `agent/failure_log.json` at the moment they happen, and write a `rules/` file when a pattern took real effort to discover. The point of the agent loop is to not repeat solved problems, not to gate progress.

## Style notes

- Mirror the sibling Godot project's idioms (`extends Node` autoloads, `JSON.stringify` + `FileAccess`, snake_case file names, `:=` for typed locals). Don't import its content; just match the shape so a future merge isn't a rewrite.
- Visuals are still programmatic placeholders — but polish is no longer forbidden. The operator's bar is "details make it special": invest in game-feel where it matters (animation, ceremony, lighting) rather than band-aiding.
- Surfacing a question to `agent/request_queue.json` is always cheaper than building the wrong thing.
