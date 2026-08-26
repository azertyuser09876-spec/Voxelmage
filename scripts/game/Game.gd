extends Node3D
class_name Game
## Chef d'orchestre : monde, entites, logique serveur, sauvegarde, ambiance.

static var instance: Game

const SAVE_DIR := "user://saves"
const DAY_LENGTH := 720.0        # secondes pour un cycle complet

var world: VoxelWorld
var player: Player
var hud: HUD
var ui: UIRoot
var remote_players: Dictionary = {}      # peer_id -> Player
var mobs: Dictionary = {}                # mob_id -> Mob
var boss: Boss
var containers: Dictionary = {}          # Vector3i -> Dictionary
var world_seed := 1337
var spawn_point := Vector3(0, 50, 0)
var save_name := "monde"
var time_of_day := 0.30

var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _next_mob_id := 1
var _mob_timer := 2.0
var _furnace_timer := 0.0
var _autosave := 0.0
var _viewers: Dictionary = {}            # Vector3i -> Array[peer]
var started := false
var spawn_ready := false                 # le terrain sous le joueur est-il charge ?


func _init() -> void:
	instance = self


func _ready() -> void:
	Blocks._build()
	Items._build()
	Recipes._build()
	Spells._build()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_build_environment()
	ui = UIRoot.new()
	add_child(ui)
	hud = ui.hud
	Net.chat_message.connect(func(who, msg): hud.add_chat(who, msg))
	ui.show_main_menu()
	if "--smoke" in OS.get_cmdline_args() or "--smoke" in OS.get_cmdline_user_args():
		_run_smoke.call_deferred()
	if "--inputtest" in OS.get_cmdline_args() or "--inputtest" in OS.get_cmdline_user_args():
		_run_input_test.call_deferred()


func _run_input_test() -> void:
	## Verifie que les commandes repondent : camera souris, deplacement clavier,
	## barre rapide, molette, sorts, et que l'interface ouverte bloque bien les
	## clics vers le monde.
	var fails: Array[String] = []
	DirAccess.remove_absolute("%s/inputtest.dat" % SAVE_DIR)
	start_singleplayer(20260821, "Testeur", "inputtest")
	var waited := 0.0
	while not spawn_ready and waited < 25.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(1.0).timeout

	# --- camera a la souris (curseur capture) ---
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var yaw0: float = player._yaw
	var pitch0: float = player._pitch
	var mm := InputEventMouseMotion.new()
	mm.relative = Vector2(220.0, 90.0)
	Input.parse_input_event(mm)
	await get_tree().process_frame
	await get_tree().process_frame
	print("[input] yaw %.3f -> %.3f | pitch %.3f -> %.3f" % [yaw0, player._yaw, pitch0, player._pitch])
	if is_equal_approx(yaw0, player._yaw):
		fails.append("la souris ne fait pas tourner la camera (curseur capture)")
	if is_equal_approx(pitch0, player._pitch):
		fails.append("la souris ne fait pas monter/descendre la vue")

	# --- camera a la souris sans capture, bouton enfonce (repli navigateur) ---
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var yaw1: float = player._yaw
	var mm2 := InputEventMouseMotion.new()
	mm2.relative = Vector2(150.0, 0.0)
	mm2.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(mm2)
	await get_tree().process_frame
	await get_tree().process_frame
	if is_equal_approx(yaw1, player._yaw):
		fails.append("repli souris (glissement bouton enfonce) inoperant")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# --- deplacement clavier ---
	player._yaw = 0.0
	var pos0: Vector3 = player.global_position
	Input.action_press("move_forward", 1.0)
	await get_tree().create_timer(0.8).timeout
	Input.action_release("move_forward")
	var moved: float = player.global_position.distance_to(pos0)
	print("[input] deplacement avant : %.2f m" % moved)
	if moved < 0.8:
		fails.append("la touche avancer ne deplace pas le joueur (%.2f m)" % moved)

	# --- barre rapide : touches, molette ---
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_4
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	if player.hotbar != 3:
		fails.append("la touche 4 ne selectionne pas le 4e emplacement (%d)" % player.hotbar)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	Input.parse_input_event(wheel)
	await get_tree().process_frame
	if player.hotbar != 4:
		fails.append("la molette ne change pas d'emplacement (%d)" % player.hotbar)

	# --- sorts ---
	player.inv.set_slot(0, {"id": Items.WAND5, "count": 1, "dura": 0})
	player.set_hotbar(0)
	var spell0: int = player.selected_spell
	var sp := InputEventKey.new()
	sp.physical_keycode = KEY_C
	sp.pressed = true
	Input.parse_input_event(sp)
	await get_tree().process_frame
	if player.selected_spell == spell0:
		fails.append("la touche C ne change pas de sort")

	# --- l'interface ouverte doit bloquer les clics vers le monde ---
	ui.open_inventory()
	await get_tree().process_frame
	if not ui.blocking():
		fails.append("l'inventaire ouvert n'est pas detecte comme bloquant")
	var edits0: int = world.edits.size()
	Input.action_press("attack", 1.0)
	await get_tree().create_timer(1.2).timeout
	Input.action_release("attack")
	if world.edits.size() != edits0:
		fails.append("on mine a travers l'inventaire ouvert")
	ui.close_panel()
	await get_tree().process_frame

	if fails.is_empty():
		print("[input] OK - toutes les commandes repondent")
		get_tree().quit(0)
	else:
		for f in fails:
			printerr("[input] ECHEC : %s" % f)
		get_tree().quit(1)


func _run_smoke() -> void:
	## Test de fumee (lance par la CI) : genere un monde, verifie le terrain, le
	## craft, la magie destructrice et les entites, puis enregistre des captures.
	var fails: Array[String] = []
	print("[smoke] demarrage")
	DirAccess.remove_absolute("%s/smoke.dat" % SAVE_DIR)   # monde vierge a chaque run
	start_singleplayer(20260821, "Testeur", "smoke")
	player.third_person = true
	player.model.set_hidden(false)
	var waited := 0.0
	while not spawn_ready and waited < 25.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	await get_tree().create_timer(4.0).timeout
	print("[smoke] chunks charges : %d (sol pret en %.1f s)" % [world.loaded_count(), waited])
	print("[smoke] joueur : %s (%s)" % [str(player.global_position),
			WorldGen.BIOME_NAMES[world.gen_main.biome_at(0, 0)]])
	if world.loaded_count() < 20:
		fails.append("trop peu de chunks charges")
	if not player.is_on_floor():
		fails.append("le joueur ne repose pas sur le sol (collision)")
	await _shot("smoke_monde")

	# craft : 1 rondin -> 4 planches, puis 2 planches -> 4 batons
	var grid := Inventory.new(4)
	grid.set_slot(0, {"id": Blocks.LOG, "count": 1, "dura": 0})
	var r1 := Recipes.match_craft(grid.slots, 2)
	if int(r1.get("out", 0)) != Blocks.PLANKS or int(r1.get("count", 0)) != 4:
		fails.append("recette planches cassee")
	grid.clear()
	grid.set_slot(0, {"id": Blocks.PLANKS, "count": 1, "dura": 0})
	grid.set_slot(2, {"id": Blocks.PLANKS, "count": 1, "dura": 0})
	var r2 := Recipes.match_craft(grid.slots, 2)
	if int(r2.get("out", 0)) != Items.STICK:
		fails.append("recette batons cassee")
	if Recipes.smelt_result(Blocks.IRON_ORE).is_empty():
		fails.append("fusion du fer cassee")
	print("[smoke] craft ok : %s / %s" % [str(r1), str(r2)])

	# magie : le sort de rang 5 doit desintegrer un cratere
	var before := world.edits.size()
	var center := player.global_position + Vector3(0, -1.0, -6.0)
	resolve_impact(center, 0.0, 6.0, 5, 1, false)
	var destroyed := world.edits.size() - before
	print("[smoke] blocs desintegres par le sort : %d" % destroyed)
	if destroyed < 50:
		fails.append("la magie ne detruit pas assez de blocs (%d)" % destroyed)
	# un sort de rang 1 ne doit PAS percer la pierre
	var b2 := world.edits.size()
	resolve_impact(player.global_position + Vector3(6, -1, 0), 0.0, 3.0, 1, 1, false)
	print("[smoke] blocs desintegres par le rang 1 : %d" % (world.edits.size() - b2))
	await get_tree().create_timer(1.0).timeout
	await _shot("smoke_magie")

	# entites
	server_spawn_mob(Mob.HUSK, player.global_position + Vector3(3.0, 1.0, -5.0))
	server_spawn_mob(Mob.SLIME, player.global_position + Vector3(-3.0, 1.0, -6.0))
	server_spawn_mob(Mob.WRAITH, player.global_position + Vector3(6.0, 1.0, -7.0))
	summon_boss(player.global_position + Vector3(0.0, 0.0, -13.0))
	await get_tree().create_timer(2.0).timeout
	if mobs.size() < 3 or boss == null:
		fails.append("les entites ne se sont pas creees")
	await _shot("smoke_entites")

	# inventaire / sauvegarde
	save_world()
	if not FileAccess.file_exists(save_path()):
		fails.append("la sauvegarde n'a pas ete ecrite")

	if fails.is_empty():
		print("[smoke] OK - tout est vert")
		get_tree().quit(0)
	else:
		for f in fails:
			printerr("[smoke] ECHEC : %s" % f)
		get_tree().quit(1)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://%s.png" % name)
	print("[smoke] capture %s" % ProjectSettings.globalize_path("user://%s.png" % name))


# ------------------------------------------------------------------- ambiance
func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var e := Environment.new()
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.30, 0.52, 0.92)
	mat.sky_horizon_color = Color(0.72, 0.83, 0.95)
	mat.ground_bottom_color = Color(0.20, 0.22, 0.26)
	mat.ground_horizon_color = Color(0.55, 0.58, 0.62)
	mat.sun_angle_max = 12.0
	sky.sky_material = mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.fog_enabled = true
	e.fog_light_color = Color(0.68, 0.78, 0.90)
	e.fog_density = 0.0035
	e.fog_sky_affect = 0.2
	_env.environment = e
	add_child(_env)

	_sun = DirectionalLight3D.new()
	_sun.rotation_degrees = Vector3(-52, -38, 0)
	_sun.light_energy = 1.0
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 70.0
	add_child(_sun)


func _process(delta: float) -> void:
	if not started:
		return
	time_of_day = fposmod(time_of_day + delta / DAY_LENGTH, 1.0)
	var ang := time_of_day * TAU
	_sun.rotation = Vector3(-sin(ang) * 1.2 - 0.35, -0.7, 0.0)
	var night: float = clampf(sin(ang), 0.0, 1.0)
	_sun.light_energy = lerpf(0.12, 1.05, night)
	var e := _env.environment
	e.ambient_light_energy = lerpf(0.18, 0.6, night)
	if player != null:
		world.update_center(player.global_position)
		if not spawn_ready:
			_check_spawn_ready()
		hud.set_debug(player.global_position, world.loaded_count(),
				WorldGen.BIOME_NAMES[world.gen_main.biome_at(
					int(player.global_position.x), int(player.global_position.z))])
	if Net.is_server():
		_server_tick(delta)
	_autosave += delta
	if _autosave > 60.0:
		_autosave = 0.0
		if not Net.is_online() or Net.hosting:
			save_world()


# ------------------------------------------------------------------ demarrage
func start_singleplayer(p_seed: int, p_name: String, save: String) -> void:
	world_seed = p_seed
	save_name = save
	_create_world()
	spawn_point = world.gen_main.spawn_point()
	_create_local_player(p_name, 1)
	load_world()
	started = true
	ui.close_all()
	hud.toast("Monde charge - graine %d" % world_seed)


func start_host(p_seed: int, p_name: String, save: String) -> void:
	start_singleplayer(p_seed, p_name, save)
	hud.add_chat("[Systeme]", "Partie hebergee. Code : %s | Code direct : %s"
			% [Net.room_code, Net.direct_code])


func start_client_world(p_seed: int, edits: PackedByteArray, size: int,
		p_spawn: Vector3) -> void:
	world_seed = p_seed
	_create_world()
	spawn_point = p_spawn
	var d := world.deserialize_edits(edits, size)
	world.apply_edits(d)
	_create_local_player(Net.local_name, Net.my_id())
	started = true
	ui.close_all()
	hud.toast("Connecte - %d modifications recues" % d.size())


func _create_world() -> void:
	if world != null:
		world.queue_free()
	world = VoxelWorld.new()
	world.name = "World"
	world.setup(world_seed)
	if OS.has_feature("mobile") or OS.has_feature("web"):
		world.view_distance = 4
	add_child(world)


func _check_spawn_ready() -> void:
	## Le monde etant genere sur un thread, on ne libere le joueur qu'une fois
	## la collision de son chunk construite : sinon il traverse le sol.
	if not world.is_loaded(VoxelWorld.chunk_of(spawn_point)):
		return
	spawn_ready = true
	player.global_position = safe_spawn()
	player.velocity = Vector3.ZERO
	player.set_physics_process(true)


func safe_spawn() -> Vector3:
	## Position sur le premier bloc libre au-dessus du sol.
	var gx := floori(spawn_point.x)
	var gz := floori(spawn_point.z)
	var gy := world.ground_height(gx, gz)
	return Vector3(float(gx) + 0.5, float(gy) + 1.1, float(gz) + 0.5)


func _create_local_player(p_name: String, peer: int) -> void:
	if player != null:
		player.queue_free()
	player = Player.new()
	player.setup(peer, p_name, true)
	add_child(player)
	player.global_position = spawn_point
	player.set_physics_process(false)     # gele tant que le sol n'existe pas
	spawn_ready = false
	player.give_starter_kit()
	player.open_container.connect(_on_open_container)
	player.stats_changed.connect(func(): hud.refresh_stats(player))
	player.hotbar_changed.connect(func(): hud.refresh_hotbar(player))
	player.inv.changed.connect(func(): hud.refresh_hotbar(player))
	hud.bind(player)


func add_remote_player(peer: int, p_name: String) -> Player:
	if remote_players.has(peer):
		return remote_players[peer]
	var p := Player.new()
	p.setup(peer, p_name, false)
	add_child(p)
	p.global_position = spawn_point
	p.model.set_nametag(p_name)
	remote_players[peer] = p
	return p


func remove_remote_player(peer: int) -> void:
	if remote_players.has(peer):
		var p: Player = remote_players[peer]
		remote_players.erase(peer)
		if is_instance_valid(p):
			p.queue_free()


# -------------------------------------------------------------- synchronisation
func collect_states() -> Dictionary:
	var out := {}
	if player != null:
		out[Net.my_id()] = [player.global_position, player.rotation.y, 0.0,
				Vector2(player.velocity.x, player.velocity.z).length(), player.hp]
	for peer in remote_players:
		var p: Player = remote_players[peer]
		out[peer] = [p.global_position, p.rotation.y, 0.0, p._net_speed, p.hp]
	return out


func apply_states(states: Dictionary) -> void:
	for k in states:
		var peer := int(k)
		if peer == Net.my_id():
			continue
		var s: Array = states[k]
		var p: Player = remote_players.get(peer, null)
		if p == null:
			p = add_remote_player(peer, String(Net.players.get(peer, {}).get("name", "Joueur")))
		p.apply_net_state(s[0], s[1], s[2], s[3], s[4])


func set_remote_state(peer: int, pos: Vector3, yaw: float, pitch: float, spd: float,
		hp: float) -> void:
	var p: Player = remote_players.get(peer, null)
	if p == null:
		p = add_remote_player(peer, String(Net.players.get(peer, {}).get("name", "Joueur")))
	p.apply_net_state(pos, yaw, pitch, spd, hp)


func collect_mob_states() -> Array:
	var out: Array = []
	for id in mobs:
		var m: Mob = mobs[id]
		out.append([id, m.global_position, m.rotation.y, m.hp])
	if boss != null:
		out.append([-1, boss.global_position, boss.rotation.y, boss.hp])
	return out


func apply_mob_states(list: Array) -> void:
	for e in list:
		var id := int(e[0])
		if id == -1:
			if boss != null:
				boss.apply_net_state(e[1], e[2], e[3])
			continue
		var m: Mob = mobs.get(id, null)
		if m != null:
			m.apply_net_state(e[1], e[2], e[3])


# ------------------------------------------------------------- logique serveur
func _drops_for(id: int) -> Array:
	match id:
		Blocks.COAL_ORE:
			return [Items.COAL, 2]
		Blocks.MANA_ORE:
			return [Items.MANA_CRYSTAL, 1 + (randi() % 2)]
		Blocks.LEAVES:
			return [Items.APPLE, 1] if randf() < 0.08 else []
		Blocks.GLASS, Blocks.ICE, Blocks.WATER:
			return []
		Blocks.GRASS:
			return [Blocks.DIRT, 1]
		Blocks.STONE:
			return [Blocks.COBBLE, 1]
		Blocks.FURNACE_LIT:
			return [Blocks.FURNACE, 1]
	if id == Blocks.BEDROCK:
		return []
	return [id, 1]


func server_break(pos: Vector3i, by_peer: int) -> void:
	var id := world.get_block(pos)
	if id == Blocks.AIR or id == Blocks.BEDROCK:
		return
	world.set_block(pos, Blocks.AIR)
	Net.broadcast_block(pos, Blocks.AIR)
	containers.erase(pos)
	var d := _drops_for(id)
	if not d.is_empty():
		Net.give_item(by_peer, int(d[0]), int(d[1]))


func server_place(pos: Vector3i, id: int, _by_peer: int) -> void:
	if world.get_block(pos) not in [Blocks.AIR, Blocks.WATER]:
		return
	world.set_block(pos, id)
	Net.broadcast_block(pos, id)


func server_cast(spell_id: int, tier: int, mastery: int, origin: Vector3, dir: Vector3,
		by_peer: int) -> void:
	var s := Spells.scaled(spell_id, tier, mastery)
	var color := Color(s["color"])
	match int(s["kind"]):
		Spells.KIND_BOLT:
			spawn_projectile_local(origin, dir, float(s["speed"]), color,
					float(s["damage"]), float(s["radius"]), int(s["break_tier"]),
					by_peer, false, true)
			if Net.hosting:
				Net.s_projectile.rpc(origin, dir, float(s["speed"]), color,
						float(s["radius"]), false, by_peer)
		Spells.KIND_NOVA:
			resolve_impact(origin, float(s["damage"]), float(s["radius"]),
					int(s["break_tier"]), by_peer, false)
			spawn_spell_fx(origin, color, float(s["radius"]))
			if Net.hosting:
				Net.s_fx.rpc(origin, color, float(s["radius"]))
		Spells.KIND_BEAM:
			var steps := int(float(s["range"]) / 1.2)
			for i in steps:
				var p := origin + dir * (1.2 * float(i))
				resolve_impact(p, float(s["damage"]) * 0.35, float(s["radius"]),
						int(s["break_tier"]), by_peer, false)
			spawn_spell_fx(origin + dir * 6.0, color, 2.0)
			if Net.hosting:
				Net.s_fx.rpc(origin + dir * 6.0, color, 2.0)


func resolve_impact(center: Vector3, damage: float, radius: float, break_tier: int,
		by_peer: int, hostile: bool) -> void:
	## Destruction du terrain + degats de zone (cote serveur uniquement).
	if break_tier > 0:
		var broken := world.magic_break(center, radius, break_tier)
		var batch: Array = []
		for e in broken:
			var p: Vector3i = e[0]
			world.set_block(p, Blocks.AIR)
			batch.append([p.x, p.y, p.z, Blocks.AIR])
			if randf() < 0.35:
				var d := _drops_for(int(e[1]))
				if not d.is_empty() and by_peer > 0:
					Net.give_item(by_peer, int(d[0]), int(d[1]))
		Net.broadcast_blocks(batch)
	if damage <= 0.0:
		return
	if hostile:
		for p in get_tree().get_nodes_in_group("players"):
			var pl := p as Player
			if pl != null and pl.global_position.distance_to(center) < radius + 0.8:
				Net.damage_player(pl.peer_id, damage,
						(pl.global_position - center).normalized())
	else:
		for m in get_tree().get_nodes_in_group("mobs"):
			var n := m as Node3D
			if n.global_position.distance_to(center) < radius + 0.8:
				var knock := (n.global_position - center).normalized()
				if m is Boss:
					(m as Boss).hurt(damage, knock, by_peer)
				elif m is Mob:
					(m as Mob).hurt(damage, knock, by_peer)


func server_hit_mob(mob_id: int, dmg: float, dir: Vector3, by_peer: int) -> void:
	if mob_id == -1 and boss != null:
		boss.hurt(dmg, dir, by_peer)
		return
	var m: Mob = mobs.get(mob_id, null)
	if m != null:
		m.hurt(dmg, dir, by_peer)


func _server_tick(delta: float) -> void:
	_mob_timer -= delta
	if _mob_timer <= 0.0:
		_mob_timer = 4.0
		_spawn_wave()
	_furnace_timer -= delta
	if _furnace_timer <= 0.0:
		_furnace_timer = 0.5
		_tick_furnaces(0.5)


func _spawn_wave() -> void:
	var night: bool = time_of_day > 0.5
	var cap: int = (18 if night else 8)
	if mobs.size() >= cap or player == null:
		return
	for i in 2:
		var ang := randf() * TAU
		var dist := randf_range(18.0, 34.0)
		var x := int(player.global_position.x + cos(ang) * dist)
		var z := int(player.global_position.z + sin(ang) * dist)
		var y := world.ground_height(x, z)
		if y <= WorldGen.SEA:
			continue
		var t := Mob.SLIME
		var r := randf()
		if night:
			t = Mob.HUSK if r < 0.6 else Mob.WRAITH
		elif r < 0.5:
			t = Mob.SLIME
		else:
			continue
		server_spawn_mob(t, Vector3(x + 0.5, y + 1.6, z + 0.5))
	# nettoyage des mobs trop loin
	for id in mobs.keys():
		var m: Mob = mobs[id]
		if m.global_position.distance_to(player.global_position) > 90.0:
			Net.despawn_mob(id)


func server_spawn_mob(type: int, pos: Vector3) -> void:
	var id := _next_mob_id
	_next_mob_id += 1
	spawn_mob_local(id, type, pos, true)
	if Net.hosting:
		Net.s_mob_spawn.rpc(id, type, pos)


func spawn_mob_local(id: int, type: int, pos: Vector3, auth: bool) -> void:
	if mobs.has(id):
		return
	var m := Mob.new()
	m.setup(id, type, auth)
	add_child(m)
	m.global_position = pos
	mobs[id] = m


func despawn_mob_local(id: int) -> void:
	var m: Mob = mobs.get(id, null)
	if m != null:
		mobs.erase(id)
		m.queue_free()


func summon_boss(pos: Vector3) -> void:
	if boss != null:
		hud.toast("Le colosse est deja invoque")
		return
	spawn_boss_local(pos + Vector3(0, 2, 0), Net.is_server())
	if Net.hosting:
		Net.s_boss_spawn.rpc(pos + Vector3(0, 2, 0))
	Net.chat_broadcast("[Systeme]", "%s s'eveille !" % Boss.NAME)


func spawn_boss_local(pos: Vector3, auth: bool) -> void:
	if boss != null:
		return
	boss = Boss.new()
	boss.setup(1, auth)
	add_child(boss)
	boss.global_position = pos
	hud.show_boss_bar(Boss.NAME)


func despawn_boss_local() -> void:
	if boss != null:
		boss.queue_free()
		boss = null
	hud.hide_boss_bar()


func spawn_projectile_local(origin: Vector3, dir: Vector3, speed: float, color: Color,
		dmg: float, radius: float, btier: int, owner: int, hostile: bool,
		auth: bool) -> void:
	var p := Projectile.new()
	p.setup(origin, dir, speed, color)
	p.damage = dmg
	p.radius = radius
	p.break_tier = btier
	p.owner_peer = owner
	p.hostile = hostile
	p.authoritative = auth and Net.is_server()
	add_child(p)


func spawn_spell_fx(pos: Vector3, color: Color, scale: float) -> void:
	var fx := CPUParticles3D.new()
	fx.emitting = true
	fx.one_shot = true
	fx.amount = int(clampf(18.0 * scale, 12.0, 90.0))
	fx.lifetime = 0.7
	fx.explosiveness = 0.95
	fx.direction = Vector3.UP
	fx.spread = 180.0
	fx.initial_velocity_min = 2.0 * scale
	fx.initial_velocity_max = 6.0 * scale
	fx.gravity = Vector3(0, -6, 0)
	fx.scale_amount_min = 0.12 * scale
	fx.scale_amount_max = 0.3 * scale
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	var q := QuadMesh.new()
	q.size = Vector2(0.3, 0.3)
	fx.mesh = q
	fx.material_override = m
	fx.position = pos
	add_child(fx)
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(fx):
			fx.queue_free())


# ------------------------------------------------------------------ conteneurs
func _on_open_container(kind: String, pos: Vector3i) -> void:
	match kind:
		"craft":
			ui.open_crafting(3)
		"altar":
			ui.open_altar(pos)
		"runes":
			ui.open_runes()
		"chest", "furnace":
			Net.request_container(pos, "open", null)


func _container_at(pos: Vector3i) -> Dictionary:
	if not containers.has(pos):
		var id := world.get_block(pos)
		var kind := String(Blocks.get_def(id).get("interact", ""))
		if kind == "chest":
			containers[pos] = {"kind": "chest", "inv": Inventory.new(27)}
		elif kind == "furnace":
			containers[pos] = {"kind": "furnace", "inv": Inventory.new(3),
					"burn": 0.0, "cook": 0.0, "burn_max": 1.0}
		else:
			return {}
	return containers[pos]


func server_container(pos: Vector3i, action: String, payload: Variant, peer: int) -> void:
	var c := _container_at(pos)
	if c.is_empty():
		return
	match action:
		"open":
			var v: Array = _viewers.get(pos, [])
			if not v.has(peer):
				v.append(peer)
			_viewers[pos] = v
			_send_container(pos, peer)
		"close":
			var v2: Array = _viewers.get(pos, [])
			v2.erase(peer)
			_viewers[pos] = v2
		"set":
			var d: Dictionary = payload
			var inv: Inventory = c["inv"]
			inv.set_slot(int(d["slot"]), {"id": int(d["id"]), "count": int(d["count"]),
					"dura": int(d.get("dura", 0))})
			_broadcast_container(pos)


func _container_data(pos: Vector3i) -> Dictionary:
	var c: Dictionary = containers.get(pos, {})
	if c.is_empty():
		return {}
	var inv: Inventory = c["inv"]
	var out := {"slots": inv.to_array()}
	if c["kind"] == "furnace":
		out["burn"] = float(c["burn"])
		out["burn_max"] = float(c["burn_max"])
		out["cook"] = float(c["cook"])
	return out


func _send_container(pos: Vector3i, peer: int) -> void:
	var c: Dictionary = containers.get(pos, {})
	if c.is_empty():
		return
	if peer == Net.my_id() or not Net.is_online():
		on_container_data(pos, String(c["kind"]), _container_data(pos))
	elif Net.hosting:
		Net.s_container.rpc_id(peer, pos, String(c["kind"]), _container_data(pos))


func _broadcast_container(pos: Vector3i) -> void:
	for peer in _viewers.get(pos, []):
		_send_container(pos, int(peer))


func on_container_data(pos: Vector3i, kind: String, data: Dictionary) -> void:
	ui.open_container(kind, pos, data)


func _tick_furnaces(dt: float) -> void:
	for pos in containers.keys():
		var c: Dictionary = containers[pos]
		if c["kind"] != "furnace":
			continue
		var inv: Inventory = c["inv"]
		var input := inv.get_slot(0)
		var fuel := inv.get_slot(1)
		var res := Recipes.smelt_result(int(input.get("id", 0)))
		var burning: bool = float(c["burn"]) > 0.0
		if burning:
			c["burn"] = float(c["burn"]) - dt
		if not res.is_empty():
			if not burning and not Inventory.is_empty_slot(fuel):
				var ft := Recipes.fuel_time(int(fuel["id"]))
				if ft > 0.0:
					inv.consume_slot(1)
					c["burn"] = ft
					c["burn_max"] = ft
					burning = true
			if burning:
				c["cook"] = float(c["cook"]) + dt
				if float(c["cook"]) >= float(res[2]):
					c["cook"] = 0.0
					inv.consume_slot(0)
					inv.add(int(res[0]), int(res[1]))
		else:
			c["cook"] = 0.0
		var lit := float(c["burn"]) > 0.0
		var cur := world.get_block(pos)
		if lit and cur == Blocks.FURNACE:
			world.set_block(pos, Blocks.FURNACE_LIT)
			Net.broadcast_block(pos, Blocks.FURNACE_LIT)
		elif not lit and cur == Blocks.FURNACE_LIT:
			world.set_block(pos, Blocks.FURNACE)
			Net.broadcast_block(pos, Blocks.FURNACE)
		containers[pos] = c
		if not _viewers.get(pos, []).is_empty():
			_broadcast_container(pos)


# ----------------------------------------------------------------- sauvegarde
func save_path() -> String:
	return "%s/%s.dat" % [SAVE_DIR, save_name]


func save_world() -> void:
	if world == null or player == null:
		return
	var cdata := {}
	for pos in containers:
		var c: Dictionary = containers[pos]
		cdata[pos] = {"kind": c["kind"], "slots": (c["inv"] as Inventory).to_array()}
	var payload := {
		"seed": world_seed, "edits": world.edits, "player": player.serialize(),
		"time": time_of_day, "containers": cdata, "version": 1,
	}
	var f := FileAccess.open(save_path(), FileAccess.WRITE)
	if f != null:
		f.store_var(payload)
		f.close()


func load_world() -> void:
	if not FileAccess.file_exists(save_path()):
		return
	var f := FileAccess.open(save_path(), FileAccess.READ)
	if f == null:
		return
	var payload = f.get_var()
	f.close()
	if not payload is Dictionary:
		return
	world_seed = int(payload.get("seed", world_seed))
	world.apply_edits(payload.get("edits", {}))
	time_of_day = float(payload.get("time", 0.3))
	player.deserialize(payload.get("player", {}))
	for pos in payload.get("containers", {}):
		var c: Dictionary = payload["containers"][pos]
		var size: int = 27 if String(c["kind"]) == "chest" else 3
		var inv := Inventory.new(size)
		inv.from_array(c["slots"])
		containers[pos] = {"kind": c["kind"], "inv": inv, "burn": 0.0, "cook": 0.0,
				"burn_max": 1.0}


static func list_saves() -> Array:
	var out: Array = []
	var d := DirAccess.open(SAVE_DIR)
	if d == null:
		return out
	for f in d.get_files():
		if f.ends_with(".dat"):
			out.append(f.get_basename())
	return out
