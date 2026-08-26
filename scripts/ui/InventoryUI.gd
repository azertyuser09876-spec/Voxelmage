extends Control
class_name InventoryUI
## Panneau d'inventaire polyvalent : inventaire, etabli 2x2/3x3, coffre, four,
## autel arcanique et table de runes. Deplacement par clic (compatible tactile).

signal closed

var player: Player
var mode := "inventory"
var container_pos := Vector3i.ZERO
var container_inv := Inventory.new(27)
var furnace_info := {"burn": 0.0, "burn_max": 1.0, "cook": 0.0}

var _cursor := Inventory.empty_slot()
var _cursor_icon: Panel
var _inv_slots: Array[Panel] = []
var _grid_slots: Array[Panel] = []
var _cont_slots: Array[Panel] = []
var _craft: Inventory
var _result_slot: Panel
var _grid_size := 2
var _body: VBoxContainer
var _title: Label
var _extra: VBoxContainer
var _cook_bar: ProgressBar
var _burn_bar: ProgressBar


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := UiKit.make_panel()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_right = 320
	panel.offset_top = -300
	panel.offset_bottom = 300
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_body = VBoxContainer.new()
	_body.custom_minimum_size = Vector2(600, 0)
	_body.add_theme_constant_override("separation", 8)
	scroll.add_child(_body)

	_cursor_icon = UiKit.make_slot(46)
	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.visible = false
	_cursor_icon.z_index = 20
	add_child(_cursor_icon)
	set_process(true)


func open(p: Player, p_mode: String, grid := 2) -> void:
	player = p
	mode = p_mode
	_grid_size = grid
	_craft = Inventory.new(grid * grid)
	_rebuild()


func set_container(pos: Vector3i, kind: String, data: Dictionary) -> void:
	container_pos = pos
	mode = kind
	var size: int = 27 if kind == "chest" else 3
	container_inv = Inventory.new(size)
	container_inv.from_array(data.get("slots", []))
	furnace_info = {"burn": float(data.get("burn", 0.0)),
			"burn_max": maxf(0.01, float(data.get("burn_max", 1.0))),
			"cook": float(data.get("cook", 0.0))}
	_rebuild()


func _process(_dt: float) -> void:
	if _cursor_icon.visible:
		_cursor_icon.position = get_global_mouse_position() - Vector2(23, 23)


# ------------------------------------------------------------------ contruction
func _rebuild() -> void:
	for c in _body.get_children():
		c.queue_free()
	_inv_slots.clear()
	_grid_slots.clear()
	_cont_slots.clear()
	_title = UiKit.label(_title_for(mode), 24)
	_body.add_child(_title)
	_extra = VBoxContainer.new()
	_body.add_child(_extra)

	match mode:
		"inventory", "craft":
			_build_craft_area()
		"chest":
			_build_container_grid(9)
		"furnace":
			_build_furnace()
		"altar":
			_build_altar()
		"runes":
			_build_runes()

	_body.add_child(HSeparator.new())
	_body.add_child(UiKit.label("Inventaire", 18))
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_body.add_child(grid)
	for i in 36:
		var idx := (i + 9) % 36        # 27 du haut puis la barre rapide
		var s := UiKit.make_slot()
		s.gui_input.connect(_slot_input.bind("inv", idx))
		grid.add_child(s)
		_inv_slots.append(s)
	var close := UiKit.button("Fermer (E)")
	close.pressed.connect(func(): closed.emit())
	_body.add_child(close)
	_refresh()


func _title_for(m: String) -> String:
	match m:
		"craft":
			return "Etabli"
		"chest":
			return "Coffre"
		"furnace":
			return "Four"
		"altar":
			return "Autel arcanique"
		"runes":
			return "Table de runes"
	return "Inventaire"


func _build_craft_area() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_extra.add_child(row)
	var grid := GridContainer.new()
	grid.columns = _grid_size
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	row.add_child(grid)
	for i in _grid_size * _grid_size:
		var s := UiKit.make_slot()
		s.gui_input.connect(_slot_input.bind("craft", i))
		grid.add_child(s)
		_grid_slots.append(s)
	row.add_child(UiKit.label("=>", 26))
	_result_slot = UiKit.make_slot(58)
	_result_slot.gui_input.connect(_slot_input.bind("result", 0))
	row.add_child(_result_slot)


func _build_container_grid(cols: int) -> void:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	_extra.add_child(grid)
	for i in container_inv.size():
		var s := UiKit.make_slot()
		s.gui_input.connect(_slot_input.bind("cont", i))
		grid.add_child(s)
		_cont_slots.append(s)


func _build_furnace() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_extra.add_child(row)
	var col1 := VBoxContainer.new()
	col1.add_child(UiKit.label("Entree", 14))
	var s0 := UiKit.make_slot()
	s0.gui_input.connect(_slot_input.bind("cont", 0))
	col1.add_child(s0)
	col1.add_child(UiKit.label("Combustible", 14))
	var s1 := UiKit.make_slot()
	s1.gui_input.connect(_slot_input.bind("cont", 1))
	col1.add_child(s1)
	row.add_child(col1)
	var col2 := VBoxContainer.new()
	_cook_bar = ProgressBar.new()
	_cook_bar.custom_minimum_size = Vector2(120, 14)
	_cook_bar.show_percentage = false
	_burn_bar = ProgressBar.new()
	_burn_bar.custom_minimum_size = Vector2(120, 14)
	_burn_bar.show_percentage = false
	col2.add_child(UiKit.label("Cuisson", 13))
	col2.add_child(_cook_bar)
	col2.add_child(UiKit.label("Combustion", 13))
	col2.add_child(_burn_bar)
	row.add_child(col2)
	var col3 := VBoxContainer.new()
	col3.add_child(UiKit.label("Sortie", 14))
	var s2 := UiKit.make_slot(58)
	s2.gui_input.connect(_slot_input.bind("cont", 2))
	col3.add_child(s2)
	row.add_child(col3)
	_cont_slots = [s0, s1, s2]


func _build_altar() -> void:
	_extra.add_child(UiKit.label(
		"Infusez une baguette avec des cristaux de mana pour augmenter sa puissance.",
		14, Color(0.8, 0.8, 0.95)))
	for r in Recipes.INFUSE:
		var row := UiKit.make_panel(UiKit.BG_SOFT)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = UiKit.item_texture(int(r["in"]))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size = Vector2(40, 40)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(icon)
		var txt := VBoxContainer.new()
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_child(UiKit.label("%s -> %s" % [Items.item_name(int(r["in"])),
				Items.item_name(int(r["out"]))], 16))
		var cost := "%d cristaux" % int(r["mana"])
		if int(r["arc"]) > 0:
			cost += ", %d arcanite" % int(r["arc"])
		if int(r["heart"]) > 0:
			cost += ", %d coeur du Neant" % int(r["heart"])
		txt.add_child(UiKit.label(cost, 13, Color(0.75, 0.78, 0.9)))
		h.add_child(txt)
		var b := UiKit.button("Infuser", 15)
		b.custom_minimum_size = Vector2(120, 38)
		b.pressed.connect(_do_infuse.bind(r))
		h.add_child(b)
		row.add_child(h)
		_extra.add_child(row)
	var summon := UiKit.button("Invoquer le Colosse du Neant (1 coeur)")
	summon.pressed.connect(func():
		if player.inv.remove(Items.VOID_HEART, 1):
			Game.instance.summon_boss(Vector3(container_pos) + Vector3(0.5, 1, 0.5))
			closed.emit()
		else:
			Game.instance.hud.toast("Il faut un Coeur du Neant"))
	_extra.add_child(summon)


func _do_infuse(r: Dictionary) -> void:
	if player.inv.count_of(int(r["in"])) < 1:
		Game.instance.hud.toast("Objet manquant")
		return
	if player.inv.count_of(Items.MANA_CRYSTAL) < int(r["mana"]) \
			or player.inv.count_of(Items.ARCANITE) < int(r["arc"]) \
			or player.inv.count_of(Items.VOID_HEART) < int(r["heart"]):
		Game.instance.hud.toast("Ressources insuffisantes")
		return
	player.inv.remove(int(r["in"]), 1)
	player.inv.remove(Items.MANA_CRYSTAL, int(r["mana"]))
	if int(r["arc"]) > 0:
		player.inv.remove(Items.ARCANITE, int(r["arc"]))
	if int(r["heart"]) > 0:
		player.inv.remove(Items.VOID_HEART, int(r["heart"]))
	player.inv.add(int(r["out"]), 1)
	player._update_wand()
	Game.instance.hud.toast("Infusion reussie : %s" % Items.item_name(int(r["out"])))
	_refresh()


func _build_runes() -> void:
	_extra.add_child(UiKit.label(
		"Gravez des runes pour augmenter votre maitrise arcanique : chaque niveau "
		+ "augmente les degats et le rayon de tous vos sorts.", 14, Color(0.8, 0.8, 0.95)))
	_extra.add_child(UiKit.label("Maitrise actuelle : %d" % player.mastery, 18, UiKit.ACCENT))
	var cost := 1 + player.mastery
	var b := UiKit.button("Graver une rune (%d tomes, %d cristaux)" % [cost, cost * 4])
	b.pressed.connect(func():
		if player.inv.count_of(Items.TOME) >= cost \
				and player.inv.count_of(Items.MANA_CRYSTAL) >= cost * 4:
			player.inv.remove(Items.TOME, cost)
			player.inv.remove(Items.MANA_CRYSTAL, cost * 4)
			player.mastery += 1
			Game.instance.hud.toast("Maitrise arcanique : %d" % player.mastery)
			_rebuild()
		else:
			Game.instance.hud.toast("Ressources insuffisantes"))
	_extra.add_child(b)
	var spells := VBoxContainer.new()
	spells.add_child(UiKit.label("Sorts connus", 18))
	for sid in Spells.for_tier(maxi(player.wand_tier, 1)):
		var s := Spells.scaled(sid, player.wand_tier, player.mastery)
		spells.add_child(UiKit.label("- %s (T%d) : %.0f degats, rayon %.1f, %d mana"
				% [s["name"], int(s["tier"]), float(s["damage"]), float(s["radius"]),
				int(s["mana"])], 14, Color(0.82, 0.85, 0.95)))
	_extra.add_child(spells)


# --------------------------------------------------------------------- slots
func _slot_input(event: InputEvent, kind: String, index: int) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var half: bool = event.button_index == MOUSE_BUTTON_RIGHT
	if kind == "result":
		_take_result()
		return
	var inv := _inv_for(kind)
	if inv == null:
		return
	var s := inv.get_slot(index)
	if Inventory.is_empty_slot(_cursor):
		if Inventory.is_empty_slot(s):
			return
		var take: int = maxi(1, int(s["count"]) / 2) if half else int(s["count"])
		_cursor = {"id": int(s["id"]), "count": take, "dura": int(s.get("dura", 0))}
		inv.consume_slot(index, take)
	else:
		if Inventory.is_empty_slot(s):
			var put: int = 1 if half else int(_cursor["count"])
			inv.set_slot(index, {"id": int(_cursor["id"]), "count": put,
					"dura": int(_cursor.get("dura", 0))})
			_cursor["count"] = int(_cursor["count"]) - put
			if int(_cursor["count"]) <= 0:
				_cursor = Inventory.empty_slot()
		elif int(s["id"]) == int(_cursor["id"]):
			var maxs := Items.max_stack(int(s["id"]))
			var move: int = mini(maxs - int(s["count"]), int(_cursor["count"]))
			if half:
				move = mini(move, 1)
			s["count"] = int(s["count"]) + move
			inv.set_slot(index, s)
			_cursor["count"] = int(_cursor["count"]) - move
			if int(_cursor["count"]) <= 0:
				_cursor = Inventory.empty_slot()
		else:
			var tmp := s.duplicate()
			inv.set_slot(index, _cursor.duplicate())
			_cursor = tmp
	if kind == "cont":
		_push_container(index)
	if kind == "inv":
		player._update_wand()
	_refresh()


func _inv_for(kind: String) -> Inventory:
	match kind:
		"inv":
			return player.inv
		"craft":
			return _craft
		"cont":
			return container_inv
	return null


func _push_container(index: int) -> void:
	var s := container_inv.get_slot(index)
	Net.request_container(container_pos, "set", {
		"slot": index, "id": int(s.get("id", 0)), "count": int(s.get("count", 0)),
		"dura": int(s.get("dura", 0))})


func _take_result() -> void:
	var res := Recipes.match_craft(_craft.slots, _grid_size)
	if res.is_empty():
		return
	if not Inventory.is_empty_slot(_cursor):
		if int(_cursor["id"]) != int(res["out"]):
			return
		_cursor["count"] = int(_cursor["count"]) + int(res["count"])
	else:
		_cursor = {"id": int(res["out"]), "count": int(res["count"]),
				"dura": int(Items.get_def(int(res["out"])).get("durability", 0))}
	for i in _craft.size():
		_craft.consume_slot(i, 1)
	_refresh()


func _refresh() -> void:
	if player == null:
		return
	for i in _inv_slots.size():
		var idx := (i + 9) % 36
		UiKit.fill_slot(_inv_slots[i], player.inv.get_slot(idx), idx == player.hotbar)
	for i in _grid_slots.size():
		UiKit.fill_slot(_grid_slots[i], _craft.get_slot(i))
	for i in _cont_slots.size():
		UiKit.fill_slot(_cont_slots[i], container_inv.get_slot(i))
	if _result_slot != null:
		var res := Recipes.match_craft(_craft.slots, _grid_size)
		UiKit.fill_slot(_result_slot, {"id": int(res.get("out", 0)),
				"count": int(res.get("count", 0))}, not res.is_empty())
	if _cook_bar != null:
		_burn_bar.max_value = float(furnace_info["burn_max"])
		_burn_bar.value = float(furnace_info["burn"])
		_cook_bar.max_value = 10.0
		_cook_bar.value = float(furnace_info["cook"])
	UiKit.fill_slot(_cursor_icon, _cursor)
	_cursor_icon.visible = not Inventory.is_empty_slot(_cursor)
	Game.instance.hud.refresh_hotbar(player)


func give_back_cursor() -> void:
	## Rend au joueur ce qu'il tient en main quand il ferme le panneau.
	if not Inventory.is_empty_slot(_cursor):
		player.inv.add(int(_cursor["id"]), int(_cursor["count"]), int(_cursor.get("dura", 0)))
		_cursor = Inventory.empty_slot()
	for i in _craft.size():
		var s := _craft.get_slot(i)
		if not Inventory.is_empty_slot(s):
			player.inv.add(int(s["id"]), int(s["count"]), int(s.get("dura", 0)))
	_craft.clear()
