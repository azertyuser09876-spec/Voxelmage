class_name Chunk
extends RefCounted
## Donnees d'un chunk + construction du maillage (execute sur un thread).

const SX := 16
const SZ := 16
const H := 64
const VOL := SX * SZ * H
const PW := SX + 2      # largeur du tableau padde (avec bordures voisines)

const ATLAS_TILES := 16.0
const UV_INSET := 0.0009

## Assombrissement par orientation de face (rendu volumetrique sans lightmap)
const FACE_SHADE: Array[float] = [1.0, 0.55, 0.82, 0.72, 0.9, 0.68]

## face : 0=+Y 1=-Y 2=+Z 3=-Z 4=+X 5=-X
const FACE_DIR: Array[Vector3i] = [
	Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1),
	Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(-1, 0, 0),
]

## Coins de chaque face, ordre horaire vu de l'exterieur (Godot : faces avant = horaire)
const FACE_VERTS: Array = [
	[Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(0, 1, 0)],  # +Y
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],  # -Y
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],  # +Z
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],  # -Z
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],  # +X
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],  # -X
]

## Voisins utilises pour l'occlusion ambiante, par face puis par coin (side1, side2, coin)
const AO_NB: Array = [
	[[Vector3i(-1, 1, 0), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)],
	 [Vector3i(1, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
	 [Vector3i(1, 1, 0), Vector3i(0, 1, -1), Vector3i(1, 1, -1)],
	 [Vector3i(-1, 1, 0), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)]],
	[[Vector3i(-1, -1, 0), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)],
	 [Vector3i(1, -1, 0), Vector3i(0, -1, -1), Vector3i(1, -1, -1)],
	 [Vector3i(1, -1, 0), Vector3i(0, -1, 1), Vector3i(1, -1, 1)],
	 [Vector3i(-1, -1, 0), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)]],
	[[Vector3i(1, 0, 1), Vector3i(0, -1, 1), Vector3i(1, -1, 1)],
	 [Vector3i(1, 0, 1), Vector3i(0, 1, 1), Vector3i(1, 1, 1)],
	 [Vector3i(-1, 0, 1), Vector3i(0, 1, 1), Vector3i(-1, 1, 1)],
	 [Vector3i(-1, 0, 1), Vector3i(0, -1, 1), Vector3i(-1, -1, 1)]],
	[[Vector3i(-1, 0, -1), Vector3i(0, -1, -1), Vector3i(-1, -1, -1)],
	 [Vector3i(-1, 0, -1), Vector3i(0, 1, -1), Vector3i(-1, 1, -1)],
	 [Vector3i(1, 0, -1), Vector3i(0, 1, -1), Vector3i(1, 1, -1)],
	 [Vector3i(1, 0, -1), Vector3i(0, -1, -1), Vector3i(1, -1, -1)]],
	[[Vector3i(1, 0, -1), Vector3i(1, -1, 0), Vector3i(1, -1, -1)],
	 [Vector3i(1, 0, -1), Vector3i(1, 1, 0), Vector3i(1, 1, -1)],
	 [Vector3i(1, 0, 1), Vector3i(1, 1, 0), Vector3i(1, 1, 1)],
	 [Vector3i(1, 0, 1), Vector3i(1, -1, 0), Vector3i(1, -1, 1)]],
	[[Vector3i(-1, 0, 1), Vector3i(-1, -1, 0), Vector3i(-1, -1, 1)],
	 [Vector3i(-1, 0, 1), Vector3i(-1, 1, 0), Vector3i(-1, 1, 1)],
	 [Vector3i(-1, 0, -1), Vector3i(-1, 1, 0), Vector3i(-1, 1, -1)],
	 [Vector3i(-1, 0, -1), Vector3i(-1, -1, 0), Vector3i(-1, -1, -1)]],
]


static func idx(x: int, y: int, z: int) -> int:
	return (y * SZ + z) * SX + x


static func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and x < SX and y >= 0 and y < H and z >= 0 and z < SZ


static func pidx(x: int, y: int, z: int) -> int:
	## Tableau padde : x,z dans [-1, SX], y dans [0, H-1]
	return (y * PW + (z + 1)) * PW + (x + 1)


static func pget(pad: PackedByteArray, x: int, y: int, z: int) -> int:
	if y < 0:
		return Blocks.BEDROCK
	if y >= H:
		return Blocks.AIR
	return pad[pidx(x, y, z)]


static func _uv_rect(tile: int) -> Rect2:
	var tx := float(tile % int(ATLAS_TILES))
	var ty := float(tile / int(ATLAS_TILES))
	var s := 1.0 / ATLAS_TILES
	return Rect2(tx * s + UV_INSET, ty * s + UV_INSET, s - UV_INSET * 2.0, s - UV_INSET * 2.0)


static func _ao(s1: bool, s2: bool, c: bool) -> float:
	if s1 and s2:
		return 0.42
	var n := (1 if s1 else 0) + (1 if s2 else 0) + (1 if c else 0)
	return [1.0, 0.78, 0.6, 0.48][n]


static func build_mesh(pad: PackedByteArray, heightmap: PackedInt32Array) -> Dictionary:
	## Construit les surfaces opaque / transparente + la collision d'un chunk.
	var v_o := PackedVector3Array()
	var n_o := PackedVector3Array()
	var u_o := PackedVector2Array()
	var c_o := PackedColorArray()
	var i_o := PackedInt32Array()
	var v_a := PackedVector3Array()
	var n_a := PackedVector3Array()
	var u_a := PackedVector2Array()
	var c_a := PackedColorArray()
	var i_a := PackedInt32Array()
	var col := PackedVector3Array()
	var lights: Array = []

	var OPQ := Blocks.OPAQUE
	var ALP := Blocks.ALPHA
	var CRS := Blocks.CROSS
	var LGT := Blocks.LIGHT
	var TIL := Blocks.TILES
	var SLD := Blocks.SOLID

	for y in H:
		for z in SZ:
			for x in SX:
				var id := int(pad[pidx(x, y, z)])
				if id == Blocks.AIR:
					continue
				var alpha: bool = ALP[id] == 1
				var solid: bool = SLD[id] == 1
				var base := Vector3(x, y, z)

				if LGT[id] >= 10 and lights.size() < 4:
					lights.append(base + Vector3(0.5, 0.5, 0.5))

				# profondeur : assombrit ce qui est enterre
				var top_h := heightmap[z * SX + x]
				var depth := maxi(0, top_h - y)
				var sky := clampf(1.0 - float(depth) * 0.055, 0.30, 1.0)

				if CRS[id] == 1:
					_emit_cross(v_a, n_a, u_a, c_a, i_a, base, TIL[id * 6 + 2], sky)
					continue

				for f in 6:
					var d := FACE_DIR[f]
					var nb := pget(pad, x + d.x, y + d.y, z + d.z)
					if nb == id and alpha:
						continue
					if OPQ[nb] == 1:
						continue
					var r := _uv_rect(TIL[id * 6 + f])
					var quad: Array = FACE_VERTS[f]
					var shade: float = FACE_SHADE[f]
					var vi := v_o.size() if not alpha else v_a.size()
					var ao := PackedFloat32Array()
					for k in 4:
						var nbs: Array = AO_NB[f][k]
						var o0: Vector3i = nbs[0]
						var o1: Vector3i = nbs[1]
						var o2: Vector3i = nbs[2]
						var s1 := OPQ[pget(pad, x + o0.x, y + o0.y, z + o0.z)] == 1
						var s2 := OPQ[pget(pad, x + o1.x, y + o1.y, z + o1.z)] == 1
						var cc := OPQ[pget(pad, x + o2.x, y + o2.y, z + o2.z)] == 1
						ao.append(_ao(s1, s2, cc))
					# Faces laterales : k=1 et k=2 sont les sommets du HAUT du bloc,
					# ils doivent recevoir le haut de la tuile (sinon texture pivotee).
					var uvs := [
						Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
						Vector2(r.position.x + r.size.x, r.position.y),
						Vector2(r.position.x, r.position.y),
						Vector2(r.position.x, r.position.y + r.size.y),
					]
					if f == 0 or f == 1:
						uvs = [
							Vector2(r.position.x, r.position.y),
							Vector2(r.position.x + r.size.x, r.position.y),
							Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
							Vector2(r.position.x, r.position.y + r.size.y),
						]
					var nvec := Vector3(d.x, d.y, d.z)
					for k in 4:
						var lum: float = shade * sky * ao[k]
						var cvec := Color(lum, lum, lum, 1.0)
						if alpha:
							v_a.append(base + quad[k])
							n_a.append(nvec)
							u_a.append(uvs[k])
							c_a.append(cvec)
						else:
							v_o.append(base + quad[k])
							n_o.append(nvec)
							u_o.append(uvs[k])
							c_o.append(cvec)
					# anti-artefact : oriente la diagonale selon l'AO
					var flip: bool = ao[0] + ao[2] < ao[1] + ao[3]
					var tri := [0, 2, 1, 0, 3, 2] if not flip else [1, 3, 2, 1, 0, 3]
					for t in tri:
						if alpha:
							i_a.append(vi + t)
						else:
							i_o.append(vi + t)
					if solid:
						for t in tri:
							col.append(base + quad[t])
	return {
		"opaque": [v_o, n_o, u_o, c_o, i_o],
		"alpha": [v_a, n_a, u_a, c_a, i_a],
		"collision": col,
		"lights": lights,
	}


static func _emit_cross(v: PackedVector3Array, n: PackedVector3Array, u: PackedVector2Array,
		c: PackedColorArray, ind: PackedInt32Array, base: Vector3, tile: int, sky: float) -> void:
	## Rendu en croix (torches, plantes)
	var r := _uv_rect(tile)
	var pairs := [
		[Vector3(0.15, 0, 0.15), Vector3(0.85, 0, 0.85)],
		[Vector3(0.85, 0, 0.15), Vector3(0.15, 0, 0.85)],
	]
	for p in pairs:
		var a: Vector3 = base + p[0]
		var b: Vector3 = base + p[1]
		var vi := v.size()
		var quad := [a, b, b + Vector3.UP, a + Vector3.UP]
		var uvs := [
			Vector2(r.position.x, r.position.y + r.size.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
			Vector2(r.position.x + r.size.x, r.position.y),
			Vector2(r.position.x, r.position.y),
		]
		var nv := (b - a).cross(Vector3.UP).normalized()
		for k in 4:
			v.append(quad[k])
			n.append(nv)
			u.append(uvs[k])
			c.append(Color(sky, sky, sky, 1.0))
		for t in [0, 2, 1, 0, 3, 2]:
			ind.append(vi + t)
		for t in [1, 2, 0, 2, 3, 0]:
			ind.append(vi + t)
