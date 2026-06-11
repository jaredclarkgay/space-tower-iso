# Floor Lifecycle — Blank Shell → Lush, via Placement

**Status:** NOT STARTED (2026-06-11) — this is the next major build. Authored 2026-06-10.
**Track:** Make-it-agentic that serves make-it-playable (see `docs/vision.md` §4).
**Builds in:** Claude Code (needs the engine + screenshot harness).
**Grounding:** a code survey of the live floor system (refs below are real as of
this date — re-confirm before editing). Reads with `docs/floor_design_system.md`
(the universal floor grammar this must fit) and `docs/opening_sequence_spec.md`
(the narrative beat that triggers the Garden's first population).

> **Build status — 2026-06-11.** Not started, BUT the opening sequence already
> shipped the seam this spec plugs into, so reconcile before building:
> - The **gate already exists** — `GameState.interiors_unlocked` +
>   `utilities_all_active()` (`opening_sequence_spec.md`, BUILT). It currently
>   **unlocks planting directly** (the interim). This spec's whole job is to make
>   that lifted gate unlock **population → ALIVE → planting** instead — i.e.
>   *replace* the interim, not add a parallel path.
> - The **Director→mouth channel exists** (`GameDirector.issue_directive` /
>   `register_mouth`). The "floor is alive" beat should be a **directive through
>   that channel** (Cody's mouth), not bespoke dialogue — Step 3 below.
> - Telemetry already emits `director_beat` / `utilities_complete` / `gate_lifted`,
>   and `agent/analysis/session_summary.py` now reads an OPENING FUNNEL. Add the
>   spec's `component_placed` / `floor_alive` events into that same funnel.
> - Still **net-new:** the per-floor `populated`/`alive` state, the placement verb
>   + palette, the bloom on the threshold, and rerouting the gate payoff to it.

## The idea

A floor begins as a **blank shell** and the player brings it to **life** by
**placing the components that belong to that floor**. The shell is the building;
the components are what make a Garden a garden, a lounge a lounge. As the player
places, the floor crosses from inert to **alive** — light, ambience, and motion
arrive as a felt moment.

This is the first, deliberately-simple version of a dynamic that will grow much
richer (`docs/vision.md`: "building each floor far more fun than a button"). For
now the goal is the **transition itself** — blank → lush — feeling compelling,
and the **lifecycle** being reusable across floors.

**Prove it on the Garden first.** Its content systems already exist, so we layer
the lifecycle on rather than inventing content. Later floors (the blank shells
Residential / Sky Lounge) adopt the same lifecycle with their own component sets.

## Locked decisions

- **Garden is the first floor** to carry the blank → lush lifecycle.
- **Population is a placement mechanic** — the player selects floor-appropriate
  components from a small palette and places them; the floor populates as they
  do. (Not an auto-bloom or a single button.)

## The architectural insight (why this is additive, not a rebuild)

The survey confirmed the seam you want **already exists**:

- Every floor builds **chrome** (slab, walls, elevator, spine, vacuum tubes) via
  shared `FloorChrome` static functions, then attaches its **content** as sibling
  nodes in `_ready()` (`scenes/garden/iso_floor.gd` `_ready()` ~L47).
- The two blank floors prove the shell stands alone: `scenes/residential/residential.gd`
  and `scenes/sky_lounge/sky_lounge.gd` build chrome and stop.
- `GameState.built_level` gates a floor's **visibility/collision**, NOT its
  content (`autoloads/game_state.gd` ~L60; `tower_controller` ~L415). Content is
  currently always built at startup.

So we are **not** inventing a shell/content split — it's there. What's missing is
small: (1) a per-floor **populated state**, (2) **gating content on it** instead
of building at startup, and (3) the **placement interaction + the alive
transition**.

## The lifecycle (the reusable part)

A floor moves through three states, tracked in `GameState` per floor (net-new —
no per-floor "alive" flag exists today):

```
BLANK            shell only (chrome built; zero content)
   │  player places the first component
POPULATING       some components placed; floor partly alive
   │  population crosses the floor's "alive" threshold
ALIVE            fully lit, ambient, operational; its gameplay loop is open
```

Model as a per-floor state dict, e.g. `GameState.garden = { populated: 0, alive: false, placed: [...] }`,
mirroring the shape of `GameState.utility`. Keep a small helper for "is this floor
alive" so gates elsewhere read one call. **Distinct from `built_level`** — that's
visibility; this is content/life.

## The placement interaction

A floor in BLANK/POPULATING exposes:

- A **palette** of floor-appropriate component types (a few, not many) — surfaced
  in the bottom-centre "floor tools" HUD slot (per `floor_design_system.md` §6),
  mirroring the existing seed selector's shape.
- **Placement slots / valid ground** — where a component may go. Reuse the plot
  grid's cell math for the Garden; generalize later.
- A **place verb** (tap-E grammar, `floor_design_system.md` §8): select a
  component, move to a valid slot, place it. Each placement: spawns the
  component's visuals, advances `populated`, and plays a small "it's taking shape"
  feedback (reuse the plant dirt-poof family in `iso_floor.gd` `_spawn_plant_dirt_poof`).
- When `populated` crosses the floor's **alive threshold**: flip `alive = true`,
  run the **bloom** — lights warm in, ambience shifts (the controller already eases
  per-floor mood; `tower_controller` environment drive), and the floor's gameplay
  loop opens. House style: "feel a moment." A **Director beat** (Cody) should
  acknowledge it — population direction flows through the same mouth channel as
  the opener (`docs/vision.md` §1, `opening_sequence_spec.md`).

## Garden as the first instance

**Start state:** barren — shell + bare ground, no starter crops (the opening spec
already removes `_seed_starter_garden()`), planting gated until ALIVE.

**Component palette (first pass — keep it to ~3 to prove the loop):**

- **Planter bed** — placing one activates a small cluster of plantable plots
  (reuse the existing plot/seed/grow/harvest system on those cells). This is the
  bridge: placement assembles the Garden; the existing crop economy runs on what
  you placed.
- **Grow-light rig** — lights + visibly warms its radius; contributes to "alive."
- **Water feature / trough** — a flow visual (reuse `_build_water_pipes` motifs);
  contributes to "alive."

**Alive threshold:** a small count (e.g. first planter bed + one of each, or N
total placements) — tune by feel. Crossing it = the Garden bloom + Cody's
"now it's a garden — go ahead and plant" beat + planting unlocks.

**Composition with the opening sequence:** the chain becomes
`enter (barren) → meet Cody → power utilities → Cody: "let's build it out" →
PLACE components → Garden crosses ALIVE → plant crops`. The opening spec's Step 5
payoff ("planting unlocks") becomes "**population unlocks**"; planting unlocks one
step later, when ALIVE.

### Load-bearing sub-decision to resolve early (don't guess blind in-engine)

Does the Garden's existing auto-built **plot grid + dispenser** become
**player-placed** (full reframe — truest to the vision, but rebuilds core Garden
wiring), or do they **stay**, with placement adding a thinner "life" layer on top
(planter beds activate *zones* of the always-present grid; lower risk)?
**Recommendation:** the thinner layer for the first increment — keep the grid
system, start it dormant/empty, let placed planter beds *activate zones* of it.
Proves the placement→alive loop without gutting the economy. Promote to full
reframe once the loop feels right. Log the call in `agent/request_queue.json`.

## Reusable abstraction (how later floors adopt it)

A floor opts into the lifecycle by declaring: its **component palette**, its
**valid slots**, and its **alive threshold + bloom**. Residential's components
might be units/furnishings/residents; the Sky Lounge's, seating/bar/decor. The
lifecycle, placement verb, HUD slot, telemetry, and bloom are shared; only the
content list differs — the same way `FloorChrome` is shared and only content
differs today.

## Telemetry (measure the new loop)

`Telemetry` autoload is wired. Add `record(...)` calls so the funnel is visible:
- `component_placed` (floor level, component type) — each placement.
- `floor_alive` (floor level, time since floor first entered) — threshold crossed.

Then `agent/analysis/session_summary.py` answers: do players place components when
invited? how many before the floor feels alive? time-to-alive per floor?

## Build sequence — incremental, each step shippable + screenshot-verifiable

Verify every visual/behavioural step with the windowed harness
(`agent/rules/godot_screenshot_harness.md`), never `--headless`.

1. **Lifecycle state + gate.** Add the Garden state dict (`populated`, `alive`,
   `placed`) and the "is alive" helper. Gate planting on `alive` (composes with
   the opening spec's utilities gate). *Verify:* state flips in a debug readout; P
   stays locked while not alive.
2. **One placeable component + the place verb.** Implement the palette HUD slot +
   tap-E placement for a single component type (planter bed). Placing it advances
   `populated` and spawns its visual. *Verify:* select → place → bed appears,
   counter ticks.
3. **The alive bloom.** When `populated` crosses the threshold, run the bloom
   (lights/ambience warm in) + flip `alive` + Cody's director beat + unlock
   planting. *Verify (harness):* before/after framing reads barren → alive.
4. **Fill the palette + zone activation.** Add the remaining components
   (grow-light, water feature); placed beds activate plot zones for the existing
   crop loop. *Verify:* place beds → plant on them → harvest works.
5. **Telemetry + the reusable seam.** Emit `component_placed` / `floor_alive`;
   factor the lifecycle so a second floor could declare its own palette. *Verify:*
   play a round, `session_summary.py` shows the placement funnel.

Step 1+2 is a coherent first session. 3 is the payoff. 4–5 deepen + generalize.

## Scope guidance + why this is agentic-serves-playable

Hold the line at **placement is simple for now** — a few component types, tap-E,
a great bloom. The richness ("building a floor is fun") is explicitly deferred;
architect the lifecycle so it can grow, don't build it yet. This is a make-it-
agentic build (a reusable floor lifecycle + state machine + Director-voiced
beats) whose entire payoff is a make-it-playable result (a floor you watch come
alive by your own hand). That convergence is the point (`docs/vision.md` §4).
Surface sub-decisions to `agent/request_queue.json` rather than guessing.
