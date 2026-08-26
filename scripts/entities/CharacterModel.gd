extends Node3D
class_name CharacterModel
## Personnage voxel construit par code (tete, torse, bras, jambes) texture par un
## "skin" 64x64 genere proceduralement, plus le pseudo flottant au-dessus de la tete.

const PX := 1.8 / 32.0        # 32 pixels de haut => 1.8 bloc
const TEX := 64.0

var head: MeshInstance3D
var body: MeshInstance3D
var arm_r: MeshInstance3D
var arm_l: MeshInstance3D
var leg_r: MeshInstance3D
var leg_l: MeshInstance3D
var head_pivot: Node3D
var arm_r_pivot: Node3D
var arm_l_pivot: Node3D
var leg_r_pivot: Node3D
var leg_l_pivot: Node3D
var nametag: Label3D

var _phase := 0.0
var _swing := 0.0
var _skin_path := "res://assets/textures/skin_player.png"


func _init(skin_path := "res://assets/textures/skin_player.png") -> void:
	_skin_path = skin_path


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load(_skin_path)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.5
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.roughness = 1.0

	# jambes : pivot en haut, a 12px du sol
	leg_r_pivot = _pivot(Vector3(-2.0 * PX, 12.0 * PX, 0))
	leg_r = _part(4, 12, 4, 0, 16, mat, true)
	leg_r_pivot.add_child(leg_r)
	leg_l_pivot = _pivot(Vector3(2.0 * PX, 12.0 * PX, 0))
	leg_l = _part(4, 12, 4, 16, 48, mat, true)
	leg_l_pivot.add_child(leg_l)

	body = _part(8, 12, 4, 16, 16, mat, false)
	body.position = Vector3(0, 12.0 * PX, 0)
	add_child(body)

	arm_r_pivot = _pivot(Vector3(-6.0 * PX, 23.0 * PX, 0))
	arm_r = _part(4, 12, 4, 40, 16, mat, true)
	arm_r.position = Vector3(0, -1.0 * PX, 0)
	arm_r_pivot.add_child(arm_r)
	arm_l_pivot = _pivot(Vector3(6.0 * PX, 23.0 * PX, 0))
	arm_l = _part(4, 12, 4, 32, 48, mat, true)
	arm_l.position = Vector3(0, -1.0 * PX, 0)
	arm_l_pivot.add_child(arm_l)

	head_pivot = _pivot(Vector3(0, 24.0 * PX, 0))
	head = _part(8, 8, 8, 0, 0, mat, false)
	head_pivot.add_child(head)

	nametag = Label3D.new()
	nametag.text = ""
	nametag.font_size = 96
	nametag.pixel_size = 0.0022
	nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	nametag.no_depth_test = true
	nametag.render_priority = 10
	nametag.outline_size = 28
	nametag.outline_modulate = Color(0, 0, 0, 0.85)
	nametag.modulate = Color(1, 1, 1)
	nametag.position = Vector3(0, 34.0 * PX, 0)
	nametag.visible = false
	add_child(nametag)


func _pivot(pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	add_child(n)
	return n


func set_nametag(text: String, color := Color(1, 1, 1)) -> void:
	if nametag == null:
		return
	nametag.text = text
	nametag.modulate = color
	nametag.visible = text != ""


func set_skin(path: String) -> void:
	_skin_path = path
	if head == null:
		return
	var mat: StandardMaterial3D = head.get_surface_override_material(0)
	if mat == null:
		return
	var m := mat.duplicate()
	m.albedo_texture = load(path)
	for p in [head, body, arm_r, arm_l, leg_r, leg_l]:
		p.set_surface_override_material(0, m)


func set_hidden(v: bool) -> void:
	## Cache le corps (vue a la premiere personne) mais garde le pseudo.
	for p in [head, body, arm_r, arm_l, leg_r, leg_l]:
		if p != null:
			p.visible = not v


func set_head_pitch(pitch_rad: float) -> void:
	if head_pivot != null:
		head_pivot.rotation.x = clampf(pitch_rad, -1.2, 1.2)


func animate(delta: float, speed: float, in_air: bool, attacking: float) -> void:
	_phase += delta * clampf(speed, 0.0, 8.0) * 2.2
	var amp := clampf(speed * 0.16, 0.0, 0.85)
	if in_air:
		amp = 0.35
	var s := sin(_phase) * amp
	if leg_r_pivot:
		leg_r_pivot.rotation.x = s
		leg_l_pivot.rotation.x = -s
		arm_r_pivot.rotation.x = -s * 0.8
		arm_l_pivot.rotation.x = s * 0.8
	_swing = maxf(0.0, attacking)
	if _swing > 0.0 and arm_r_pivot:
		arm_r_pivot.rotation.x = -sin(_swing * PI) * 2.2
		arm_r_pivot.rotation.z = sin(_swing * PI) * 0.35


# ------------------------------------------------------------------ maillage
static func _uv_for(face: int, rect: Rect2, k: int) -> Vector2:
	## Table (s,t) par face et par sommet, coherente avec Chunk.FACE_VERTS.
	const M := [
		[[1, 0], [0, 0], [0, 1], [1, 1]],   # +Y
		[[1, 0], [0, 0], [0, 1], [1, 1]],   # -Y
		[[1, 1], [1, 0], [0, 0], [0, 1]],   # +Z
		[[1, 1], [1, 0], [0, 0], [0, 1]],   # -Z
		[[1, 1], [1, 0], [0, 0], [0, 1]],   # +X
		[[1, 1], [1, 0], [0, 0], [0, 1]],   # -X
	]
	var st: Array = M[face][k]
	return rect.position + Vector2(float(st[0]) * rect.size.x, float(st[1]) * rect.size.y)


static func build_box(w: int, h: int, d: int, u: int, v: int, pivot_top: bool) -> ArrayMesh:
	## Boite texturee facon skin Minecraft (dimensions en pixels de skin).
	var fw := float(w) * PX
	var fh := float(h) * PX
	var fd := float(d) * PX
	var off := Vector3(-fw * 0.5, -fh if pivot_top else 0.0, -fd * 0.5)
	var s := 1.0 / TEX
	var rects := [
		Rect2(float(u + d) * s, float(v) * s, float(w) * s, float(d) * s),                    # +Y
		Rect2(float(u + d + w) * s, float(v) * s, float(w) * s, float(d) * s),                # -Y
		Rect2(float(u + d + w + d) * s, float(v + d) * s, float(w) * s, float(h) * s),        # +Z
		Rect2(float(u + d) * s, float(v + d) * s, float(w) * s, float(h) * s),                # -Z
		Rect2(float(u + d + w) * s, float(v + d) * s, float(d) * s, float(h) * s),            # +X
		Rect2(float(u) * s, float(v + d) * s, float(d) * s, float(h) * s),                    # -X
	]
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	for f in 6:
		var quad: Array = Chunk.FACE_VERTS[f]
		var dir: Vector3i = Chunk.FACE_DIR[f]
		var base := verts.size()
		for k in 4:
			var p: Vector3 = quad[k]
			verts.append(Vector3(p.x * fw, p.y * fh, p.z * fd) + off)
			norms.append(Vector3(dir.x, dir.y, dir.z))
			uvs.append(_uv_for(f, rects[f], k))
		for t in [0, 2, 1, 0, 3, 2]:
			idx.append(base + t)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _part(w: int, h: int, d: int, u: int, v: int, mat: Material, pivot_top: bool) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = build_box(w, h, d, u, v, pivot_top)
	mi.set_surface_override_material(0, mat)
	return mi
