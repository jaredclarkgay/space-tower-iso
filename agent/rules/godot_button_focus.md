# Button focus_mode default vs. global ui_accept

## Rule
Set `focus_mode = 0` (FOCUS_NONE) on any `Button` that:
1. Is in a non-modal HUD layer where the player isn't expected to use Tab navigation, AND
2. Could be unintentionally activated by a key the project rebinds to a gameplay action.

`Button.focus_mode` defaults to `FOCUS_ALL`, which means the button can grab keyboard focus. Godot's built-in `ui_accept` action is bound to **Space** and **Enter**. If the project ALSO binds Space to a gameplay action (e.g. `jump`), pressing Space fires both:
- The gameplay action's handler, AND
- `ui_accept`, which activates whichever Button has focus.

The first time the player pressed Space to jump, the focused HUD Button activated.

## Quick fix in .tscn
```
[node name="MyButton" type="Button" parent="HUD/SomePanel"]
focus_mode = 0
text = "..."
```

## When to keep focus enabled
- Modal dialogs where keyboard navigation is intended.
- Buttons inside a focused panel where the player has already engaged a UI flow (e.g. confirmation dialogs).

## Diagnosis pattern
Symptom: a Button activates without being clicked, often "out of the gates" or shortly after game start. Trace:
1. Does the project bind Space or Enter to a gameplay action?
2. Does any Button have focus that you didn't expect?
3. If yes to both: focus_mode = 0 on the offending Button.

## See also
- `failure_log.json` F-008 (SchematicsButton activated by jump).
