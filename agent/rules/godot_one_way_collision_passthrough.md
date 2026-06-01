# Jump pass-through ceilings via per-floor slab-layer gating

**When:** A stacked-world iso build where the player should jump UP
*unobstructed* by the ceiling (jump as high as they can) but always fall back to
the **same** floor — never land on the floor above — except for one designated
"solid ceiling" floor (e.g. a glass canopy) that should still block (bonk).

> Supersedes the earlier velocity-gated-player-mask approach (F-021). That made
> the player rise through a slab and then *land on the floor above*, which the
> operator explicitly did not want (F-023). Gate the **slab bodies** per floor,
> not the player's mask.

## The trick

Two collision layers + gate each regular slab body by the player's current floor:

- **Regular floor slabs → collision layer 2.** Built by `FloorChrome.build_slab`
  (body named `"SlabBody"`).
- **The one solid ceiling → collision layer 1** (e.g. the Canopy's
  `"TiledSlabBody"`, collision always on). Never gated.
- **Player mask:** keep BOTH layer 1 and layer 2 on at all times. Do **not**
  toggle the mask by velocity.

```gdscript
# tower_controller.gd — cache each regular floor's SlabBody in _ready(), then
# in _update() (which runs every frame):
var at_or_below: bool = (floor_level <= _current_level)
if slab:                                  # null for the canopy → never touched
    slab.collision_layer = 2 if at_or_below else 0   # 0 = pass-through

# iso_player.gd — slab mask stays on permanently (set once in _ready):
set_collision_mask_value(2, true)
# ...no per-frame toggle before move_and_slide() anymore.
```

A `StaticBody3D` with `collision_layer = 0` collides with nothing (the player's
mask has nothing to match), so the floors above become pass-through while your
own floor + everything below stay solid.

## Why this over alternatives

- **Velocity-gated player mask** (the old way): re-enabling the mask while
  falling makes you land on the first slab below you — which, after rising past
  it, is the floor *above* your takeoff. Wrong outcome.
- **`CollisionShape3D.one_way_collision`** is per-shape and orients to local +Y —
  fragile across a tiled slab with holes and varied transforms. Per-body layer
  gating is global and order-independent.
- Gating the **body** (not the mask) lets "my floor solid / floors above
  pass-through / one ceiling always solid" all hold simultaneously — the mask
  can't express "this slab yes, that slab no" because all regular slabs share a
  layer.

## Pairs with: grounded-only floor changes (critical)

`tower_controller.gd._update()` only re-evaluates `_current_level` when
`is_on_floor()` is true. So during the entire airtime the set of solid floors is
frozen at the takeoff floor → floors above stay pass-through the whole jump, and
the player arcs up through where the ceiling is and falls back to the takeoff
slab. **This grounded-gate is what makes the pass-through correct** — without it,
rising into the floor-above's reveal band would flip its slab solid mid-air and
you'd catch on it. Vertical floor changes happen only via stairs + elevator.

## Verifying without a human

A windowed physics harness (NOT `--headless`, which renders nothing) can assert
this: set `player.velocity.y = PLAYER_JUMP_VELOCITY_MAX`, step `physics_frame`
~150×, track peak y / `is_on_ceiling()` / final `_current_level`. Expect: regular
floor → no bonk, lands on same level; canopy floor → bonk, lands on same level.
