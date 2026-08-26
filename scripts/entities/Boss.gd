extends CharacterBody3D
class_name Boss
## Colosse du Neant : boss a trois phases, capable de detruire le decor.

const MAX_HP := 420.0
const NAME := "Colosse du Neant"

var boss_id := 0
var hp := MAX_HP
var authoritative := false
var phase := 1

var model: CharacterModel
var _cd := 2.0
var _target: Node3D
var _net_pos := Vector3.ZERO
var _net_yaw := 0.0
var _summoned := 0
var _rage := 1.0


func setup(id: int, auth: bool) -> void:
	boss_id = id
	authoritative = auth


func _ready() -> void:
	add_to_group("boss")
	add_to_group("mobs")
	var col := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.height = 4.4
	caps.radius = 1.1
	col.shape = caps
	col.position = Vector3(0, 2.2, 0)
	add_child(col)
	collision_layer = 4
	collision_mask = 1
	model = CharacterModel.new("res://assets/textures/skin_boss.png")
	add_child(model)
	model.scale = Vector3.ONE * 2.6
	model.set_nametag(NAME, Color(1.0, 0.45, 0.35))
	var glow := OmniLight3D.new()
	glow.omni_range = 14.0
	glow.light_color = Color(0.8, 0.35, 1.0)
	glow.light_energy = 2.0
	glow.position = Vector3(0, 3.0, 0)
	add_child(glow)


func _physics_process(delta: float) -> void:
	if not authoritative:
		global_position = global_position.lerp(_net_pos, clampf(delta * 10.0, 0.0, 1.0))
		rotation.y = lerp_angle(rotation.y, _net_yaw, clampf(delta * 10.0, 0.0, 1.0))
		model.animate(delta, 2.0, false, 0.0)
		return

	var ratio := hp / MAX_HP
	phase = 1 if ratio > 0.62 else (2 if ratio > 0.28 else 3)
	_rage = 1.0 + (1.0 - ratio) * 1.2

	_cd -= delta * _rage
	if _target == null or not is_instance_valid(_target):
		_target = _nearest_player()
	var dir := Vector3.ZERO
	if _target != null:
		var to: Vector3 = _target.global_position - global_position
		to.y = 0.0
		rotation.y = atan2(-to.x, -to.z) + PI
		if to.length() > 3.5:
			dir = to.normalized()
		if _cd <= 0.0:
			_do_attack(to.length())

	velocity.x = move_toward(velocity.x, dir.x * (2.6 * _rage), 30.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * (2.6 * _rage), 30.0 * delta)
	if is_on_floor():
		if is_on_wall() and dir.length() > 0.1:
			velocity.y = 9.0
	else:
		velocity.y -= Player.GRAVITY * delta
	move_and_slide()
	model.animate(delta, Vector2(velocity.x, velocity.z).length(), not is_on_floor(), 0.0)


func _nearest_player() -> Node3D:
	var best: Node3D = null
	var bd := 60.0
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player and not (p as Player).dead:
			var d := global_position.distance_to((p as Node3D).global_position)
			if d < bd:
				bd = d
				best = p
	return best


func _do_attack(dist: float) -> void:
	match phase:
		1:
			if dist < 6.0:
				_slam(4.0, 12.0)
				_cd = 3.2
			else:
				_volley(1)
				_cd = 2.4
		2:
			if _summoned < 6 and randf() < 0.35:
				_summon()
				_cd = 3.0
			elif dist < 8.0:
				_slam(6.0, 18.0)
				_cd = 2.8
			else:
				_volley(3)
				_cd = 2.0
		3:
			if randf() < 0.4:
				_slam(8.5, 24.0)
				_cd = 2.4
			else:
				_volley(5)
				_cd = 1.5


func _slam(radius: float, dmg: float) -> void:
	## Onde de choc : degats + destruction du terrain autour du boss.
	var center := global_position + Vector3(0, 0.5, 0)
	Net.boss_shockwave(center, radius, dmg, phase + 2)


func _volley(count: int) -> void:
	if _target == null:
		return
	var origin := global_position + Vector3(0, 3.2, 0)
	for i in count:
		var spread := Vector3(randf_range(-0.18, 0.18), randf_range(-0.05, 0.12),
				randf_range(-0.18, 0.18))
		var dir := ((_target.global_position + Vector3(0, 1, 0)) - origin).normalized() + spread
		Net.spawn_boss_projectile(origin, dir.normalized(), 9.0 * _rage)


func _summon() -> void:
	for i in 2:
		var off := Vector3(randf_range(-4, 4), 1.0, randf_range(-4, 4))
		Net.spawn_mob(Mob.HUSK if randf() < 0.6 else Mob.WRAITH, global_position + off)
		_summoned += 1


func hurt(dmg: float, knock: Vector3, by_peer: int) -> void:
	if not authoritative:
		return
	hp -= dmg
	velocity += knock * 0.8
	Net.boss_state(hp)
	if hp <= 0.0:
		_die(by_peer)


func _die(by_peer: int) -> void:
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			Net.give_item((p as Player).peer_id, Items.VOID_HEART, 2)
			Net.give_item((p as Player).peer_id, Items.ARCANITE, 12)
			Net.give_item((p as Player).peer_id, Items.TOME, 2)
	Net.chat_broadcast("[Systeme]", "%s a ete terrasse !" % NAME)
	Net.despawn_boss()


func apply_net_state(pos: Vector3, yaw: float, php: float) -> void:
	_net_pos = pos
	_net_yaw = yaw
	hp = php
