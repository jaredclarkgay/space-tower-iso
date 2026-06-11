# Director → mouth channel (narrative direction without a god-speaker)

**When this applies:** you have a game/app where "what the player needs to do
next" comes from one brain, but it can be *spoken* by several surfaces (an NPC, a
HUD toast, an objective line, a PA system, the environment). The naive version
buries the player-facing words inside whichever speaker happens to deliver them,
and every new speaker re-wires the spine. Don't.

## The shape (see `autoloads/game_director.gd`)

1. **The Director owns the CONTENT of direction**, not just the sequencing. A
   *directive* is mouth-agnostic data — `{id, speaker?, lines, objective?,
   transient?, telemetry_beat}` — in a `DIRECTIVES` library on the Director. Keep
   the player-facing words here, not in any speaker. Authoring a new beat = adding
   a dict entry.

2. **Mouths register, they aren't hard-referenced.** A mouth is any node with a
   `mouth_id` property + `deliver_directive(d) -> bool` (return true = "I rendered
   it"). They `register_mouth(self, priority)` on ready. The Director keeps them
   sorted by priority; it never imports or `get_node`s a specific speaker.

3. **`issue_directive(id_or_dict)` does two things at once:**
   - **Broadcast** via `directive_issued` signal — *every* mouth sees it, so
     passive ones (HUD objective line) mirror the objective regardless of who
     speaks. A passive mouth listens to the signal and never gets routed to.
   - **Route the spoken delivery** to ONE mouth: the directive's named `speaker`
     if set, else the highest-priority mouth whose `deliver_directive` returns
     true. First acceptor wins; `return` stops there.

4. **Non-spoken directives are `transient: true`** — they don't become the
   `active_directive` (so they don't overwrite the standing objective) and route
   to a cheap mouth (e.g. HUD toast for a "you can't do that yet" reason). Surface
   a gate's *reason* through the channel, never as a silent no-op.

5. **Telemetry is free** — `issue_directive` records `telemetry_beat` centrally,
   so every beat is counted without per-speaker plumbing.

## Why it's worth the indirection

- One greeting, one source of truth. We had TWO divergent first-entry greetings
  (a cinematic path issuing the real beat + a dead legacy panel that contradicted
  the gate). Routing *both* arrival paths through `issue_directive("power_utilities")`
  collapsed them to one (commit `2a0fcf7`). If words live in the speaker, this
  divergence is the default outcome.
- A character can have TWO voices cleanly: Cody renders directives in a terse
  "director mode" (one line, advance-to-continue) distinct from his chatty
  pull-to-talk dialogue tree. The mode is chosen by *which entry point* called
  him, not by branching inside one render path.

## Keep the Director pure

The Director reads + mirrors world state (`GameState`); it never stores a parallel
copy. `complete_utilities()` flips the gate flag *in GameState*, records telemetry,
and issues the payoff directive — it's the single funnel for "the world changed →
direct the player." Gate flags (`interiors_unlocked`) live in GameState; the
*decision* to lift them and *say so* lives in the Director.
