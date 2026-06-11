# Vision — the north star

> The "why" layer. Not current state (that's `STATUS.md`), not conventions
> (that's `CLAUDE.md`), not facts (that's the code). This is what the game is
> *reaching for* — the ideas everything else should serve. When a design
> decision is unclear, this is the document that breaks the tie. Edited rarely
> and deliberately; it should age slowly.

## 1. The Director and its many mouths

`GameDirector` is the game's intelligence about **what the player needs next** —
the narrative spine, the sense of "here is where you are, here is what matters
now." It is the brain. It does not speak in its own voice; it speaks through
**mouths**.

There are many possible mouths — the HUD, the environment itself, other
characters, a building PA, a future cast. **Cody is the primary one.** Direction
should flow through a *routable channel* (the Director decides a beat; a chosen
mouth renders it), never be hardcoded to a single speaker. That way the game can
grow more voices without rewiring the spine, and Cody's primacy stays a *choice*,
not a constraint.

## 2. Cody

Cody is **not** a UI for instructions wearing a robot costume. He is a
**companion with a character of his own** — he just happens to be exceptionally
well-suited to relaying the Director's intent, which is *why* he became its
primary mouth. Companion first; narrator second; the narration is a natural
consequence of who he is, not his definition.

Practically, this means: every time Cody carries direction, he should also carry
*personality*. A Cody line is a character moment that happens to contain
guidance — never a tooltip with a face.

## 3. Why Cody matters — the theme

We are entering a real world where capable, present robots and agentic LLMs are
becoming part of daily life. **Cody is a character-proxy for that reality.**
Through him, the game gets to explore — warmly, concretely, at human scale — what
it is like to live and work alongside an adaptive, agentic machine companion: one
that helps, anticipates, has a temperament, and grows more capable over time.

So lean *into* his agentic flexibility rather than hiding it. Cody's ability to
adapt, to relay, to act on the player's behalf, to develop — that is not
incidental polish, it is the point. As the game and the real world both move
forward, Cody is where the game has something to say.

## 4. The two tracks are one

This project is built in two kinds of session — **"make it playable"** (feel,
delight, the moment-to-moment) and **"make it agentic"** (the Director, Cody, the
systems and structural apparatus). They are framed as opposites, but on the
ideas above they **converge**: deepening `GameDirector` or Cody is *agentic* work
whose entire payoff is a more *playable* game. The opening sequence
(`docs/opening_sequence_spec.md`) is the first proof — building the director→mouth
channel (agentic) is exactly what makes the meeting-Cody moment land (playable).
When a piece of work serves both, it is almost always the right thing to build.

## 5. The grid foundation

The whole game is **grid-founded** — floors, placement, building, and movement
all resolve to a shared grid. When a mechanic *could* be free-form or
grid-snapped, **choose the grid.** It is the substrate that makes "build a floor
by placing components" legible, keeps systems composable across floors, and gives
the agentic layer clean coordinates to reason about. Organic / free-form
placement isn't forbidden forever, but the grid is the default and the
foundation — deviations need a reason. (Committed 2026-06-11, with the
floor-population placement mechanic as its first deliberate instance.)

---

*Relationship to other docs:* the broader franchise canon (lore, factions, the
Reckoning) lives in `docs/space-tower-project-knowledge-v3.md`; this file is the
living north star for the **iso build's** direction specifically. Where they
touch, this one governs current intent.
