extends Node
## Gestionnaire reseau (autoload "Net").
##
## L'hote lance le serveur DEPUIS l'application (aucun logiciel tiers).
## Transport : WebSocketMultiplayerPeer, qui fonctionne en natif (Windows,
## Android) et permet aussi aux clients navigateur de se connecter.

signal connected_ok
signal connect_failed
signal disconnected
signal players_changed
signal chat_message(who: String, msg: String)
signal status(msg: String)

const PORT := 24565
const MAX_PLAYERS := 16

var lan: LanDiscovery
var directory: Directory

var hosting := false
var online := false
var local_name := "Joueur"
var server_name := "Partie"
var is_public := true
var room_code := ""
var direct_code := ""
var players: Dictionary = {}        # peer_id -> {"name": String}

var _peer: WebSocketMultiplayerPeer
var _state_acc := 0.0


func _ready() -> void:
	lan = LanDiscovery.new()
	lan.name = "Lan"
	add_child(lan)
	directory = Directory.new()
	directory.name = "Directory"
	add_child(directory)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connect_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	set_process(true)


func is_online() -> bool:
	return online


func is_server() -> bool:
	return not online or hosting


func my_id() -> int:
	return multiplayer.get_unique_id() if online else 1


# ------------------------------------------------------------------ hebergement
func host_game(p_name: String, p_server_name: String, public: bool,
		port: int = PORT) -> bool:
	local_name = p_name
	server_name = p_server_name
	is_public = public
	_peer = WebSocketMultiplayerPeer.new()
	var err := _peer.create_server(port)
	if err != OK:
		status.emit("Impossible d'ouvrir le port %d (erreur %d)" % [port, err])
		return false
	multiplayer.multiplayer_peer = _peer
	hosting = true
	online = true
	room_code = RoomCode.random_short()
	direct_code = RoomCode.encode_direct(RoomCode.local_ipv4(), port)
	players = {1: {"name": local_name}}
	players_changed.emit()

	lan.start_broadcast({
		"name": server_name, "code": room_code, "direct": direct_code,
		"port": port, "public": public, "players": 1, "max": MAX_PLAYERS,
		"version": ProjectSettings.get_setting("application/config/version", "1.0"),
	})
	if public:
		directory.announce({
			"name": server_name, "code": room_code, "direct": direct_code,
			"port": port, "players": 1, "max": MAX_PLAYERS,
		})
	status.emit("Serveur demarre sur le port %d" % port)
	return true


func join_game(ip: String, port: int = PORT) -> bool:
	_peer = WebSocketMultiplayerPeer.new()
	var url := "ws://%s:%d" % [ip, port]
	var err := _peer.create_client(url)
	if err != OK:
		status.emit("Connexion impossible a %s" % url)
		return false
	multiplayer.multiplayer_peer = _peer
	hosting = false
	online = true
	status.emit("Connexion a %s..." % url)
	return true


func leave() -> void:
	if hosting:
		lan.stop_broadcast()
		directory.stop_announce()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	hosting = false
	online = false
	players.clear()
	players_changed.emit()


func update_beacon() -> void:
	if not hosting:
		return
	var info := lan.beacon
	info["players"] = players.size()
	lan.beacon = info


# --------------------------------------------------------------- evenements bas niveau
func _on_peer_connected(id: int) -> void:
	status.emit("Pair %d connecte" % id)


func _on_peer_disconnected(id: int) -> void:
	var who: String = String(players.get(id, {}).get("name", "?"))
	players.erase(id)
	players_changed.emit()
	update_beacon()
	if Game.instance:
		Game.instance.remove_remote_player(id)
	if hosting:
		s_player_left.rpc(id)
		s_chat.rpc("[Systeme]", "%s a quitte la partie" % who)


func _on_connected() -> void:
	c_hello.rpc_id(1, local_name)
	connected_ok.emit()


func _on_connect_failed() -> void:
	online = false
	connect_failed.emit()
	status.emit("Echec de la connexion")


func _on_server_disconnected() -> void:
	online = false
	disconnected.emit()
	status.emit("Deconnecte du serveur")


func _process(delta: float) -> void:
	if not online or not hosting or Game.instance == null:
		return
	_state_acc += delta
	if _state_acc >= 0.08:
		_state_acc = 0.0
		var st := Game.instance.collect_states()
		if not st.is_empty():
			s_states.rpc(st)
		var ms := Game.instance.collect_mob_states()
		if not ms.is_empty():
			s_mob_states.rpc(ms)


# ================================================================= CLIENT -> SERVEUR
@rpc("any_peer", "reliable")
func c_hello(name: String) -> void:
	if not hosting:
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": name}
	players_changed.emit()
	update_beacon()
	var w: VoxelWorld = Game.instance.world
	var raw := var_to_bytes(w.edits)
	s_welcome.rpc_id(id, Game.instance.world_seed, raw.compress(FileAccess.COMPRESSION_ZSTD),
			raw.size(), _player_names(), Game.instance.spawn_point)
	s_player_joined.rpc(id, name)
	s_chat.rpc("[Systeme]", "%s a rejoint la partie" % name)
	for m in Game.instance.mobs.values():
		s_mob_spawn.rpc_id(id, m.mob_id, m.mob_type, m.global_position)
	if Game.instance.boss != null:
		s_boss_spawn.rpc_id(id, Game.instance.boss.global_position)


func _player_names() -> Dictionary:
	var out := {}
	for k in players:
		out[k] = players[k]["name"]
	return out


@rpc("any_peer", "unreliable_ordered")
func c_state(pos: Vector3, yaw: float, pitch: float, spd: float, hp: float) -> void:
	if not hosting:
		return
	Game.instance.set_remote_state(multiplayer.get_remote_sender_id(), pos, yaw, pitch, spd, hp)


@rpc("any_peer", "reliable")
func c_break(pos: Vector3i) -> void:
	if hosting:
		Game.instance.server_break(pos, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func c_place(pos: Vector3i, id: int) -> void:
	if hosting:
		Game.instance.server_place(pos, id, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func c_cast(spell_id: int, tier: int, mastery: int, origin: Vector3, dir: Vector3) -> void:
	if hosting:
		Game.instance.server_cast(spell_id, tier, mastery, origin, dir,
				multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func c_hit_mob(mob_id: int, dmg: float, dir: Vector3) -> void:
	if hosting:
		Game.instance.server_hit_mob(mob_id, dmg, dir, multiplayer.get_remote_sender_id())


@rpc("any_peer", "reliable")
func c_chat(msg: String) -> void:
	if hosting:
		var who: String = String(players.get(multiplayer.get_remote_sender_id(),
				{}).get("name", "?"))
		s_chat.rpc(who, msg)
		chat_message.emit(who, msg)


@rpc("any_peer", "reliable")
func c_container(pos: Vector3i, action: String, payload: Variant) -> void:
	if hosting:
		Game.instance.server_container(pos, action, payload,
				multiplayer.get_remote_sender_id())


# ================================================================= SERVEUR -> CLIENT
@rpc("authority", "reliable")
func s_welcome(seed_value: int, edits: PackedByteArray, size: int, names: Dictionary,
		spawn: Vector3) -> void:
	players.clear()
	for k in names:
		players[int(k)] = {"name": String(names[k])}
	players_changed.emit()
	Game.instance.start_client_world(seed_value, edits, size, spawn)


@rpc("authority", "reliable")
func s_player_joined(id: int, name: String) -> void:
	players[id] = {"name": name}
	players_changed.emit()


@rpc("authority", "reliable")
func s_player_left(id: int) -> void:
	players.erase(id)
	players_changed.emit()
	if Game.instance:
		Game.instance.remove_remote_player(id)


@rpc("authority", "unreliable_ordered")
func s_states(states: Dictionary) -> void:
	if Game.instance:
		Game.instance.apply_states(states)


@rpc("authority", "reliable")
func s_block(pos: Vector3i, id: int) -> void:
	if Game.instance:
		Game.instance.world.set_block(pos, id)


@rpc("authority", "reliable")
func s_blocks(list: Array) -> void:
	if Game.instance == null:
		return
	var d := {}
	for e in list:
		d[Vector3i(e[0], e[1], e[2])] = int(e[3])
	Game.instance.world.apply_edits(d)


@rpc("authority", "reliable")
func s_chat(who: String, msg: String) -> void:
	chat_message.emit(who, msg)


@rpc("authority", "reliable")
func s_mob_spawn(id: int, type: int, pos: Vector3) -> void:
	if Game.instance:
		Game.instance.spawn_mob_local(id, type, pos, false)


@rpc("authority", "unreliable_ordered")
func s_mob_states(list: Array) -> void:
	if Game.instance:
		Game.instance.apply_mob_states(list)


@rpc("authority", "reliable")
func s_mob_despawn(id: int) -> void:
	if Game.instance:
		Game.instance.despawn_mob_local(id)


@rpc("authority", "reliable")
func s_boss_spawn(pos: Vector3) -> void:
	if Game.instance:
		Game.instance.spawn_boss_local(pos, false)


@rpc("authority", "reliable")
func s_boss_state(hp: float) -> void:
	if Game.instance and Game.instance.boss:
		Game.instance.boss.hp = hp
		Game.instance.hud.set_boss_hp(hp / Boss.MAX_HP)


@rpc("authority", "reliable")
func s_boss_despawn() -> void:
	if Game.instance:
		Game.instance.despawn_boss_local()


@rpc("authority", "reliable")
func s_projectile(origin: Vector3, dir: Vector3, speed: float, color: Color,
		radius: float, hostile: bool, owner: int) -> void:
	if Game.instance:
		Game.instance.spawn_projectile_local(origin, dir, speed, color, 0.0, radius,
				0, owner, hostile, false)


@rpc("authority", "reliable")
func s_damage(amount: float, dir: Vector3) -> void:
	if Game.instance and Game.instance.player:
		Game.instance.player.take_damage(amount, dir)


@rpc("authority", "reliable")
func s_give(item: int, count: int) -> void:
	if Game.instance and Game.instance.player:
		Game.instance.player.inv.add(item, count)
		Game.instance.hud.toast("+%d %s" % [count, Items.item_name(item)])


@rpc("authority", "reliable")
func s_container(pos: Vector3i, kind: String, data: Dictionary) -> void:
	if Game.instance:
		Game.instance.on_container_data(pos, kind, data)


@rpc("authority", "reliable")
func s_fx(pos: Vector3, color: Color, scale: float) -> void:
	if Game.instance:
		Game.instance.spawn_spell_fx(pos, color, scale)


# ============================================================ API COTE GAMEPLAY
## Ces fonctions marchent en solo (application directe) comme en ligne.

func request_break(pos: Vector3i) -> void:
	if is_server():
		Game.instance.server_break(pos, my_id())
	else:
		c_break.rpc_id(1, pos)


func request_place(pos: Vector3i, id: int) -> void:
	if is_server():
		Game.instance.server_place(pos, id, my_id())
	else:
		c_place.rpc_id(1, pos, id)


func request_cast(spell_id: int, tier: int, mastery: int, origin: Vector3, dir: Vector3) -> void:
	if is_server():
		Game.instance.server_cast(spell_id, tier, mastery, origin, dir, my_id())
	else:
		c_cast.rpc_id(1, spell_id, tier, mastery, origin, dir)


func request_hit_mob(mob_id: int, dmg: float, dir: Vector3) -> void:
	if is_server():
		Game.instance.server_hit_mob(mob_id, dmg, dir, my_id())
	else:
		c_hit_mob.rpc_id(1, mob_id, dmg, dir)


func request_container(pos: Vector3i, action: String, payload: Variant) -> void:
	if is_server():
		Game.instance.server_container(pos, action, payload, my_id())
	else:
		c_container.rpc_id(1, pos, action, payload)


func send_player_state(pos: Vector3, yaw: float, pitch: float, spd: float, hp: float) -> void:
	if online and not hosting:
		c_state.rpc_id(1, pos, yaw, pitch, spd, hp)


func send_chat(msg: String) -> void:
	if not online:
		chat_message.emit(local_name, msg)
	elif hosting:
		s_chat.rpc(local_name, msg)
		chat_message.emit(local_name, msg)
	else:
		c_chat.rpc_id(1, msg)


func broadcast_block(pos: Vector3i, id: int) -> void:
	if hosting:
		s_block.rpc(pos, id)


func broadcast_blocks(list: Array) -> void:
	if hosting and not list.is_empty():
		s_blocks.rpc(list)


func chat_broadcast(who: String, msg: String) -> void:
	if hosting:
		s_chat.rpc(who, msg)
	chat_message.emit(who, msg)


func damage_player(peer: int, dmg: float, dir: Vector3) -> void:
	if peer == my_id() or not online:
		if Game.instance and Game.instance.player:
			Game.instance.player.take_damage(dmg, dir)
	elif hosting:
		s_damage.rpc_id(peer, dmg, dir)


func give_item(peer: int, item: int, count: int) -> void:
	if peer == my_id() or not online:
		if Game.instance and Game.instance.player:
			Game.instance.player.inv.add(item, count)
			Game.instance.hud.toast("+%d %s" % [count, Items.item_name(item)])
	elif hosting:
		s_give.rpc_id(peer, item, count)


func spawn_mob(type: int, pos: Vector3) -> void:
	if Game.instance:
		Game.instance.server_spawn_mob(type, pos)


func despawn_mob(id: int) -> void:
	if Game.instance:
		Game.instance.despawn_mob_local(id)
	if hosting:
		s_mob_despawn.rpc(id)


func despawn_boss() -> void:
	if Game.instance:
		Game.instance.despawn_boss_local()
	if hosting:
		s_boss_despawn.rpc()


func boss_state(hp: float) -> void:
	if Game.instance:
		Game.instance.hud.set_boss_hp(hp / Boss.MAX_HP)
	if hosting:
		s_boss_state.rpc(hp)


func boss_shockwave(center: Vector3, radius: float, dmg: float, break_tier: int) -> void:
	if Game.instance:
		Game.instance.resolve_impact(center, dmg, radius, break_tier, 0, true)
		Game.instance.spawn_spell_fx(center, Color(0.9, 0.4, 1.0), radius)
	if hosting:
		s_fx.rpc(center, Color(0.9, 0.4, 1.0), radius)


func spawn_boss_projectile(origin: Vector3, dir: Vector3, dmg: float) -> void:
	_spawn_hostile(origin, dir, 22.0, Color(1.0, 0.4, 0.3), dmg, 2.0, 3)


func spawn_mob_projectile(origin: Vector3, dir: Vector3, dmg: float, _mob_id: int) -> void:
	_spawn_hostile(origin, dir, 18.0, Color(0.6, 1.0, 0.9), dmg, 0.8, 1)


func _spawn_hostile(origin: Vector3, dir: Vector3, speed: float, color: Color,
		dmg: float, radius: float, btier: int) -> void:
	if Game.instance:
		Game.instance.spawn_projectile_local(origin, dir, speed, color, dmg, radius,
				btier, 0, true, true)
	if hosting:
		s_projectile.rpc(origin, dir, speed, color, radius, true, 0)
