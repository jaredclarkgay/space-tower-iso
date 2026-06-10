# CLAUDE.md — Space Tower Iso

> **⚠️ Architecture update — this doc lags behind major refactors.** The game is
> now ONE stacked-world scene: `scenes/tower/tower.tscn` (the `run/main_scene`)
> with a single player/camera/HUD and the floors as offset child nodes under
> `Floors/` (content-named: `Utility, Garden, ArboretumGround, ArboretumCanopy,
> Residential, SkyLounge, Roof`), each at `y = level * FLOOR_3D_STORY_HEIGHT`
> (story height **6 m**), all driven by `scenes/tower/tower_controller.gd`.
> **`level` is 0-indexed: Utility is Floor 0 (the basement), counting up; the Roof
> has no number.** Floors don't scene-swap — you **walk / fall / ride / hop**
> between them in one continuous world, visibility gated to the current floor +
> below. The elevator is a physical car (`scenes/shared/elevator_platform.gd`);
> the Arboretum ground↔canopy stairs + the corner vacuum-lift hop are the other
> two traversal methods. Trees are genome-driven with a developmental growth
> shader (`scenes/shared/arboretum_tree.gd`). **Sections below that describe
> separate-scene floors, a scene-swap elevator, or the OLD 1-indexed floor
> numbers are historical** — trust `scenes/tower/`, the git log, and
> `agent/session_log.md` for current truth.
>
> **Current state at a glance → `STATUS.md` (repo root).** This doc is durable
> conventions; `STATUS.md` is the always-current snapshot, auto-refreshed by the
> session-capture hook. Trust order: code → `git log` → `agent/session_log.md` →
> `STATUS.md` → this file.

## What this repo is

A Godot 4 game built around a single **isometric** view: a controllable character, a pan/zoom/rotate orthographic camera, and a stack of building floors the player brings online and grows.

It began as a throwaway vertical slice testing whether iso should replace Space Tower's old 3D-exterior + 2D-sim split. **That experiment succeeded.** The operator has committed to this direction — iso *is* the baseline, and this repo is now where the game is actively built and expanded, not a slice to be archived. Treat scope-creep guidance from the original brief as superseded; new floors and mechanics are expected here.

The sibling repo `space-tower/` (full game, original two-mode rendering) still exists and is referenced for autoload shape and idioms, but this iso repo is the live direction going forward.

## Current scope (what actually exists)

This is **multi-floor** and has real mechanics. **Canonical floor order** (0-indexed; verified against the elevator destination graph + stairs + vacuum-lift range), listed bottom → top:

| # | Floor | Dir | What it is |
|---|---|---|---|
| **0** | **Utility / Basement** | `scenes/utility/` | Bottom floor / infrastructure. Pull the master breaker, then connect + activate 6 utility sources (water, power, atmosphere, data, waste, cargo). Its spine pipes glow on every floor they pass through. State: `GameState.utility`. |
| **1** | **Garden** | `scenes/garden/` | Spawn / home floor and the mechanically richest one: 30×30 plot grid with a ROYGBV value gradient, player-driven seed planting (south-wall dispenser, 6-cell HUD seed selector, `P` plant verb), Cody GX-5 helper robot (arrival ceremony + dialogue tree + Schematics modal), food economy, three camera modes (ISO / PROFILE / OTS). Scripts keep their `iso_*.gd` names (they describe the renderer, not the floor). |
| **2** | **Arboretum (ground)** | `scenes/arboretum_ground/` | Edge tree plots, `P` to plant a sapling, two tree varieties, continuous growth persisted in `GameState.arboretum.trees`. Straight stairs up to the Canopy. |
| **3** | **Canopy deck** | `scenes/arboretum_canopy/` | Upper half of the Arboretum. Slab built tile-by-tile with pre-cut holes (elevator shaft, stair aperture, tree holes). **No elevator stop** — reachable on foot via the stairs (or a vacuum hop). Renders the crowns of trees grown on Floor 2 once growth crosses a threshold. |
| **4** | **Residential** | `scenes/residential/` | **Blank shell** — fully wired into the tower (slab/walls/elevator/spine/tubes) but no housing or residents yet. A worldbuilding-phase fill. |
| **5** | **Sky Lounge** | `scenes/sky_lounge/` | **Blank shell** — sky-bar observation lounge ringed in floor-to-ceiling glass. Walk up to the glass → **[E] look out the window**: a third-person **POV** — the camera drops over/behind the head (perspective), you **drag** (or Q/R + ↑↓) to free-look, and the body+head turn to face where you look; E/Esc eases back. Looks out at the placeholder `scenes/shared/cityscape.gd`. |
| **Roof** | **Construction Vista** | `scenes/roof/` | The top: open-sky construction deck with a drivable (cosmetic) crane, the shaft topping out, capped corner tubes. No floor number. Reached by vacuum hop. |

> **Numbering note (locked Session 9):** Utility is **Floor 0 (the basement)**; numbers count up; the Roof is unnumbered. Internal `level` is 0-indexed to match the display (`base_y = level * FLOOR_3D_STORY_HEIGHT`). Dirs + `GameState` keys + `Floors/` node names are all content-named so the layout reads itself. The original brief's "Garden = Floor 3" and the Session-8-era 1-indexed numbers are **stale**.

Floors connect three ways: a **multi-destination elevator** (`scenes/shared/elevator_platform.gd` — the car AND its floor chooser both live here) serving Floors **0, 1, 2, 4, 5**; **straight stairs** for Arboretum ground↔canopy (`scenes/shared/stairs.gd`); and the **corner vacuum-lift hop** (`scenes/shared/vacuum_lift.gd`, ±1 floor) reaching everything 0→Roof. The Canopy has no elevator stop; the Roof is tube-only.

Still genuinely absent — **this is the green-field for the narrative-arc work**: a **phase/quest/objective director** (no in-game step sequencer exists), a **day-night / time-of-day system** (there's only a sim clock driving tree growth), **player-driven construction** (floors are built procedurally at startup, not by the player), a **hire/population system** (Cody is a single scripted NPC; Residential has no residents), a **win condition / progression goal**, and **save/load + audio** (both are no-op stubs). Skill-tree unlocks are visual-only; tree growth has no water/sunlight gating yet. (Note: the living iso camera DOES follow the player — that's done.)

## House style (carried over from the slice)

- **Feel a moment.** State transitions get ceremony, not a bare visibility toggle (Cody's arrival, Schematics bounce-in, chat camera close-up).
- **Programmatic visuals.** Placeholder geometry built in code; no imported art pipeline yet.
- **Details make it special.** When something feels off, fix the principle being violated rather than band-aiding it.

## How to run

```sh
godot --path . --editor      # open in editor
godot --path .               # run the main scene (tower.tscn); --debug for the debugger
```

Main scene: `res://scenes/tower/tower.tscn` (the unified stacked world), wired in `project.godot` as `run/main_scene`. **There are no per-floor `.tscn` files** — each floor is a `.gd` controller (e.g. `scenes/garden/iso_floor.gd`) instanced as an offset child `Node3D` of `tower.tscn`, building its geometry procedurally. `tower.tscn` is the only runtime scene. (See the architecture callout at the top.)

The Godot editor app is installed at `/Applications/Godot.app`. The CLI (`godot`) may not be on `$PATH`; alias it or invoke via `/Applications/Godot.app/Contents/MacOS/Godot --path . ...` if needed.

## Constraints (locked)

- Godot 4.x (4.6 targeted), GDScript only.
- **GL Compatibility renderer.** Web export must remain possible.
- No C#, no GDExtension, no plugins beyond what ships with Godot.
- Game code lives under `scenes/`: one **content-named** dir per floor (`scenes/utility/`, `scenes/garden/`, `scenes/arboretum_ground/`, `scenes/arboretum_canopy/`, `scenes/residential/`, `scenes/sky_lounge/`, `scenes/roof/`) plus reusable cross-floor modules in `scenes/shared/`. **A new floor gets its own content-named `scenes/<name>/` dir + controller, inherits `scenes/shared/floor_chrome.gd`** (slab/walls/elevator/spine) + `vacuum_tube.gd`, and is wired into `tower.tscn` (a `Floors/<Name>` node) + `tower_controller._FLOORS` + the elevator `SERVED` list. See `docs/floor_design_system.md`. The two blank floors (`residential`, `sky_lounge`) are the minimal template.
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
| `rules/` | Self-authored skill files (now ~14, indexed below). Each captures a pattern that took real effort to discover. |

When in doubt, **append rather than guess**. Surfacing an unresolved decision in `request_queue.json` beats picking blindly.

### Consulting `agent/rules/` before non-trivial work

Each rule is ~50–100 lines and captures a pattern that took real effort to discover. Reading the matching rule first is a 30-second tax that prevents repeating a failure that's already in the log.

| If you're working on... | Read first |
|---|---|
| **Verifying ANY visual/behavioural change by screenshot (the core loop)** | **`rules/godot_screenshot_harness.md`** — windowed harness, capture modes, the grounding + high-fps gotchas |
| **Adding a floor / vehicle / vertical-traversal method, or ANY cross-floor visual** | **`rules/stacked_tower_invariants.md`** (start here) |
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
| Stairs between Arboretum ground ↔ canopy (Floors 2 ↔ 3) | `scenes/shared/stairs.gd` (the spiral staircase was deleted — see F-019; straight stairs replaced it) |
| Tiled slab with holes (elevator + stair aperture + tree holes) | `scenes/arboretum_canopy/arboretum_canopy.gd` `_build_tiled_slab_with_holes` |
| Multi-destination elevator / floor chooser | `scenes/shared/elevator_platform.gd` (the car + its chooser State machine) |
| Cross-floor entities (tree crown on the floor above, glowing spine pipes) | `scenes/arboretum_ground/arboretum_ground.gd` + `scenes/shared/floor_chrome.gd` `build_passive_spine_pipes` |
| Adding a floor / the look-out camera / placeholder cityscape | `scenes/residential/` + `scenes/sky_lounge/` (blank-floor template), `scenes/shared/cityscape.gd`, look-out mode in `scenes/garden/iso_camera.gd` (`_update_lookout`) |

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
| `docs/vision.md` | **The north star — the "why" layer.** The Director-and-its-many-mouths principle, who Cody is (companion + primary mouth + theme), and the agentic↔playable convergence. Breaks design-decision ties. |
| `docs/opening_sequence_spec.md` | Build brief for the opening sequence (meet Cody → utilities-first gate). Where the director→mouth channel is born. |
| `docs/floor_population_spec.md` | Build brief for the reusable floor lifecycle (blank shell → lush, via component placement). Proven on the Garden first; the mechanic the opening sequence's gate unlocks. |
| `docs/space-tower-project-knowledge-v3.md` | The canonical brief. Constants, design principles, faction vocab, floor signatures, the Reckoning. |
| `docs/space-tower-mvp-spec-v2.md` | MVP scope for the full game (out of scope here, but anchors expectations). |
| `docs/rgb-floor5-design-brief.md` | The RGB experience — describes what the slice must NOT erode. |
| `docs/builder-agent-design-v1.md` | Agent loop, request types, session log shape. |
| `docs/player-journey-map-v3-final.html` | Step 07 "The Garden of Eden" — the visual reference for the **Garden** (now Floor 1). |
| `docs/floor_design_system.md` | **Universal floor rules.** Footprint, walls, camera, lighting, HUD, and interaction grammar every floor inherits. Read before adding a new floor. |

## History — the original slice (all done)

The five-phase vertical-slice brief that started this repo is **complete**, and its STOP-at-scope guidance is retired now that the operator has committed to the direction:

1. **Phase 0** — Bootstrap. Done (`a8317b1`).
2. **Phase 1** — Setup + research (`references/iso_research.md`). Done (`d8e3cb8`).
3. **Phase 2** — Architecture decision: Path B + 3D-orthographic. Done (`16fe1d9`).
4. **Phase 3** — Build the slice (the Garden, now `scenes/garden/`). Done — runnable.
5. **Phase 4/5** — Self-eval + handoff. The slice answered "yes, iso works"; the repo continued past handoff into active development.

## How work proceeds now

This is an ongoing build, driven by the operator's screenshot-and-iterate loop. Still **surface a decision rather than guess** — log open questions to `agent/request_queue.json`, append failures to `agent/failure_log.json` at the moment they happen, and write a `rules/` file when a pattern took real effort to discover. The point of the agent loop is to not repeat solved problems, not to gate progress.

## Style notes

- Mirror the sibling Godot project's idioms (`extends Node` autoloads, `JSON.stringify` + `FileAccess`, snake_case file names, `:=` for typed locals). Don't import its content; just match the shape so a future merge isn't a rewrite.
- Visuals are still programmatic placeholders — but polish is no longer forbidden. The operator's bar is "details make it special": invest in game-feel where it matters (animation, ceremony, lighting) rather than band-aiding.
- Surfacing a question to `agent/request_queue.json` is always cheaper than building the wrong thing.
