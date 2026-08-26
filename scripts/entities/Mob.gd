extends CharacterBody3D
class_name Mob
## Creature. L'IA ne tourne que sur l'hote ; les clients interpolent les etats recus.

enum { SLIME, HUSK, WRAITH }

const TYPE_DATA := {
	SLIME: {"name": "Gelee", "hp": 12.0, "dmg": 3.0, "speed": 2.6, "aggro": 16.0,
			"skin": "res://assets/textures/skin_slime.png", "cube": true, "scale": 0.9,
			"xp": 1, "loot": [[Items.MANA_CRYSTAL, 1, 0.25]]},
	HUSK: {"name": "Decharne", "hp": 22.0, "dmg": 5.0, "speed": 3.4, "aggro": 22.0,
			"skin": "res://assets/textures/skin_husk.png", "cube": false, "scale": 1.0,
			"xp": 3, "loot": [[Items.COAL, 2, 0.5], [Items.IRON_INGOT, 1, 0.2]]},
	WRAITH: {"name": "Spectre", "hp": 18.0, "dmg": 6.0, "speed": 3.0, "aggro": 26.0,
			"skin": "res://assets/textures/skin_wraith.png", "cube": false, "scale": 1.05,
			"xp": 5, "loot": [[Items.MANA_CRYSTAL, 2, 0.6], [Items.VOID_HEART, 1, 0.06],
			[Items.TOME, 1, 0.08]]},
}

var mob_id := 0
var mob_type := HUSK
var hp := 20.0
var max_hp := 20.0
var authoritative := false

var model: Node3D
var _target: Node3D
var _attack_cd := 0.0
var _jump_cd := 0.0
var _repath := 0.0
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _wander := Vector3.ZERO
var _stuck := 0.0


func setup(id: int, type: int, auth: bool) -> void:
	mob_id = id
	mob_type = type
	authoritative = auth
	max_hp = float(TYPE_DATA[type]["hp"])
	hp = max_hp


func _ready() -> void:
	add_to_group("mobs")
	var d: Dictionary = TYPE_DATA[mob_type]
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.height = 1.7 if not bool(d["cube"]) else 0.9
	caps.radius = 0.32
	col.shape = caps
	col.position = Vector3(0, caps.height * 0.5, 0)
	add_child(col)
	collision_layer = 4
	collision_mask = 1
	_build_visual(d)


func _build_visual(d: Dictionary) -> void:
	if bool(d["cube"]):
		var mi := MeshInstance3D.new()
		mi.mesh = CharacterModel.build_box(14, 14, 14, 0, 0, false)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = load(String(d["skin"]))
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		mat.albedo_color = Color(1, 1, 1, 0.88)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mi.mesh = CharacterModel.build_box(14, 14, 14, 0, 0, false)
		mi.set_surface_override_material(0, mat)
		model = mi
	else:
		model = CharacterModel.new(String(d["skin"]))
	add_child(model)
	model.scale = Vector3.ONE * float(d["scale"])
	if model is CharacterModel:
		(model as CharacterModel).set_nametag("")


func _physics_process(delta: float) -> void:
	if not authoritative:
		global_position = global_position.lerp(_net_pos, clampf(delta * 12.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 12.0, 0.0, 1.0))
		if model is CharacterModel:
			(model as CharacterModel).animate(delta, 3.0, false, 0.0)
		return

	var d: Dictionary = TYPE_DATA[mob_type]
	_attack_cd = maxf(0.0, _attack_cd - delta)
	_jump_cd = maxf(0.0, _jump_cd - delta)
	_repath -= delta
	if _repath <= 0.0:
		_repath = 0.5
		_target = _find_target(float(d["aggro"]))

	var speed := float(d["speed"])
	var dir := Vector3.ZERO
	if _target != null:
		var to: Vector3 = _target.global_position - global_position
		to.y = 0.0
		var dist := to.length()
		if dist > 1.4:
			dir = to.normalized()
		rotation.y = atan2(-to.x, -to.z) + PI
		if mob_type == WRAITH and dist < 20.0 and dist > 4.0 and _attack_cd <= 0.0:
			_attack_cd = 2.4
			_ranged_attack(_target)
		elif dist < 2.0 and _attack_cd <= 0.0:
			_attack_cd = 1.1
			_melee_attack(_target, float(d["dmg"]))
	else:
		if _repath <= 0.0 or _wander == Vector3.ZERO:
			_wander = Vector3(randf() - 0.5, 0, randf() - 0.5).normalized()
		dir = _wander * 0.35

	if mob_type == SLIME:
		if is_on_floor() and _jump_cd <= 0.0:
			_jump_cd = 0.9
			velocity.y = 7.0
			velocity.x = dir.x * speed * 1.6
			velocity.z = dir.z * speed * 1.6
	else:
		velocity.x = move_toward(velocity.x, dir.x * speed, 40.0 * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, 40.0 * delta)

	if is_on_floor():
		if dir.length() > 0.1 and is_on_wall() and _jump_cd <= 0.0:
			velocity.y = 8.0        # franchit un bloc
			_jump_cd = 0.5
	else:
		velocity.y -= Player.GRAVITY * delta
	move_and_slide()
	if global_position.y < -6.0:
		die(null)
	if model is CharacterModel:
		(model as CharacterModel).animate(delta, Vector2(velocity.x, velocity.z).length(),
				not is_on_floor(), 0.0)


func _find_target(range_m: float) -> Node3D:
	var best: Node3D = null
	var bd := range_m
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and not (p as Player).dead:
			var dd := global_position.distance_to((p as Node3D).global_position)
			if dd < bd:
				bd = dd
				best = p
	return best


func _melee_attack(t: Node3D, dmg: float) -> void:
	if t is Player:
		Net.damage_player((t as Player).peer_id, dmg,
				(t.global_position - global_position).normalized())


func _ranged_attack(t: Node3D) -> void:
	var origin := global_position + Vector3(0, 1.3, 0)
	var dir := ((t.global_position + Vector3(0, 1.0, 0)) - origin).normalized()
	Net.spawn_mob_projectile(origin, dir, 6.0, mob_id)


func apply_net_state(pos: Vector3, yaw: float, php: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	hp = php


func hurt(dmg: float, knock: Vector3, by_peer: int) -> void:
	if not authoritative:
		return
	hp -= dmg
	velocity += knock * 4.0 + Vector3.UP * 3.0
	if hp <= 0.0:
		die(by_peer)


func die(by_peer) -> void:
	if by_peer != null and int(by_peer) > 0:
		var loot: Array = TYPE_DATA[mob_type]["loot"]
		for l in loot:
			if randf() < float(l[2]):
				Net.give_item(int(by_peer), int(l[0]), int(l[1]))
	Net.despawn_mob(mob_id)
