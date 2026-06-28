# Generalizing a hardwired single-instance system into a declared shared module

## Rule

When a system was built end-to-end for ONE instance (one floor, one entity,
one screen) and now needs a second, don't copy-paste it. Pull the **shared
machinery** (state, the verb, the ghost/preview, the threshold transition,
telemetry) onto an **instanced** helper under `scenes/shared/`, and let each
caller **DECLARE its content** into the helper via a config dict of scalars +
`Callable`s (a strategy table), not via subclassing. Mirror how static chrome
modules are shared (`godot_shared_module_pattern.md`) — but this one is
*stateful*, so it's `RefCounted.new()` held by the floor, not `static func`.

## Shape

```gdscript
# scenes/shared/floor_lifecycle.gd  (instanced, holds per-floor lifecycle state)
extends RefCounted
var _cfg: Dictionary
func declare(cfg: Dictionary) -> void: _cfg = cfg     # {level, threshold,
    # is_populatable:Callable, snap_anchor:Callable, is_valid_anchor:Callable,
    # slot_local_pos:Callable, spawn_component:Callable, on_alive:Callable}
func find_slot(p): ...        # SHARED verb — calls _cfg.snap_anchor / is_valid_anchor
func place(slot): ...         # SHARED — calls _cfg.spawn_component, bumps count,
                              #   emits component_placed{level}, crosses threshold -> on_alive
```

The Garden and Residential each `declare(...)` their own content; the verb,
the grid-snap, the ghost, and the bloom-threshold logic exist once.

## Keys that make the swap invisible (verified on Garden→Residential)

1. **Keep the original public method names as thin delegators.** Garden kept
   `find_nearest_bed_slot_near` / `place_planter_bed` forwarding to the module
   — so `iso_player` + every harness compiled and behaved identically with
   zero edits. Rename later, if ever.
2. **id-key the generalized store, alias the original key back.**
   `GameState.floor_state(id)` / `floor_alive(id)`; `"garden"` routes to the
   pre-existing `garden` dict so every old reference is untouched.
   `garden_alive()` becomes a one-line delegate.
3. **Resolve "the current instance" at the call site, not at wire time.** The
   place verb now asks the tower controller for `current_floor_node()` and
   drives its generic `populate_*` interface — so the SAME input populates
   whichever floor the player stands on. The shared HUD reads the *current*
   floor's `populate_palette()` instead of a hardwired `GameState.garden`.
4. **Stamp the instance id/level into telemetry** (`component_placed{level}`,
   `floor_alive{level}`) so one event stream distinguishes the instances.

## The regression oracle (the non-obvious verification lesson)

The refactor's job is "the original instance behaves IDENTICALLY." You cannot
prove that with a screenshot **pixel diff** — bloom pulses and scale-pops are
time-based, so two runs (even two *baseline* runs) never match byte-for-byte.
The real oracle is a **state trace + telemetry diff**: assert the same state
sequence (`populated 0→1→3`, `alive flips at 3`) and the same emitted-event
funnel before/after. Screenshots drop to an eyeball "visually indistinguishable"
check, not the proof. Say so honestly in the report — "state+telemetry
identical; screenshots eyeballed" — don't claim a pixel match you didn't run.

Also: drive the regression through the **real input path** (`Input.action_press`
→ the player's own branch), not just the public API, or you'll miss a missing
delegate that only the input path exercises (caught `populate_slot_local_pos`
this way before it shipped).
