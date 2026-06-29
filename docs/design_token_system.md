# Design-Token System — PRD (centralize the game's aesthetic into one dial)

> **What this is.** A product brief for giving Space Tower Iso a single source of
> aesthetic truth — named color/material/scale "tokens" that every procedural builder
> reads — so the look can be tuned globally (and, later, live) instead of edited in
> 400 scattered places. PRD, not implementation: a Claude Code session does the code.
>
> **When.** A *follow-up* to the opening-sequence redesign, not concurrent. This is the
> groundwork for the aesthetic pass, established early (while floors are still being
> added) so it's cheap.
>
> **Trust the code.** File pointers below are orientation; verify against current
> source before editing. Trust order: code → git log → agent/session_log.md → STATUS.md.

---

## 1. The problem (measured, not assumed)

This game builds its geometry and materials **in code at runtime** — there is no
imported-art pipeline and (almost) no authored `.tscn`/`Resource` materials. That has
one big consequence for tuning the look:

- **Godot's built-in design tools mostly won't help.** The inspector, material editor,
  and material previews operate on *authored* nodes and Resource assets. Here the mesh
  and its material don't exist until the game runs, so there's nothing in the editor to
  select and drag a slider on. (The one exception: the 2D HUD is `Control` nodes, which
  *can* be centralized via a Godot **`Theme`** resource — see §6.)
- **Dimensions are already global-ready.** Structural proportions live as named
  constants in `autoloads/constants.gd` (story height, wall height, elevator radius,
  camera offsets — ≈156 knobs). Changing `FLOOR_3D_STORY_HEIGHT` restacks every floor.
  This side already works the way we want; **it's the model to copy.**
- **Colors are not.** There are **~402 inline `Color(...)` literals** across the scene
  scripts and only **~6** reference a central place. A global palette change today means
  hunting across ~20 files. *(Counts measured 2026-06-29; treat as approximate.)*

So the fix is not "adopt Godot's tools" (they don't fit a procedural game) and not "build
a big rig now." It's: **finish the centralization that `constants.gd` already started —
for color/material the way it already did for dimensions — behind semantic names.**

## 2. The approach — tokens, in the grain of the codebase

The whole engine already lives by one idea: **data is the truth, and the renderers read
the data** (`GameState` is pure data; floor controllers render it). A design-token layer
is that same idea applied to *look*:

- A **single source of aesthetic truth** — a structured table of named tokens (colors,
  material roles, a few accent scales/widths).
- Every procedural builder **reads a token by name** instead of writing a literal.
- Tokens are **semantic, not literal**: name them by *role*, so the meaning survives a
  recolor. `STRUCT_SLAB`, `STRUCT_WALL`, `ACCENT_PLACEHOLDER`, `SYSTEM_WATER` — **not**
  `GRAY_18` or `BLUE_1`. A token says what a color is *for*; its value can change freely.

This makes a global recolor a handful of edits in one place, and it's the prerequisite
for an optional live tuning panel later (§5) — which is the "aesthetic control rig" the
operator imagined, made cheap because the data is already in one spot.

## 3. Where it lives (honoring the locked constraint)

**Constraint (CLAUDE.md):** the four autoloads (`Constants`, `GameState`, `SaveManager`,
`AudioManager`) are the *only* globals. So **do not add a 5th autoload.**

**Recommended home:** a structured **`PALETTE` section inside `autoloads/constants.gd`**
(where the centralized colors already live — `PLANT_TYPES`, `SITE_GROUND_COLOR`, the
utility system colors, etc.). Add small typed accessors (e.g. `Constants.col("STRUCT_WALL")`
or grouped dicts) mirroring the existing accessor idiom. This keeps one global, matches
where color constants already are, and needs no architectural change.

*(Alternative considered: a `palette.gd` with `class_name Palette` + static consts. Viable,
but watch the `class_name` + headless-import caveat in `agent/rules/gdscript_class_name_caveats.md`.
The Constants section is lower-risk.)*

## 4. The seam already exists

Material creation is already funnelled through helpers — e.g. `_make_material(color)` in
`scenes/garden/cody_3d_view.gd` and `_flat_material(color)` in `scenes/shared/floor_chrome.gd`.
**These helpers are the insertion point.** Most of the migration is: replace the literal
passed *into* a helper with a token lookup. The plumbing to apply a color is already there;
we're only changing where the color *comes from*.

GL Compatibility note (from `ARCHITECTURE_REPORT.md`): there's no compositor, so "look" is
`StandardMaterial3D` **albedo + emission** per object. Tokens feed exactly those two fields;
a future per-object highlight helper would read an `ACCENT_*` emission token.

## 5. Optional later: the live tuning panel (the "rig")

Once tokens are centralized, a small in-game/editor panel can drive them live: sliders →
write a runtime override of the palette → builders re-read on the next rebuild (rebuild is
already how floors refresh). **This only ever touches *look*, never gameplay state**, so it
does not conflict with the "tower stays deterministic" decision
(`decision-tower-deterministic-polaroid-in-tool`) — aesthetics aren't part of the
authored/locked world model. Build the panel **only when the aesthetic pass actually starts**;
the token layer is what makes it a small job rather than a big one.

## 6. Migration order (incremental — NOT a big-bang refactor)

Do this in waves, each independently shippable and screenshot-verifiable. Highest leverage
first:

1. **Structural neutrals — the tower's "concrete & steel" base.** The repeated grays in
   `scenes/shared/floor_chrome.gd` (slab `Color(0.18,0.18,0.20)`, walls/frames `0.32`,
   `0.30`, `0.28` …). These define the base look of *every* floor and are clustered in one
   shared file → biggest visual change per edit, lowest risk. Tokens: `STRUCT_SLAB`,
   `STRUCT_WALL`, `STRUCT_FRAME`, `STRUCT_TRIM`.
2. **Cross-floor systems palette.** The six utility/spine colors (water, power, atmosphere,
   data, waste, cargo) — already *semi*-centralized in `constants.gd` (`base_color`/`glow_color`
   dicts, `WATER_PIPE_COLOR`, etc.). Finish unifying so the glow reads identically on every
   floor it passes through. Tokens: `SYSTEM_<NAME>` + `SYSTEM_<NAME>_GLOW`.
3. **Accent / emphasis colors.** `PLACEHOLDER_COLOR` (magenta), `GROW_LIGHT_COLOR`,
   `ARBORETUM_HEADER_AMBER`, dispenser/prompt accents. Tokens: `ACCENT_*`.
4. **Per-floor signature colors.** Each floor's local character (garden greens, sky-lounge
   glass, roof). These are *intentionally* local — migrate **last**, and only the values
   that benefit from sharing. Don't over-tokenize a one-off.
5. **HUD / Control colors → a Godot `Theme`.** The 2D HUD is the one place Godot's built-in
   tooling *does* apply: collect the `tower_hud.gd` / `seed_hud.gd` / `*_hud.gd` style colors
   into a shared `Theme` resource. Separate track from the 3D tokens.

## 7. Non-goals (scope guards)

- **Not** converting the game to authored `.tscn`/Resource materials — that fights the
  procedural architecture and is the wrong tool for this game.
- **Not** building the live tuning panel in this pass (§5 is later).
- **Not** tokenizing every one-off color on day one — semantic roles for shared/structural
  look first; leave deliberate local colors alone until they prove they want sharing.
- **Not** touching dimensions — they're already centralized and fine.

## 8. Acceptance / how to verify

- **Palette-swap test:** change one structural token (e.g. `STRUCT_WALL`) and confirm the
  change appears on **every** floor in a single edit — screenshot before/after via the
  windowed harness (`agent/rules/godot_screenshot_harness.md`).
- **No literal regressions:** after each wave, `grep` confirms the migrated cluster's inline
  `Color(...)` literals are gone from the target files (count goes down toward the ~6→many
  ratio inverting).
- **No visual diff at wave 1:** the first migration should be a *pure refactor* — tokens seeded
  with today's exact values, so the game looks identical until you intentionally change one.

## 9. Open decisions

1. **Token home** — `PALETTE` section in `constants.gd` (recommended) vs. a `palette.gd`
   const class. *(Recommend the former; honors the 4-autoload constraint.)*
2. **Accessor shape** — grouped dicts (`Constants.PALETTE.STRUCT_SLAB`) vs. a `col(name)`
   lookup vs. flat named consts. Pick one and apply uniformly.
3. **How far semantic naming goes** — purely role-based, or a two-tier system (raw ramp →
   semantic alias) like real design systems use. Two-tier is more powerful but heavier;
   probably overkill until the rig exists.

## Related docs

- `ARCHITECTURE_REPORT.md` — GL-Compatibility look = material albedo/emission; no compositor.
- `docs/floor_design_system.md` — universal floor rules the structural tokens serve.
- `autoloads/constants.gd` — where centralized colors already live; the token home.
- `agent/rules/godot_screenshot_harness.md` — the verify loop for every wave.
