extends Node
class_name LanDiscovery
## Decouverte des parties sur le reseau local (broadcast UDP).
## L'hote emet une balise chaque seconde ; les clients ecoutent et remplissent
## la liste des serveurs. Aucune infrastructure externe.

const BEACON_PORT := 24566
const INTERVAL := 1.0
const TTL := 4.0

signal servers_updated(list: Array)

var broadcasting := false
var listening := false
var beacon: Dictionary = {}

var _udp_out: PacketPeerUDP
var _udp_in: PacketPeerUDP
var _acc := 0.0
var _found: Dictionary = {}


func _ready() -> void:
	set_process(true)


func start_broadcast(info: Dictionary) -> void:
	if OS.has_feature("web"):
		return
	beacon = info
	if _udp_out == null:
		_udp_out = PacketPeerUDP.new()
		_udp_out.set_broadcast_enabled(true)
	_udp_out.set_dest_address("255.255.255.255", BEACON_PORT)
	broadcasting = true


func stop_broadcast() -> void:
	broadcasting = false
	if _udp_out != null:
		_udp_out.close()
		_udp_out = null


func start_listen() -> void:
	if OS.has_feature("web") or listening:
		return
	_udp_in = PacketPeerUDP.new()
	var err := _udp_in.bind(BEACON_PORT, "0.0.0.0")
	listening = err == OK
	if not listening:
		push_warning("LAN : impossible d'ecouter sur le port %d" % BEACON_PORT)


func stop_listen() -> void:
	listening = false
	if _udp_in != null:
		_udp_in.close()
		_udp_in = null


func _process(delta: float) -> void:
	_acc += delta
	if broadcasting and _udp_out != null and _acc >= INTERVAL:
		var payload := beacon.duplicate()
		payload["t"] = Time.get_unix_time_from_system()
		_udp_out.put_packet(JSON.stringify(payload).to_utf8_buffer())
	if _acc >= INTERVAL:
		_acc = 0.0
		_prune()

	if listening and _udp_in != null:
		while _udp_in.get_available_packet_count() > 0:
			var raw := _udp_in.get_packet().get_string_from_utf8()
			var ip := _udp_in.get_packet_ip()
			var data = JSON.parse_string(raw)
			if data is Dictionary:
				data["ip"] = ip
				data["seen"] = Time.get_ticks_msec() / 1000.0
				data["source"] = "LAN"
				_found[String(data.get("code", ip))] = data
				servers_updated.emit(list())


func _prune() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var dirty := false
	for k in _found.keys():
		if now - float(_found[k].get("seen", 0.0)) > TTL:
			_found.erase(k)
			dirty = true
	if dirty:
		servers_updated.emit(list())


func list() -> Array:
	var out: Array = []
	for k in _found:
		out.append(_found[k])
	return out


func find_by_code(code: String) -> Dictionary:
	var c := RoomCode.normalize(code)
	for k in _found:
		if RoomCode.normalize(String(_found[k].get("code", ""))) == c:
			return _found[k]
	return {}
