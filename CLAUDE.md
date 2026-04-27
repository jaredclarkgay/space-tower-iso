# CLAUDE.md — Space Tower Iso (Vertical Slice)

## What this repo is

A throwaway-able Godot 4 prototype that renders **one Garden floor** isometrically with a controllable character and a free camera. It exists to test whether iso should become Space Tower's baseline view, collapsing the existing 3D-exterior + 2D-sim split into a single perspective.

This is **not** the full game. The full game lives at the sibling repo `space-tower/` and continues to ship untouched. If this slice proves the iso pivot wrong, this repo gets archived and nothing is lost.

## What it is NOT

- A rewrite of Space Tower.
- A polished demo. Programmatic placeholder visuals only.
- A staging ground for new mechanics. No build mechanic, no NPCs, no economy, no UI, no audio, no save/load.
- Multi-floor. **Exactly one floor** (Floor 3, the Garden). Stacking is a Phase-N concern, not a Phase 3 concern.

## How to run

```sh
godot --path . --editor      # open in editor
godot --path . --debug       # run main scene (after Phase 3 lands one)
```

Main scene: `res://scenes/iso_prototype/iso_prototype.tscn` (created in Phase 3; project will refuse to run before then — that's expected).

The Godot editor app is installed at `/Applications/Godot.app`. The CLI (`godot`) may not be on `$PATH`; alias it or invoke via `/Applications/Godot.app/Contents/MacOS/Godot --path . ...` if needed.

## Constraints (locked)

- Godot 4.x (4.6 targeted), GDScript only.
- **GL Compatibility renderer.** Web export must remain possible.
- No C#, no GDExtension, no plugins beyond what ships with Godot.
- All new game code lives under `scenes/iso_prototype/`.
- The four autoloads (`Constants`, `GameState`, `SaveManager`, `AudioManager`) are the only globals.

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

## Phase gates (from the brief)

The brief at `iso-vertical-slice-brief.md` (operator-local copy) defines five phases with hard STOP gates. Honor every gate — surface what was produced and wait for approval before proceeding.

1. **Phase 0** — Bootstrap. **Done** (commit `a8317b1`).
2. **Phase 1** — Setup and research (`references/iso_research.md`). **Done** (commit `d8e3cb8`).
3. **Phase 2** — Architecture decision. **Done** — Path B + 3D-orthographic locked (commit `16fe1d9`).
4. **Phase 3** — Build the slice. **Done** — `scenes/iso_prototype/` complete and runnable.
5. **Phase 4** — Self-evaluation. Pending operator playthrough.
6. **Phase 5** — Handoff (screenshots, summary, push). Pending Phase 4.

## Style notes

- Mirror the sibling Godot project's idioms (`extends Node` autoloads, `JSON.stringify` + `FileAccess`, snake_case file names, `:=` for typed locals). Don't import its content; just match the shape so a future merge isn't a rewrite.
- Programmatic visuals win every tie in this slice. Polish is forbidden.
- Surfacing a question to `agent/request_queue.json` is always cheaper than building the wrong thing.
