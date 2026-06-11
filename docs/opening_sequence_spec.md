# Opening Sequence — Cody as Director, Utilities-First Gate

**Status:** ★ LARGELY BUILT (2026-06-11). Authored 2026-06-10.
**Track:** Make-it-playable. **Builds in:** Claude Code (needs the engine +
screenshot harness to verify). **Source of grounding:** a code survey of the
live repo (file/function refs below are real as of this date — re-confirm before
editing).

> **Build status — 2026-06-11 (verified against the code).** Most of this brief
> has shipped to `main`; the steps below remain as the *design record*. What
> landed:
> - **Director→mouth channel — BUILT** (`b2e487c`). `GameDirector` owns a
>   `DIRECTIVES` dict (lines + objective + telemetry_beat) and a routable channel:
>   `register_mouth(node, priority)`, `issue_directive(id)`, signal
>   `directive_issued`. **Cody is the primary mouth** (`deliver_directive()`,
>   terse "director mode", separate from his chat tree); **HUD is a passive mouth**
>   (mirrors the objective, renders toasts). This realizes `docs/vision.md` §1–2.
> - **Step 1 (barren Garden + Cody greeter) — BUILT.** Starter garden skipped;
>   Cody off harvest-count.
> - **Steps 2/3/5 (gate + opening beat + payoff) — BUILT** (`4ab9306`).
>   `GameState.interiors_unlocked` + `utilities_all_active()`; planting hard-gated
>   with a HUD-toast reason; Garden dim until the 6th Utility source →
>   `GameDirector.complete_utilities()` flips the gate, warms the Garden, issues
>   the `garden_live` beat.
> - **Step 4 (cinematic entry) — SUBSTANTIALLY BUILT** (`a5224d7`, `dfbd90b`,
>   `606a092`): OTS descend/walk, profile two-shot, zoom-in, replayable.
> - **One first-entry greeting — BUILT** (`2a0fcf7`): legacy "start harvesting"
>   panel deleted; `_finish_arrival` + `greet_on_entry` route through the channel.
>
> **⚠️ Known divergence from the plan:** the lifted gate currently **unlocks
> planting directly** (interim), NOT the floor-population lifecycle the hand-off
> below describes. Replacing that interim is the open work in
> `docs/floor_population_spec.md`.
>
> **Still open:** revamp Cody's chatty `DIALOGUE_TREE` (terser, less
> conversational) so it matches his new director mode.

## The idea

The first link in the real narrative spine. The player finishes raising the
tower, walks into a **barren** Garden, and is met by **Cody — glowing, already
there**, who acts as the game's **director**: he greets you and sends you down
to power on the building's utilities before anything can grow. You go to the
Utility floor, activate all six sources, and return to a Garden that visibly
comes alive — and only now can you plant.

**Director principle:** `GameDirector` decides *what's next*; it speaks through
**mouths**, and **Cody is the primary one** — but not the only possible one.
Build the direction path as a *routable channel* (the Director picks a beat; a
chosen mouth renders it), not as Cody-specific plumbing, so later beats can be
voiced by other mouths without rewiring. See `docs/vision.md` §1–2 — this opener
is where that channel is born.

## Locked decisions

- **Hard gate + payoff.** Planting / interior development is disabled until
  utilities are on. When they come on, the Garden powers up (light + ambience
  warm in) and Cody confirms it's open — the gate lifting is a felt reward.
- **"Utilities on" = all 6 sources active.** The full Utility-floor mechanic:
  pull the master breaker, then connect **and** activate all six sources
  (water, power, atmosphere, data, waste, cargo).
- **Arc modeling:** do **not** reorder the `GameDirector.Phase` enum. Entering
  the Garden sets `BUILD_INTERIORS`; a new `GameState` gate
  (e.g. `interiors_unlocked`) stays false until utilities finish. Gameplay
  gates on the flag, not on a new phase.

## What the survey found (so we build on reality, not the docs)

- **Cody is currently a *reward*, not a greeter** — he arrives only at
  `plants_harvested >= Constants.ROBOT_UNLOCK_THRESHOLD`
  (`scenes/garden/iso_robot.gd`, `_physics_process` ~L91, `_begin_arrival` ~L264).
  His trigger must move to **first Garden entry**.
- **Cody's dialogue is a data-driven tree** — `DIALOGUE_TREE` const (~L1010),
  nodes with `text`/`choices` or `text_func`/`choices_func`; choices carry
  `next` or `action`. Opened via `try_interact()` → `open_dialogue()` (~L765),
  sets `GameState.dialogue_open`. Adding a director node is data, not new plumbing.
- **Cody glows already** — a per-state emissive LED (`_update_led` ~L588), with
  an `_led_override_active` escape hatch for scripted moments. Reuse it.
- **The Garden spawns lush, not barren** — `_seed_starter_garden()`
  (`scenes/garden/iso_floor.gd` ~L404, called from `_build_garden_grid` ~L366)
  pre-plants a mature Voronoi garden. Skip it for a barren start.
- **Camera has what we need** — OTS (over-the-shoulder) mode exists
  (`scenes/garden/iso_camera.gd`, `CAMERA_MODE_OTS` ~L559); plus a soft-focus
  override (`GameState.camera_focus_active` / `camera_focus_point`, `_update_iso`
  ~L296) and a dialogue close-up that frames player + Cody together
  (`_enter_dialogue_focus` ~L467). The cinematic approach is mostly reuse.
- **Utilities are cosmetic today — nothing gates on them.**
  `scenes/utility/utility.gd`: master breaker → `GameState.utility.master_on`
  (~L843); per-source `utility.connected[id]` (~L1026) and `utility.pipe_active[id]`
  (~L1039). **No single "all six active" flag exists — add one.**
- **Entering the Garden sets no phase today** — `tower_controller._spawn_in_garden()`
  (~L132) doesn't advance the arc. The BUILD_INTERIORS step is unbuilt; we wire it.
- **HUD objective line reads the phase** — `tower_hud.gd` `_set_objective()` (~L286).
  Good channel for the "go to the Utility floor" objective, but prefer routing
  player-facing direction through Cody where possible.

## Build sequence — incremental, each step shippable + screenshot-verifiable

Ordered so one session can land a coherent slice. Verify every visual/behavioural
step with the windowed screenshot harness (`agent/rules/godot_screenshot_harness.md`),
never `--headless`.

**Step 1 — Barren Garden + Cody as greeter.** *(smallest first session)*
Skip `_seed_starter_garden()` so the grid starts empty. Move Cody's trigger from
harvest-count to first Garden entry — he's parked by the elevator, glowing,
awaiting you on walk-in (his existing arrival ceremony can play on entry).
*Verify:* walk in → Garden empty → Cody present and glowing.

**Step 2 — The gate + flag.** Add `GameState.interiors_unlocked := false` and a
helper for "all 6 sources active" (derive from `utility.pipe_active`). Disable
the plant verb while locked (the `P` path in `scenes/garden/iso_player.gd` and/or
`iso_floor.plant()`), with a clear reason surfaced ("Power's not on yet").
*Verify:* pressing `P` does nothing + shows the reason.

**Step 3 — Cody's opening director beat.** New `DIALOGUE_TREE` node: Cody greets,
explains the Garden has no power, and directs you to the lower floor. Auto-open
(or strongly prompt) the conversation on first entry. Set the first objective
("Go to the Utility floor — switch on the utilities"), ideally voiced by Cody and
mirrored in the HUD objective line. *Verify:* dialogue reads; objective appears.

**Step 4 — Cinematic entry.** On first Garden entry, a scripted camera move:
over-the-shoulder approach toward Cody easing into the dialogue close-up (reuse
`CAMERA_MODE_OTS` + `camera_focus_active`/`camera_focus_point` →
`_enter_dialogue_focus`). Keep it short; ease back to normal control after the
talk. *Verify (screenshot harness):* the approach + close-up frame Cody cleanly
at the supported aspect ratios.

**Step 5 — The payoff + gate lift.** When all six sources go active, the Garden
powers up — lights/ambience warm in (the controller already eases per-floor mood;
`tower_controller` environment drive) — `interiors_unlocked` flips true, and Cody
delivers his confirming director line ("Power's flowing — now let's build this
place out"). *Verify:* activate utilities → return → Garden lit → the gate is
lifted.

> **Hands off to the floor lifecycle here.** What the lifted gate unlocks is
> **population**, not planting directly — the player now *places the Garden's
> components* and the floor crosses to ALIVE, after which planting opens. That
> mechanic lives in `docs/floor_population_spec.md`; this opener and that spec
> share one barren-Garden start + one gate, so **build the barren Garden + gate
> once** (here, Steps 1–2) and let the population spec layer on top.

## Telemetry (close the analysis loop on the new funnel)

The stream already emits `phase_entered`, `floor_reached`, `crop_planted`. Add
`Telemetry.record(...)` calls (autoload already wired) for the new beats so the
funnel is measurable:
- `director_beat` (with a beat id) when a Cody director line fires.
- `utilities_complete` when the sixth source activates.
- `gate_lifted` when `interiors_unlocked` flips.

Then `agent/analysis/session_summary.py` can answer the real question this
feature raises: *when Cody sends them to utilities, do players go — and how long
until they come back and plant?* (`time_to.first_plant_ms` should finally be
non-null, and we can add a utilities-detour timing.)

## Engraining the vision (build to this, not just to spec)

This opener is the first chance to set the game's north star (`docs/vision.md`)
in actual code. Three things to honor while building, so the theme is load-bearing
rather than decorative:

- **Build the director→player path as a routable channel, not Cody-hardcoding.**
  A "director beat" should be data the Director emits and a *mouth* renders;
  Cody is the mouth here. Concretely: don't bury the utilities direction inside
  Cody's dialogue tree alone — let it originate as a Director beat that Cody
  *delivers*. Future mouths (HUD, environment, other characters) then cost
  nothing. (`vision.md` §1.)
- **Cody's lines are character first, instructions second.** Companion with a
  temperament who *happens* to relay direction — never a tooltip with a face.
  His opening beat should reveal who he is (a little warmth, a little wit, a hint
  of an adaptive/agentic mind at work) while it tells you to go power the floor.
  (`vision.md` §2.)
- **Lean into his agentic nature as a feature.** Cody is the game's proxy for
  living alongside capable, present robots/agents. Let the writing and behavior
  hint that he adapts, anticipates, and grows — this is the seam the game will
  keep pulling on. Don't sand it down into a generic helper. (`vision.md` §3.)

These are also why this "make it playable" beat is simultaneously a "make it
agentic" one: the routable director channel and a characterful, adaptive Cody are
agentic infrastructure whose payoff is a more playable opening. (`vision.md` §4.)

## Scope guidance

Step 1 alone is a complete, satisfying first session (barren Garden + a glowing
greeter changes the whole open). Steps 2–3 make the gate real. Step 4 is the
cinematic polish; Step 5 is the payoff that rewards the detour. Don't try to land
all five blind — ship and screenshot each before moving on. Surface any
sub-decision to `agent/request_queue.json` rather than guessing.
