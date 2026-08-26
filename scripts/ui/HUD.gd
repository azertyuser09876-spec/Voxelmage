extends Control
class_name HUD
## Affichage en jeu : barre rapide, vie, mana, sort actif, chat, barre de boss.

var player: Player

var _hotbar_slots: Array[Panel] = []
var _hp_bar: ProgressBar
var _mana_bar: ProgressBar
var _spell_label: Label
var _crosshair: Control
var _break_bar: ProgressBar
var _chat_box: VBoxContainer
var _chat_input: LineEdit
var _toast: Label
var _debug: Label
var _boss_root: VBoxContainer
var _boss_bar: ProgressBar
var _death: Control
var _damage_overlay: ColorRect
var _hint: Label
var _chat_lines: Array[String] = []
var _toast_time := 0.0
var _damage_time := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_crosshair()
	_build_bars()
	_build_hotbar()
	_build_chat()
	_build_boss()
	_build_misc()
	set_process(true)


func bind(p: Player) -> void:
	player = p
	refresh_stats(p)
	refresh_hotbar(p)


# ------------------------------------------------------------------ contruction
func _build_crosshair() -> void:
	_crosshair = Control.new()
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_crosshair)
	for i in 2:
		var r := ColorRect.new()
		r.color = Color(1, 1, 1, 0.85)
		r.size = Vector2(14, 2) if i == 0 else Vector2(2, 14)
		r.position = -r.size * 0.5
		_crosshair.add_child(r)
	_break_bar = ProgressBar.new()
	_break_bar.show_percentage = false
	_break_bar.custom_minimum_size = Vector2(70, 6)
	_break_bar.position = Vector2(-35, 22)
	_break_bar.max_value = 1.0
	_break_bar.visible = false
	_crosshair.add_child(_break_bar)


func _build_bars() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	box.offset_left = 18
	box.offset_top = -170
	box.offset_right = 300
	box.offset_bottom = -110
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_hp_bar = _bar(UiKit.LIFE)
	_mana_bar = _bar(UiKit.MANA)
	box.add_child(_hp_bar)
	box.add_child(_mana_bar)
	_spell_label = UiKit.label("", 16, UiKit.ACCENT)
	box.add_child(_spell_label)


func _bar(color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = Vector2(230, 16)
	b.show_percentage = false
	b.max_value = 100.0
	var bg := UiKit.panel_style(Color(0.08, 0.07, 0.1, 0.85), 6, 1)
	var fg := UiKit.panel_style(color, 6, 0)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	return b


func _build_hotbar() -> void:
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	row.offset_left = -9 * 29
	row.offset_right = 9 * 29
	row.offset_top = -80
	row.offset_bottom = -20
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	add_child(row)
	for i in 9:
		var s := UiKit.make_slot(54)
		s.mouse_filter = Control.MOUSE_FILTER_STOP
		var idx := i
		s.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and player:
				player.set_hotbar(idx))
		row.add_child(s)
		_hotbar_slots.append(s)


func _build_chat() -> void:
	_chat_box = VBoxContainer.new()
	_chat_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_chat_box.offset_left = 16
	_chat_box.offset_top = 60
	_chat_box.offset_right = 520
	_chat_box.offset_bottom = 300
	_chat_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chat_box)
	_chat_input = UiKit.line_edit("Message... (Entree pour envoyer)")
	_chat_input.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_input.offset_left = 16
	_chat_input.offset_top = -104
	_chat_input.offset_right = 520
	_chat_input.offset_bottom = -64
	_chat_input.visible = false
	_chat_input.text_submitted.connect(_on_chat_submit)
	_chat_input.focus_exited.connect(close_chat)
	add_child(_chat_input)


func _build_boss() -> void:
	_boss_root = VBoxContainer.new()
	_boss_root.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_boss_root.offset_left = -260
	_boss_root.offset_right = 260
	_boss_root.offset_top = 24
	_boss_root.offset_bottom = 80
	_boss_root.visible = false
	_boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_boss_root)
	var l := UiKit.label("", 20, Color(1.0, 0.55, 0.45))
	l.name = "BossName"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_root.add_child(l)
	_boss_bar = _bar(Color(0.85, 0.25, 0.5))
	_boss_bar.custom_minimum_size = Vector2(520, 20)
	_boss_root.add_child(_boss_bar)


func _build_misc() -> void:
	_toast = UiKit.label("", 20, Color(1, 0.95, 0.7))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_left = -300
	_toast.offset_right = 300
	_toast.offset_top = 110
	_toast.offset_bottom = 140
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	add_child(_toast)

	_debug = UiKit.label("", 13, Color(0.8, 0.85, 0.95))
	_debug.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_debug.offset_left = -320
	_debug.offset_right = -12
	_debug.offset_top = 10
	_debug.offset_bottom = 90
	_debug.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_debug)

	_hint = UiKit.label("Cliquez pour capturer la souris", 18, Color(1, 0.95, 0.75))
	_hint.set_anchors_preset(Control.PRESET_CENTER)
	_hint.offset_left = -240
	_hint.offset_right = 240
	_hint.offset_top = 60
	_hint.offset_bottom = 90
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.visible = false
	add_child(_hint)

	_damage_overlay = ColorRect.new()
	_damage_overlay.color = Color(0.7, 0.05, 0.05, 0.0)
	_damage_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_damage_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_damage_overlay)

	_death = UiKit.make_panel(Color(0.1, 0.02, 0.04, 0.88))
	_death.set_anchors_preset(Control.PRESET_CENTER)
	_death.offset_left = -220
	_death.offset_right = 220
	_death.offset_top = -80
	_death.offset_bottom = 80
	_death.visible = false
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	var t := UiKit.label("Vous etes mort", 32, Color(1, 0.5, 0.5))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(t)
	var s := UiKit.label("Reapparition dans quelques secondes...", 16)
	s.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(s)
	_death.add_child(col)
	add_child(_death)


# ------------------------------------------------------------------ mise a jour
func _process(delta: float) -> void:
	if _hint != null:
		_hint.visible = visible and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED \
				and not Game.instance.ui.blocking() and not chat_is_open() \
				and not DisplayServer.is_touchscreen_available()
	if player != null:
		_hp_bar.value = player.hp / Player.MAX_HP * 100.0
		_mana_bar.value = player.mana / Player.MAX_MANA * 100.0
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
	if _damage_time > 0.0:
		_damage_time -= delta
		_damage_overlay.color.a = clampf(_damage_time * 0.42, 0.0, 0.30)
	if Input.is_action_just_pressed("chat") and not _chat_input.visible \
			and not Game.instance.ui.blocking():
		open_chat()


func refresh_stats(p: Player) -> void:
	player = p
	var s := Spells.get_spell(p.selected_spell)
	var holding_wand := Items.wand_tier(int(p.held_item().get("id", 0))) > 0
	var locked: bool = holding_wand and p.wand_tier < int(s["tier"])
	var suffix := ""
	if locked:
		suffix = "  [baguette trop faible]"
	elif not holding_wand:
		suffix = "  (equipez une baguette)"
	_spell_label.text = "Sort : %s (T%d)%s" % [s["name"], int(s["tier"]), suffix]
	_spell_label.add_theme_color_override("font_color",
			Color(0.9, 0.4, 0.4) if locked else UiKit.ACCENT)


func refresh_hotbar(p: Player) -> void:
	player = p
	for i in 9:
		UiKit.fill_slot(_hotbar_slots[i], p.inv.get_slot(i), i == p.hotbar)
	refresh_stats(p)


func set_break_progress(_pos: Vector3i, v: float) -> void:
	_break_bar.visible = v > 0.01
	_break_bar.value = clampf(v, 0.0, 1.0)


func toast(msg: String) -> void:
	_toast.text = msg
	_toast_time = 2.5


func flash_damage() -> void:
	_damage_time = 0.7


func show_death() -> void:
	_death.visible = true


func hide_death() -> void:
	_death.visible = false


func show_boss_bar(name: String) -> void:
	_boss_root.visible = true
	(_boss_root.get_node("BossName") as Label).text = name
	_boss_bar.value = 100.0


func set_boss_hp(ratio: float) -> void:
	_boss_bar.value = clampf(ratio, 0.0, 1.0) * 100.0


func hide_boss_bar() -> void:
	_boss_root.visible = false


func set_debug(pos: Vector3, chunks: int, biome: String) -> void:
	_debug.text = "%.0f / %.0f / %.0f\n%s\n%d chunks - %d FPS" % [
		pos.x, pos.y, pos.z, biome, chunks, Engine.get_frames_per_second()]


func add_chat(who: String, msg: String) -> void:
	_chat_lines.append("<%s> %s" % [who, msg])
	while _chat_lines.size() > 8:
		_chat_lines.pop_front()
	for c in _chat_box.get_children():
		c.queue_free()
	for line in _chat_lines:
		_chat_box.add_child(UiKit.label(line, 15))


func chat_is_open() -> bool:
	return _chat_input != null and _chat_input.visible


func open_chat() -> void:
	_chat_input.visible = true
	_chat_input.grab_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_chat() -> void:
	## Toujours rendre la souris au jeu, quelle que soit la facon de sortir.
	if not _chat_input.visible:
		return
	_chat_input.visible = false
	_chat_input.text = ""
	_chat_input.release_focus()
	if Game.instance != null and Game.instance.ui != null:
		Game.instance.ui.regrab_mouse()


func _on_chat_submit(text: String) -> void:
	if text.strip_edges() != "":
		Net.send_chat(text.strip_edges())
	close_chat()
