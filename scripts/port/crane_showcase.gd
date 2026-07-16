@tool
class_name CraneShowcase
extends Node3D

## F6 bulk-quay vignette — ore yard, grab crane, docked bulk carrier.

const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")
const DOCKED_HULL_ID := "hull_90x24"

const QUAY_LENGTH_M := 140.0
const QUAY_WIDTH_M := 72.0
const QUAY_DECK_TOP_Y := 0.0
const QUAY_DECK_SLAB_H := 0.55
const CRANE_LANE_W := 22.0
const STORAGE_LANE_W := 28.0
const ROAD_W := 12.0
const DECK_COLOR := Color(0.133, 0.133, 0.133)
const PIER_MASS_COLOR := Color(0.18, 0.19, 0.20)

@export var orbit_yaw_deg := 35.0
@export var orbit_pitch_deg := -22.0
@export var orbit_distance := 72.0

var _crane: BulkCrane
var _camera: Camera3D
var _hud: Label
var _orbiting := false
var _orbit_yaw := 35.0
var _orbit_pitch := -22.0
var _focus_bucket := true
var _focus := Vector3(18.0, 8.0, 0.0)


func _ready() -> void:
	_orbit_yaw = orbit_yaw_deg
	_orbit_pitch = orbit_pitch_deg
	_ensure_environment()
	_ensure_camera()
	_ensure_hud()
	_spawn_quay_scene()
	_spawn_crane()
	_spawn_docked_ship()
	_ensure_scale_human()
	_focus_on_bucket()
	_update_camera()
	_refresh_hud()


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _crane != null:
		_crane.playtest_input(delta)
		if _focus_bucket:
			_track_bucket_focus()
			_update_camera()
	_refresh_hud()


func _unhandled_input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_HOME:
				_focus_bucket = false
				_orbit_yaw = orbit_yaw_deg
				_orbit_pitch = orbit_pitch_deg
				orbit_distance = 72.0
				_focus = Vector3(12.0, 8.0, 0.0)
				_update_camera()
			KEY_B:
				_focus_on_bucket()
				_update_camera()
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			orbit_distance = clampf(orbit_distance * 0.9, 3.0, 120.0)
			_update_camera()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			orbit_distance = clampf(orbit_distance * 1.1, 3.0, 120.0)
			_update_camera()
	if event is InputEventMouseMotion and _orbiting:
		var mm := event as InputEventMouseMotion
		_orbit_yaw -= mm.relative.x * 0.25
		_orbit_pitch = clampf(_orbit_pitch - mm.relative.y * 0.25, -80.0, 20.0)
		_update_camera()


func _focus_on_bucket() -> void:
	_focus_bucket = true
	orbit_distance = 9.0
	_orbit_yaw = 40.0
	_orbit_pitch = -18.0
	_track_bucket_focus()


func _track_bucket_focus() -> void:
	if _crane == null:
		return
	var bucket := _crane.get_bucket()
	if bucket == null or not is_instance_valid(bucket):
		_focus = Vector3(22.0, 8.0, -6.0)
		return
	_focus = bucket.global_position + Vector3(0.0, -1.0, 0.0)


func _update_camera() -> void:
	if _camera == null:
		return
	var yaw := deg_to_rad(_orbit_yaw)
	var pitch := deg_to_rad(_orbit_pitch)
	var offset := Vector3(
		orbit_distance * cos(pitch) * sin(yaw),
		orbit_distance * sin(pitch) * -1.0,
		orbit_distance * cos(pitch) * cos(yaw),
	)
	_camera.global_position = _focus + offset
	_camera.look_at(_focus, Vector3.UP)


func _refresh_hud() -> void:
	if _hud == null:
		return
	var mode := "BUCKET FOCUS" if _focus_bucket else "quay overview"
	var lines: PackedStringArray = PackedStringArray([
		"CRANE SHOWCASE — %s" % mode,
		"quay · ore mounds · grab crane · docked %s" % DOCKED_HULL_ID,
		"B  bucket focus · Home  overview",
		"A D  slew · W S  boom · Q E  hoist · Space  jaws · RMB orbit",
		"Lower open bucket into mound to load · close jaws to dump",
		"",
	])
	if _crane != null:
		lines.append_array(_crane.get_status_lines())
	_hud.text = "\n".join(lines)


func _spawn_quay_scene() -> void:
	if get_node_or_null("QuayScene") != null:
		return
	var root := Node3D.new()
	root.name = "QuayScene"
	add_child(root)
	_stamp_quay_pier(root)
	_stamp_ore_yard(root)


func _stamp_quay_pier(parent: Node3D) -> void:
	var pier := Node3D.new()
	pier.name = "QuayPier"
	parent.add_child(pier)

	var half_w := QUAY_WIDTH_M * 0.5
	var water_bottom := WaveSurface.WATER_LEVEL - 3.0
	var pier_h := QUAY_DECK_TOP_Y - water_bottom
	var pier_center_y := QUAY_DECK_TOP_Y - pier_h * 0.5

	var mass := MeshBuilder.box(
		Vector3(QUAY_WIDTH_M, pier_h, QUAY_LENGTH_M),
		PIER_MASS_COLOR,
		0.95,
		0.0,
	)
	mass.name = "PierMass"
	mass.position = Vector3(0.0, pier_center_y, 0.0)
	mass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pier.add_child(mass)

	var deck := MeshBuilder.box(
		Vector3(QUAY_WIDTH_M, QUAY_DECK_SLAB_H, QUAY_LENGTH_M),
		DECK_COLOR.lightened(0.04),
		1.0,
		0.0,
	)
	deck.name = "Deck"
	deck.position = Vector3(
		0.0,
		QUAY_DECK_TOP_Y - QUAY_DECK_SLAB_H * 0.5,
		0.0,
	)
	deck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pier.add_child(deck)

	var coping := MeshBuilder.box(
		Vector3(1.2, 0.7, QUAY_LENGTH_M * 0.96),
		Color(0.55, 0.56, 0.58),
		0.9,
		0.05,
	)
	coping.name = "BerthEdge"
	coping.position = Vector3(half_w - 0.6, QUAY_DECK_TOP_Y + 0.05, 0.0)
	pier.add_child(coping)

	var road := MeshBuilder.box(
		Vector3(ROAD_W, 0.22, QUAY_LENGTH_M * 0.92),
		Color(0.07, 0.07, 0.08),
		1.0,
		0.0,
	)
	road.name = "Road"
	var storage_x := -(half_w - STORAGE_LANE_W * 0.5)
	var crane_x := half_w - CRANE_LANE_W * 0.5
	road.position = Vector3(
		(storage_x + crane_x) * 0.5,
		QUAY_DECK_TOP_Y - 0.05,
		0.0,
	)
	pier.add_child(road)


func _stamp_ore_yard(parent: Node3D) -> void:
	var yard := Node3D.new()
	yard.name = "OreYard"
	parent.add_child(yard)

	var half_w := QUAY_WIDTH_M * 0.5
	var lane_x := -(half_w - STORAGE_LANE_W * 0.5)
	var ore_color := CommodityCatalog.commodity_color("iron_ore")
	var apron := MeshBuilder.box(
		Vector3(STORAGE_LANE_W * 0.96, 0.22, QUAY_LENGTH_M * 0.88),
		ore_color,
		0.9,
		0.0,
	)
	apron.name = "OreApron"
	apron.position = Vector3(lane_x, QUAY_DECK_TOP_Y + 0.02, 0.0)
	yard.add_child(apron)

	var stripe := MeshBuilder.box(
		Vector3(1.1, 0.85, QUAY_LENGTH_M * 0.9),
		ore_color.lightened(0.12),
		0.75,
		0.05,
	)
	stripe.name = "OreStripe"
	stripe.position = Vector3(-(half_w - 0.55), QUAY_DECK_TOP_Y + 0.08, 0.0)
	yard.add_child(stripe)

	var mound_z := [-42.0, -18.0, 8.0, 32.0]
	for index in range(mound_z.size()):
		var mound := OreMound.create(
			"iron_ore",
			Vector3(STORAGE_LANE_W * 0.82, 6.5, 18.0),
			index + 1,
		)
		mound.name = "OreMound_%d" % index
		mound.position = Vector3(lane_x, QUAY_DECK_TOP_Y, float(mound_z[index]))
		yard.add_child(mound)


func _crane_mount_position() -> Vector3:
	var half_w := QUAY_WIDTH_M * 0.5
	var crane_x := half_w - CRANE_LANE_W * 0.5
	return Vector3(crane_x, QUAY_DECK_TOP_Y, 0.0)


func _spawn_crane() -> void:
	if _crane != null and is_instance_valid(_crane):
		_crane.queue_free()
		_crane = null
	var quay := get_node_or_null("QuayScene") as Node3D
	if quay == null:
		return
	var mount := Node3D.new()
	mount.name = "CraneMount"
	mount.position = _crane_mount_position()
	quay.add_child(mount)
	_crane = BULK_CRANE_SCRIPT.new() as BulkCrane
	_crane.name = "BulkCrane"
	## Match port quay rigs: boom reaches seaward (+X) toward the ship.
	_crane.rotation_degrees.y = -90.0
	mount.add_child(_crane)
	call_deferred("_pose_crane")


func _pose_crane() -> void:
	if _crane == null:
		return
	_crane.boom_angle_deg = 42.0
	_crane.hoist_length_m = 18.0
	_crane.bucket_open = 0.0
	_crane.set("_bucket_open_target", 0.0)


func _spawn_docked_ship() -> void:
	if get_node_or_null("QuayScene/DockedShip") != null:
		return
	var quay := get_node_or_null("QuayScene") as Node3D
	if quay == null:
		return
	var entry := HullRegistry.get_by_id(DOCKED_HULL_ID)
	var beam_m := float(entry.get("beam_m", 24.0))
	var half_w := QUAY_WIDTH_M * 0.5
	var ship := HullRegistry.build_hull(DOCKED_HULL_ID)
	if ship == null:
		push_warning("CraneShowcase: failed to build hull %s" % DOCKED_HULL_ID)
		return
	ship.name = "DockedShip"
	ship.freeze = true
	quay.add_child(ship)
	## Bow −Z, stern +Z; port (−X) faces the quay coping on +X.
	ship.position = Vector3(half_w + beam_m * 0.5 + 4.0, 0.0, 0.0)
	ship.rotation_degrees.y = 0.0
	call_deferred("_place_docked_ship", ship)


func _place_docked_ship(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	ship.place_at_waterline(WaveSurface.WATER_LEVEL)
	ship.freeze = true


func _ensure_environment() -> void:
	if get_node_or_null("WorldEnvironment") != null:
		return
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.62, 0.78)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)
	env.ambient_light_energy = 0.55
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	add_child(sun)


func _ensure_camera() -> void:
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera == null:
		_camera = Camera3D.new()
		_camera.name = "Camera3D"
		add_child(_camera)
	_camera.current = true
	_camera.fov = 55.0


func _ensure_scale_human() -> void:
	if get_node_or_null("ScaleHuman") != null:
		return
	var human := NpcBase.new()
	human.name = "ScaleHuman"
	human.position = Vector3(-28.0, QUAY_DECK_TOP_Y, 48.0)
	add_child(human)
	var lbl := Label3D.new()
	lbl.name = "ScaleLabel"
	lbl.text = "1.8 m"
	lbl.font_size = 48
	lbl.pixel_size = 0.006
	lbl.position = Vector3(-28.0, QUAY_DECK_TOP_Y + 2.15, 48.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(0.95, 0.8, 0.3)
	lbl.outline_size = 8
	add_child(lbl)


func _ensure_hud() -> void:
	if get_node_or_null("HUD") != null:
		_hud = get_node("HUD/Panel/Label") as Label
		return
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16, 16)
	panel.custom_minimum_size = Vector2(420, 0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)
	_hud = Label.new()
	_hud.name = "Label"
	_hud.add_theme_font_size_override("font_size", 14)
	margin.add_child(_hud)
