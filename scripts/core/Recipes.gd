class_name Recipes
extends RefCounted
## Recettes : etabli (2x2 / 3x3), four, autel arcanique.

static var CRAFT: Array[Dictionary] = []
static var SMELT: Dictionary = {}
static var INFUSE: Array[Dictionary] = []


static func _static_init() -> void:
	_build()


static func _shaped(pattern: Array, key: Dictionary, out: int, count: int) -> void:
	## pattern : lignes de caracteres, ex ["XX", "XX"]. key : {"X": item_id}
	var h := pattern.size()
	var w := 0
	for line in pattern:
		w = maxi(w, String(line).length())
	var grid: Array[int] = []
	grid.resize(w * h)
	for y in h:
		var line := String(pattern[y])
		for x in w:
			var c := line.substr(x, 1) if x < line.length() else " "
			grid[y * w + x] = int(key.get(c, 0))
	CRAFT.append({"type": "shaped", "w": w, "h": h, "grid": grid,
			"out": out, "count": count})


static func _shapeless(items: Array, out: int, count: int) -> void:
	CRAFT.append({"type": "shapeless", "items": items, "out": out, "count": count})


static func _build() -> void:
	if not CRAFT.is_empty():
		return
	var P := Blocks.PLANKS
	var S := Items.STICK
	var C := Blocks.COBBLE
	var I := Items.IRON_INGOT
	var A := Items.ARCANITE
	var M := Items.MANA_CRYSTAL

	_shapeless([Blocks.LOG], P, 4)
	_shapeless([Blocks.DARK_PLANKS], Blocks.PLANKS, 1)
	_shaped(["P", "P"], {"P": P}, S, 4)
	_shaped(["PP", "PP"], {"P": P}, Blocks.CRAFTING_TABLE, 1)
	_shaped(["CCC", "C C", "CCC"], {"C": C}, Blocks.FURNACE, 1)
	_shaped(["PPP", "P P", "PPP"], {"P": P}, Blocks.CHEST, 1)
	_shaped(["CC", "CC"], {"C": C}, Blocks.STONE_BRICKS, 4)
	_shaped(["M", "S"], {"M": Items.COAL, "S": S}, Blocks.TORCH, 4)
	_shapeless([M, M, M, M, M, M, M, M, M], Blocks.MANA_BLOCK, 1)
	_shapeless([A, A, A, A, A, A, A, A, A], Blocks.ARCANITE_BLOCK, 1)
	_shapeless([Blocks.MANA_BLOCK], M, 9)
	_shapeless([Blocks.ARCANITE_BLOCK], A, 9)
	_shapeless([Items.APPLE, Items.APPLE, Items.APPLE], Items.BREAD, 1)
	_shapeless([Blocks.GLASS, M], Items.POTION_MANA, 1)
	_shapeless([Blocks.GLASS, Items.APPLE, M], Items.POTION_HEAL, 1)

	# outils
	for t in [[P, Items.PICK_WOOD, Items.SWORD_WOOD, Items.AXE_WOOD, 0],
			[C, Items.PICK_STONE, Items.SWORD_STONE, Items.AXE_STONE, Items.SHOVEL_STONE],
			[I, Items.PICK_IRON, Items.SWORD_IRON, Items.AXE_IRON, Items.SHOVEL_IRON],
			[A, Items.PICK_ARC, Items.SWORD_ARC, Items.AXE_ARC, 0]]:
		var mat: int = t[0]
		_shaped(["MMM", " S ", " S "], {"M": mat, "S": S}, t[1], 1)
		_shaped(["M", "M", "S"], {"M": mat, "S": S}, t[2], 1)
		_shaped(["MM", "MS", " S"], {"M": mat, "S": S}, t[3], 1)
		if int(t[4]) != 0:
			_shaped(["M", "S", "S"], {"M": mat, "S": S}, t[4], 1)

	# magie
	_shaped([" M", "S "], {"M": M, "S": S}, Items.WAND1, 1)
	_shaped([" M ", "MSM", " S "], {"M": M, "S": S}, Items.TOME, 1)
	_shaped(["BBB", "BMB", "BBB"], {"B": Blocks.STONE_BRICKS, "M": Blocks.MANA_BLOCK},
			Blocks.ALTAR, 1)
	_shaped(["TTT", "PPP"], {"T": Items.TOME, "P": P}, Blocks.RUNE_TABLE, 1)

	# four : entree -> [sortie, quantite, duree]
	SMELT = {
		Blocks.IRON_ORE: [Items.IRON_INGOT, 1, 6.0],
		Blocks.GOLD_ORE: [Items.GOLD_INGOT, 1, 7.0],
		Blocks.MANA_ORE: [Items.MANA_CRYSTAL, 2, 8.0],
		Blocks.ARCANITE_ORE: [Items.ARCANITE, 1, 12.0],
		Blocks.SAND: [Blocks.GLASS, 1, 5.0],
		Blocks.COBBLE: [Blocks.STONE, 1, 5.0],
		Blocks.LOG: [Items.COAL, 1, 6.0],
		Blocks.GRAVEL: [Blocks.SAND, 1, 4.0],
		Items.APPLE: [Items.BREAD, 1, 4.0],
	}

	# autel arcanique : infusion (ameliore les baguettes)
	INFUSE = [
		{"in": Items.WAND1, "mana": 8, "arc": 0, "heart": 0, "out": Items.WAND2},
		{"in": Items.WAND2, "mana": 16, "arc": 2, "heart": 0, "out": Items.WAND3},
		{"in": Items.WAND3, "mana": 32, "arc": 8, "heart": 0, "out": Items.WAND4},
		{"in": Items.WAND4, "mana": 48, "arc": 16, "heart": 1, "out": Items.WAND5},
		{"in": Items.TOME, "mana": 6, "arc": 1, "heart": 0, "out": Items.TOME},
	]


static func fuel_time(id: int) -> float:
	var d := Items.get_def(id)
	if d.has("fuel"):
		return float(d["fuel"])
	match id:
		Blocks.PLANKS, Blocks.LOG:
			return 1.5
		Blocks.DARK_PLANKS:
			return 2.0
		Items.STICK:
			return 0.6
		Blocks.CRAFTING_TABLE, Blocks.CHEST:
			return 2.0
		Blocks.MANA_BLOCK:
			return 40.0
	return 0.0


static func _grid_ids(grid: Array, gw: int) -> Dictionary:
	## Retourne les ids non vides + la boite englobante.
	var ids: Array[int] = []
	var minx := 99
	var maxx := -1
	var miny := 99
	var maxy := -1
	for i in grid.size():
		var s: Dictionary = grid[i]
		var id := int(s.get("id", 0)) if not Inventory.is_empty_slot(s) else 0
		ids.append(id)
		if id != 0:
			var x: int = i % gw
			var y: int = i / gw
			minx = mini(minx, x)
			maxx = maxi(maxx, x)
			miny = mini(miny, y)
			maxy = maxi(maxy, y)
	return {"ids": ids, "minx": minx, "maxx": maxx, "miny": miny, "maxy": maxy}


static func match_craft(grid: Array, gw: int) -> Dictionary:
	## grid : tableau de slots de taille gw*gw. Retourne {} ou {out, count}
	if CRAFT.is_empty():
		_build()
	var info := _grid_ids(grid, gw)
	var ids: Array = info["ids"]
	if int(info["maxx"]) < 0:
		return {}
	var bw: int = int(info["maxx"]) - int(info["minx"]) + 1
	var bh: int = int(info["maxy"]) - int(info["miny"]) + 1
	var present: Array[int] = []
	for id in ids:
		if int(id) != 0:
			present.append(int(id))
	present.sort()

	for r in CRAFT:
		if r["type"] == "shaped":
			if int(r["w"]) != bw or int(r["h"]) != bh:
				continue
			var ok := true
			for y in bh:
				for x in bw:
					var want: int = int(r["grid"][y * int(r["w"]) + x])
					var got: int = int(ids[(y + int(info["miny"])) * gw + x + int(info["minx"])])
					if want != got:
						ok = false
						break
				if not ok:
					break
			if ok:
				return {"out": int(r["out"]), "count": int(r["count"])}
		else:
			var need: Array = (r["items"] as Array).duplicate()
			need.sort()
			if need.size() != present.size():
				continue
			var same := true
			for i in need.size():
				if int(need[i]) != int(present[i]):
					same = false
					break
			if same:
				return {"out": int(r["out"]), "count": int(r["count"])}
	return {}


static func smelt_result(id: int) -> Array:
	if SMELT.is_empty():
		_build()
	return SMELT.get(id, [])


static func infuse_for(id: int) -> Dictionary:
	if INFUSE.is_empty():
		_build()
	for r in INFUSE:
		if int(r["in"]) == id:
			return r
	return {}
