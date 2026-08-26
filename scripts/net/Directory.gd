extends Node
class_name Directory
## Annuaire public (optionnel).
##
## Par defaut l'application lit une liste statique publiee par GitHub Pages
## depuis ce depot (docs/servers.json) : aucun hebergement a payer.
## Si l'utilisateur renseigne l'URL d'un annuaire dynamique (le code source est
## dans directory/, deployable en un clic), l'app peut aussi ANNONCER sa partie
## et resoudre les codes a 6 caracteres depuis Internet.

signal servers_updated(list: Array)
signal resolved(info: Dictionary)

var list_url := ""          # ex: https://<user>.github.io/voxelmage/servers.json
var api_url := ""           # ex: https://mon-annuaire.example.com

var _http_list: HTTPRequest
var _http_api: HTTPRequest
var _cache: Array = []
var _announce_acc := 0.0
var _announce_payload: Dictionary = {}
var announcing := false


func _ready() -> void:
	_http_list = HTTPRequest.new()
	add_child(_http_list)
	_http_list.request_completed.connect(_on_list)
	_http_api = HTTPRequest.new()
	add_child(_http_api)
	_http_api.request_completed.connect(_on_api)
	set_process(true)


func configure(p_list_url: String, p_api_url: String) -> void:
	list_url = p_list_url.strip_edges()
	api_url = p_api_url.strip_edges().rstrip("/")


func refresh() -> void:
	if api_url != "":
		_http_api.request(api_url + "/servers")
	elif list_url != "":
		_http_list.request(list_url)
	else:
		servers_updated.emit([])


func announce(payload: Dictionary) -> void:
	_announce_payload = payload
	announcing = api_url != ""
	if announcing:
		_post("/announce", payload)


func stop_announce() -> void:
	if announcing and api_url != "":
		_post("/close", {"code": _announce_payload.get("code", "")})
	announcing = false


func resolve(code: String) -> void:
	if api_url == "":
		resolved.emit({})
		return
	_http_api.request(api_url + "/resolve?code=" + RoomCode.normalize(code))


func _post(path: String, body: Dictionary) -> void:
	_http_api.request(api_url + path, ["Content-Type: application/json"],
			HTTPClient.METHOD_POST, JSON.stringify(body))


func _process(delta: float) -> void:
	if not announcing:
		return
	_announce_acc += delta
	if _announce_acc >= 25.0:
		_announce_acc = 0.0
		_post("/announce", _announce_payload)


func _parse(body: PackedByteArray) -> Array:
	var data = JSON.parse_string(body.get_string_from_utf8())
	if data is Array:
		return data
	if data is Dictionary and data.has("servers"):
		return data["servers"]
	return []


func _on_list(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		servers_updated.emit([])
		return
	_cache = _parse(body)
	for s in _cache:
		if s is Dictionary:
			s["source"] = "Public"
	servers_updated.emit(_cache)


func _on_api(_r: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	if code != 200:
		servers_updated.emit([])
		return
	var txt := body.get_string_from_utf8()
	var data = JSON.parse_string(txt)
	if data is Dictionary and data.has("ip"):
		resolved.emit(data)
		return
	_cache = _parse(body)
	for s in _cache:
		if s is Dictionary:
			s["source"] = "Public"
	servers_updated.emit(_cache)


func cached() -> Array:
	return _cache
