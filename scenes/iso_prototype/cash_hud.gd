extends Label

# Renders cumulative cash earned from selling produce down the vacuum tubes.
# Source of truth is GameState.cash. Pulses briefly on increase so the
# player sees the deposit register without needing a separate floater.

@onready var _gs: Node = get_node("/root/GameState")

var _displayed_cash := 0
var _flash_t := 0.0


func _ready() -> void:
	_displayed_cash = _gs.cash
	text = "$%d" % _displayed_cash


func _process(delta: float) -> void:
	if _gs.cash != _displayed_cash:
		_displayed_cash = _gs.cash
		text = "$%d" % _displayed_cash
		_flash_t = 0.5
	if _flash_t > 0.0:
		_flash_t = max(0.0, _flash_t - delta)
		var k: float = _flash_t / 0.5
		# Flash brighter green on deposit, decay back to normal.
		modulate = Color(1.0, 1.0, 1.0).lerp(Color(0.7, 1.4, 0.7), k)
	else:
		modulate = Color(1.0, 1.0, 1.0)
