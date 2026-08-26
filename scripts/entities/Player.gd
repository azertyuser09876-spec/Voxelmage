extends CharacterBody3D
class_name Player
## Joueur. Le meme script sert au joueur local (entrees + camera) et aux joueurs
## distants (interpolation depuis les etats reseau).

signal stats_changed
signal open_container(kind: String, pos: Vector3i)
signal hotbar_changed
signal died

const EYE := 1.62
const WALK := 4.4
const SPRINT := 6.0
const SNEAK := 1.6
const GRAVITY := 26.0
const JUMP := 8.4
const REACH := 5.0
const MAX_HP := 20.0
const MAX_MANA := 100.0

var peer_id := 1
var pseudo := "Joueur"
var is_local := false

var hp := MAX_HP
var mana := MAX_MANA
var mastery := 0
var wand_tier := 0
var selected_spell := 0
var hotbar := 0
var inv := Inventory.new(36)
var dead := false

var model: CharacterModel
var cam_pivot: Node3D
var camera: Camera3D
var third_person := false

var _yaw := 0.0
var _pitch := 0.0
var _mine_target := Vector3i(9999, 0, 0)
var _mine_progress := 0.0
var _cooldowns := {}
var _attack_anim := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _net_pitch := 0.0
var _net_speed := 0.0
var _send_acc := 0.0
var _fall_from := -1.0
var _hurt_flash := 0.0
var _respawn_timer := 0.0
var look_sensitivity := 0.0022


func _ready() -> void:
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.height = 1.8
	caps.radius = 0.32
	col.shape = caps
	col.position = Vector3(0, 0.9, 0)
	add_child(col)
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.4
	floor_max_angle = deg_to_rad(50)

	model = CharacterModel.new("res://assets/textures/skin_player.png")
	add_child(model)
	model.set_nametag(pseudo if not is_local else "")

	if is_local:
		add_to_group("local_player")
		cam_pivot = Node3D.new()
		cam_pivot.position = Vector3(0, EYE, 0)
		add_child(cam_pivot)
		camera = Camera3D.new()
		camera.fov = 74.0
		camera.far = 320.0
		camera.current = true
		cam_pivot.add_child(camera)
		model.set_hidden(true)
	add_to_group("players")


func setup(p_id: int, p_name: String, local: bool) -> void:
	peer_id = p_id
	pseudo = p_name
	is_local = local


func give_starter_kit() -> void:
	inv.add(Items.PICK_WOOD, 1)
	inv.add(Items.SWORD_WOOD, 1)
	inv.add(Items.WAND1, 1)
	inv.add(Blocks.TORCH, 16)
	inv.add(Items.BREAD, 4)
	_update_wand()


# ------------------------------------------------------------------- entrees
func add_look(delta: Vector2) -> void:
	_yaw -= delta.x
	_pitch = clampf(_pitch - delta.y, -1.5, 1.5)


func _unhandled_input(event: InputEvent) -> void:
	if not is_local or dead:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		# Curseur capture : cas normal. Sinon on accepte quand meme le
		# glissement bouton enfonce (navigateur qui refuse le pointer lock,
		# retour d'Alt-Tab, etc.) pour ne jamais bloquer la camera.
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				or (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
				or (mm.button_mask & MOUSE_BUTTON_MASK_RIGHT) != 0:
			add_look(mm.relative * look_sensitivity)
		return
	if Game.instance != null and Game.instance.ui != null and Game.instance.ui.blocking():
		return
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			set_hotbar(posmod(hotbar - 1, 9))
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			set_hotbar(posmod(hotbar + 1, 9))
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F5:
		third_person = not third_person
		model.set_hidden(not third_person)
	if event.is_action_pressed("spell_next"):
		cycle_spell(1)
	if event.is_action_pressed("spell_prev"):
		cycle_spell(-1)
	if event.is_action_pressed("drop"):
		_drop_selected()
	for i in 9:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			set_hotbar(i)


func set_hotbar(i: int) -> void:
	hotbar = clampi(i, 0, 8)
	_update_wand()
	hotbar_changed.emit()


func cycle_spell(dir: int) -> void:
	var avail := Spells.for_tier(wand_tier)
	if avail.is_empty():
		return
	var cur := avail.find(selected_spell)
	selected_spell = avail[posmod(cur + dir, avail.size())]
	stats_changed.emit()


func _update_wand() -> void:
	var s := inv.get_slot(hotbar)
	wand_tier = Items.wand_tier(int(s.get("id", 0)))
	var avail := Spells.for_tier(wand_tier)
	if not avail.has(selected_spell):
		selected_spell = avail[0] if not avail.is_empty() else 0


func held_item() -> Dictionary:
	return inv.get_slot(hotbar)


# ------------------------------------------------------------------ physique
func _physics_process(delta: float) -> void:
	if not is_local:
		_remote_update(delta)
		return
	if dead:
		_respawn_timer -= delta
		if _respawn_timer <= 0.0:
			respawn()
		return

	mana = minf(MAX_MANA, mana + delta * (3.0 + float(mastery) * 0.8))
	for k in _cooldowns.keys():
		_cooldowns[k] = maxf(0.0, float(_cooldowns[k]) - delta)
	_attack_anim = maxf(0.0, _attack_anim - delta * 3.0)
	_hurt_flash = maxf(0.0, _hurt_flash - delta)

	var in_water := _in_water()
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (Basis(Vector3.UP, _yaw) * Vector3(input.x, 0, input.y)).normalized()
	var speed := WALK
	if Input.is_action_pressed("sneak"):
		speed = SNEAK
	elif Input.is_action_pressed("sprint"):
		speed = SPRINT
	if in_water:
		speed *= 0.6

	velocity.x = move_toward(velocity.x, dir.x * speed, 60.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 60.0 * delta)

	if in_water:
		velocity.y = maxf(velocity.y - GRAVITY * 0.22 * delta, -3.0)
		if Input.is_action_pressed("jump"):
			velocity.y = 3.6
		_fall_from = -1.0
	elif is_on_floor():
		if _fall_from > 0.0:
			var fall := _fall_from - global_position.y
			if fall > 3.5:
				take_damage((fall - 3.5) * 2.0, Vector3.ZERO)
			_fall_from = -1.0
		if Input.is_action_pressed("jump"):
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
		_fall_from = maxf(_fall_from, global_position.y)

	move_and_slide()
	if global_position.y < -8.0:
		take_damage(1000.0, Vector3.ZERO)

	rotation.y = _yaw
	model.set_head_pitch(-_pitch)
	model.animate(delta, Vector2(velocity.x, velocity.z).length(), not is_on_floor(), _attack_anim)
	_update_camera()
	_handle_actions(delta)

	_send_acc += delta
	if _send_acc >= 0.05:
		_send_acc = 0.0
		if Net.is_online():
			Net.send_player_state(global_position, _yaw, _pitch,
					Vector2(velocity.x, velocity.z).length(), hp)


func _update_camera() -> void:
	cam_pivot.rotation.x = _pitch
	if third_person:
		var back := cam_pivot.global_transform.basis.z * 4.0 + Vector3(0, 0.4, 0)
		var space := get_world_3d().direct_space_state
		var q := PhysicsRayQueryParameters3D.create(cam_pivot.global_position,
				cam_pivot.global_position + back)
		q.collision_mask = 1
		var hit := space.intersect_ray(q)
		var target: Vector3 = hit["position"] - back.normalized() * 0.3 if hit \
				else cam_pivot.global_position + back
		camera.global_position = target
		camera.look_at(cam_pivot.global_position - cam_pivot.global_transform.basis.z * 2.0)
	else:
		camera.position = Vector3.ZERO
		camera.rotation = Vector3.ZERO


func _in_water() -> bool:
	var w := Game.instance.world if Game.instance else null
	if w == null:
		return false
	var p := global_position + Vector3(0, 1.0, 0)
	return w.get_block(Vector3i(floori(p.x), floori(p.y), floori(p.z))) == Blocks.WATER


func _remote_update(delta: float) -> void:
	global_position = global_position.lerp(_net_pos, clampf(delta * 14.0, 0.0, 1.0))
	rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 14.0, 0.0, 1.0))
	model.set_head_pitch(-_net_pitch)
	model.animate(delta, _net_speed, false, 0.0)


func apply_net_state(pos: Vector3, yaw: float, pitch: float, spd: float, php: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	_net_pitch = pitch
	_net_speed = spd
	hp = php


# ------------------------------------------------------------------- actions
func aim_ray() -> Dictionary:
	var w: VoxelWorld = Game.instance.world
	var from := cam_pivot.global_position
	var dir := -cam_pivot.global_transform.basis.z
	return w.raycast(from, dir, REACH)


func _handle_actions(delta: float) -> void:
	if Game.instance != null and Game.instance.ui != null and Game.instance.ui.blocking():
		# inventaire, coffre ou menu ouvert : aucun clic ne doit atteindre le monde
		_mine_progress = 0.0
		Game.instance.hud.set_break_progress(Vector3i.ZERO, 0.0)
		return
	var held := held_item()
	var held_id := int(held.get("id", 0))
	var is_wand: bool = String(Items.get_def(held_id).get("kind", "")) == "wand"

	if Input.is_action_just_pressed("use"):
		_use_action()

	if Input.is_action_pressed("attack"):
		if is_wand:
			_cast_spell()
		else:
			_mine(delta)
	else:
		_mine_progress = 0.0
		_mine_target = Vector3i(9999, 0, 0)
		Game.instance.hud.set_break_progress(Vector3i.ZERO, 0.0)

	if Input.is_action_just_pressed("attack") and not is_wand:
		_melee()
	if Input.is_action_just_pressed("cast"):
		_cast_spell()


func _mine(delta: float) -> void:
	var hit := aim_ray()
	if hit.is_empty():
		_mine_progress = 0.0
		Game.instance.hud.set_break_progress(Vector3i.ZERO, 0.0)
		return
	var pos: Vector3i = hit["pos"]
	if pos != _mine_target:
		_mine_target = pos
		_mine_progress = 0.0
	var held := held_item()
	var d := Items.get_def(int(held.get("id", 0)))
	var t := Blocks.break_time(int(hit["id"]), int(d.get("tool", 0)),
			int(d.get("level", 0)), float(d.get("speed", 1.0)))
	_attack_anim = 1.0
	if t < 0.0:
		return
	_mine_progress += delta / t
	Game.instance.hud.set_break_progress(pos, _mine_progress)
	if _mine_progress >= 1.0:
		_mine_progress = 0.0
		if int(d.get("durability", 0)) > 0:
			inv.damage_tool(hotbar)
		Net.request_break(pos)


func _melee() -> void:
	_attack_anim = 1.0
	var from := cam_pivot.global_position
	var dir := -cam_pivot.global_transform.basis.z
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 4.0)
	q.collision_mask = 4 | 2
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	var col = hit["collider"]
	var dmg := float(Items.get_def(int(held_item().get("id", 0))).get("damage", 1.0))
	if col is Mob:
		Net.request_hit_mob(col.mob_id, dmg, (col.global_position - global_position).normalized())
		if int(Items.get_def(int(held_item().get("id", 0))).get("durability", 0)) > 0:
			inv.damage_tool(hotbar)


func _cast_spell() -> void:
	var s := Spells.scaled(selected_spell, wand_tier, mastery)
	if wand_tier < int(s["tier"]):
		Game.instance.hud.toast("Baguette trop faible pour ce sort")
		return
	if float(_cooldowns.get(selected_spell, 0.0)) > 0.0:
		return
	if mana < float(s["mana"]):
		Game.instance.hud.toast("Mana insuffisant")
		return
	mana -= float(s["mana"])
	_cooldowns[selected_spell] = float(s["cd"])
	_attack_anim = 1.0
	stats_changed.emit()
	var origin := cam_pivot.global_position - cam_pivot.global_transform.basis.z * 0.6
	var dir := -cam_pivot.global_transform.basis.z
	if int(s["kind"]) == Spells.KIND_SELF:
		if float(s.get("heal", 0.0)) > 0.0:
			hp = minf(MAX_HP, hp + float(s["heal"]))
		if float(s.get("dash", 0.0)) > 0.0:
			velocity += dir * float(s["dash"])
		Game.instance.spawn_spell_fx(global_position + Vector3(0, 1, 0), Color(s["color"]), 1.5)
		return
	Net.request_cast(selected_spell, wand_tier, mastery, origin, dir)


func _use_action() -> void:
	var hit := aim_ray()
	if hit.is_empty():
		_consume_food()
		return
	var pos: Vector3i = hit["pos"]
	var id := int(hit["id"])
	var inter := String(Blocks.get_def(id).get("interact", ""))
	if inter != "" and not Input.is_action_pressed("sneak"):
		open_container.emit(inter, pos)
		return
	var held := held_item()
	var hid := int(held.get("id", 0))
	if hid != 0 and Items.is_block(hid):
		var target: Vector3i = pos + Vector3i(hit["normal"])
		if _would_collide(target):
			return
		var cur := Game.instance.world.get_block(target)
		if cur != Blocks.AIR and cur != Blocks.WATER:
			return
		Net.request_place(target, Items.block_id(hid))
		inv.consume_slot(hotbar)
		hotbar_changed.emit()
	else:
		_consume_food()


func _consume_food() -> void:
	var held := held_item()
	var d := Items.get_def(int(held.get("id", 0)))
	if d.has("food") or d.has("heal") or d.has("mana"):
		hp = minf(MAX_HP, hp + float(d.get("food", 0.0)) + float(d.get("heal", 0.0)))
		mana = minf(MAX_MANA, mana + float(d.get("mana", 0.0)))
		inv.consume_slot(hotbar)
		stats_changed.emit()


func _would_collide(p: Vector3i) -> bool:
	var box := AABB(Vector3(p.x, p.y, p.z), Vector3.ONE)
	var me := AABB(global_position - Vector3(0.32, 0.0, 0.32), Vector3(0.64, 1.8, 0.64))
	return box.intersects(me)


func _drop_selected() -> void:
	inv.consume_slot(hotbar)
	hotbar_changed.emit()


# --------------------------------------------------------------------- degats
func take_damage(amount: float, from_dir: Vector3) -> void:
	if dead:
		return
	hp -= amount
	_hurt_flash = 0.4
	velocity += from_dir * 5.0 + Vector3.UP * 2.5
	stats_changed.emit()
	if is_local:
		Game.instance.hud.flash_damage()
	if hp <= 0.0:
		hp = 0.0
		dead = true
		_respawn_timer = 3.0
		died.emit()
		if is_local:
			Game.instance.hud.show_death()


func respawn() -> void:
	dead = false
	hp = MAX_HP
	mana = MAX_MANA
	velocity = Vector3.ZERO
	global_position = Game.instance.safe_spawn()
	stats_changed.emit()
	if is_local:
		Game.instance.hud.hide_death()


func serialize() -> Dictionary:
	return {
		"pos": global_position, "yaw": _yaw, "hp": hp, "mana": mana,
		"inv": inv.to_array(), "hotbar": hotbar, "mastery": mastery,
		"spell": selected_spell,
	}


func deserialize(d: Dictionary) -> void:
	global_position = d.get("pos", global_position)
	_yaw = float(d.get("yaw", 0.0))
	hp = float(d.get("hp", MAX_HP))
	mana = float(d.get("mana", MAX_MANA))
	mastery = int(d.get("mastery", 0))
	selected_spell = int(d.get("spell", 0))
	hotbar = int(d.get("hotbar", 0))
	inv.from_array(d.get("inv", []))
	_update_wand()
	stats_changed.emit()
