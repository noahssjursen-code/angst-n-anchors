extends Node3D

const Lod = preload("res://scripts/network/remote_vessel_lod.gd")
var _rings: Array[Dictionary] = []
var _legend: Label
var _policy: Dictionary = {}
var _server := ""
var _pending := false
var _retry_at := 0
var _elapsed := 0.0

func _ready() -> void:
	name = "NetworkRangeGizmo"
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	_legend = Label.new()
	_legend.position = Vector2(20, 100)
	_legend.add_theme_color_override("font_color", Color.WHITE)
	_legend.add_theme_color_override("font_outline_color", Color.BLACK)
	_legend.add_theme_constant_override("outline_size", 5)
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_legend)
	WorldGizmos.register(self, WorldGizmos.LAYER_NETWORK)
	_rebuild()

func _process(delta: float) -> void:
	_legend.visible = visible
	if not visible: return
	_elapsed += delta
	if _elapsed < 0.1: return
	_elapsed = 0.0
	var ship := LocalPlayerView.get_active_ship() as Node3D
	var boat_pos := ship.global_position if is_instance_valid(ship) else WorldReference.gameplay_position()
	var observer := WorldReference.stream_position(get_viewport())
	position_rings(boat_pos, observer)
	var remote := WorldGateway.is_remote()
	if remote:
		var url := str(ServerConfig.get_http_base_url())
		if url != _server:
			_server = url
			_policy.clear()
			_retry_at = 0
			_rebuild()
		if _policy.is_empty() and not _pending and Time.get_ticks_msec() >= _retry_at: _fetch_policy(url)
	elif not _policy.is_empty():
		_policy.clear()
		_server = ""
		_rebuild()
	var timeout := float(NetworkManager.entity_timeout_ms) / 1000.0
	_legend.text = "VESSEL LOD / NETWORK RANGE\nCyan: simplified model beyond %.0f m · full model returns below %.0f m\nCyan rings centre on your boat (distance guide); LOD follows the camera.\nCamera offset from boat: %.0f m · nearby passengers keep full detail." % [Lod.FAR_M, Lod.NEAR_M, observer.distance_to(boat_pos)]
	if not remote:
		_legend.text += "\nSingle player — no multiplayer interest boundary."
	elif _policy.is_empty():
		_legend.text += "\nServer range policy unavailable — no guessed network rings."
	else:
		_legend.text += "\nObserver-centred network rings (moving ship target cadence):"
		for i in _policy.ship_bands_m.size():
			_legend.text += "\n  %.0f m: %.0f ms" % [float(_policy.ship_bands_m[i]), float(_policy.intervals_ms[i])]
		_legend.text += "\nPurple: players %.0f m · red: ships %.0f m stop receiving updates.\nUnseen replicas expire after %.0f s without updates; stationary updates may be slower." % [float(_policy.player_range_m), float(_policy.ship_range_m), timeout]

func position_rings(boat_pos: Vector3, observer: Vector3) -> void:
	for ring: Dictionary in _rings:
		var centre: Vector3 = observer if ring.network else boat_pos
		# Horizontal intersection of the real 3D interest sphere.
		var height := centre.y - boat_pos.y
		var radius := sqrt(maxf(0.0, float(ring.radius) * float(ring.radius) - height * height)) if ring.network else float(ring.radius)
		var node: Node3D = ring.node
		node.visible = radius > 0.0
		node.position = Vector3(centre.x, boat_pos.y + 1.0, centre.z)
		node.scale = Vector3(maxf(radius, 0.001), 1.0, maxf(radius, 0.001))
		var label: Label3D = ring.label
		label.visible = node.visible
		label.position = node.position + Vector3(radius * 0.707, 3, radius * (-0.707 if ring.network else 0.707))

func _fetch_policy(url: String) -> void:
	_pending = true
	_retry_at = Time.get_ticks_msec() + 10000
	var request := HTTPRequest.new()
	request.timeout = 5.0
	add_child(request)
	var error := request.request(url.trim_suffix("/") + "/v1/network-policy")
	if error == OK:
		var response: Array = await request.request_completed
		if int(response[1]) == 200 and url == _server:
			var parsed: Variant = JSON.parse_string((response[3] as PackedByteArray).get_string_from_utf8())
			if parsed is Dictionary and parsed.get("ship_bands_m", []) is Array and parsed.get("intervals_ms", []) is Array and parsed.get("ship_bands_m", []).size() == 4 and parsed.get("intervals_ms", []).size() == 4 and parsed.has("ship_range_m") and parsed.has("player_range_m"):
				_policy = parsed
				_rebuild()
	request.queue_free()
	_pending = false

func _rebuild() -> void:
	for ring: Dictionary in _rings:
		ring.node.queue_free()
		ring.label.queue_free()
	_rings.clear()
	_add_ring(Lod.FAR_M, Color.CYAN, false, false)
	_add_ring(Lod.NEAR_M, Color(0.2, 0.6, 0.7), false, true)
	if _policy.is_empty(): return
	for distance in _policy.ship_bands_m:
		if is_equal_approx(float(distance), float(_policy.ship_range_m)): continue
		_add_ring(float(distance), Color(1.0, 0.7, 0.15), true, true)
	_add_ring(float(_policy.ship_range_m), Color(1.0, 0.2, 0.2), true, false)
	_add_ring(float(_policy.player_range_m), Color(0.8, 0.3, 1.0), true, true)

func _add_ring(radius: float, color: Color, network: bool, dashed: bool) -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = color
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for i in 256:
		if dashed and i % 4 >= 2: continue
		for index in [i, i + 1]:
			var angle := TAU * float(index) / 256.0
			mesh.surface_add_vertex(Vector3(cos(angle), 0, sin(angle)))
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	var label := Label3D.new()
	label.text = ("Network" if network else ("Distant model" if radius == Lod.FAR_M else "Full model")) + " · %.0f m" % radius
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.no_depth_test = true
	label.font_size = 28
	label.pixel_size = 0.0015
	add_child(label)
	_rings.append({"node": instance, "label": label, "radius": radius, "network": network})
