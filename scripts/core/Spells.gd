class_name Spells
extends RefCounted
## Sorts. Plus la baguette monte en tier, plus le sort casse de blocs et fait mal.
## break_tier : niveau maximal de durete de bloc que le sort peut desintegrer
## (voir Blocks.magic_tier : 1=terre/bois, 2=pierre, 3=minerais, 4=arcanite, 5=obsidienne)

const KIND_BOLT := 0     # projectile
const KIND_NOVA := 1     # explosion centree sur le lanceur
const KIND_BEAM := 2     # rayon perforant instantane
const KIND_SELF := 3     # effet sur soi

static var LIST: Array[Dictionary] = []


static func _static_init() -> void:
	_build()


static func _add(id: int, name: String, tier: int, kind: int, mana: float, cd: float,
		dmg: float, radius: float, btier: int, color: Color, opts: Dictionary = {}) -> void:
	var d := {
		"id": id, "name": name, "tier": tier, "kind": kind, "mana": mana, "cd": cd,
		"damage": dmg, "radius": radius, "break_tier": btier, "color": color,
		"speed": 34.0, "range": 60.0, "desc": "",
	}
	for k in opts:
		d[k] = opts[k]
	LIST.append(d)


static func _build() -> void:
	if not LIST.is_empty():
		return
	_add(0, "Etincelle", 1, KIND_BOLT, 4.0, 0.28, 5.0, 0.9, 1,
		Color(0.55, 0.85, 1.0), {"speed": 42.0,
		"desc": "Trait rapide. Desintegre terre, sable et bois."})
	_add(1, "Elan", 1, KIND_SELF, 8.0, 2.5, 0.0, 0.0, 0,
		Color(0.7, 1.0, 0.9), {"dash": 16.0, "desc": "Bond arcanique vers l'avant."})
	_add(2, "Eclat de mana", 2, KIND_BOLT, 11.0, 0.7, 9.0, 2.1, 2,
		Color(0.62, 0.45, 1.0), {"speed": 32.0,
		"desc": "Explose a l'impact. Perce la pierre."})
	_add(3, "Nova", 3, KIND_NOVA, 26.0, 3.0, 14.0, 4.2, 3,
		Color(1.0, 0.72, 0.35), {"desc": "Onde de choc circulaire. Broie les minerais."})
	_add(4, "Soin runique", 3, KIND_SELF, 22.0, 6.0, 0.0, 0.0, 0,
		Color(0.4, 1.0, 0.5), {"heal": 12.0, "desc": "Restaure des points de vie."})
	_add(5, "Rayon du Vide", 4, KIND_BEAM, 34.0, 1.8, 20.0, 1.9, 4,
		Color(0.75, 0.35, 1.0), {"range": 44.0,
		"desc": "Fore un tunnel droit et transperce tout."})
	_add(6, "Cataclysme", 5, KIND_BOLT, 75.0, 7.5, 42.0, 7.0, 5,
		Color(1.0, 0.35, 0.25), {"speed": 26.0,
		"desc": "Meteore arcanique. Rien ne resiste, pas meme l'obsidienne."})


static func all() -> Array[Dictionary]:
	if LIST.is_empty():
		_build()
	return LIST


static func get_spell(id: int) -> Dictionary:
	for s in all():
		if int(s["id"]) == id:
			return s
	return all()[0]


static func for_tier(tier: int) -> Array[int]:
	## Sorts utilisables avec une baguette de ce tier.
	var out: Array[int] = []
	for s in all():
		if int(s["tier"]) <= tier:
			out.append(int(s["id"]))
	return out


static func scaled(spell_id: int, wand_tier: int, mastery: int) -> Dictionary:
	## Applique le bonus de baguette et la maitrise (table de runes).
	var s := get_spell(spell_id).duplicate()
	var p := 1.0 + 0.22 * float(maxi(0, wand_tier - int(s["tier"]))) + 0.12 * float(mastery)
	s["damage"] = float(s["damage"]) * p
	s["radius"] = float(s["radius"]) * (1.0 + 0.10 * float(maxi(0, wand_tier - int(s["tier"])))
			+ 0.06 * float(mastery))
	s["heal"] = float(s.get("heal", 0.0)) * p
	return s
