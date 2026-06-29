# Opening Sequence Redesign — Build Brief (Boot → First Plant)

> **What this is.** A design brief to bring into a Claude Code build session. It
> re-chapters the *current* opening (so the session knows the baseline it's
> replacing) and lays out the *target* flow, grounded in what the code actually is
> today. It is a **design doc, not an implementation** — the session does the code.
>
> **Trust order** (per `CLAUDE.md`): code → `git log` → `agent/session_log.md` →
> `STATUS.md`. File pointers below are orientation, not line-pinned claims; verify
> against current code before editing.

---

## Part 0 — Design principles (the spine of the redesign)

These are the rules every chapter must obey. They're the "much more logical"
you're after.

1. **Free movement is the default; there is exactly ONE hard lock.** The player
   can walk, jump, descend into the pit, and roam anywhere at all times. The
   **only** moment control is taken in the entire opening is when the player enters
   the tower and Cody GX-5 rises from the column. Everything else — building,
   talking to workers, hiring the partner — happens while the player moves freely.
   *(Today the opening seizes the camera in ~4 stretches and freezes the player
   through a ~10s Cody cinematic. That's the core thing being fixed.)*

2. **One consistent interaction grammar.** Today "HIRE A PARTNER" is a centered
   **card UI** while "build" is a **press-B-while-locked** affordance — two
   different grammars for the same kind of moment. Unify them. **Recommended:**
   world-space contextual prompts (`[E]` / `[B]`) that appear as you approach the
   relevant spot, matching how every other verb in the game already works (plant,
   interact, elevator). Decide once, apply everywhere.

3. **The Director speaks through mouths — now there are two.** Both Cody and the
   Partner are *mouths* of the single `GameDirector` (see `docs/vision.md`,
   `autoloads/game_director.gd`). Split their domains cleanly:
   - **Cody GX-5 — the construction & tending mouth.** The literal building:
     raising floors, the column/elevator, growing and tending. The tower's own bot.
   - **The Partner — the business mouth.** A *human* character who **never appears in
     person.** They reach you by **phone** — voiced through a dialogue box exactly
     like Cody's, with a business-person **portrait**. Their domain: external
     resources, contracts, world-specific details that become relevant as the tower
     advances — the things Cody wouldn't touch.

4. **Construction is player-directed and incremental.** Floors build **one at a
   time, when the player chooses**, basement/control-center first. The player is
   **not** locked into building all floors before proceeding. Later **events unlock**
   construction of new floors and floor details. *(This replaces today's instant
   all-6-floors pre-build at startup.)*

5. **Feel a moment — but don't cage the player to do it.** Keep ceremony for true
   state-changes (the Partner's arrival, Cody's rise). Ceremony may move the camera,
   but outside the one allowed lock it must remain breakable — the player can move
   through it.

6. **The construction apparatus rides the top of the tower.** The crane, the three
   workers, and the open construction deck are **always at the current topmost
   floor** — they are not a fixed roof. Each time a new floor is built, they
   **relocate to the edges of that new floor** and keep working from there, so the
   top of the tower is a live worksite that climbs as the building grows. Crucially,
   the **top is see-through** — the player can look *through* the open roof/deck and
   **watch the new floor's elements assemble** (the crane placing them, the workers
   building them on). This is the visual through-line of the whole game: you always
   see *where the building is becoming*. *(This unifies the pit's worksite from
   Chapter 0 with today's static roof "Construction Vista" in `scenes/roof/` — it
   becomes a moving worksite, not a fixed cap.)*

---

## Part A — Current flow, chaptered (the baseline being replaced)

🔒 = player control taken away (frozen and/or camera seized).

| Chapter | Beats | Control |
|---|---|---|
| **0 · Empty Lot** | Boot onto a flat exterior lot, tower hidden. | Free, full camera. |
| **1 · Hire a Partner** | Click centered **card**; pick a partner name. | Free, but **card-UI grammar**. |
| **2 · Construct** 🔒 | Whole tower rises — all 6 floors at once (~0.6s each). | 🔒 Frozen; camera seized into dollhouse framing, then eased to grade. |
| **3 · Exterior Walk + Entry** | Walk across lot, cross the doorway threshold. | Move only; camera owned by controller, eases into iso on entry. |
| **4 · Cody Arrival Cinematic** 🔒🔒 | Scripted auto-walk to mark → Cody emerges from elevator → profile two-shot → dialogue → resume ease. ~10s+. | 🔒 Frozen the whole time. **The big railroad.** |
| **5 · Power the Utilities** | Pull master breaker; connect + activate 6 sources. | Free, full camera. |
| **6 · Garden Population** | Place ≥3 planter beds → Garden goes "alive". | Free, full camera. |
| **7 · First Plant** | Walk to plot, `P`, kneel, sprout. | Free (locked in kneel pose ~0.5s; camera not seized). |

The diagnosis: Chapters 5–7 already respect free movement. Chapters 1–4 are the
railroad — inconsistent grammar (Ch1), a forced pre-build (Ch2), and a long
control-stealing cinematic (Ch4). The redesign keeps the spirit of 5–7 and rebuilds
0–4 around the principles above.

---

## Part B — Target flow, chaptered (the redesign)

### Chapter 0 — The Pit (cold open)

The player stands at grade **in front of a hole in the ground** — a construction
pit, not a flat lot.

- **The crane is IN the pit**, not on the roof. *(Migration: crane currently lives
  in `scenes/roof/crane.gd`.)*
- **The central elevator-column stands in the pit.** The player can **look at it but
  not interact** with it. World-fact to establish: in this world, every tower begins
  as a column sunk into the ground that houses the tower's dedicated bot — a Cody
  GX-5. This is standard practice, not unique to this build.
- **Three construction workers** are down in the pit. Each has a **distinct
  personality** and is **talkable** (`[E]`), in any order:
  - **Worker A — the column / transport.** Comments that the column is the tower's
    spine: as they build, it carries everything (and everyone) upward. *(It becomes
    the elevator.)*
  - **Worker B — the ground / control.** Explains that this ground level becomes the
    tower's **control center** — everything runs from here.
  - **Worker C — the bot.** Excited that once the column is powered/operational, the
    player will **meet the tower's bot**. "First time's always something."
- **Movement is fully free.** Walk the rim, **jump into the pit**, approach the
  column, talk to the workers in any order.
- **Camera:** living iso follow, full player control. No seize.

### Chapter 1 — Hire your Partner

Reframe "hire a partner" into the **world-prompt grammar** (Principle 2) — approach
a marker/spot, `[E]` to hire/choose — *not* a separate card screen. **Three
candidates** to choose from (down from five; **keep Tobin**).

- The Partner **never walks on-screen.** The moment you choose, they **call you** —
  a dialogue box opens (same treatment as Cody) showing their **business-person
  portrait**, framed as a phone call.
- On the call they **explain the situation**: work with your builders to construct
  the **Control Center**, and from there build *the tallest tower humans have ever
  built — floor by floor.*
- Establishes the Partner as the Director's **business mouth** (external resources,
  world details), distinct from Cody's construction focus.
- **Camera:** a phone-call dialogue box needs no arrival cinematic and no lock — the
  player stays free (Principle 1).

### Chapter 2 — Build the Control Center (player-directed, from the crane)

**You build by getting into the crane.** Climbing into the crane cab *is* the build
affordance — the Partner's call explains that *this is how floors go up.* World-prompt
grammar (Principle 2): walk to the crane, `[E]` to take the controls; the build is
issued from the cab, not from a locked "press B" on the ground. Taking the cab is
voluntary and exitable — it's an interaction the player opts into, not a forced lock.

- The player builds the **Control Center floor first**, incrementally, at their own
  direction. They are never forced to build before proceeding.
- **On each build action the whole worksite animates:** all three workers break into
  a **rapid building action** while the floor-build sequence plays out and the crane
  places the new elements.
- **Then the worksite climbs (Principle 6).** Once a floor is built, the **crane +
  the three workers + the open deck relocate to the edges of the new top floor**, and
  the player sees **through** the open top as the elements assemble. Every later
  floor-build repeats this.
- The floors above are **not** built now. They **unlock through later events**
  (Principle 4).
- **Camera:** may lift to frame the build, but **tracks the player and stays
  breakable** — outside the one allowed lock the player keeps movement.

### Chapter 3 — Enter & meet Cody (the ONE allowed lock)

The player enters the tower / the column powers / **Cody GX-5 rises from the
column.**

- This is the **single moment** in the whole opening where control is taken. Keep it
  **tight** — recommend trimming today's ~10s arrival to its essential beat: Cody
  rises, delivers one line, control returns.
- Cody is the **construction & tending mouth** going forward.

### Chapter 4 — Power the utilities (the control center comes online)

The existing six-source utility gate, now diegetically the **control center**
(the basement you just built) coming online.

- Pull the master breaker; connect + activate the six sources.
- **Free movement throughout** (already true today — preserve it).

### Chapter 5 — The Garden floor: build it, then grow it

Consistent with Chapter 2, the Garden becomes a **player-directed floor build**
(unlocked by completing the control center), then placement → "alive".

- Place planter beds (world-prompt grammar) → Garden crosses the alive threshold.
- *(Today the Garden pre-exists; under floor-by-floor it should be a floor the player
  builds.)*

### Chapter 6 — First plant

As today: walk to a plot, `P`, kneel, sprout. Free camera; brief kneel-pose lock
only.

---

## Part C — Concrete code deltas for the build session

A migration checklist tying the vision to today's code. Verify each against current
source before acting.

- **Crane → pit, then make it climb.** Move from `scenes/roof/crane.gd` (roof) into
  the opening pit, then make the crane + workers + open deck **relocate to the top
  floor's edges on each build** (Principle 6) instead of sitting on a fixed roof.
- **See-through top.** The current floor + below are visible (today's gating in
  `scenes/tower/tower_controller.gd`); the **topmost floor's roof/deck must read as
  open/transparent** so the player watches the new floor assemble. Reconcile with the
  existing visibility gating and the roof "Construction Vista" (`scenes/roof/`).
- **Pit geometry.** Replace the flat opening with a hole-in-the-ground pit
  (`scenes/shared/empty_lot.gd`, `scenes/shared/site_ground.gd` are today's exterior).
- **Visible-but-inert central column** in the pit (the elevator-column;
  `scenes/shared/elevator_platform.gd` today lives inside the built tower).
- **Three worker NPCs** with personalities + dialogue. No worker NPC exists today —
  reuse the mouth/dialogue pattern from `scenes/garden/iso_robot.gd` (Cody). They
  **persist**: they help build the tower and **become residents once housing exists**
  (ties into the Residential floor, `scenes/residential/`).
- **Crane as the build controller.** Climbing into the crane cab is the build verb;
  the build action triggers the workers' rapid build + the floor-build sequence
  (`scenes/roof/crane.gd` becomes a usable controller, not cosmetic).
- **Rename Floor 0 → "Control Center"** (from "Utility / Basement"). Reaches
  `scenes/utility/`, `GameState.utility`, the `Floors/Utility` node in `tower.tscn`,
  HUD strings, and the elevator destination labels — scope the rename before doing it.
- **Unify hire + build grammar.** Reconcile `scenes/garden/hire_partner.gd` (card UI)
  with the build lock in `scenes/tower/tower_controller.gd`.
- **Remove the build position-lock** and the **instant all-floor pre-build** in the
  `tower_controller` construction path.
- **Partner is dialogue-only (phone), no world model.** No on-screen arrival — a
  Cody-style dialogue box with a business portrait, framed as a call. Reduce
  `Constants.PARTNER_NAMES` from five to **three** (keep **Tobin**). Wire the chosen
  partner's portrait into the dialogue box.
- **Partner as a second Director mouth** — register via `register_mouth()` in
  `autoloads/game_director.gd`; add business-domain directives.
- **Trim the Cody arrival cinematic** to the one allowed lock.
- **Player-directed, unlock-gated floor construction** — a new system; today floors
  pre-build at startup. Needs an "unlock event → buildable floor" hook.
- **Garden as a built floor**, consistent with the floor-by-floor model.

---

## Part D — Open decisions to resolve in the session

**Resolved — locked into the chapters above:**

- **Diegetic naming** — Floor 0 is the **Control Center** (replaces "Utility /
  Basement").
- **Build mechanic** — you build **from inside the crane** (`[E]` to take the cab);
  each build triggers the workers' rapid build action + the floor-build sequence.
- **Partner presence** — **never in person**: phone-call dialogue box + portrait
  only. **Three** candidates, **keep Tobin**.
- **Worker fate** — the three workers **persist**; they help build and **become
  residents once housing exists**.

**Still open:**

1. **Interaction grammar** — confirm **world-space prompts** as the single trigger
   style for hire + build + interact. *(Recommended. Grammar = how a verb is
   triggered in the world, e.g. a contextual `[E]`/`[B]` that appears as you approach
   a thing — not how a character speaks.)*
2. **First unlock event** — what triggers the *next* floor becoming buildable after
   the Control Center? *(Deferred — decide once building is underway.)*
3. **Crane build UX** — how the cab reads: one-button build vs. aim/place, and the
   exit affordance.

---

## Related project docs

- `docs/vision.md` — the Director-and-its-many-mouths principle (now Cody +
  Partner). North star.
- `docs/opening_sequence_spec.md` — the *original* opening brief (meet Cody →
  utilities gate). This doc supersedes its flow.
- `docs/floor_population_spec.md` — the blank-shell → lush floor lifecycle the
  floor-by-floor model leans on.
- `docs/floor_design_system.md` — universal floor rules for any new built floor.
