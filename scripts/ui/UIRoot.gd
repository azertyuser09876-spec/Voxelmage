extends CanvasLayer
class_name UIRoot
## Racine de l'interface : menu, HUD, panneaux, pause.

var hud: HUD
var menu: MainMenu
var panel: InventoryUI
var touch: TouchControls
var pause: Control
var _panel_open := false


func _init() -> void:
	layer = 10


func _ready() -> void:
	hud = HUD.new()
	hud.visible = false
	add_child(hud)

	menu = MainMenu.new()
	add_child(menu)
	menu.start_solo.connect(_on_solo)
	menu.start_host.connect(_on_host)
	menu.join_request.connect(_on_join)

	panel = InventoryUI.new()
	panel.visible = false
	add_child(panel)
	panel.closed.connect(close_panel)

	_build_pause()

	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		touch = TouchControls.new()
		touch.visible = false
		add_child(touch)

	Net.disconnected.connect(func(): show_main_menu())
	set_process_input(true)
	get_viewport().size_changed.connect(_fit_all)
	_fit_all()
	_fit_all.call_deferred()


func _fit_all() -> void:
	## Un Control enfant direct d'un CanvasLayer n'herite pas toujours de la
	## taille du viewport : on la lui impose explicitement.
	var vp := get_viewport().get_visible_rect().size
	for c in [hud, menu, panel, pause, touch]:
		if c != null and is_instance_valid(c):
			(c as Control).set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			(c as Control).size = vp
			(c as Control).position = Vector2.ZERO


func _build_pause() -> void:
	pause = Control.new()
	pause.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause.add_child(dim)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -180
	box.offset_right = 180
	box.offset_top = -160
	box.offset_bottom = 160
	box.add_theme_constant_override("separation", 10)
	pause.add_child(box)
	box.add_child(UiKit.label("Pause", 30))
	var resume := UiKit.button("Reprendre")
	resume.pressed.connect(func(): set_pause(false))
	box.add_child(resume)
	var info := UiKit.label("", 14, Color(0.8, 0.85, 1.0))
	info.name = "Info"
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(info)
	var save := UiKit.button("Sauvegarder")
	save.pressed.connect(func():
		Game.instance.save_world()
		hud.toast("Partie sauvegardee"))
	box.add_child(save)
	var quit := UiKit.button("Quitter vers le menu")
	quit.pressed.connect(func():
		Game.instance.save_world()
		Net.leave()
		show_main_menu())
	box.add_child(quit)
	add_child(pause)


# ------------------------------------------------------------------ navigation
func show_main_menu() -> void:
	menu.visible = true
	menu.show_page("main")
	hud.visible = false
	panel.visible = false
	pause.visible = false
	if touch:
		touch.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = false


func close_all() -> void:
	menu.visible = false
	hud.visible = true
	panel.visible = false
	pause.visible = false
	if touch:
		touch.visible = true
	_capture_mouse(true)


func _capture_mouse(on: bool) -> void:
	if DisplayServer.is_touchscreen_available() and OS.has_feature("mobile"):
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func set_pause(on: bool) -> void:
	pause.visible = on
	get_tree().paused = on
	_capture_mouse(not on)
	if on:
		var txt := "Solo"
		if Net.is_online():
			txt = "Code de partie : %s\nCode direct : %s\nJoueurs : %d" % [
					Net.room_code, Net.direct_code, Net.players.size()]
		(pause.get_node("VBoxContainer/Info") as Label).text = txt


func regrab_mouse() -> void:
	if not blocking():
		_capture_mouse(true)


func blocking() -> bool:
	## Vrai si une interface capte les clics (menu, inventaire, pause).
	return menu.visible or _panel_open or pause.visible


func _input(event: InputEvent) -> void:
	if menu.visible:
		return
	# Un clic dans le jeu recapture le curseur : indispensable dans le
	# navigateur (le verrouillage exige un geste) et apres un Alt-Tab.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and not blocking() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_mouse(true)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause"):
		if hud.chat_is_open():
			hud.close_chat()
			get_viewport().set_input_as_handled()
			return
		if _panel_open:
			close_panel()
		else:
			set_pause(not pause.visible)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("inventory"):
		if _panel_open:
			close_panel()
		else:
			open_inventory()
		get_viewport().set_input_as_handled()


# --------------------------------------------------------------------- panneaux
func open_inventory() -> void:
	_open("inventory", 2)


func open_crafting(grid: int) -> void:
	_open("craft", grid)


func open_altar(pos: Vector3i) -> void:
	panel.container_pos = pos
	_open("altar", 2)


func open_runes() -> void:
	_open("runes", 2)


func _open(mode: String, grid: int) -> void:
	if Game.instance.player == null:
		return
	panel.open(Game.instance.player, mode, grid)
	panel.visible = true
	_panel_open = true
	_capture_mouse(false)
	if touch:
		touch.visible = false


func open_container(kind: String, pos: Vector3i, data: Dictionary) -> void:
	if Game.instance.player == null:
		return
	panel.player = Game.instance.player
	panel.set_container(pos, kind, data)
	panel.visible = true
	_panel_open = true
	_capture_mouse(false)
	if touch:
		touch.visible = false


func close_panel() -> void:
	if _panel_open:
		panel.give_back_cursor()
		if panel.mode in ["chest", "furnace"]:
			Net.request_container(panel.container_pos, "close", null)
	panel.visible = false
	_panel_open = false
	_capture_mouse(true)
	if touch:
		touch.visible = true


# ---------------------------------------------------------------- demarrages
func _on_solo(seed_value: int, pseudo: String, save: String) -> void:
	Net.local_name = pseudo
	Game.instance.start_singleplayer(seed_value, pseudo, save if save != "" else "monde")


func _on_host(seed_value: int, pseudo: String, save: String, server_name: String,
		public: bool) -> void:
	Net.local_name = pseudo
	if Net.host_game(pseudo, server_name, public):
		Game.instance.start_host(seed_value, pseudo, save if save != "" else "monde")


func _on_join(ip: String, port: int, pseudo: String) -> void:
	Net.local_name = pseudo
	Net.join_game(ip, port)
	hud.toast("Connexion en cours...")
