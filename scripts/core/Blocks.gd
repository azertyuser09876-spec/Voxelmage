class_name Blocks
extends RefCounted
## Registre des blocs. Les index de tuiles correspondent a tools/generate_assets.py

# --- ids de blocs -----------------------------------------------------------
const AIR := 0
const STONE := 1
const DIRT := 2
const GRASS := 3
const SAND := 4
const LOG := 5
const LEAVES := 6
const PLANKS := 7
const COBBLE := 8
const GLASS := 9
const WATER := 10
const SNOW := 11
const CACTUS := 12
const COAL_ORE := 13
const IRON_ORE := 14
const GOLD_ORE := 15
const MANA_ORE := 16
const ARCANITE_ORE := 17
const OBSIDIAN := 18
const BEDROCK := 19
const GRAVEL := 20
const ICE := 21
const STONE_BRICKS := 22
const CRAFTING_TABLE := 23
const FURNACE := 24
const FURNACE_LIT := 25
const CHEST := 26
const ALTAR := 27
const RUNE_TABLE := 28
const MANA_BLOCK := 29
const VOID_ROCK := 30
const ARCANITE_BLOCK := 31
const DARK_PLANKS := 32
const RED_SAND := 33
const TORCH := 34
const COUNT := 35

# types d'outils
const TOOL_NONE := 0
const TOOL_PICK := 1
const TOOL_AXE := 2
const TOOL_SHOVEL := 3

static var DB: Array[Dictionary] = []

# Tables plates pour la boucle chaude du mailleur (acces direct, sans Dictionary)
static var OPAQUE := PackedByteArray()
static var SOLID := PackedByteArray()
static var ALPHA := PackedByteArray()
static var CROSS := PackedByteArray()
static var LIGHT := PackedByteArray()
static var TILES := PackedInt32Array()    # COUNT * 6 (une entree par face)


static func _static_init() -> void:
	_build()


static func _def(id: int, name: String, top: int, side: int, bottom: int, hard: float,
		tool: int, level: int, magic_tier: int, opts: Dictionary = {}) -> void:
	var d := {
		"id": id, "name": name, "top": top, "side": side, "bottom": bottom,
		"hard": hard, "tool": tool, "level": level, "magic_tier": magic_tier,
		"solid": true, "opaque": true, "alpha": false, "light": 0,
		"drop": id, "interact": "", "cross": false,
	}
	for k in opts:
		d[k] = opts[k]
	DB[id] = d


static func _build() -> void:
	if DB.size() == COUNT:
		return
	DB.resize(COUNT)
	_def(AIR, "Air", 0, 0, 0, 0.0, TOOL_NONE, 0, 0, {"solid": false, "opaque": false})
	_def(STONE, "Pierre", 0, 0, 0, 1.5, TOOL_PICK, 1, 2, {"drop": COBBLE})
	_def(DIRT, "Terre", 1, 1, 1, 0.6, TOOL_SHOVEL, 0, 1)
	_def(GRASS, "Herbe", 2, 3, 1, 0.7, TOOL_SHOVEL, 0, 1, {"drop": DIRT})
	_def(SAND, "Sable", 4, 4, 4, 0.5, TOOL_SHOVEL, 0, 1)
	_def(LOG, "Rondin", 6, 5, 6, 1.2, TOOL_AXE, 0, 1)
	_def(LEAVES, "Feuillage", 7, 7, 7, 0.3, TOOL_NONE, 0, 1,
		{"opaque": false, "alpha": true, "drop": -1})
	_def(PLANKS, "Planches", 8, 8, 8, 1.0, TOOL_AXE, 0, 1)
	_def(COBBLE, "Pierre taillee", 9, 9, 9, 1.6, TOOL_PICK, 1, 2)
	_def(GLASS, "Verre", 10, 10, 10, 0.4, TOOL_NONE, 0, 1,
		{"opaque": false, "alpha": true, "drop": -1})
	_def(WATER, "Eau", 11, 11, 11, 999.0, TOOL_NONE, 9, 9,
		{"solid": false, "opaque": false, "alpha": true, "drop": -1})
	_def(SNOW, "Neige", 12, 13, 1, 0.4, TOOL_SHOVEL, 0, 1)
	_def(CACTUS, "Cactus", 15, 14, 15, 0.5, TOOL_NONE, 0, 1, {"opaque": false})
	_def(COAL_ORE, "Minerai de charbon", 16, 16, 16, 2.2, TOOL_PICK, 1, 2, {"drop": -1})
	_def(IRON_ORE, "Minerai de fer", 17, 17, 17, 2.6, TOOL_PICK, 2, 3, {"drop": -1})
	_def(GOLD_ORE, "Minerai d'or", 18, 18, 18, 2.8, TOOL_PICK, 2, 3, {"drop": -1})
	_def(MANA_ORE, "Minerai de mana", 19, 19, 19, 3.0, TOOL_PICK, 2, 3,
		{"drop": -1, "light": 7})
	_def(ARCANITE_ORE, "Minerai d'arcanite", 20, 20, 20, 4.0, TOOL_PICK, 3, 4,
		{"drop": -1, "light": 6})
	_def(OBSIDIAN, "Obsidienne", 21, 21, 21, 12.0, TOOL_PICK, 3, 5)
	_def(BEDROCK, "Socle", 22, 22, 22, -1.0, TOOL_NONE, 9, 9, {"drop": -1})
	_def(GRAVEL, "Gravier", 23, 23, 23, 0.6, TOOL_SHOVEL, 0, 1)
	_def(ICE, "Glace", 24, 24, 24, 0.5, TOOL_PICK, 1, 1,
		{"alpha": true, "opaque": false, "drop": -1})
	_def(STONE_BRICKS, "Briques", 25, 25, 25, 2.0, TOOL_PICK, 1, 2)
	_def(CRAFTING_TABLE, "Etabli", 26, 27, 8, 1.2, TOOL_AXE, 0, 1, {"interact": "craft"})
	_def(FURNACE, "Four", 30, 30, 30, 2.5, TOOL_PICK, 1, 2,
		{"interact": "furnace", "front": 28})
	_def(FURNACE_LIT, "Four allume", 30, 30, 30, 2.5, TOOL_PICK, 1, 2,
		{"interact": "furnace", "front": 29, "light": 13, "drop": FURNACE})
	_def(CHEST, "Coffre", 33, 32, 33, 1.6, TOOL_AXE, 0, 1,
		{"interact": "chest", "front": 31})
	_def(ALTAR, "Autel arcanique", 34, 35, 25, 3.5, TOOL_PICK, 2, 3,
		{"interact": "altar", "light": 8})
	_def(RUNE_TABLE, "Table de runes", 36, 37, 8, 2.0, TOOL_AXE, 0, 2,
		{"interact": "runes", "light": 5})
	_def(MANA_BLOCK, "Bloc de mana", 38, 38, 38, 3.0, TOOL_PICK, 2, 3, {"light": 12})
	_def(VOID_ROCK, "Roche du Neant", 39, 39, 39, 5.0, TOOL_PICK, 3, 4)
	_def(ARCANITE_BLOCK, "Bloc d'arcanite", 40, 40, 40, 4.5, TOOL_PICK, 3, 4, {"light": 10})
	_def(DARK_PLANKS, "Planches sombres", 41, 41, 41, 1.2, TOOL_AXE, 0, 1)
	_def(RED_SAND, "Sable rouge", 42, 42, 42, 0.5, TOOL_SHOVEL, 0, 1)
	_def(TORCH, "Torche", 43, 43, 43, 0.1, TOOL_NONE, 0, 1,
		{"solid": false, "opaque": false, "alpha": true, "cross": true, "light": 14})
	_build_tables()


static func _build_tables() -> void:
	OPAQUE.resize(COUNT)
	SOLID.resize(COUNT)
	ALPHA.resize(COUNT)
	CROSS.resize(COUNT)
	LIGHT.resize(COUNT)
	TILES.resize(COUNT * 6)
	for i in COUNT:
		var d: Dictionary = DB[i]
		OPAQUE[i] = 1 if bool(d.get("opaque", true)) else 0
		SOLID[i] = 1 if bool(d.get("solid", true)) else 0
		ALPHA[i] = 1 if bool(d.get("alpha", false)) else 0
		CROSS[i] = 1 if bool(d.get("cross", false)) else 0
		LIGHT[i] = int(d.get("light", 0))
		for f in 6:
			TILES[i * 6 + f] = face_tile(i, f)


static func get_def(id: int) -> Dictionary:
	if DB.size() != COUNT:
		_build()
	if id < 0 or id >= DB.size():
		return DB[0]
	return DB[id]


static func is_solid(id: int) -> bool:
	return get_def(id).get("solid", true)


static func is_opaque(id: int) -> bool:
	return get_def(id).get("opaque", true)


static func is_alpha(id: int) -> bool:
	return get_def(id).get("alpha", false)


static func is_cross(id: int) -> bool:
	return get_def(id).get("cross", false)


static func light_of(id: int) -> int:
	return int(get_def(id).get("light", 0))


static func magic_tier(id: int) -> int:
	return int(get_def(id).get("magic_tier", 1))


static func block_name(id: int) -> String:
	return String(get_def(id).get("name", "?"))


static func face_tile(id: int, face: int) -> int:
	## face : 0=+Y 1=-Y 2=+Z 3=-Z 4=+X 5=-X
	var d := get_def(id)
	if face == 0:
		return int(d["top"])
	if face == 1:
		return int(d["bottom"])
	if face == 3 and d.has("front"):
		return int(d["front"])
	return int(d["side"])


static func break_time(id: int, tool_type: int, tool_level: int, tool_speed: float) -> float:
	## Duree de minage en secondes. -1 = incassable.
	var d := get_def(id)
	var hard: float = float(d["hard"])
	if hard < 0.0:
		return -1.0
	if int(d["level"]) > tool_level:
		return hard * 5.0
	var s := 1.0
	if int(d["tool"]) == tool_type and tool_type != TOOL_NONE:
		s = tool_speed
	return maxf(0.05, hard / s)
