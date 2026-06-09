# Space Tower Iso — STATUS

> **What this file is.** The single, always-current, human-readable snapshot of
> where the game is *right now*. It is a lens over the code, not a second source
> of truth. **Trust order stays: code → `git log` → `agent/session_log.md` →
> this file → `CLAUDE.md`.** Code is the primitive; `CLAUDE.md` holds durable
> conventions; `agent/session_log.md` is append-only history; **this file holds
> the present tense.** Use it to brief a fresh agent (or yourself) and to
> generate prompts that are synced to a real baseline.
>
> **Last refreshed:** 2026-06-08 — end of Session 14 (`67a4a1d`) plus an
> uncommitted telemetry pass. **Nothing pushed yet.**

## One-liner

A single-view isometric tower-builder in Godot. You hire a partner, raise a
tower floor-by-floor from an empty lot, walk in, and bring each floor to life —
all in one continuous stacked 3D world (no scene swaps, no level loads). Began
as a throwaway slice to test whether iso should replace Space Tower's old
3D-exterior + 2D-sim split; that experiment succeeded and this repo is now the
live direction.

## Tech / shape

- Godot 4.x (4.6 targeted), GDScript only, GL Compatibility renderer (web export
  must stay possible). No C#, no GDExtension, no plugins.
- ~14,000 lines of GDScript across 43 scripts. Programmatic placeholder art — no
  imported asset pipeline.
- Repo: `~/Developer/Unwind/space-tower-iso`. Sibling `space-tower/` (original
  full game) is referenced for idioms only.

## Architecture (the load-bearing idea)

- **One runtime scene:** `scenes/tower/tower.tscn`, driven by
  `scenes/tower/tower_controller.gd`. There are **no per-floor `.tscn` files** —
  each floor is a `.gd` controller that builds its geometry procedurally,
  instanced as an offset child node at `y = (level − GROUND_LEVEL) × story`
  (story = 6 m).
- **One player, one camera, one HUD.** Floors are gated to "current floor +
  everything below" so the top-down iso view isn't ceilinged. You walk / fall /
  ride / hop between floors.
- **7 autoloads (the only globals):** `Constants` (tunable knobs), `GameState`
  (single source of truth for the world), `SaveManager` + `AudioManager` (both
  ~15-line no-op stubs), `GameDirector` (the narrative phase spine), `TimeOfDay`
  (day/night clock), `Telemetry` (append-only session event stream → JSONL; a
  pure sink, drives nothing). **Litmus:** what's *true* in the world →
  `GameState`; what should *happen next* → `GameDirector`; what *actually
  happened* this session → `Telemetry`.

## The world — 7 floors (0-indexed; Garden is now ground level)

| # | Floor | State |
|---|---|---|
| 0 | Utility / Basement | Real mechanic: pull breaker, connect + activate 6 systems; spine pipes glow up the stack. Now below grade. |
| 1 | Garden | The richest floor + the ground-floor entrance: 30×30 plot grid, seed planting, harvest, Cody GX-5 helper robot, food economy, 3 camera modes. |
| 2 | Arboretum (ground) | Plant saplings; genome-driven trees with a growth shader; stairs up. |
| 3 | Canopy | Glass-floored upper deck; renders crowns of trees grown below. No elevator stop. |
| 4 | Residential | Blank shell — fully wired, no residents yet. |
| 5 | Sky Lounge | Blank shell — has a working "[E] look out the window" 3rd-person POV onto a placeholder cityscape. |
| — | Roof / Vista | Open construction deck, cosmetic crane. |

Three traversal methods: multi-destination **elevator** (serves 0, 1, 2, 4, 5),
**stairs** (2 ↔ 3), corner **vacuum-lift hop** (±1 floor, reaches everything).

## The arc — `GameDirector.Phase` (7 beats, linear spine)

`EMPTY_LOT → HIRE_PARTNER → BUILD_STRUCTURE → BUILD_INTERIORS → ACTIVATE_FLOORS → SHARE → TEMPORAL`

- **Playable now (the front half):** survey the lot → hire 1 of 5 partners →
  raise the tower floor-by-floor as a visible builder watching from the ground →
  walk in through a doorway → occupy the Garden and farm. Plus a working
  day/night lighting cycle (latches on at `TEMPORAL`).
- **Stubbed / shallow:** `BUILD_INTERIORS` (floors currently rise with full
  content — no true shell-then-fit-out split), `ACTIVATE_FLOORS`, and `SHARE`
  are placeholder transitions, not real mechanics. The hire is a name only (no
  mechanical consequence). Save/load + audio are no-ops.

## What just shipped (Session 14 — local only, not pushed)

Reworked the construction experience around continuity + a builder's-eye view:
re-anchored so the Garden is literally the ground floor (basement dropped below
grade), door continuity (you walk in at grade straight into the Garden), a
visible builder who stands back and watches each floor rise, a big central
"Press B" prompt with confirm beats, hid the dead camera buttons during build,
and aspect-aware framing (narrow windows no longer clip the tower).

**Since then:** added the `Telemetry` autoload — an append-only JSONL event
stream recording phase changes, partner hire, crop plant/harvest, and
floor-reached, each timestamped from session start so "time-to-X" is a
downstream delta. Dev/from-source runs write into the repo's gitignored
`_telemetry/` (readable everywhere the repo is); exported/web builds fall back
to `user://`. Gated by `Constants.TELEMETRY_ENABLED` / `TELEMETRY_ECHO`. First
lens on the stream: `agent/analysis/session_summary.py` (latest session →
furthest phase, floors, crops, time-to-X; `--all` aggregates, `--json` for an
agent).

## Biggest open question / next direction

The big **worldbuilding** phase (backlog `Q-005`). The scaffolding is built and
waiting to be filled — who lives in Residential and what do they need? what's
the Sky Lounge for? what *is* the city outside the tower? — plus making the hire
and the floors **consequential** (right now they're mostly cosmetic/narrative).
Other live threads: the Garden's two-currency economy (`Q-003`), and
construct-from-empty polish — true interior split, build cost, crane-driven
placement, partner on-site (`C-001`).

---

## Next move — Playable

*Each "Make it playable" session opens here, picks one, ships it small.*

- Give the **hire** a single mechanical consequence (one stat or one unlocked
  verb that differs across the 5 partners) so the choice stops being cosmetic.
- Add **water / sunlight gating** to one tree variety so growth is earned, not
  automatic — the first real depth on the Arboretum sim.
- Make produce do something: wire one **consumer** for Garden food (a need a
  resident or the player can satisfy) so the food economy closes a loop.

## Next move — Agentic

*Each "Make it agentic" session opens here, picks one, ships it small.*

- Build a **session-summary reader** over the telemetry JSONL (latest session →
  phases reached, time-to-X, planted vs harvested) — the first lens on the new
  event stream, and the seed of the analysis agent.
- Split `BUILD_INTERIORS` into a real **shell-then-fit-out** step in
  `GameDirector` so the phase spine matches the fiction.
- Turn the 5 partners into **data-driven** definitions (one dict/resource) so a
  new partner is data, not code — the flexibility seam for the hire system.
- Add an **objective/step** field to `GameDirector` (the missing in-game step
  sequencer) so phases can carry a player-facing "what now."
- Move `SaveManager` / `AudioManager` off no-op stubs (even minimally) so the
  autoload contracts are real.

---

## How this file stays current

Regenerated by the Builder-Agent session-capture run that fires on `/clear`
(and auto-compact) via your global `~/.claude/settings.json` hook →
`agent/capture_session.sh`. That same run distills `agent/` and now also
rewrites this snapshot from the **code + git log** so it can't drift from
reality. If you ever read this and the code disagrees, **the code wins** — fix
this file (or just `/clear` to regenerate it).

**This file projects the CODE (what exists) — not play data.** The `Telemetry`
stream is a separate projection of *play* (what happened). Keep them apart: do
**not** paste session metrics into STATUS, or it stops being regenerable from
code. Telemetry's only licensed influence here is on the **Next move** lists —
as a human-reviewed recommendation ("nobody reaches Floor 5 → prioritize X"),
never as raw state.
