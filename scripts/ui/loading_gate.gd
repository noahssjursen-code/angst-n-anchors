extends CanvasLayer

## Autoload — register as "LoadingGate".
## Full-screen overlay that stays up until World finishes booting
## (layout, ports, player spawn) or a non-world destination settles.

const WORLD_SCENE := "res://scenes/world.tscn"
const BRAND_MARK := preload("res://resources/ui/brand/anchor-mark-paper.svg")
const MIN_DISPLAY_S := 0.4
const WORLD_FALLBACK_S := 90.0
const TITLE_FALLBACK_S := 2.5

var pending_scene_path: String = ""
var status_hint: String = "Loading…"

var _root: Control
var _status: Label
var _detail: Label
var _elapsed := 0.0
var _active := false
var _waiting_for_world := false
var _world_boot_done := false
var _connected_world: Node = null


func _ready() -> void:
	layer = 80
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build_ui()
	set_process(false)
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)


func begin(scene_path: String, status: String = "Loading…") -> void:
	_disconnect_world()
	pending_scene_path = scene_path
	status_hint = status if not status.is_empty() else "Loading…"
	_elapsed = 0.0
	_active = true
	_waiting_for_world = scene_path == WORLD_SCENE
	_world_boot_done = false
	visible = true
	_status.text = status_hint
	_detail.text = "Charting the coast…"
	set_process(true)
	get_tree().change_scene_to_file(scene_path)


static func go_to(tree: SceneTree, scene_path: String, status: String = "Loading…") -> void:
	var gate := tree.root.get_node_or_null("LoadingGate")
	if gate == null:
		tree.change_scene_to_file(scene_path)
		return
	gate.begin(scene_path, status)


func notify_world_ready() -> void:
	if _waiting_for_world:
		_world_boot_done = true
		_detail.text = "Harbour ready"


func set_detail(text: String) -> void:
	if _detail != null and not text.is_empty():
		_detail.text = text


func _process(delta: float) -> void:
	if not _active:
		return
	_elapsed += delta
	_refresh_detail()
	_try_bind_world()
	if _waiting_for_world:
		if _elapsed >= MIN_DISPLAY_S and (_world_boot_done or _elapsed >= WORLD_FALLBACK_S):
			_finish()
	elif _elapsed >= MIN_DISPLAY_S:
		_finish()
	elif not _waiting_for_world and _elapsed >= TITLE_FALLBACK_S:
		_finish()


func _finish() -> void:
	_disconnect_world()
	_active = false
	_waiting_for_world = false
	_world_boot_done = false
	visible = false
	set_process(false)
	pending_scene_path = ""


func _on_node_added(node: Node) -> void:
	if not _active or not _waiting_for_world:
		return
	if node is World or (node.get_script() != null and node.has_signal("boot_finished")):
		_bind_world(node)


func _try_bind_world() -> void:
	if not _waiting_for_world or _connected_world != null:
		return
	var scene := get_tree().current_scene
	if scene != null and (scene is World or scene.has_signal("boot_finished")):
		_bind_world(scene)


func _bind_world(world: Node) -> void:
	if world == null or _connected_world == world:
		return
	_disconnect_world()
	_connected_world = world
	if world.has_signal("boot_finished"):
		if not world.boot_finished.is_connected(_on_world_boot_finished):
			world.boot_finished.connect(_on_world_boot_finished)
	_detail.text = "Generating waters…"


func _on_world_boot_finished() -> void:
	notify_world_ready()


func _disconnect_world() -> void:
	if _connected_world != null and is_instance_valid(_connected_world):
		if _connected_world.has_signal("boot_finished") \
				and _connected_world.boot_finished.is_connected(_on_world_boot_finished):
			_connected_world.boot_finished.disconnect(_on_world_boot_finished)
	_connected_world = null


func _refresh_detail() -> void:
	if _world_boot_done:
		return
	var streamer := get_tree().get_first_node_in_group("world_terrain_streamer")
	if streamer != null and streamer.has_method("is_boot_priority") and bool(streamer.call("is_boot_priority")):
		var focus := streamer.call("boot_focus") as Vector3 if streamer.has_method("boot_focus") else Vector3.ZERO
		var near_pending := 0
		if streamer.has_method("pending_near"):
			near_pending = int(streamer.call("pending_near", focus))
		if near_pending > 0:
			_detail.text = "Raising the land… %d nearby" % near_pending
		else:
			_detail.text = "Raising the land…"
		return
	if streamer != null and streamer.has_method("pending_near"):
		var cam := get_viewport().get_camera_3d()
		var focus := cam.global_position if cam != null else Vector3.ZERO
		var near_pending := int(streamer.call("pending_near", focus))
		if near_pending > 0:
			_detail.text = "Raising the land… %d nearby" % near_pending
			return
		if streamer.has_method("get_debug_stats"):
			var pending := int(streamer.get_debug_stats().get("pending", 0))
			if pending > 0:
				_detail.text = "Raising the land… %d chunks" % pending
				return
	var telemetry := get_node_or_null("/root/Telemetry")
	if telemetry == null:
		return
	# Prefer in-flight load timers over completed events (completed ones like
	# port.load:* · 0ms are historical and look "stuck" on the gate).
	if telemetry.has_method("active_load_event_names"):
		var active: PackedStringArray = telemetry.call("active_load_event_names")
		if not active.is_empty():
			_detail.text = "%s…" % active[0]
			return
	if telemetry.load_events.is_empty():
		return
	var last: Variant = telemetry.load_events[telemetry.load_events.size() - 1]
	if typeof(last) != TYPE_DICTIONARY:
		return
	var event := last as Dictionary
	var name := str(event.get("name", ""))
	if name.is_empty():
		return
	_detail.text = "%s…" % name


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = BrandTheme.shared()
	add_child(_root)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = BrandTokens.SEA_DEEP
	_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.custom_minimum_size = Vector2(520, 0)
	center.add_child(vbox)

	var mark := TextureRect.new()
	mark.texture = BRAND_MARK
	mark.custom_minimum_size = Vector2(84.0, 84.0)
	mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	vbox.add_child(mark)

	var title := BrandLabel.new("ANGST 'N ANCHORS", BrandLabel.Role.DISPLAY_LARGE)
	title.text = "ANGST 'N ANCHORS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE)
	vbox.add_child(title)

	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(180, BrandTokens.RULE_WIDTH)
	rule.color = BrandTokens.BRASS
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(rule)

	_status = BrandLabel.new("", BrandLabel.Role.INVERSE_DATA)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_color_override(&"font_color", BrandTokens.BRASS)
	vbox.add_child(_status)

	_detail = BrandLabel.new("", BrandLabel.Role.INVERSE_BODY)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.add_theme_color_override(&"font_color", BrandTokens.INK_INVERSE_DIM)
	vbox.add_child(_detail)
