class_name WorldGen
extends RefCounted
## Generation deterministe : meme graine => meme monde sur tous les clients.
## Seules les modifications des joueurs transitent par le reseau.

const SEA := 30

enum { PLAINS, FOREST, DESERT, MOUNTAINS, SNOW, SWAMP, ARCANE }

const BIOME_NAMES := ["Plaines", "Foret", "Desert", "Montagnes", "Toundra",
		"Marais", "Terres arcaniques"]

var seed_value: int = 0
var _n_cont := FastNoiseLite.new()
var _n_hill := FastNoiseLite.new()
var _n_temp := FastNoiseLite.new()
var _n_humid := FastNoiseLite.new()
var _n_cave := FastNoiseLite.new()
var _n_ore := FastNoiseLite.new()
var _n_mount := FastNoiseLite.new()


func _init(world_seed: int = 1337) -> void:
	seed_value = world_seed
	_setup(_n_cont, world_seed, 0.0052, FastNoiseLite.TYPE_PERLIN, 4)
	_setup(_n_hill, world_seed + 11, 0.021, FastNoiseLite.TYPE_SIMPLEX, 3)
	_setup(_n_temp, world_seed + 23, 0.0021, FastNoiseLite.TYPE_PERLIN, 2)
	_setup(_n_humid, world_seed + 37, 0.0026, FastNoiseLite.TYPE_PERLIN, 2)
	_setup(_n_cave, world_seed + 51, 0.055, FastNoiseLite.TYPE_SIMPLEX, 2)
	_setup(_n_ore, world_seed + 67, 0.09, FastNoiseLite.TYPE_SIMPLEX, 1)
	_setup(_n_mount, world_seed + 83, 0.0064, FastNoiseLite.TYPE_SIMPLEX, 3)


func _setup(n: FastNoiseLite, s: int, freq: float, type: int, octaves: int) -> void:
	n.seed = s
	n.frequency = freq
	n.noise_type = type
	n.fractal_octaves = octaves


func biome_at(wx: int, wz: int) -> int:
	var t := _n_temp.get_noise_2d(wx, wz)
	var h := _n_humid.get_noise_2d(wx, wz)
	var m := _n_mount.get_noise_2d(wx, wz)
	if h > 0.55 and t > 0.1:
		return ARCANE
	if m > 0.42:
		return MOUNTAINS
	if t > 0.35 and h < 0.0:
		return DESERT
	if t < -0.35:
		return SNOW
	if h > 0.28 and t > -0.2:
		return SWAMP if h > 0.42 else FOREST
	if h > 0.05:
		return FOREST
	return PLAINS


func height_at(wx: int, wz: int) -> int:
	var b := biome_at(wx, wz)
	var base := 32.0
	base += _n_cont.get_noise_2d(wx, wz) * 11.0
	base += _n_hill.get_noise_2d(wx, wz) * 4.5
	match b:
		MOUNTAINS:
			var m: float = maxf(0.0, _n_mount.get_noise_2d(wx, wz) - 0.42) * 2.6
			base += m * 34.0 + 6.0
		DESERT:
			base = base * 0.85 + 6.0
		SWAMP:
			base = lerpf(base, float(SEA) - 1.0, 0.65)
		ARCANE:
			base += _n_hill.get_noise_2d(wx * 2, wz * 2) * 6.0 + 2.0
	return clampi(int(base), 4, Chunk.H - 6)


func _hash2(a: int, b: int, salt: int) -> int:
	var h := int(a * 374761393 + b * 668265263 + seed_value * 2654435761 + salt * 1013904223)
	h = (h ^ (h >> 13)) * 1274126177
	return absi(h ^ (h >> 16))


func _rand01(a: int, b: int, salt: int) -> float:
	return float(_hash2(a, b, salt) % 100000) / 100000.0


func surface_block(biome: int, y: int, top: int) -> int:
	if y == top:
		match biome:
			DESERT:
				return Blocks.SAND
			SNOW:
				return Blocks.SNOW
			MOUNTAINS:
				return Blocks.STONE if y > 46 else Blocks.GRASS
			ARCANE:
				return Blocks.VOID_ROCK
			SWAMP:
				return Blocks.GRASS if y > SEA else Blocks.DIRT
			_:
				return Blocks.GRASS
	if y > top - 4:
		match biome:
			DESERT:
				return Blocks.SAND
			MOUNTAINS:
				return Blocks.STONE
			ARCANE:
				return Blocks.VOID_ROCK
			_:
				return Blocks.DIRT
	return Blocks.STONE


func generate(cx: int, cz: int) -> PackedByteArray:
	var data := PackedByteArray()
	data.resize(Chunk.VOL)
	data.fill(0)
	var ox := cx * Chunk.SX
	var oz := cz * Chunk.SZ

	for lz in Chunk.SZ:
		for lx in Chunk.SX:
			var wx := ox + lx
			var wz := oz + lz
			var biome := biome_at(wx, wz)
			var top := height_at(wx, wz)
			for y in range(0, Chunk.H):
				var id := Blocks.AIR
				if y == 0:
					id = Blocks.BEDROCK
				elif y <= top:
					id = surface_block(biome, y, top)
					if y < top - 2 and y < 52:
						var cv := _n_cave.get_noise_3d(wx, y * 1.7, wz)
						if cv > 0.60 and y > 2:
							id = Blocks.AIR
					if id == Blocks.STONE or id == Blocks.VOID_ROCK:
						id = _ore_at(wx, y, wz, id, biome)
				elif y <= SEA:
					id = Blocks.WATER
				data[Chunk.idx(lx, y, lz)] = id

	_decorate(data, cx, cz)
	return data


func _ore_at(wx: int, y: int, wz: int, base: int, biome: int) -> int:
	var n := _n_ore.get_noise_3d(wx, y, wz)
	var r := _rand01(wx, wz * 31 + y, 7)
	if biome == ARCANE and y < 44 and n > 0.72 and r < 0.55:
		return Blocks.MANA_ORE
	if y < 14 and n > 0.80 and r < 0.30:
		return Blocks.ARCANITE_ORE
	if y < 12 and n > 0.66:
		return Blocks.OBSIDIAN if r < 0.10 else Blocks.GOLD_ORE
	if y < 30 and n > 0.70 and r < 0.5:
		return Blocks.IRON_ORE
	if y < 46 and n > 0.66 and r < 0.55:
		return Blocks.COAL_ORE
	if y < 40 and n < -0.78:
		return Blocks.GRAVEL
	if y < 40 and n > 0.74 and r > 0.86:
		return Blocks.MANA_ORE
	return base


func _put(data: PackedByteArray, lx: int, y: int, lz: int, id: int, force := false) -> void:
	if not Chunk.in_bounds(lx, y, lz):
		return
	if not force and data[Chunk.idx(lx, y, lz)] != Blocks.AIR:
		if not (id == Blocks.LOG or id == Blocks.STONE_BRICKS):
			return
	data[Chunk.idx(lx, y, lz)] = id


func _decorate(data: PackedByteArray, cx: int, cz: int) -> void:
	## Arbres, cactus et ruines : on balaie une marge pour eviter les coupures aux bords.
	var ox := cx * Chunk.SX
	var oz := cz * Chunk.SZ
	for lz in range(-4, Chunk.SZ + 4):
		for lx in range(-4, Chunk.SX + 4):
			var wx := ox + lx
			var wz := oz + lz
			var biome := biome_at(wx, wz)
			var top := height_at(wx, wz)
			if top <= SEA:
				continue
			var r := _rand01(wx, wz, 3)
			match biome:
				FOREST:
					if r < 0.055:
						_tree(data, lx, top + 1, lz, wx, wz, false)
				PLAINS:
					if r < 0.010:
						_tree(data, lx, top + 1, lz, wx, wz, false)
				SNOW:
					if r < 0.030:
						_tree(data, lx, top + 1, lz, wx, wz, true)
				SWAMP:
					if r < 0.022:
						_tree(data, lx, top + 1, lz, wx, wz, false)
				DESERT:
					if r < 0.006:
						var hgt := 2 + _hash2(wx, wz, 9) % 3
						for i in hgt:
							_put(data, lx, top + 1 + i, lz, Blocks.CACTUS)
				ARCANE:
					if r < 0.012:
						_arcane_spire(data, lx, top + 1, lz, wx, wz)
			if _rand01(wx, wz, 21) < 0.00035:
				_ruin(data, lx, top, lz, wx, wz)


func _tree(data: PackedByteArray, lx: int, y: int, lz: int, wx: int, wz: int, pine: bool) -> void:
	var h := (4 + _hash2(wx, wz, 5) % 3) + (1 if pine else 0)
	for i in h:
		_put(data, lx, y + i, lz, Blocks.LOG, true)
	var top := y + h
	if pine:
		for layer in 3:
			var rad := 2 - layer
			for dz in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					if absi(dx) + absi(dz) <= rad + 1:
						_put(data, lx + dx, top - layer, lz + dz, Blocks.LEAVES)
		_put(data, lx, top + 1, lz, Blocks.LEAVES)
	else:
		for dy in range(-2, 2):
			var rad := 2 if dy < 0 else 1
			for dz in range(-rad, rad + 1):
				for dx in range(-rad, rad + 1):
					if absi(dx) == rad and absi(dz) == rad and dy > -2:
						continue
					_put(data, lx + dx, top + dy, lz + dz, Blocks.LEAVES)


func _arcane_spire(data: PackedByteArray, lx: int, y: int, lz: int, wx: int, wz: int) -> void:
	var h := 4 + _hash2(wx, wz, 13) % 5
	for i in h:
		_put(data, lx, y + i, lz, Blocks.VOID_ROCK, true)
	_put(data, lx, y + h, lz, Blocks.MANA_BLOCK, true)
	if h > 5:
		_put(data, lx + 1, y + h - 2, lz, Blocks.MANA_ORE)
		_put(data, lx, y + h - 2, lz + 1, Blocks.MANA_ORE)


func _ruin(data: PackedByteArray, lx: int, y: int, lz: int, wx: int, wz: int) -> void:
	## Petite ruine : salle en briques avec un coffre et un autel.
	var w := 5
	for dy in range(0, 5):
		for dz in range(-w, w + 1):
			for dx in range(-w, w + 1):
				var edge: bool = absi(dx) == w or absi(dz) == w
				if dy == 0 or dy == 4:
					_put(data, lx + dx, y + dy, lz + dz, Blocks.STONE_BRICKS, true)
				elif edge:
					var hole: bool = (dy == 2 and (_hash2(wx + dx, wz + dz, 17) % 5 == 0))
					_put(data, lx + dx, y + dy, lz + dz,
							Blocks.AIR if hole else Blocks.STONE_BRICKS, true)
				else:
					_put(data, lx + dx, y + dy, lz + dz, Blocks.AIR, true)
	_put(data, lx, y + 1, lz, Blocks.ALTAR, true)
	_put(data, lx + 2, y + 1, lz + 2, Blocks.CHEST, true)
	_put(data, lx - 2, y + 1, lz - 2, Blocks.CHEST, true)
	for i in 4:
		_put(data, lx + (2 if i % 2 == 0 else -2), y + 3, lz + (2 if i < 2 else -2),
				Blocks.TORCH, true)


func spawn_point() -> Vector3:
	for r in range(0, 64):
		for a in range(0, 8):
			var wx := int(cos(a * PI / 4.0) * r * 6.0)
			var wz := int(sin(a * PI / 4.0) * r * 6.0)
			var b := biome_at(wx, wz)
			var h := height_at(wx, wz)
			if h > SEA + 1 and b != ARCANE:
				return Vector3(wx + 0.5, h + 2.4, wz + 0.5)
	return Vector3(0.5, 48.0, 0.5)
