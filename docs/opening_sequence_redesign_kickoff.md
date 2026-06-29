# Claude Code kickoff prompt — Opening Sequence Redesign

> Copy everything in the block below into a fresh Claude Code session opened on the
> `space-tower-iso` repo.

---

```
We're reworking the game's opening sequence (boot → first plant). The full design
brief is in `docs/opening_sequence_redesign.md` — read it first, in full, before
writing anything.

GROUND RULES (from CLAUDE.md — follow them):
- Trust the CODE, not the docs, for current behavior. Trust order: code → git log →
  agent/session_log.md → STATUS.md → CLAUDE.md. The brief's file pointers are
  orientation; verify each against current source before you touch it.
- Surface decisions, don't guess. The brief's Part D marks several decisions RESOLVED
  (naming, build mechanic, partner presence, worker fate) and a few STILL OPEN. Do
  NOT silently pick on the open ones — bring them to me, or log them to
  agent/request_queue.json, before building anything that depends on them.
- Consult agent/rules/ before non-trivial work. At minimum read
  rules/stacked_tower_invariants.md (anything cross-floor / vertical traversal) and
  rules/godot_screenshot_harness.md (the screenshot verify loop) before starting.
- Constraints are locked: Godot 4.6, GDScript only, GL Compatibility renderer, no
  C#/GDExtension/plugins, web export must stay possible.
- Verify visual/behavioural changes by screenshot using the windowed harness, not by
  assertion.

THE NON-NEGOTIABLE PRINCIPLES (Part 0 of the brief):
1. Free movement is the default. Exactly ONE hard control-lock in the whole opening:
   the moment the player enters the tower and Cody rises. Everything else stays
   free-roam.
2. One consistent interaction grammar for hire + build (today they differ).
3. Two Director mouths: Cody = construction/tending; the Partner = a human,
   business-facing mouth who NEVER appears in person (phone-call dialogue box +
   portrait only; 3 candidates, keep Tobin). Both register through GameDirector.
4. Floor construction is player-directed and unlock-gated — NOT an instant
   all-floors pre-build at startup. The build verb is CLIMBING INTO THE CRANE; each
   build triggers the workers' rapid build + the floor-build sequence. Floor 0 is the
   "Control Center."
5. Ceremony may move the camera but stays breakable outside the one lock.
6. The construction apparatus (crane + 3 workers + open deck) rides the top of the
   tower, relocating to each new floor's edges as it's built, with a see-through top
   so the player watches the new floor assemble.

HOW I WANT TO WORK:
- Don't build the whole thing in one shot. Start by reading the brief + the actual
  opening code paths it names, then give me: (a) a short confirmation of what the
  code does TODAY vs. what the brief assumes, flagging any mismatch, and (b) a
  proposed, ordered implementation plan broken into reviewable chunks — with the Part
  D decisions called out where they block a chunk.
- Wait for my go-ahead on the plan before writing gameplay code.
- We iterate screenshot-by-screenshot, chunk by chunk.

Start now: read docs/opening_sequence_redesign.md and the opening code it points to,
then report back with (a) the today-vs-brief reconciliation and (b) the chunked plan.
Do not write code yet.
```

---

**Why it's shaped this way:** it front-loads the brief, hard-codes the CLAUDE.md
guardrails (code-over-docs, surface-decisions, rules/, screenshot verify), restates
the six principles so they survive context compaction, and forces a
reconcile-then-plan step before any code — so the session catches where the brief's
assumptions and the current code diverge *before* it spends effort.
