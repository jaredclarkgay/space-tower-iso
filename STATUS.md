# Space Tower Iso — STATUS

> **What this file is.** The single, always-current, human-readable snapshot of
> where the game is *right now*. It is a lens over the code, not a second source
> of truth. **Trust order stays: code → `git log` → `agent/session_log.md` →
> this file → `CLAUDE.md`.** Code is the primitive; `CLAUDE.md` holds durable
> conventions; `agent/session_log.md` is append-only history; **this file holds
> the present tense.** Use it to brief a fresh agent (or yourself) and to
> generate prompts that are synced to a real baseline.
>
> **Last refreshed:** 2026-06-11 — end of Session 17 (`cccf38b`). **Nothing
> pushed yet.**

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
  ~15-line no-op stubs), `GameDirector` (the narrative phase spine **+ a
  directive→mouth channel**: it owns the player-facing direction as data and
  routes spoken delivery to a registered mouth — Cody or the HUD), `TimeOfDay`
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

## What just shipped (Session 17 — local only, not pushed)

**The Director→mouth channel + the first real gate (the opening sequence ships).**
The keystone from `docs/vision.md`: `GameDirector` now owns a `DIRECTIVES` library
(mouth-agnostic content — lines + objective + telemetry id) and a routable channel.
Mouths register with a `mouth_id` + `deliver_directive()`; `issue_directive()`
*broadcasts* to every mouth (the HUD mirrors the objective) **and** routes the spoken
delivery to one (Cody @ priority 10, HUD @ 0). Cody renders directives in a terse
"director mode" distinct from his chatty pull-to-talk tree. On top of it: the
**utilities-first gate** — planting is dead until `GameState.interiors_unlocked`;
while locked the Garden reads *unpowered* (dimmed/cooled preset), and the lock reason
surfaces as a transient HUD toast through the channel, never a silent no-op.
Completing the sixth Utility source calls `GameDirector.complete_utilities()` → flips
the gate, records `utilities_complete`/`gate_lifted`, and Cody confirms — the per-frame
env ease then warms the Garden back to full identity (spine risers glow): a felt
payoff. Both arrival paths now issue the *same* single greeting beat (the dead legacy
"start harvesting" panel that contradicted the gate was deleted). Also: a
core-systems audit fixed **F-030** — a dev chapter-jump that interrupted a
transform-owning traversal mode (crane/elevator/vacuum hop) left the owner running and
froze the player on the wrong floor; every owner now has `force_release()` and teardown
calls all of them. Plus a roof crane plunge gag, the `floor_design_system.md` rewrite
for the stacked world, content-named constants, and a story-height/floor-numbering
truth-sync sweep.

**Earlier (Session 16 — local only).**
**The Garden first-entry cinematic — meet Cody.** Arriving in the Garden is now a
real opening: you walk in, the camera glides behind you, Cody emerges from the
elevator, and you slide straight into the first conversation — one calm,
continuous motion with no snaps, and replayable. The load-bearing change is the
camera model: persistent live `_cam_*` members eased toward per-beat targets in a
single `_drive_arrival_camera` (beats only *set targets*, so hand-offs never
snap); a single yaw→profile rotate is carried across the beat boundary instead of
restarting; sweeps are monotonic (the old `(1−cos)` orbit was a visible reversal,
removed). New **dev chapter-jump overlay** (`scenes/shared/chapter_jump.gd`, gated
on `Constants.DEV_CHAPTER_JUMP`): an always-clickable dropdown to jump to any
beat/floor from any state, backed by the controller's `CHAPTERS` +
`jump_to_chapter()` + a defensive `_teardown_transient_state()`. Plus fixes:
no see-through floor (clamp the cinematic camera over the footprint so it never
looks under the slab at the doorway; tower now sits on the ground with the
basement hidden from above), and `cinematic_reset()` on Cody + the elevator so
the opener replays in full.

**Earlier (Session 15 — local only).** **One persistent place you can enter,
leave, and fall off of.** Retired the
separate empty-lot datum — survey, hire, build, walk-in and walk-back-out now all
happen on one `site_ground` plane at x=0 (no teleport, no ground swap). The
ground reads through the Garden doorways from inside (no void), daylight blends
in near the openings, and the doorway threshold is two-way. New **roof plunge**:
step off the open roof → the camera follows, the body tumbles, lands on the dirt
(fall-catch bypassed), knocked flat ~3 s with a swear bubble, then gets back up
outside. **Containment + phantom-collision fixes:** upper-floor walls sealed with
invisible collision (11 m) above the visible wall so a charged jump can't clear
the perimeter; the site-ground collision is now a frame with the footprint cut
out so the below-grade basement isn't ceilinged. Plus: canopy trees capped so
crowns never poke through Floor 4; elevator shaft capped at wall height +
chooser listed high-to-low; feathered ceiling-ping; extension-grid distance
fade; Utility breaker prompt/arrows fixed to use world position (the basement
rides at y=-6 after the Session-14 re-anchor).

**Earlier (Session 14 + telemetry):** re-anchored so the Garden is literally the
ground floor (basement below grade), builder's-eye construction with a "Press B"
prompt, aspect-aware framing. Added the `Telemetry` autoload — append-only JSONL
event stream (phase changes, hire, plant/harvest, floor-reached, timestamped from
session start), written to the gitignored `_telemetry/` on dev runs. First lens:
`agent/analysis/session_summary.py`.

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

- **Floor-population slice** (the planned next build, `docs/floor_population_spec.md`):
  close the post-gate "now what?" gap. Replace the interim gate→plant with
  gate→populate→ALIVE→plant — slot-based grid-snapped placement of one component
  (a planter bed) on bare ground, with Cody introducing the verb through the
  Director channel. Reuses the gate + directive channel that just shipped.
- Give the **hire** a single mechanical consequence (one stat or one unlocked
  verb that differs across the 5 partners) so the choice stops being cosmetic.
- Add **water / sunlight gating** to one tree variety so growth is earned, not
  automatic — the first real depth on the Arboretum sim.
- Make produce do something: wire one **consumer** for Garden food (a need a
  resident or the player can satisfy) so the food economy closes a loop.

## Next move — Agentic

*Each "Make it agentic" session opens here, picks one, ships it small.*

- Add a **second mouth** to the Director channel (an environment mouth, a PA, or a
  resident) to prove the channel generalizes past Cody+HUD — and/or wire a real
  auto-advance **gate** on a phase transition (the spine is still manually set).
- Split `BUILD_INTERIORS` into a real **shell-then-fit-out** step in
  `GameDirector` so the phase spine matches the fiction.
- Turn the 5 partners into **data-driven** definitions (one dict/resource) so a
  new partner is data, not code — the flexibility seam for the hire system.
- Extend `agent/analysis/session_summary.py` (the telemetry lens, now reads the
  opening funnel) toward an actual recommendation step that feeds Next-move lists.
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
