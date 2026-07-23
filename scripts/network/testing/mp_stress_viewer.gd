extends Node3D

## Live stress-test viewer. Joins the deployed server as one real observer
## client and renders every replicated entity in its area of interest as a
## simple marker — captains as capsules, ships as boxes — so server-driven
## crowds are visible on screen while `cmd/stressbot` (in the Go repo) drives
## the load.
##
## Running the scene (F6) is all that is needed: after connecting it launches
## the prebuilt bot swarm (`stressbot.exe` in the sibling server repo) as a
## background process and winds it down gracefully when the scene closes.
##
## Controls:
##   WASD          move the observer (this moves the server-side AOI focus)
##   Mouse wheel   zoom
##   1 / 2 / 3     teleport: stress hotspot / spread clusters / empty ocean
##   B             stop / restart the bot swarm
##   Shift         fast movement
##
## HUD shows client-observed truth: visible entities, snapshot rate, downlink
## bandwidth, and per-entity update staleness percentiles, plus the server's
## active session count. Headless runs print the same stats to stdout and quit
## after `--stress-view-seconds=N` (default 30) for scripted probing.

const VirtualClientScript = preload("res://scripts/network/testing/virtual_client.gd")

const DEFAULT_HTTP := "http://142.93.43.16:8080"
const DEFAULT_UDP_HOST := "142.93.43.16"
const UDP_PORT := 7777
const PASSWORD := "mp-harness-password-1"

## Must match the stressbot defaults (cmd/stressbot in the server repo).
const HOTSPOT_CENTER := Vector3(37600.0, 1.0, 37600.0)
const SPREAD_ORIGIN := Vector3(30000.0, 1.0, 30000.0)
const EMPTY_OCEAN := Vector3(20000.0, 1.0, 12000.0)

const STALE_DROP_S := 5.0

## Crowd swarm: one busy harbour + background world (~160 bots).
const CROWD_ARGS: Array[String] = [
	"-hotspot", "100", "-spread", "40", "-ships", "20", "-duration", "30m",
]
## AOI ruler swarm: one tight cohort of captains that starts close to the pin
## and is pushed outward/pulled back with the arrow keys (they glide at boat
## speed), so the SAME group is observed at every distance. Two far ships show
## the ship-range contrast. The rings from _build_aoi_rings are the ruler.
const COHORT_SIZE := 24
const RULER_ARGS: Array[String] = [
	"-cohort", "24", "-ring-ships", "2", "-duration", "30m",
]
## Server-truth cadence bands for players (see internal/aoi/cadence.go):
## [outer radius, ring color, label]
const RING_DEFS: Array = [
	[40.0, Color(0.25, 0.85, 0.35), "40 m · updates every 50 ms"],
	[150.0, Color(0.85, 0.85, 0.25), "150 m · every 100 ms"],
	[500.0, Color(0.95, 0.55, 0.15), "500 m · every 250 ms"],
	[1000.0, Color(0.9, 0.2, 0.25), "1000 m · every 1 s — player AOI ends"],
	[1200.0, Color(0.45, 0.45, 0.5), "1200 m · beyond AOI — players invisible"],
]

var _observer: MpVirtualClient
var _bot_pid := -1
var _bot_status := "swarm: off"
var _swarm_mode := "ruler" ## "ruler" | "crowd"
var _extrapolate := false
var _tracks: Dictionary = {} ## entity id -> {"pos": Vector3, "at_ms": int, "vel": Vector3}
var _use_local_server := false
var _cohort_target := 60.0
var _cohort_written := 60.0
var _cohort_last_write_ms := 0
var _markers: Dictionary = {} ## entity id -> {"node": Node3D, "type": String}
var _camera: Camera3D
var _hud: RichTextLabel
var _status_line := "connecting…"
var _server_info := "server: —"
var _cam_height := 320.0
var _last_rx_packets := 0
var _last_rx_bytes := 0
var _last_snapshots := 0
var _last_rate_ms := 0
var _rates := {"pps": 0.0, "kbps": 0.0, "snaps": 0.0}
var _server_poll_accum := 0.0
var _headless_deadline_ms := -1
var _player_material: StandardMaterial3D
var _ship_material: StandardMaterial3D


func _ready() -> void:
	_build_world()
	_build_hud()
	call_deferred("_connect")


func _connect() -> void:
	var http_base := DEFAULT_HTTP
	var udp_host := DEFAULT_UDP_HOST
	var view_seconds := 30
	var headless_autostart := false
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "--mp-server=local":
			http_base = "http://127.0.0.1:8080"
			udp_host = "127.0.0.1"
			_use_local_server = true
		elif text.begins_with("--stress-view-seconds="):
			view_seconds = maxi(5, int(text.get_slice("=", 1)))
		elif text == "--stress-autostart":
			headless_autostart = true
	var headless := DisplayServer.get_name() == "headless"
	if headless:
		_headless_deadline_ms = Time.get_ticks_msec() + view_seconds * 1000

	_observer = VirtualClientScript.new()
	_observer.name = "Observer"
	_observer.setup("stress-viewer", http_base, udp_host, UDP_PORT)
	add_child(_observer)

	var auth: Dictionary = await _observer.login_or_register("mp-test-observer@harness.local", PASSWORD)
	if not bool(auth.get("ok")):
		_status_line = "AUTH FAILED: %s" % auth.get("message")
		return
	var cap: Dictionary = await _observer.ensure_captain("MP Test Observer")
	if not bool(cap.get("ok")):
		_status_line = "CAPTAIN FAILED: %s" % cap.get("message")
		return
	var opened: Dictionary = await _observer.open_world_session("stress-viewer")
	if not bool(opened.get("ok")):
		_status_line = "SESSION FAILED: %s" % opened.get("message")
		return
	var udp: Dictionary = _observer.udp_start()
	if not bool(udp.get("ok")):
		_status_line = "UDP FAILED: %s" % udp.get("message")
		return
	_observer.set_avatar(HOTSPOT_CENTER + Vector3(0, 0, 20))
	_status_line = "connected — observing hotspot"
	if not headless or headless_autostart:
		_start_bots()


func _process(delta: float) -> void:
	if _observer == null or not _observer.is_session_ready():
		_update_hud()
		return
	_handle_movement(delta)
	_sync_markers(delta)
	_update_rates()
	_server_poll_accum += delta
	if _server_poll_accum >= 3.0:
		_server_poll_accum = 0.0
		_poll_server()
	_update_hud()
	if _headless_deadline_ms > 0 and Time.get_ticks_msec() >= _headless_deadline_ms:
		_headless_deadline_ms = -1
		print(_stats_text(true))
		_stop_bots()
		_observer.close_session()
		get_tree().quit(0)


func _stressbot_exe_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join(
		"../angst-n-anchors-mp/stressbot.exe"
	).simplify_path()


func _stop_flag_path() -> String:
	return OS.get_user_data_dir().path_join("stressbot_stop_flag")


func _command_file_path() -> String:
	return OS.get_user_data_dir().path_join("stressbot_command")


## Writes the cohort distance to the command file the bot process polls.
## Throttled: at most one write per 300 ms and only on meaningful change.
func _flush_cohort_command() -> void:
	if _bot_pid <= 0:
		return
	var now := Time.get_ticks_msec()
	if absf(_cohort_target - _cohort_written) < 5.0 or now - _cohort_last_write_ms < 300:
		return
	var file := FileAccess.open(_command_file_path(), FileAccess.WRITE)
	if file == null:
		return
	file.store_string("distance %.0f" % _cohort_target)
	file.close()
	_cohort_written = _cohort_target
	_cohort_last_write_ms = now


func _start_bots() -> void:
	if _bot_pid > 0:
		return
	var exe := _stressbot_exe_path()
	if not FileAccess.file_exists(exe):
		_bot_status = "swarm: MISSING %s" % exe
		return
	if FileAccess.file_exists(_stop_flag_path()):
		DirAccess.remove_absolute(_stop_flag_path())
	var args: Array[String] = (RULER_ARGS if _swarm_mode == "ruler" else CROWD_ARGS).duplicate()
	args.append_array(["-stop-file", _stop_flag_path()])
	if _swarm_mode == "ruler":
		args.append_array(["-command-file", _command_file_path()])
		_cohort_target = 60.0
		_cohort_written = 60.0
	if _use_local_server:
		args.append_array(["-server", "http://127.0.0.1:8080", "-udp", "127.0.0.1:7777"])
	_bot_pid = OS.create_process(exe, args)
	if _bot_pid <= 0:
		_bot_status = "swarm: LAUNCH FAILED"
	else:
		_bot_status = "swarm[%s]: starting — captains appear in ~15 s (pid %d)" % [_swarm_mode, _bot_pid]


func _stop_bots() -> void:
	if _bot_pid <= 0:
		return
	var flag := FileAccess.open(_stop_flag_path(), FileAccess.WRITE)
	if flag != null:
		flag.store_string("stop")
		flag.close()
	_bot_pid = -1
	_bot_status = "swarm: stopping — bots log out over a few seconds"


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.is_pressed():
		var wheel := event as InputEventMouseButton
		if wheel.button_index == MOUSE_BUTTON_WHEEL_UP:
			_cam_height = maxf(25.0, _cam_height * 0.85)
		elif wheel.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_cam_height = minf(2400.0, _cam_height * 1.18)
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		match (event as InputEventKey).keycode:
			KEY_1:
				_teleport(HOTSPOT_CENTER, "hotspot")
			KEY_2:
				_teleport(SPREAD_ORIGIN, "spread clusters")
			KEY_3:
				_teleport(EMPTY_OCEAN, "empty ocean")
			KEY_B:
				if _bot_pid > 0:
					_stop_bots()
				else:
					_start_bots()
			KEY_R:
				_swarm_mode = "crowd" if _swarm_mode == "ruler" else "ruler"
				if _bot_pid > 0:
					_stop_bots()
					_bot_status = "swarm: switching to %s — old bots logging out…" % _swarm_mode
					## The old process needs to see the stop flag (1 s poll) and
					## finish its staggered logout before a new swarm starts.
					get_tree().create_timer(5.0).timeout.connect(_start_bots, CONNECT_ONE_SHOT)
				else:
					_bot_status = "swarm: off (mode → %s)" % _swarm_mode
			KEY_V:
				_extrapolate = not _extrapolate


func _teleport(pos: Vector3, label: String) -> void:
	_observer.set_avatar(pos + Vector3(0, 0, 20))
	for entity_id in _markers.keys():
		(_markers[entity_id] as Dictionary).get("node").queue_free()
	_markers.clear()
	_status_line = "connected — observing %s" % label


func _handle_movement(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.z -= 1
	if Input.is_key_pressed(KEY_S):
		direction.z += 1
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1
	if Input.is_key_pressed(KEY_D):
		direction.x += 1
	if direction != Vector3.ZERO:
		var speed := _cam_height * (3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_observer.set_avatar(_observer.observer_pos + direction.normalized() * speed * delta)
	## Arrow keys drive the COHORT's distance target: hold UP to send the group
	## sailing away from you through the rings, DOWN to call them back. The
	## bots glide toward the target at boat speed; you stay put.
	if _swarm_mode == "ruler":
		var push := 0.0
		if Input.is_key_pressed(KEY_UP):
			push += 1.0
		if Input.is_key_pressed(KEY_DOWN):
			push -= 1.0
		if push != 0.0:
			var rate := 300.0 if Input.is_key_pressed(KEY_SHIFT) else 80.0
			_cohort_target = clampf(_cohort_target + push * rate * delta, 30.0, 2600.0)
		_flush_cohort_command()
	var focus := _observer.observer_pos
	_camera.position = focus + Vector3(0, _cam_height, _cam_height * 0.45)
	_camera.look_at(focus, Vector3.FORWARD)


func _sync_markers(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for entity_id in _observer.snapshot_entities.keys():
		var info := _observer.snapshot_entities[entity_id] as Dictionary
		var last_seen := int(info.get("last_seen_ms", 0))
		var age_s := float(now - last_seen) / 1000.0
		var entity := info.get("entity", {}) as Dictionary
		var target: Vector3 = entity.get("pos", Vector3.ZERO)
		# Velocity tracking for the optional dead-reckoning view (V key).
		var track: Dictionary = _tracks.get(entity_id, {})
		if track.is_empty():
			_tracks[entity_id] = {"pos": target, "at_ms": last_seen, "vel": Vector3.ZERO}
		elif int(track.get("at_ms", 0)) != last_seen:
			var dt := float(last_seen - int(track.get("at_ms", 0))) / 1000.0
			if dt > 0.02:
				track["vel"] = (target - (track.get("pos") as Vector3)) / dt
			track["pos"] = target
			track["at_ms"] = last_seen
		if _extrapolate:
			var vel: Vector3 = (_tracks.get(entity_id, {}) as Dictionary).get("vel", Vector3.ZERO)
			target += vel * minf(age_s, 2.0)
		if age_s > STALE_DROP_S:
			if _markers.has(entity_id):
				(_markers[entity_id] as Dictionary).get("node").queue_free()
				_markers.erase(entity_id)
			_tracks.erase(entity_id)
			continue
		if not _markers.has(entity_id):
			_markers[entity_id] = {
				"node": _spawn_marker(str(entity.get("type", "")), str(entity_id)),
				"type": str(entity.get("type", "")),
			}
		var node := (_markers[entity_id] as Dictionary).get("node") as Node3D
		if node.position == Vector3.ZERO:
			node.position = target
		else:
			node.position = node.position.lerp(target, minf(1.0, 10.0 * delta))
	for entity_id in _markers.keys().duplicate():
		if not _observer.snapshot_entities.has(entity_id):
			(_markers[entity_id] as Dictionary).get("node").queue_free()
			_markers.erase(entity_id)


func _spawn_marker(entity_type: String, entity_id: String) -> Node3D:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	if entity_type.begins_with("ship_"):
		var box := BoxMesh.new()
		box.size = Vector3(24.0, 6.0, 90.0)
		mesh.mesh = box
		mesh.material_override = _ship_material
		mesh.position.y = 3.0
	else:
		var capsule := CapsuleMesh.new()
		capsule.radius = 0.8
		capsule.height = 3.6
		mesh.mesh = capsule
		mesh.material_override = _player_material
		mesh.position.y = 1.8
	root.add_child(mesh)
	var label := Label3D.new()
	label.text = entity_id.substr(0, 8)
	label.position.y = 5.0 if entity_type.begins_with("ship_") else 3.4
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 48
	label.modulate = Color(1, 1, 1, 0.8)
	root.add_child(label)
	add_child(root)
	return root


func _update_rates() -> void:
	var now := Time.get_ticks_msec()
	if _last_rate_ms == 0:
		_last_rate_ms = now
		return
	var elapsed := float(now - _last_rate_ms) / 1000.0
	if elapsed < 1.0:
		return
	_rates["pps"] = float(_observer.rx_packets - _last_rx_packets) / elapsed
	_rates["kbps"] = float(_observer.rx_bytes - _last_rx_bytes) / elapsed / 1024.0
	_rates["snaps"] = float(_observer.snapshot_count - _last_snapshots) / elapsed
	_last_rx_packets = _observer.rx_packets
	_last_rx_bytes = _observer.rx_bytes
	_last_snapshots = _observer.snapshot_count
	_last_rate_ms = now
	if _headless_deadline_ms > 0:
		print(_stats_text(false))


func _poll_server() -> void:
	var res: Dictionary = await _observer._http(HTTPClient.METHOD_GET, "/healthz", null, "")
	if bool(res.get("ok")):
		_server_info = "server sessions: %d" % int((res.get("payload", {}) as Dictionary).get("active_sessions", -1))
	else:
		_server_info = "server: unreachable"


func _staleness_percentiles() -> Dictionary:
	var now := Time.get_ticks_msec()
	var ages: Array[float] = []
	for entity_id in _markers.keys():
		var info: Dictionary = _observer.snapshot_entities.get(entity_id, {})
		if not info.is_empty():
			ages.append(float(now - int(info.get("last_seen_ms", now))) / 1000.0)
	if ages.is_empty():
		return {"p50": 0.0, "p95": 0.0}
	ages.sort()
	return {
		"p50": ages[ages.size() / 2],
		"p95": ages[mini(ages.size() - 1, int(float(ages.size()) * 0.95))],
	}


func _stats_text(final_line: bool) -> String:
	var players := 0
	var ships := 0
	for entity_id in _markers.keys():
		if str((_markers[entity_id] as Dictionary).get("type", "")).begins_with("ship_"):
			ships += 1
		else:
			players += 1
	var stale := _staleness_percentiles()
	var prefix := "[stress-viewer FINAL]" if final_line else "[stress-viewer]"
	return "%s visible players=%d ships=%d | rx %.0f pps %.1f KB/s snaps %.0f/s | staleness p50=%.2fs p95=%.2fs | %s" % [
		prefix, players, ships,
		float(_rates["pps"]), float(_rates["kbps"]), float(_rates["snaps"]),
		float(stale["p50"]), float(stale["p95"]), _server_info,
	]


func _update_hud() -> void:
	if _hud == null:
		return
	_hud.clear()
	_hud.append_text("[b]MP stress viewer[/b]  %s   [i]%s[/i]\n" % [_status_line, _bot_status])
	_hud.append_text("%s   render: %s\n" % [
		_stats_text(false),
		"[color=cyan]extrapolated (client-style)[/color]" if _extrapolate else "raw server truth",
	])
	var pos := _observer.observer_pos if _observer != null else Vector3.ZERO
	if _swarm_mode == "ruler":
		_hud.append_text("%s\n" % _cohort_text())
	_hud.append_text("observer (%.0f, %.0f)  zoom %.0f m   [1] hotspot  [2] spread  [3] ocean  [B] swarm  [R] ruler/crowd  [V] raw/extrap  WASD pan  ARROWS push/pull cohort (Shift = fast)\n" % [pos.x, pos.z, _cam_height])


## Cohort status: where you are sending the group, which cadence band that
## distance lands in (measured from YOUR position, since AOI is observer-
## centred), and how many of them the server still shows you.
func _cohort_text() -> String:
	var visible := 0
	var nearest := INF
	var farthest := 0.0
	var pos := _observer.observer_pos
	for entity_id in _markers.keys():
		var marker := _markers[entity_id] as Dictionary
		if str(marker.get("type", "")).begins_with("ship_"):
			continue
		visible += 1
		var node := marker.get("node") as Node3D
		var distance := Vector2(node.position.x - pos.x, node.position.z - pos.z).length()
		nearest = minf(nearest, distance)
		farthest = maxf(farthest, distance)
	var range_text := "—"
	if visible > 0:
		range_text = "%.0f–%.0f m from you" % [nearest, farthest]
	return "cohort target: %.0f m (band there: %s) · server shows you %d/%d captains (%s)" % [
		_cohort_target, _band_label(_cohort_target), visible, COHORT_SIZE, range_text,
	]


## Which update cadence the server gives an entity at this distance from you.
func _band_label(distance: float) -> String:
	if distance <= 40.0:
		return "50 ms"
	if distance <= 150.0:
		return "100 ms"
	if distance <= 500.0:
		return "250 ms"
	if distance <= 1000.0:
		return "1 s"
	return "beyond AOI — invisible"




func _build_world() -> void:
	_player_material = StandardMaterial3D.new()
	_player_material.albedo_color = Color(0.95, 0.62, 0.12)
	_ship_material = StandardMaterial3D.new()
	_ship_material.albedo_color = Color(0.25, 0.55, 0.9)

	var sea := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(50000, 50000)
	sea.mesh = plane
	var sea_material := StandardMaterial3D.new()
	sea_material.albedo_color = Color(0.09, 0.16, 0.22)
	sea.material_override = sea_material
	sea.position = Vector3(25000, -0.5, 25000)
	add_child(sea)

	for center in [HOTSPOT_CENTER, SPREAD_ORIGIN, EMPTY_OCEAN]:
		var pillar := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 2.0
		cylinder.bottom_radius = 2.0
		cylinder.height = 40.0
		pillar.mesh = cylinder
		var pillar_material := StandardMaterial3D.new()
		pillar_material.albedo_color = Color(0.8, 0.2, 0.3)
		pillar.material_override = pillar_material
		pillar.position = center + Vector3(0, 20, 0)
		add_child(pillar)
	_build_aoi_rings()


## Archery-board distance rings around the red hotspot pin, one per server
## cadence band, so orbiting ruler bots visualize update frequency by distance.
func _build_aoi_rings() -> void:
	for ring_variant in RING_DEFS:
		var radius := float(ring_variant[0])
		var color := ring_variant[1] as Color
		var text := str(ring_variant[2])
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		var thickness := maxf(1.0, radius * 0.006)
		torus.inner_radius = radius - thickness
		torus.outer_radius = radius + thickness
		torus.rings = 128
		ring.mesh = torus
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = color
		ring.material_override = material
		ring.position = HOTSPOT_CENTER + Vector3(0, 0.3, 0)
		add_child(ring)
		var label := Label3D.new()
		label.text = text
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 220
		label.modulate = color
		label.position = HOTSPOT_CENTER + Vector3(0, 8.0, -radius)
		add_child(label)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, 30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.04, 0.06, 0.09)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.55, 0.6)
	environment.ambient_light_energy = 0.7
	env.environment = environment
	add_child(env)

	_camera = Camera3D.new()
	_camera.far = 8000.0
	_camera.position = HOTSPOT_CENTER + Vector3(0, 120, 60)
	add_child(_camera)
	_camera.look_at(HOTSPOT_CENTER, Vector3.FORWARD)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := ColorRect.new()
	panel.color = Color(0.03, 0.05, 0.07, 0.75)
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, 92)
	layer.add_child(panel)
	_hud = RichTextLabel.new()
	_hud.bbcode_enabled = true
	_hud.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_hud.offset_left = 16.0
	_hud.offset_top = 8.0
	_hud.offset_right = -16.0
	_hud.offset_bottom = 92.0
	layer.add_child(_hud)


func _exit_tree() -> void:
	_stop_bots()
	if _observer != null:
		_observer.close_session()
