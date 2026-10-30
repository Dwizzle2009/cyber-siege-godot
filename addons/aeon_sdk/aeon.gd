extends Node
## The Aeon SDK for Godot 4 (autoload "Aeon"). Mirrors libaeon's contract in GDScript.
##
## Reads the environment the console provides at launch (AEON_SDK, AEON_API_URL, AEON_SESSION,
## AEON_SKU, AEON_PLAYER_ID, AEON_LANG, and since 1.1 AEON_REFRESH_HZ, AEON_VRR, AEON_OUTPUT,
## AEON_STATE). Outside Aeon every call succeeds silently and is_on_aeon() is false, so the game
## runs unchanged in the editor and on a developer's desktop.
## Reports (unlocks, progress, scores, events) are queued, retried with backoff, and kept in
## user://aeon_queue.jsonl across launches if the network is down. Nothing here blocks the game.
## 1.1: console events (guide_opened/guide_closed, suspended/resumed) come from a small file the
## shell rewrites (AEON_STATE), polled ten times a second; player carries avatar_color and
## banner_color for in-game display; display() says what the console launched the game on.

const SDK_VERSION := "1.2.0"

signal leaderboard_received(category: String, entries: Array, my_rank: int, my_score: int, has_me: bool)
signal purchase_result(sku: String, completed: bool)
## The Guide now covers the game: pause, mute, stop the clock.
signal guide_opened
## Back to the game.
signal guide_closed
## The console went to rest. The process was frozen, so this arrives together with resumed.
signal suspended
## The console woke: reset timers, re-check anything time-based.
signal resumed

var on_aeon: bool = false
var player := { "id": "", "gamertag": "Player", "lang": "en", "avatar_color": "#6366f1", "banner_color": "#0ea5e9", "avatar_url": "", "sandbox": false }
var _display := { "refresh_hz": 0, "vrr": false, "output": "", "prefer": "" }   # 1.2: prefer = "" | "performance" | "quality"
var _state_path := ""
var _state_seq := -1
var _state_next_poll := 0
var _guide_open := false
var _resumes := 0
var _api := ""
var _token := ""
var _sku := ""
var _owned: Array[String] = []
var _queue: Array = []          # dicts: {k, path, method, body, durable, tries, next_at, cb}
var _busy := false
var _http: HTTPRequest
const _QUEUE_FILE := "user://aeon_queue.jsonl"

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 15.0
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	var sdk := OS.get_environment("AEON_SDK")
	_api = OS.get_environment("AEON_API_URL")
	_token = OS.get_environment("AEON_SESSION")
	_sku = OS.get_environment("AEON_SKU")
	if sdk != "1" or _api == "" or _token == "" or _sku == "":
		on_aeon = false
		return
	on_aeon = true
	player["id"] = OS.get_environment("AEON_PLAYER_ID")
	var lang := OS.get_environment("AEON_LANG")
	if lang != "": player["lang"] = lang
	var hz := OS.get_environment("AEON_REFRESH_HZ")
	if hz != "": _display["refresh_hz"] = int(round(float(hz)))
	_display["vrr"] = OS.get_environment("AEON_VRR") == "1"
	_display["output"] = OS.get_environment("AEON_OUTPUT")
	_display["prefer"] = OS.get_environment("AEON_PREFER")   # 1.2: the player's Settings > Performance > Game preset
	_state_path = OS.get_environment("AEON_STATE")
	if _state_path != "": _poll_state(false)   # baseline, no signals
	_load_queue()
	# who's playing, what they own -- non-durable, answered via the normal queue
	_enqueue({ "k": "me", "path": "/sdk/me", "method": HTTPClient.METHOD_GET, "body": "", "durable": false })
	_enqueue({ "k": "ent", "path": "/sdk/entitlements", "method": HTTPClient.METHOD_GET, "body": "", "durable": false })

func is_on_aeon() -> bool:
	return on_aeon

func sdk_version() -> String:
	return SDK_VERSION

## True while the Guide covers the game (false off-Aeon).
func is_guide_open() -> bool:
	return _guide_open

## What the console launched the game on: { refresh_hz, vrr, output, prefer }. Zeros off-Aeon.
## prefer is the player's console-wide game preset: "" (game decides), "performance" (frame rate first:
## lower render scale, 120 or a steady 60) or "quality" (resolution and effects first; 30 or 60 is fine).
## Honor it as the default of your own graphics menu; the player can still change it in-game.
func display() -> Dictionary:
	return _display.duplicate()

## 1.2: one call that applies the preset for a typical 3D game -- render scale and a frame cap from the
## refresh rate -- and returns what it chose. Call it once at startup, or skip it and read display() yourself.
func apply_preset(perf_scale: float = 0.67, quality_scale: float = 1.0) -> Dictionary:
	var d := display()
	var hz: int = d["refresh_hz"]
	var out := { "prefer": d["prefer"], "scale": 1.0, "max_fps": 0 }
	if d["prefer"] == "performance":
		out["scale"] = perf_scale
		out["max_fps"] = hz if hz > 0 else 0
	elif d["prefer"] == "quality":
		out["scale"] = quality_scale
		out["max_fps"] = 60 if hz >= 60 else hz
	else:
		return out
	var vp := get_tree().root
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if out["scale"] < 1.0 else Viewport.SCALING_3D_MODE_BILINEAR
	vp.scaling_3d_scale = out["scale"]
	Engine.max_fps = out["max_fps"]
	return out

# ---------------- public API ----------------

func unlock(id: String) -> void:
	_enqueue({ "k": "unlock", "path": "/sdk/achievements/%s/unlock" % id, "method": HTTPClient.METHOD_POST, "body": "{}", "durable": true })

func progress(id: String, value: int, max_value: int) -> void:
	_enqueue({ "k": "progress", "path": "/sdk/achievements/%s/progress" % id, "method": HTTPClient.METHOD_POST,
		"body": JSON.stringify({ "value": value, "max": max_value }), "durable": true })

func submit_score(category: String, score: int, metadata = null) -> void:
	_enqueue({ "k": "submit", "path": "/sdk/leaderboards/%s/submit" % category, "method": HTTPClient.METHOD_POST,
		"body": JSON.stringify({ "score": score, "metadata": metadata }), "durable": true })

## Emits leaderboard_received when the answer arrives (empty off-Aeon or offline).
func get_leaderboard(category: String, n: int = 25, friends: bool = false) -> void:
	_enqueue({ "k": "lb", "path": "/sdk/leaderboards/%s?n=%d&friends=%d" % [category, n, 1 if friends else 0],
		"method": HTTPClient.METHOD_GET, "body": "", "durable": false, "category": category })

func owns(sku: String) -> bool:
	if not on_aeon: return true   # dev builds show all content
	return sku in _owned

func set_presence(status: String) -> void:
	_enqueue({ "k": "presence", "path": "/sdk/presence", "method": HTTPClient.METHOD_PUT,
		"body": JSON.stringify({ "status": status.left(120) }), "durable": false })

## The console shows the purchase UI; emits purchase_result(sku, completed) when it's resolved.
func purchase(sku: String) -> void:
	_enqueue({ "k": "purchase", "path": "/sdk/purchase", "method": HTTPClient.METHOD_POST,
		"body": JSON.stringify({ "sku": sku }), "durable": false, "sku": sku })

func send_event(name: String, payload = null) -> void:
	_enqueue({ "k": "event", "path": "/sdk/events", "method": HTTPClient.METHOD_POST,
		"body": JSON.stringify([{ "name": name, "payload": payload }]), "durable": true })

# ---------------- queue ----------------

func _enqueue(job: Dictionary) -> void:
	if not on_aeon:
		if job.k == "lb": leaderboard_received.emit(job.get("category", ""), [], 0, 0, false)
		if job.k == "purchase": purchase_result.emit(job.get("sku", ""), false)
		return
	job["tries"] = job.get("tries", 0)
	job["next_at"] = job.get("next_at", 0.0)
	_queue.append(job)
	if job.get("durable", false): _save_queue()
	_pump()

func _process(_dt: float) -> void:
	if on_aeon and _state_path != "" and Time.get_ticks_msec() >= _state_next_poll:
		_state_next_poll = Time.get_ticks_msec() + 100
		_poll_state(true)
	if on_aeon and not _busy and not _queue.is_empty():
		_pump()

# ---------------- console events (AEON_STATE) ----------------

# The file is a few bytes; reading it ten times a second costs nothing, and its "seq" catches two changes
# inside one second where a modification time (seconds) would not.
func _poll_state(emit: bool) -> void:
	var f := FileAccess.open(_state_path, FileAccess.READ)
	if f == null: return
	var d = JSON.parse_string(f.get_as_text())
	f.close()
	if not (d is Dictionary): return
	var seq: int = int(d.get("seq", 0))
	if seq == _state_seq: return
	_state_seq = seq
	var guide: bool = bool(d.get("guide", false))
	var resumes: int = int(d.get("resumes", _resumes))
	if emit:
		if resumes != _resumes:
			suspended.emit()
			resumed.emit()
		if guide != _guide_open:
			if guide: guide_opened.emit()
			else: guide_closed.emit()
	_guide_open = guide
	_resumes = resumes

func _pump() -> void:
	if _busy or _queue.is_empty(): return
	var now := Time.get_unix_time_from_system()
	for j in _queue:
		if j.next_at <= now:
			_busy = true
			_current = j
			var headers := PackedStringArray(["Authorization: Bearer " + _token, "Content-Type: application/json", "User-Agent: aeon-godot/" + SDK_VERSION])
			var err := _http.request(_api + j.path, headers, j.method, j.body)
			if err != OK:
				_busy = false
				_retry(j)
			return

var _current: Dictionary = {}

func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var j := _current
	_current = {}
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS or code == 0:
		_retry(j)
		return
	_queue.erase(j)
	if j.get("durable", false): _save_queue()
	if code >= 500:
		j.tries += 1
		if j.tries <= 5:
			j.next_at = Time.get_unix_time_from_system() + 5.0 * j.tries
			_queue.append(j)
		return
	var text := body.get_string_from_utf8()
	var data = JSON.parse_string(text) if text != "" else null
	match j.k:
		"me":
			if code == 200 and data is Dictionary:
				player["gamertag"] = data.get("gamertag", player["gamertag"])
				player["id"] = data.get("player_id", player["id"])
				var ac = data.get("avatar_color", "")
				if ac is String and ac.length() == 7: player["avatar_color"] = ac
				var bc = data.get("banner_color", "")
				if bc is String and bc.length() == 7: player["banner_color"] = bc
				player["avatar_url"] = String(data.get("avatar_url", ""))
				player["sandbox"] = bool(data.get("sandbox", false))
		"ent":
			if code == 200 and data is Dictionary:
				_owned.clear()
				for s in data.get("owned", []): _owned.append(String(s))
		"lb":
			var entries: Array = []
			var my_rank := 0
			var my_score := 0
			var has_me := false
			if code == 200 and data is Dictionary:
				entries = data.get("entries", [])
				if data.get("my_rank") != null:
					has_me = true
					my_rank = int(data.get("my_rank"))
					my_score = int(data.get("my_score", 0))
			leaderboard_received.emit(j.get("category", ""), entries, my_rank, my_score, has_me)
		"purchase":
			if code == 200 and data is Dictionary and data.get("status") == "completed":
				_enqueue({ "k": "ent", "path": "/sdk/entitlements", "method": HTTPClient.METHOD_GET, "body": "", "durable": false })   # 1.1.1: owns() turns true
				purchase_result.emit(j.get("sku", ""), true)
			elif code == 200 and data is Dictionary and data.has("id"):
				_enqueue({ "k": "purchase_poll", "path": "/sdk/purchase/%s" % data["id"], "method": HTTPClient.METHOD_GET,
					"body": "", "durable": false, "sku": j.get("sku", ""), "next_at": Time.get_unix_time_from_system() + 2.0 })
			else:
				purchase_result.emit(j.get("sku", ""), false)
		"purchase_poll":
			var st = data.get("status", "") if data is Dictionary else ""
			if st == "pending" and j.tries < 300:
				j.tries += 1
				j.next_at = Time.get_unix_time_from_system() + 2.0
				_queue.append(j)
			else:
				if st == "completed":
					_enqueue({ "k": "ent", "path": "/sdk/entitlements", "method": HTTPClient.METHOD_GET, "body": "", "durable": false })   # 1.1.1
				purchase_result.emit(j.get("sku", ""), st == "completed")
	_pump()

func _retry(j: Dictionary) -> void:
	j.tries += 1
	j.next_at = Time.get_unix_time_from_system() + (2.0 * j.tries if j.tries < 5 else 30.0)
	if not j.get("durable", false) and j.tries > 3:
		_queue.erase(j)   # presence / reads: give up quietly
		if j.k == "lb": leaderboard_received.emit(j.get("category", ""), [], 0, 0, false)
		if j.k == "purchase": purchase_result.emit(j.get("sku", ""), false)

func _save_queue() -> void:
	var f := FileAccess.open(_QUEUE_FILE, FileAccess.WRITE)
	if f == null: return
	for j in _queue:
		if j.get("durable", false):
			f.store_line(JSON.stringify({ "k": j.k, "path": j.path, "method": j.method, "body": j.body }))
	f.close()

func _load_queue() -> void:
	if not FileAccess.file_exists(_QUEUE_FILE): return
	var f := FileAccess.open(_QUEUE_FILE, FileAccess.READ)
	if f == null: return
	var n := 0
	while not f.eof_reached():
		var line := f.get_line()
		if line == "": continue
		var d = JSON.parse_string(line)
		if d is Dictionary:
			d["durable"] = true
			d["tries"] = 0
			d["next_at"] = 0.0
			_queue.append(d)
			n += 1
	f.close()
	if n > 0: print("[aeon] %d queued report(s) from a previous session" % n)
