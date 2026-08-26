extends Control
class_name MainMenu
## Menu principal : solo, hebergement, navigateur de serveurs, options.

signal start_solo(seed_value: int, pseudo: String, save: String)
signal start_host(seed_value: int, pseudo: String, save: String, server_name: String, public: bool)
signal join_request(ip: String, port: int, pseudo: String)

const CFG := "user://settings.cfg"

var pseudo := "Joueur"
var list_url := ""
var api_url := ""

var _pages: Dictionary = {}
var _current := "main"
var _server_list: VBoxContainer
var _status: Label
var _code_edit: LineEdit
var _seed_edit: LineEdit
var _save_edit: LineEdit
var _name_edit: LineEdit
var _srv_edit: LineEdit
var _public_check: CheckBox
var _saves_list: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_load_settings()
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.09, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var logo := TextureRect.new()
	logo.texture = load("res://assets/textures/icon.png")
	logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	logo.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	logo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	logo.offset_left = -72
	logo.offset_right = 72
	logo.offset_top = 18
	logo.offset_bottom = 162
	add_child(logo)
	var title := UiKit.label("VOXELMAGE", 46, UiKit.ACCENT)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.offset_left = -300
	title.offset_right = 300
	title.offset_top = 168
	title.offset_bottom = 220
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)

	_status = UiKit.label("", 15, Color(0.8, 0.85, 1.0))
	_status.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_status.offset_top = -44
	_status.offset_bottom = -16
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_status)

	_build_main()
	_build_solo()
	_build_host()
	_build_join()
	_build_options()
	show_page("main")

	Net.status.connect(func(m): _status.text = m)
	Net.lan.servers_updated.connect(func(_l): _refresh_list())
	Net.directory.servers_updated.connect(func(_l): _refresh_list())
	Net.connect_failed.connect(func(): _status.text = "Connexion impossible.")


func _center_box(page: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_CENTER)
	scroll.offset_left = -260
	scroll.offset_right = 260
	scroll.offset_top = -70
	scroll.offset_bottom = 300
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.custom_minimum_size = Vector2(500, 0)
	scroll.add_child(box)
	add_child(scroll)
	_pages[page] = scroll
	return box


func show_page(p: String) -> void:
	_current = p
	for k in _pages:
		(_pages[k] as Control).visible = k == p
	if p == "join":
		refresh_servers()


func _build_main() -> void:
	var box := _center_box("main")
	var b1 := UiKit.button("Jouer en solo")
	b1.pressed.connect(func(): show_page("solo"))
	var b2 := UiKit.button("Heberger une partie")
	b2.pressed.connect(func(): show_page("host"))
	var b3 := UiKit.button("Rejoindre une partie")
	b3.pressed.connect(func(): show_page("join"))
	var b4 := UiKit.button("Options")
	b4.pressed.connect(func(): show_page("options"))
	var b5 := UiKit.button("Quitter")
	b5.pressed.connect(func(): get_tree().quit())
	for b in [b1, b2, b3, b4, b5]:
		box.add_child(b)
	if OS.has_feature("web"):
		box.add_child(UiKit.label(
			"Version navigateur : le solo fonctionne, l'hebergement necessite l'app.",
			13, Color(0.9, 0.8, 0.5)))


func _build_solo() -> void:
	var box := _center_box("solo")
	box.add_child(UiKit.label("Nouveau monde", 24))
	_save_edit = UiKit.line_edit("Nom du monde", "monde")
	box.add_child(_save_edit)
	_seed_edit = UiKit.line_edit("Graine (vide = aleatoire)")
	box.add_child(_seed_edit)
	var go := UiKit.button("Creer / charger")
	go.pressed.connect(func():
		_save_settings()
		start_solo.emit(_read_seed(), pseudo, _save_edit.text.strip_edges()))
	box.add_child(go)
	box.add_child(UiKit.label("Mondes sauvegardes", 18))
	_saves_list = VBoxContainer.new()
	box.add_child(_saves_list)
	var back := UiKit.button("Retour")
	back.pressed.connect(func(): show_page("main"))
	box.add_child(back)
	_refresh_saves()


func _refresh_saves() -> void:
	for c in _saves_list.get_children():
		c.queue_free()
	for s in Game.list_saves():
		var b := UiKit.button(str(s))
		b.pressed.connect(func(): start_solo.emit(0, pseudo, str(s)))
		_saves_list.add_child(b)


func _build_host() -> void:
	var box := _center_box("host")
	box.add_child(UiKit.label("Heberger (serveur integre a l'app)", 22))
	_srv_edit = UiKit.line_edit("Nom du serveur", "Partie de " + pseudo)
	box.add_child(_srv_edit)
	_public_check = CheckBox.new()
	_public_check.text = "Partie publique (visible dans la liste)"
	_public_check.button_pressed = true
	box.add_child(_public_check)
	box.add_child(UiKit.label(
		"Prive : la partie n'est pas annoncee, on la rejoint par code.", 13,
		Color(0.75, 0.78, 0.9)))
	var go := UiKit.button("Demarrer le serveur")
	go.pressed.connect(func():
		_save_settings()
		start_host.emit(_read_seed(), pseudo, _srv_edit.text.strip_edges().to_lower(),
				_srv_edit.text.strip_edges(), _public_check.button_pressed))
	box.add_child(go)
	var back := UiKit.button("Retour")
	back.pressed.connect(func(): show_page("main"))
	box.add_child(back)


func _build_join() -> void:
	var box := _center_box("join")
	box.add_child(UiKit.label("Parties disponibles", 22))
	_server_list = VBoxContainer.new()
	_server_list.add_theme_constant_override("separation", 6)
	box.add_child(_server_list)
	var refresh := UiKit.button("Actualiser")
	refresh.pressed.connect(refresh_servers)
	box.add_child(refresh)
	box.add_child(UiKit.label("Rejoindre par code ou adresse IP", 18))
	_code_edit = UiKit.line_edit("Code a 6 ou 8 caracteres, ou 192.168.1.20")
	box.add_child(_code_edit)
	var join := UiKit.button("Rejoindre")
	join.pressed.connect(_join_by_code)
	box.add_child(join)
	var back := UiKit.button("Retour")
	back.pressed.connect(func(): show_page("main"))
	box.add_child(back)


func _build_options() -> void:
	var box := _center_box("options")
	box.add_child(UiKit.label("Options", 24))
	box.add_child(UiKit.label("Pseudo", 16))
	_name_edit = UiKit.line_edit("Pseudo", pseudo)
	_name_edit.text_changed.connect(func(t): pseudo = t.strip_edges())
	box.add_child(_name_edit)
	box.add_child(UiKit.label("Annuaire public (URL du servers.json)", 16))
	var e1 := UiKit.line_edit("https://<user>.github.io/voxelmage/servers.json", list_url)
	e1.text_changed.connect(func(t): list_url = t.strip_edges())
	box.add_child(e1)
	box.add_child(UiKit.label("Annuaire dynamique (optionnel, codes courts en ligne)", 16))
	var e2 := UiKit.line_edit("https://mon-annuaire.exemple.com", api_url)
	e2.text_changed.connect(func(t): api_url = t.strip_edges())
	box.add_child(e2)
	var save := UiKit.button("Enregistrer")
	save.pressed.connect(func():
		_save_settings()
		Net.directory.configure(list_url, api_url)
		_status.text = "Options enregistrees.")
	box.add_child(save)
	var back := UiKit.button("Retour")
	back.pressed.connect(func(): show_page("main"))
	box.add_child(back)


func _read_seed() -> int:
	var t := _seed_edit.text.strip_edges() if _seed_edit else ""
	if t == "":
		return randi() % 999999
	if t.is_valid_int():
		return int(t)
	return abs(t.hash()) % 999999


# --------------------------------------------------------------- liste serveurs
func refresh_servers() -> void:
	Net.lan.start_listen()
	Net.directory.configure(list_url, api_url)
	Net.directory.refresh()
	_refresh_list()


func _refresh_list() -> void:
	if _server_list == null:
		return
	for c in _server_list.get_children():
		c.queue_free()
	var all: Array = Net.lan.list() + Net.directory.cached()
	if all.is_empty():
		_server_list.add_child(UiKit.label(
			"Aucune partie trouvee. Sur le meme reseau, les parties apparaissent "
			+ "automatiquement.", 14, Color(0.8, 0.8, 0.9)))
		return
	for s in all:
		if not s is Dictionary:
			continue
		var row := UiKit.make_panel(UiKit.BG_SOFT)
		var h := HBoxContainer.new()
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(UiKit.label("%s  [%s]" % [String(s.get("name", "Partie")),
				String(s.get("source", "?"))], 17))
		info.add_child(UiKit.label("%d/%d joueurs - code %s" % [
				int(s.get("players", 1)), int(s.get("max", 16)),
				String(s.get("code", "?"))], 13, Color(0.75, 0.78, 0.9)))
		h.add_child(info)
		var b := UiKit.button("Rejoindre", 15)
		b.custom_minimum_size = Vector2(130, 40)
		var ip := String(s.get("ip", ""))
		var port := int(s.get("port", Net.PORT))
		var direct := String(s.get("direct", ""))
		b.pressed.connect(func():
			if ip != "":
				join_request.emit(ip, port, pseudo)
			elif direct != "":
				var d := RoomCode.decode_direct(direct)
				if not d.is_empty():
					join_request.emit(String(d["ip"]), int(d["port"]), pseudo))
		h.add_child(b)
		row.add_child(h)
		_server_list.add_child(row)


func _join_by_code() -> void:
	var raw := _code_edit.text.strip_edges()
	if raw == "":
		return
	if raw.count(".") == 3:
		var parts := raw.split(":")
		join_request.emit(parts[0], int(parts[1]) if parts.size() > 1 else Net.PORT, pseudo)
		return
	match RoomCode.kind_of(raw):
		"direct":
			var d := RoomCode.decode_direct(raw)
			if d.is_empty():
				_status.text = "Code direct invalide."
			else:
				join_request.emit(String(d["ip"]), int(d["port"]), pseudo)
		"short":
			var found := Net.lan.find_by_code(raw)
			if not found.is_empty():
				join_request.emit(String(found["ip"]), int(found.get("port", Net.PORT)), pseudo)
				return
			if api_url != "":
				Net.directory.resolved.connect(func(info):
					if info.is_empty():
						_status.text = "Code introuvable dans l'annuaire."
					else:
						join_request.emit(String(info["ip"]), int(info.get("port", Net.PORT)),
								pseudo), CONNECT_ONE_SHOT)
				Net.directory.resolve(raw)
			else:
				_status.text = "Code court introuvable sur le reseau local. " \
						+ "Utilisez le code direct (8 caracteres) hors LAN."
		_:
			_status.text = "Code invalide."


# ------------------------------------------------------------------- reglages
func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CFG) == OK:
		pseudo = String(cfg.get_value("user", "pseudo", "Joueur"))
		list_url = String(cfg.get_value("net", "list_url", ""))
		api_url = String(cfg.get_value("net", "api_url", ""))
	Net.local_name = pseudo
	Net.directory.configure(list_url, api_url)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("user", "pseudo", pseudo)
	cfg.set_value("net", "list_url", list_url)
	cfg.set_value("net", "api_url", api_url)
	cfg.save(CFG)
	Net.local_name = pseudo
