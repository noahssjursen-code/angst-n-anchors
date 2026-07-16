@tool
class_name CraneShowcase
extends Node3D

## F6 bulk-quay vignette — ore yard, grab crane, docked bulk carrier.

const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")
const BULK_CRANE_AUTO_SCRIPT := preload("res://scripts/port/bulk_crane_auto_operator.gd")
const BULK_EQUIP_JOB_SCRIPT := preload("res://scripts/port/bulk_crane_equipment_job.gd")
const CRANE_OPERATOR_SCRIPT := preload("res://scripts/port/crane_operator_npc.gd")
const DOCKED_PREBUILT_ID := "bulk_small"
const SHOWCASE_PORT_ID := "crane_showcase"
const SHOWCASE_BERTH_ID := "crane_showcase/ore_quay"

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
var _auto: BulkCraneAutoOperator
var _harbour: HarbourController
var _equip_id := ""
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
	_setup_harbour()
	_spawn_crane()
	_spawn_docked_ship()
	_ensure_scale_human()
	_focus_on_bucket()
	_update_camera()
	_refresh_hud()


func _exit_tree() -> void:
	if _harbour != null:
		_harbour.unregister_all()
		_harbour.deactivate()
		_harbour = null


var _hud_timer := 0.0


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if _crane != null:
		if _auto == null or not _auto.is_active():
			_crane.playtest_input(delta)
		if _focus_bucket:
			_track_bucket_focus()
			_update_camera()
	_hud_timer += delta
	if _hud_timer >= 0.12:
		_hud_timer = 0.0
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
			KEY_L:
				_start_auto_load()
			KEY_O:
				_start_auto_unload()
			KEY_X:
				_stop_auto()
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
		"quay · ore mounds · grab crane · docked %s" % _docked_vessel_label(),
		"B  bucket focus · Home  overview",
		"L  harbour load · O  harbour unload · X  stop  (via HarbourController)",
		"Talk to crane operator at the cabin  ·  A/D W/S Q/E Space · RMB orbit",
		"",
	])
	if _harbour != null:
		var snap := _harbour.snapshot()
		lines.append(
			"Harbour  berths %d  ships %d  jobs %d" % [
				(snap.get("berths", []) as Array).size(),
				(snap.get("ships", []) as Array).size(),
				(snap.get("jobs", []) as Array).size(),
			]
		)
		lines.append("")
	if _auto != null:
		lines.append(_auto.get_status_line())
		if _auto.is_active():
			lines.append("Ellipse  A=green pickup · B=orange drop · cyan=arc")
			lines.append("         yellow=aim on arc · pink=bucket · magenta=gap")
		lines.append("")
	if _crane != null:
		lines.append_array(_crane.get_status_lines())
	var ship := get_node_or_null("QuayScene/DockedShip") as BoatBody
	if ship != null:
		lines.append("")
		lines.append("Ship holds")
		for hold in ship.get_bulk_holds():
			var st := hold.get_state()
			if st.is_empty():
				lines.append(
					"  %s  empty / %.0f t" % [st.hold_id, st.capacity_tonnes_t]
				)
			else:
				lines.append(
					"  %s  %s %.1f / %.0f t" % [
						st.hold_id,
						st.commodity_id,
						st.filled_tonnes_t,
						st.capacity_tonnes_t,
					]
				)
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

	var body := StaticBody3D.new()
	body.name = "PierCollision"
	body.collision_layer = 1
	body.collision_mask = 0
	pier.add_child(body)
	var shape := BoxShape3D.new()
	shape.size = Vector3(QUAY_WIDTH_M, pier_h, QUAY_LENGTH_M)
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	col.position = Vector3(0.0, pier_center_y, 0.0)
	body.add_child(col)

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


func _setup_harbour() -> void:
	if _harbour != null:
		_harbour.unregister_all()
		_harbour.deactivate()
	_harbour = HarbourController.new()
	_harbour.setup(SHOWCASE_PORT_ID)
	add_child(_harbour)
	_harbour.activate()
	var slot := QuayBerthSlot.new()
	slot.setup(
		SHOWCASE_BERTH_ID,
		"ore_quay",
		"bulk_ore",
		PackedStringArray(["iron_ore"]),
		QUAY_LENGTH_M,
		QUAY_WIDTH_M,
		1.0,
	)
	var quay := get_node_or_null("QuayScene") as Node3D
	if quay != null:
		quay.add_child(slot)
	else:
		add_child(slot)
	_harbour.register_berth(slot)
	if quay != null:
		var yard := quay.get_node_or_null("OreYard")
		if yard != null:
			for child in yard.get_children():
				if child is OreMound:
					_harbour.register_yard(child, SHOWCASE_BERTH_ID)


func _stamp_ore_yard(parent: Node3D) -> void:
	var yard := Node3D.new()
	yard.name = "OreYard"
	parent.add_child(yard)

	var half_w := QUAY_WIDTH_M * 0.5
	var lane_x := -(half_w - STORAGE_LANE_W * 0.5)
	var ore_color := CommodityCatalog.commodity_color("iron_ore")
	## Edge stripe only — no full orange apron (matches live bulk quay).
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
	var storage_x := -(half_w - STORAGE_LANE_W * 0.5)
	var berth_edge_x := half_w - CRANE_LANE_W * 0.5
	var road_center_x := (storage_x + berth_edge_x) * 0.5
	## Just seaward of the road — between asphalt and ore yard.
	return Vector3(road_center_x + 4.0, QUAY_DECK_TOP_Y, 0.0)


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
	_auto = BULK_CRANE_AUTO_SCRIPT.new() as BulkCraneAutoOperator
	_auto.name = "AutoOperator"
	_crane.add_child(_auto)
	_equip_id = HarbourController.make_equip_id(SHOWCASE_BERTH_ID, "equip_grab_unloader", 0)
	if _harbour != null:
		var job := BULK_EQUIP_JOB_SCRIPT.new() as BulkCraneEquipmentJob
		job.setup(_equip_id, "equip_grab_unloader", SHOWCASE_BERTH_ID)
		job.bind_crane(_crane)
		_crane.add_child(job)
		_harbour.register_equipment(job, SHOWCASE_BERTH_ID)
		var operator := CRANE_OPERATOR_SCRIPT.new() as CraneOperatorNpc
		operator.name = "CraneOperator"
		operator.position = Vector3(-2.2, 0.0, 3.5)
		operator.configure(_harbour, SHOWCASE_BERTH_ID, _equip_id)
		mount.add_child(operator)
	call_deferred("_pose_crane")


func _docked_ship() -> BoatBody:
	return get_node_or_null("QuayScene/DockedShip") as BoatBody


func _start_auto_load() -> void:
	_ensure_ship_plugged()
	if _harbour != null:
		_harbour.request_load(SHOWCASE_BERTH_ID, "iron_ore")
		return
	if _crane == null:
		return
	var ship := _docked_ship()
	if ship == null:
		return
	_crane.start_auto_load(ship, "iron_ore")


func _start_auto_unload() -> void:
	_ensure_ship_plugged()
	if _harbour != null:
		_harbour.request_unload(SHOWCASE_BERTH_ID)
		return
	if _crane == null:
		return
	var ship := _docked_ship()
	if ship == null:
		return
	_crane.start_auto_unload(ship)


func _stop_auto() -> void:
	if _harbour != null and not _equip_id.is_empty():
		_harbour.stop_equipment(_equip_id)
		return
	if _crane != null:
		_crane.stop_auto()


func _ensure_ship_plugged() -> void:
	if _harbour == null:
		return
	var ship := _docked_ship()
	if ship == null:
		return
	_harbour.plug_ship(SHOWCASE_BERTH_ID, ship)


func _pose_crane() -> void:
	if _crane == null:
		return
	_crane.boom_angle_deg = 42.0
	_crane.hoist_length_m = 18.0
	_crane.bucket_open = 0.0
	_crane.set_bucket_jaws_target(0.0)


func _docked_vessel_label() -> String:
	var preset := _prebuilt_entry(DOCKED_PREBUILT_ID)
	if preset.is_empty():
		return DOCKED_PREBUILT_ID
	return str(preset.get("prebuilt_name", DOCKED_PREBUILT_ID))


static func _prebuilt_entry(preset_id: String) -> Dictionary:
	for raw in PrebuiltVesselCatalog.catalog_entries():
		var entry := raw as Dictionary
		if str(entry.get("prebuilt_id", "")) == preset_id:
			return entry
	return {}


func _spawn_docked_ship() -> void:
	if get_node_or_null("QuayScene/DockedShip") != null:
		return
	var quay := get_node_or_null("QuayScene") as Node3D
	if quay == null:
		return
	var preset := _prebuilt_entry(DOCKED_PREBUILT_ID)
	if preset.is_empty():
		push_warning("CraneShowcase: missing prebuilt %s" % DOCKED_PREBUILT_ID)
		return
	var hull_id := str(preset.get("hull_id", ""))
	var hull_entry := HullRegistry.get_by_id(hull_id)
	var beam_m := float(hull_entry.get("beam_m", 10.0))
	var half_w := QUAY_WIDTH_M * 0.5
	var layout: Dictionary = preset.get("prebuilt_layout", {}) as Dictionary
	var registration_id := str(preset.get("registration_id", ""))
	var ship := VesselSpawn.instantiate(hull_id, layout, registration_id)
	if ship == null:
		push_warning("CraneShowcase: failed to spawn prebuilt %s" % DOCKED_PREBUILT_ID)
		return
	VesselSpawn.apply_propulsion_override(ship, preset)
	VesselSpawn.apply_identity(ship, {
		"name": str(preset.get("prebuilt_name", "Bulk Small")),
		"registration_id": registration_id,
		"uid": "showcase_%s" % DOCKED_PREBUILT_ID,
	})
	ship.name = "DockedShip"
	ship.freeze = true
	quay.add_child(ship)
	## Bow −Z, stern +Z; port (−X) faces the quay coping on +X.
	ship.position = Vector3(half_w + beam_m * 0.5 + 4.0, 0.0, 6.0)
	ship.rotation_degrees.y = 0.0
	call_deferred("_place_docked_ship", ship)


func _place_docked_ship(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	ship.place_at_waterline(WaveSurface.WATER_LEVEL)
	ship.freeze = true
	_ensure_ship_plugged()


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
