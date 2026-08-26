class_name Inventory
extends RefCounted
## Conteneur generique (inventaire joueur, coffre, four...).
## Un slot = {"id": int, "count": int, "dura": int}

signal changed

var slots: Array[Dictionary] = []


func _init(size: int = 36) -> void:
	slots.resize(size)
	for i in size:
		slots[i] = empty_slot()


static func empty_slot() -> Dictionary:
	return {"id": 0, "count": 0, "dura": 0}


static func is_empty_slot(s: Dictionary) -> bool:
	return s.is_empty() or int(s.get("id", 0)) == 0 or int(s.get("count", 0)) <= 0


func size() -> int:
	return slots.size()


func get_slot(i: int) -> Dictionary:
	if i < 0 or i >= slots.size():
		return empty_slot()
	return slots[i]


func set_slot(i: int, s: Dictionary) -> void:
	if i < 0 or i >= slots.size():
		return
	slots[i] = s if not is_empty_slot(s) else empty_slot()
	changed.emit()


func add(id: int, count: int, dura: int = -1) -> int:
	## Ajoute des items, retourne la quantite qui n'a PAS pu entrer.
	if id == 0 or count <= 0:
		return 0
	var maxs := Items.max_stack(id)
	var rest := count
	if maxs > 1:
		for i in slots.size():
			var s := slots[i]
			if int(s["id"]) == id and int(s["count"]) < maxs:
				var can: int = mini(maxs - int(s["count"]), rest)
				s["count"] = int(s["count"]) + can
				slots[i] = s
				rest -= can
				if rest <= 0:
					changed.emit()
					return 0
	for i in slots.size():
		if is_empty_slot(slots[i]):
			var put: int = mini(maxs, rest)
			var d := dura
			if d < 0:
				d = int(Items.get_def(id).get("durability", 0))
			slots[i] = {"id": id, "count": put, "dura": d}
			rest -= put
			if rest <= 0:
				changed.emit()
				return 0
	changed.emit()
	return rest


func count_of(id: int) -> int:
	var n := 0
	for s in slots:
		if int(s.get("id", 0)) == id:
			n += int(s.get("count", 0))
	return n


func remove(id: int, count: int) -> bool:
	if count_of(id) < count:
		return false
	var rest := count
	for i in slots.size():
		var s := slots[i]
		if int(s["id"]) == id:
			var take: int = mini(int(s["count"]), rest)
			s["count"] = int(s["count"]) - take
			rest -= take
			slots[i] = empty_slot() if int(s["count"]) <= 0 else s
			if rest <= 0:
				break
	changed.emit()
	return true


func consume_slot(i: int, count: int = 1) -> void:
	var s := get_slot(i)
	if is_empty_slot(s):
		return
	s["count"] = int(s["count"]) - count
	slots[i] = empty_slot() if int(s["count"]) <= 0 else s
	changed.emit()


func damage_tool(i: int, amount: int = 1) -> void:
	var s := get_slot(i)
	if is_empty_slot(s):
		return
	var maxd := int(Items.get_def(int(s["id"])).get("durability", 0))
	if maxd <= 0:
		return
	s["dura"] = int(s.get("dura", maxd)) - amount
	if int(s["dura"]) <= 0:
		slots[i] = empty_slot()
	else:
		slots[i] = s
	changed.emit()


func first_free() -> int:
	for i in slots.size():
		if is_empty_slot(slots[i]):
			return i
	return -1


func clear() -> void:
	for i in slots.size():
		slots[i] = empty_slot()
	changed.emit()


func to_array() -> Array:
	var a: Array = []
	for s in slots:
		a.append([int(s.get("id", 0)), int(s.get("count", 0)), int(s.get("dura", 0))])
	return a


func from_array(a: Array) -> void:
	for i in mini(a.size(), slots.size()):
		var e = a[i]
		if e is Array and e.size() >= 2:
			slots[i] = {"id": int(e[0]), "count": int(e[1]),
					"dura": int(e[2]) if e.size() > 2 else 0}
	changed.emit()
