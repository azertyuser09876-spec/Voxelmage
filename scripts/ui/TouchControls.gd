extends Control
class_name TouchControls
## Commandes tactiles (Android) : joystick analogique, regard par glissement,
## boutons d'action. Les boutons pilotent les MEMES actions que le clavier.

const STICK_R := 110.0
const KNOB_R := 44.0

var _stick_center := Vector2.ZERO
var _stick_touch := -1
var _look_touch := -1
var _knob: Control
var _base: Control
var _pressed_actions: Array[String] = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_stick()
	_build_buttons()
	set_process_input(true)


func _build_stick() -> void:
	_base = Control.new()
	_base.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_base.position = Vector2(150, -170)
	_base.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_base)
	var ring := _circle(STICK_R, Color(1, 1, 1, 0.14))
	_base.add_child(ring)
	_knob = _circle(KNOB_R, Color(1, 1, 1, 0.30))
	_base.add_child(_knob)


func _circle(r: float, color: Color) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(r * 2, r * 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func(): c.draw_circle(Vector2.ZERO, r, color))
	return c


func _btn(text: String, pos: Vector2, size: Vector2, action: String) -> void:
	var b := Button.new()
	b.text = text
	b.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	b.position = pos
	b.custom_minimum_size = size
	b.size = size
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_stylebox_override("normal",
			UiKit.panel_style(Color(0.18, 0.17, 0.26, 0.75), 30, 2))
	b.add_theme_stylebox_override("pressed",
			UiKit.panel_style(Color(0.42, 0.34, 0.62, 0.9), 30, 2))
	b.add_theme_stylebox_override("hover",
			UiKit.panel_style(Color(0.24, 0.22, 0.34, 0.8), 30, 2))
	if action == "":
		add_child(b)
		return
	b.button_down.connect(func(): Input.action_press(action))
	b.button_up.connect(func(): Input.action_release(action))
	add_child(b)


func _build_buttons() -> void:
	_btn("Saut", Vector2(-130, -230), Vector2(110, 110), "jump")
	_btn("Miner", Vector2(-260, -150), Vector2(110, 110), "attack")
	_btn("Poser", Vector2(-130, -110), Vector2(110, 110), "use")
	_btn("Sort", Vector2(-260, -270), Vector2(110, 110), "cast")
	_btn("Accroupi", Vector2(-390, -110), Vector2(110, 70), "sneak")
	_btn("Courir", Vector2(-390, -190), Vector2(110, 70), "sprint")

	var inv := Button.new()
	inv.text = "Sac"
	inv.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	inv.position = Vector2(-110, 100)
	inv.custom_minimum_size = Vector2(90, 60)
	inv.add_theme_stylebox_override("normal",
			UiKit.panel_style(Color(0.18, 0.17, 0.26, 0.75), 10, 2))
	inv.pressed.connect(func(): Game.instance.ui.open_inventory())
	add_child(inv)

	var next_spell := Button.new()
	next_spell.text = "Sort >"
	next_spell.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	next_spell.position = Vector2(-110, 170)
	next_spell.custom_minimum_size = Vector2(90, 60)
	next_spell.add_theme_stylebox_override("normal",
			UiKit.panel_style(Color(0.18, 0.17, 0.26, 0.75), 10, 2))
	next_spell.pressed.connect(func():
		if Game.instance.player:
			Game.instance.player.cycle_spell(1))
	add_child(next_spell)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var vp := get_viewport_rect().size
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			if t.position.x < vp.x * 0.45 and t.position.y > vp.y * 0.35:
				_stick_touch = t.index
				_stick_center = t.position
			elif t.position.x > vp.x * 0.45:
				_look_touch = t.index
		else:
			if t.index == _stick_touch:
				_stick_touch = -1
				_release_moves()
				_knob.position = Vector2.ZERO
			if t.index == _look_touch:
				_look_touch = -1
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == _stick_touch:
			var off := d.position - _stick_center
			if off.length() > STICK_R:
				off = off.normalized() * STICK_R
			_knob.position = off
			_apply_stick(off / STICK_R)
		elif d.index == _look_touch:
			var pl = get_tree().get_first_node_in_group("local_player")
			if pl != null:
				pl.add_look(d.relative * 0.006)


func _apply_stick(v: Vector2) -> void:
	_press("move_right", maxf(0.0, v.x))
	_press("move_left", maxf(0.0, -v.x))
	_press("move_back", maxf(0.0, v.y))
	_press("move_forward", maxf(0.0, -v.y))


func _press(action: String, strength: float) -> void:
	if strength > 0.12:
		Input.action_press(action, strength)
		if not _pressed_actions.has(action):
			_pressed_actions.append(action)
	else:
		Input.action_release(action)
		_pressed_actions.erase(action)


func _release_moves() -> void:
	for a in ["move_forward", "move_back", "move_left", "move_right"]:
		Input.action_release(a)
	_pressed_actions.clear()
