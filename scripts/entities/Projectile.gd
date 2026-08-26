extends Node3D
class_name Projectile
## Projectile de sort (joueur, mob ou boss). Seul l'hote applique les degats et
## la destruction du terrain ; les clients n'affichent que le visuel.

var vel := Vector3.ZERO
var life := 4.0
var damage := 5.0
var radius := 1.0
var break_tier := 0
var owner_peer := 0
var authoritative := false
var hostile := false          # true => vise les joueurs
var color := Color(0.6, 0.8, 1.0)

var _mesh: MeshInstance3D


var _origin := Vector3.ZERO


func setup(p_origin: Vector3, p_dir: Vector3, p_speed: float, p_color: Color) -> void:
	_origin = p_origin
	position = p_origin
	vel = p_dir.normalized() * p_speed
	color = p_color


func _ready() -> void:
	global_position = _origin
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.22
	sm.height = 0.44
	sm.radial_segments = 8
	sm.rings = 4
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.set_surface_override_material(0, mat)
	add_child(_mesh)
	var l := OmniLight3D.new()
	l.light_color = color
	l.omni_range = 7.0
	l.light_energy = 1.6
	l.shadow_enabled = false
	add_child(l)


func _physics_process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	var step := vel * delta
	var target := global_position + step
	var w: VoxelWorld = Game.instance.world if Game.instance else null
	if w != null:
		var hit := w.raycast(global_position, step.normalized(), step.length() + 0.2)
		if not hit.is_empty():
			global_position = hit["hit_point"]
			_impact()
			return
	# entites
	var space := get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.45
	q.shape = sh
	q.transform = Transform3D(Basis(), target)
	q.collision_mask = 2 if hostile else 4
	var res := space.intersect_shape(q, 4)
	for r in res:
		var col = r["collider"]
		if hostile and col is Player:
			if (col as Player).peer_id != owner_peer:
				global_position = target
				_impact()
				return
		elif not hostile and (col is Mob or col is Boss):
			global_position = target
			_impact()
			return
	global_position = target
	vel.y -= 3.0 * delta
	_mesh.rotate_y(delta * 6.0)


func _impact() -> void:
	if Game.instance:
		Game.instance.spawn_spell_fx(global_position, color, maxf(1.0, radius))
	if authoritative and Game.instance:
		Game.instance.resolve_impact(global_position, damage, radius, break_tier,
				owner_peer, hostile)
	queue_free()
