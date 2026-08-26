extends Node3D
class_name VoxelWorld
## Monde voxel : streaming de chunks sur un thread, edition de blocs, raycast DDA.

signal chunk_ready(cpos: Vector2i)
signal block_changed(pos: Vector3i, id: int)

const ATLAS_PATH := "res://assets/textures/blocks.png"

@export var view_distance := 5
@export var max_apply_per_frame := 2

var world_seed := 1337
var gen: WorldGen                      # instance du thread de travail
var gen_main: WorldGen                 # instance du thread principal
var edits: Dictionary = {}             # Vector3i -> id (modifications joueurs)

var _data: Dictionary = {}             # Vector2i -> PackedByteArray
var _nodes: Dictionary = {}            # Vector2i -> Node3D
var _queued: Dictionary = {}
var _queue: Array[Vector2i] = []
var _results: Array = []
var _mutex := Mutex.new()
var _sem := Semaphore.new()
var _thread: Thread
var _running := true
var _center := Vector2i(9999, 9999)
var _mat_opaque: StandardMaterial3D
var _mat_alpha: StandardMaterial3D
var _ready_chunks := 0


func setup(s: int) -> void:
	world_seed = s
	gen = WorldGen.new(s)
	gen_main = WorldGen.new(s)


func _ready() -> void:
	if gen == null:
		setup(world_seed)
	_make_materials()
	_thread = Thread.new()
	_thread.start(_worker)


func _make_materials() -> void:
	var tex: Texture2D = load(ATLAS_PATH)
	_mat_opaque = StandardMaterial3D.new()
	_mat_opaque.albedo_texture = tex
	_mat_opaque.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	_mat_opaque.vertex_color_use_as_albedo = true
	_mat_opaque.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	_mat_opaque.roughness = 1.0
	_mat_alpha = _mat_opaque.duplicate()
	_mat_alpha.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_mat_alpha.alpha_scissor_threshold = 0.35
	_mat_alpha.cull_mode = BaseMaterial3D.CULL_DISABLED


func _exit_tree() -> void:
	_running = false
	_sem.post()
	if _thread != null and _thread.is_started():
		_thread.wait_to_finish()


# ---------------------------------------------------------------- coordonnees
static func chunk_of(pos: Vector3) -> Vector2i:
	return Vector2i(floori(pos.x / float(Chunk.SX)), floori(pos.z / float(Chunk.SZ)))


static func to_chunk_local(p: Vector3i) -> Array:
	var cx := floori(float(p.x) / float(Chunk.SX))
	var cz := floori(float(p.z) / float(Chunk.SZ))
	return [Vector2i(cx, cz), p.x - cx * Chunk.SX, p.y, p.z - cz * Chunk.SZ]


# ------------------------------------------------------------------- streaming
func update_center(pos: Vector3) -> void:
	var c := chunk_of(pos)
	if c == _center:
		return
	_center = c
	_refresh_queue()


func _refresh_queue() -> void:
	var wanted: Array[Vector2i] = []
	for dz in range(-view_distance, view_distance + 1):
		for dx in range(-view_distance, view_distance + 1):
			if dx * dx + dz * dz > view_distance * view_distance + 2:
				continue
			wanted.append(_center + Vector2i(dx, dz))
	wanted.sort_custom(func(a, b): return (a - _center).length_squared() \
			< (b - _center).length_squared())
	_mutex.lock()
	for c in wanted:
		if not _nodes.has(c) and not _queued.has(c):
			_queued[c] = true
			_queue.append(c)
	_mutex.unlock()
	for i in wanted.size():
		_sem.post()
	# dechargement
	for c in _nodes.keys():
		if (c - _center).length_squared() > (view_distance + 2) * (view_distance + 2):
			var n: Node = _nodes[c]
			_nodes.erase(c)
			if is_instance_valid(n):
				n.queue_free()
			_mutex.lock()
			_data.erase(c)
			_mutex.unlock()


func _worker() -> void:
	while _running:
		_sem.wait()
		if not _running:
			return
		_mutex.lock()
		var c: Vector2i = _queue.pop_front() if not _queue.is_empty() else Vector2i(99999, 0)
		_mutex.unlock()
		if c.x == 99999:
			continue
		var res := _build_chunk(c)
		_mutex.lock()
		_results.append([c, res])
		_mutex.unlock()


func _ensure_data(c: Vector2i) -> PackedByteArray:
	## Appelle uniquement depuis le worker (ou sous mutex).
	_mutex.lock()
	var have: bool = _data.has(c)
	var d: PackedByteArray = _data.get(c, PackedByteArray())
	_mutex.unlock()
	if have:
		return d
	d = gen.generate(c.x, c.y)
	_mutex.lock()
	# applique les modifications enregistrees
	for k in edits:
		var p: Vector3i = k
		if floori(float(p.x) / float(Chunk.SX)) == c.x and floori(float(p.z) / float(Chunk.SZ)) == c.y:
			var lx := p.x - c.x * Chunk.SX
			var lz := p.z - c.y * Chunk.SZ
			if Chunk.in_bounds(lx, p.y, lz):
				d[Chunk.idx(lx, p.y, lz)] = int(edits[k])
	_data[c] = d
	_mutex.unlock()
	return d


func _build_chunk(c: Vector2i) -> Dictionary:
	var pad := PackedByteArray()
	pad.resize(Chunk.PW * Chunk.PW * Chunk.H)
	var neighbours := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			neighbours[Vector2i(dx, dz)] = _ensure_data(c + Vector2i(dx, dz))
	for y in Chunk.H:
		for z in range(-1, Chunk.SZ + 1):
			for x in range(-1, Chunk.SX + 1):
				var nx := 0
				var nz := 0
				var lx := x
				var lz := z
				if x < 0:
					nx = -1
					lx = Chunk.SX - 1
				elif x >= Chunk.SX:
					nx = 1
					lx = 0
				if z < 0:
					nz = -1
					lz = Chunk.SZ - 1
				elif z >= Chunk.SZ:
					nz = 1
					lz = 0
				var src: PackedByteArray = neighbours[Vector2i(nx, nz)]
				pad[Chunk.pidx(x, y, z)] = src[Chunk.idx(lx, y, lz)]
	var hm := PackedInt32Array()
	hm.resize(Chunk.SX * Chunk.SZ)
	for z in Chunk.SZ:
		for x in Chunk.SX:
			var top := 0
			for y in range(Chunk.H - 1, -1, -1):
				if Blocks.OPAQUE[pad[Chunk.pidx(x, y, z)]] == 1:
					top = y
					break
			hm[z * Chunk.SX + x] = top
	return Chunk.build_mesh(pad, hm)


func _process(_dt: float) -> void:
	var applied := 0
	while applied < max_apply_per_frame:
		_mutex.lock()
		var item = _results.pop_front() if not _results.is_empty() else null
		_mutex.unlock()
		if item == null:
			break
		_apply_chunk(item[0], item[1])
		applied += 1


func _apply_chunk(c: Vector2i, res: Dictionary) -> void:
	_queued.erase(c)
	var old: Node = _nodes.get(c, null)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	root.position = Vector3(c.x * Chunk.SX, 0, c.y * Chunk.SZ)
	var mesh := ArrayMesh.new()
	for pass_name in ["opaque", "alpha"]:
		var arr: Array = res[pass_name]
		if (arr[0] as PackedVector3Array).is_empty():
			continue
		var sa := []
		sa.resize(Mesh.ARRAY_MAX)
		sa[Mesh.ARRAY_VERTEX] = arr[0]
		sa[Mesh.ARRAY_NORMAL] = arr[1]
		sa[Mesh.ARRAY_TEX_UV] = arr[2]
		sa[Mesh.ARRAY_COLOR] = arr[3]
		sa[Mesh.ARRAY_INDEX] = arr[4]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sa)
		mesh.surface_set_material(mesh.get_surface_count() - 1,
				_mat_opaque if pass_name == "opaque" else _mat_alpha)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)

	var faces: PackedVector3Array = res["collision"]
	if not faces.is_empty():
		var body := StaticBody3D.new()
		body.collision_layer = 1
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)

	for lp in res["lights"]:
		var l := OmniLight3D.new()
		l.position = lp
		l.omni_range = 9.0
		l.light_energy = 0.9
		l.light_color = Color(1.0, 0.85, 0.6)
		l.shadow_enabled = false
		root.add_child(l)

	add_child(root)
	_nodes[c] = root
	if old != null and is_instance_valid(old):
		old.queue_free()
	_ready_chunks += 1
	chunk_ready.emit(c)


func remesh(c: Vector2i) -> void:
	_mutex.lock()
	if not _queued.has(c):
		_queued[c] = true
		_queue.push_front(c)
	_mutex.unlock()
	_sem.post()


func is_loaded(c: Vector2i) -> bool:
	return _nodes.has(c)


func loaded_count() -> int:
	return _nodes.size()


# ---------------------------------------------------------------- acces blocs
func get_block(p: Vector3i) -> int:
	if p.y < 0 or p.y >= Chunk.H:
		return Blocks.AIR if p.y >= Chunk.H else Blocks.BEDROCK
	var c := Vector2i(floori(float(p.x) / float(Chunk.SX)), floori(float(p.z) / float(Chunk.SZ)))
	_mutex.lock()
	var d: PackedByteArray = _data.get(c, PackedByteArray())
	_mutex.unlock()
	if d.is_empty():
		return Blocks.AIR
	return d[Chunk.idx(p.x - c.x * Chunk.SX, p.y, p.z - c.y * Chunk.SZ)]


func set_block(p: Vector3i, id: int, record := true) -> bool:
	if p.y <= 0 or p.y >= Chunk.H:
		return false
	var c := Vector2i(floori(float(p.x) / float(Chunk.SX)), floori(float(p.z) / float(Chunk.SZ)))
	var lx := p.x - c.x * Chunk.SX
	var lz := p.z - c.y * Chunk.SZ
	_mutex.lock()
	var has: bool = _data.has(c)
	if has:
		var d: PackedByteArray = _data[c]
		d[Chunk.idx(lx, p.y, lz)] = id
		_data[c] = d
	if record:
		edits[p] = id
	_mutex.unlock()
	if not has:
		return false
	remesh(c)
	if lx == 0:
		remesh(c + Vector2i(-1, 0))
	if lx == Chunk.SX - 1:
		remesh(c + Vector2i(1, 0))
	if lz == 0:
		remesh(c + Vector2i(0, -1))
	if lz == Chunk.SZ - 1:
		remesh(c + Vector2i(0, 1))
	block_changed.emit(p, id)
	return true


func apply_edits(dict: Dictionary) -> void:
	## Applique un lot de modifications recues du serveur.
	var touched := {}
	_mutex.lock()
	for k in dict:
		var p: Vector3i = k
		edits[p] = int(dict[k])
		var c := Vector2i(floori(float(p.x) / float(Chunk.SX)), floori(float(p.z) / float(Chunk.SZ)))
		if _data.has(c):
			var d: PackedByteArray = _data[c]
			d[Chunk.idx(p.x - c.x * Chunk.SX, p.y, p.z - c.y * Chunk.SZ)] = int(dict[k])
			_data[c] = d
			touched[c] = true
	_mutex.unlock()
	for c in touched:
		remesh(c)


func serialize_edits() -> PackedByteArray:
	_mutex.lock()
	var raw := var_to_bytes(edits)
	_mutex.unlock()
	return raw.compress(FileAccess.COMPRESSION_ZSTD)


func deserialize_edits(raw: PackedByteArray, uncompressed_size: int) -> Dictionary:
	var data := raw.decompress(uncompressed_size, FileAccess.COMPRESSION_ZSTD)
	var v = bytes_to_var(data)
	return v if v is Dictionary else {}


# -------------------------------------------------------------------- raycast
func raycast(from: Vector3, dir: Vector3, max_dist := 6.0) -> Dictionary:
	## DDA voxel. Retourne {} ou {pos, normal, id, hit_point}
	var d := dir.normalized()
	var p := Vector3i(floori(from.x), floori(from.y), floori(from.z))
	var step := Vector3i(signi(int(sign(d.x))), signi(int(sign(d.y))), signi(int(sign(d.z))))
	var tdelta := Vector3(
		INF if is_zero_approx(d.x) else absf(1.0 / d.x),
		INF if is_zero_approx(d.y) else absf(1.0 / d.y),
		INF if is_zero_approx(d.z) else absf(1.0 / d.z))
	var tmax := Vector3(
		INF if is_zero_approx(d.x) else ((float(p.x) + (1.0 if d.x > 0.0 else 0.0)) - from.x) / d.x,
		INF if is_zero_approx(d.y) else ((float(p.y) + (1.0 if d.y > 0.0 else 0.0)) - from.y) / d.y,
		INF if is_zero_approx(d.z) else ((float(p.z) + (1.0 if d.z > 0.0 else 0.0)) - from.z) / d.z)
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var id := get_block(p)
		if id != Blocks.AIR and id != Blocks.WATER:
			return {"pos": p, "normal": normal, "id": id, "hit_point": from + d * t}
		if tmax.x < tmax.y and tmax.x < tmax.z:
			p.x += step.x
			t = tmax.x
			tmax.x += tdelta.x
			normal = Vector3i(-step.x, 0, 0)
		elif tmax.y < tmax.z:
			p.y += step.y
			t = tmax.y
			tmax.y += tdelta.y
			normal = Vector3i(0, -step.y, 0)
		else:
			p.z += step.z
			t = tmax.z
			tmax.z += tdelta.z
			normal = Vector3i(0, 0, -step.z)
	return {}


func ground_height(x: int, z: int) -> int:
	for y in range(Chunk.H - 1, 0, -1):
		if Blocks.is_solid(get_block(Vector3i(x, y, z))):
			return y
	return 1


# ------------------------------------------------------------------- destruction magique
func magic_break(center: Vector3, radius: float, break_tier: int) -> Array:
	## Detruit une sphere de blocs dont le tier magique <= break_tier.
	## Retourne la liste des [Vector3i, id] detruits.
	var out: Array = []
	var r := int(ceil(radius))
	var cp := Vector3i(floori(center.x), floori(center.y), floori(center.z))
	for dy in range(-r, r + 1):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var p := cp + Vector3i(dx, dy, dz)
				if p.y <= 0 or p.y >= Chunk.H:
					continue
				var dist := Vector3(dx, dy, dz).length()
				if dist > radius:
					continue
				var id := get_block(p)
				if id == Blocks.AIR or id == Blocks.BEDROCK or id == Blocks.WATER:
					continue
				if Blocks.magic_tier(id) > break_tier:
					continue
				out.append([p, id])
	return out
