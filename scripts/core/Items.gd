class_name Items
extends RefCounted
## Registre des items. id < 100 => item-bloc (placable), id >= 100 => item pur.

const STICK := 100
const COAL := 101
const IRON_INGOT := 102
const GOLD_INGOT := 103
const MANA_CRYSTAL := 104
const ARCANITE := 105
const PICK_WOOD := 106
const PICK_STONE := 107
const PICK_IRON := 108
const PICK_ARC := 109
const SWORD_WOOD := 110
const SWORD_STONE := 111
const SWORD_IRON := 112
const SWORD_ARC := 113
const AXE_WOOD := 114
const AXE_STONE := 115
const AXE_IRON := 116
const AXE_ARC := 117
const SHOVEL_STONE := 118
const SHOVEL_IRON := 119
const WAND1 := 120
const WAND2 := 121
const WAND3 := 122
const WAND4 := 123
const WAND5 := 124
const TOME := 125
const POTION_HEAL := 126
const POTION_MANA := 127
const BREAD := 128
const APPLE := 129
const VOID_HEART := 130

static var DB: Dictionary = {}


static func _static_init() -> void:
	_build()


static func _tool(id: int, name: String, icon: int, tool: int, level: int,
		speed: float, dmg: float, dura: int) -> void:
	DB[id] = {
		"id": id, "name": name, "icon": icon, "stack": 1, "kind": "tool",
		"tool": tool, "level": level, "speed": speed, "damage": dmg, "durability": dura,
	}


static func _mat(id: int, name: String, icon: int, stack := 64, extra: Dictionary = {}) -> void:
	var d := {"id": id, "name": name, "icon": icon, "stack": stack, "kind": "material",
			"tool": Blocks.TOOL_NONE, "level": 0, "speed": 1.0, "damage": 1.0}
	for k in extra:
		d[k] = extra[k]
	DB[id] = d


static func _build() -> void:
	if not DB.is_empty():
		return
	# items-blocs
	for i in range(1, Blocks.COUNT):
		var bd := Blocks.get_def(i)
		if i == Blocks.WATER or i == Blocks.BEDROCK or i == Blocks.FURNACE_LIT:
			continue
		DB[i] = {
			"id": i, "name": bd["name"], "icon": -1, "block": i, "stack": 64,
			"kind": "block", "tool": Blocks.TOOL_NONE, "level": 0, "speed": 1.0,
			"damage": 1.0,
		}
	_mat(STICK, "Baton", 0)
	_mat(COAL, "Charbon", 1, 64, {"fuel": 8.0})
	_mat(IRON_INGOT, "Lingot de fer", 2)
	_mat(GOLD_INGOT, "Lingot d'or", 3)
	_mat(MANA_CRYSTAL, "Cristal de mana", 4)
	_mat(ARCANITE, "Arcanite", 5)
	_mat(VOID_HEART, "Coeur du Neant", 30, 16)
	_mat(TOME, "Tome arcanique", 25, 16)
	_mat(BREAD, "Pain", 28, 16, {"food": 6.0})
	_mat(APPLE, "Pomme", 29, 16, {"food": 3.0})
	_mat(POTION_HEAL, "Potion de vie", 26, 8, {"heal": 10.0})
	_mat(POTION_MANA, "Potion de mana", 27, 8, {"mana": 60.0})

	_tool(PICK_WOOD, "Pioche en bois", 6, Blocks.TOOL_PICK, 1, 2.5, 2.0, 60)
	_tool(PICK_STONE, "Pioche en pierre", 7, Blocks.TOOL_PICK, 2, 4.5, 3.0, 132)
	_tool(PICK_IRON, "Pioche en fer", 8, Blocks.TOOL_PICK, 3, 7.0, 4.0, 250)
	_tool(PICK_ARC, "Pioche en arcanite", 9, Blocks.TOOL_PICK, 3, 12.0, 5.0, 900)
	_tool(SWORD_WOOD, "Epee en bois", 10, Blocks.TOOL_NONE, 0, 1.0, 5.0, 60)
	_tool(SWORD_STONE, "Epee en pierre", 11, Blocks.TOOL_NONE, 0, 1.0, 7.0, 132)
	_tool(SWORD_IRON, "Epee en fer", 12, Blocks.TOOL_NONE, 0, 1.0, 9.0, 250)
	_tool(SWORD_ARC, "Epee en arcanite", 13, Blocks.TOOL_NONE, 0, 1.0, 13.0, 900)
	_tool(AXE_WOOD, "Hache en bois", 14, Blocks.TOOL_AXE, 1, 2.5, 3.0, 60)
	_tool(AXE_STONE, "Hache en pierre", 15, Blocks.TOOL_AXE, 2, 4.5, 4.0, 132)
	_tool(AXE_IRON, "Hache en fer", 16, Blocks.TOOL_AXE, 3, 7.0, 5.0, 250)
	_tool(AXE_ARC, "Hache en arcanite", 17, Blocks.TOOL_AXE, 3, 12.0, 6.5, 900)
	_tool(SHOVEL_STONE, "Pelle en pierre", 18, Blocks.TOOL_SHOVEL, 2, 4.5, 2.5, 132)
	_tool(SHOVEL_IRON, "Pelle en fer", 19, Blocks.TOOL_SHOVEL, 3, 7.0, 3.5, 250)

	for t in range(1, 6):
		var id := WAND1 + t - 1
		DB[id] = {
			"id": id, "name": "Baguette T%d" % t, "icon": 19 + t, "stack": 1,
			"kind": "wand", "tier": t, "tool": Blocks.TOOL_NONE, "level": 0,
			"speed": 1.0, "damage": 1.0 + t, "power": 1.0 + 0.35 * (t - 1),
		}


static func get_def(id: int) -> Dictionary:
	if DB.is_empty():
		_build()
	return DB.get(id, {"id": 0, "name": "?", "icon": -1, "stack": 64, "kind": "material",
			"tool": Blocks.TOOL_NONE, "level": 0, "speed": 1.0, "damage": 1.0})


static func item_name(id: int) -> String:
	return String(get_def(id).get("name", "?"))


static func max_stack(id: int) -> int:
	return int(get_def(id).get("stack", 64))


static func is_block(id: int) -> bool:
	return get_def(id).has("block")


static func block_id(id: int) -> int:
	return int(get_def(id).get("block", 0))


static func icon_index(id: int) -> int:
	return int(get_def(id).get("icon", -1))


static func wand_tier(id: int) -> int:
	return int(get_def(id).get("tier", 0))


static func exists(id: int) -> bool:
	if DB.is_empty():
		_build()
	return DB.has(id)
