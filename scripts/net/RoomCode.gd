class_name RoomCode
extends RefCounted
## Codes de partie.
##
## - CODE COURT (6 caracteres)  : cle de salon. Resolue par la decouverte LAN
##   (broadcast UDP) ou par l'annuaire optionnel. Zero infrastructure sur un
##   reseau local.
## - CODE DIRECT (8 caracteres) : encode l'adresse IPv4 + le port. Fonctionne
##   partout sans aucun serveur tiers (il suffit d'ouvrir le port).
##
## Alphabet Crockford base32 : pas de I, L, O, U (evite les confusions a l'oral).

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const SHORT_LEN := 6
const DIRECT_LEN := 8
const DEFAULT_PORT := 24565


static func random_short() -> String:
	var s := ""
	for i in SHORT_LEN:
		s += ALPHABET[randi() % ALPHABET.length()]
	return s


static func _to_base32(value: int, length: int) -> String:
	var s := ""
	var v := value
	for i in length:
		s = ALPHABET[v & 31] + s
		v >>= 5
	return s


static func _from_base32(code: String) -> int:
	var v := 0
	for c in code.to_upper():
		var i := ALPHABET.find(c)
		if i < 0:
			return -1
		v = (v << 5) | i
	return v


static func encode_direct(ip: String, port: int = DEFAULT_PORT) -> String:
	## 32 bits d'IPv4 + 8 bits de decalage de port => 8 caracteres.
	var parts := ip.split(".")
	if parts.size() != 4:
		return ""
	var v := 0
	for p in parts:
		v = (v << 8) | (int(p) & 255)
	var off: int = clampi(port - DEFAULT_PORT, 0, 255)
	return _to_base32((v << 8) | off, DIRECT_LEN)


static func decode_direct(code: String) -> Dictionary:
	var c := normalize(code)
	if c.length() != DIRECT_LEN:
		return {}
	var v := _from_base32(c)
	if v < 0:
		return {}
	var off := v & 255
	var ipv := v >> 8
	var ip := "%d.%d.%d.%d" % [(ipv >> 24) & 255, (ipv >> 16) & 255, (ipv >> 8) & 255, ipv & 255]
	return {"ip": ip, "port": DEFAULT_PORT + off}


static func normalize(code: String) -> String:
	var out := ""
	for c in code.to_upper():
		if c == "I":
			c = "1"
		elif c == "L":
			c = "1"
		elif c == "O":
			c = "0"
		elif c == "U":
			c = "V"
		if ALPHABET.find(c) >= 0:
			out += c
	return out


static func kind_of(code: String) -> String:
	var c := normalize(code)
	if c.length() == DIRECT_LEN:
		return "direct"
	if c.length() == SHORT_LEN:
		return "short"
	return "invalid"


static func local_ipv4() -> String:
	for a in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127."):
			return a
	return "127.0.0.1"
