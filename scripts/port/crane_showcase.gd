@tool
class_name CraneShowcase
extends Node3D

## F6 multi-quay crane row — cycle bays for each harbour crane type.

const BULK_CRANE_SCRIPT := preload("res://scripts/port/bulk_crane.gd")
const BULK_CRANE_AUTO_SCRIPT := preload("res://scripts/port/bulk_crane_auto_operator.gd")
const BULK_EQUIP_JOB_SCRIPT := preload("res://scripts/port/bulk_crane_equipment_job.gd")
const PROVISION_CRANE_SCRIPT := preload("res://scripts/port/provision_crane.gd")
const CRANE_OPERATOR_SCRIPT := preload("res://scripts/port/crane_operator_npc.gd")
const DOCKED_PREBUILT_ID := "bulk_small"
const PROVISION_DOCKED_PREBUILT_ID := "28_10_m"
const SHOWCASE_PORT_ID := "crane_showcase"
const SHOWCASE_BERTH_ID := "crane_showcase/ore_quay"

const QUAY_LENGTH_M := 140.0
const QUAY_WIDTH_M := 72.0
const QUAY_GAP_M := 24.0
const QUAY_DECK_TOP_Y := 0.0
const QUAY_DECK_SLAB_H := 0.55
const CRANE_LANE_W := 22.0
const STORAGE_LANE_W := 28.0
const ROAD_W := 12.0
const DECK_COLOR := Color(0.133, 0.133, 0.133)
const PIER_MASS_COLOR := Color(0.18, 0.19, 0.20)

## Bay catalog — append new crane types here.
const BAYS: Array[Dictionary] = [
	{
		"id": "bulk_ore",
		"name": "Bulk ore · grab crane",
		"crane": "bulk",
	},
	{
		"id": "provisions",
		"name": "Provisions · T crane",
		"crane": "provision",
	},
]

@export var orbit_yaw_deg := 35.0
@export var orbit_pitch_deg := -22.0
@export var orbit_distance := 72.0

var _bay_roots: Array[Node3D] = []
var _bay_index := 0
var _bulk_crane: BulkCrane
var _provision_crane: ProvisionCrane
var _auto: BulkCraneAutoOperator
var _harbour: HarbourController
var _equip_id := ""
var _camera: Camera3D
var _hud: Label
var _orbiting := false
var _orbit_yaw := 35.0
var _orbit_pitch := -22.0
var _focus_tool := true
var _focus := Vector3(18.0, 8.0, 0.0)
var _hud_timer := 0.0


func _ready() -> void:
	_orbit_yaw = orbit_yaw_deg
	_orbit_pitch = orbit_pitch_deg
	_ensure_environment()
	_ensure_camera()
	_ensure_hud()
	_spawn_quay_row()
	_ensure_scale_human()
	_set_bay(0, true)
	_refresh_hud()


func _exit_tree() -> void:
	if _harbour != null:
		_harbour.unregister_all()
		_harbour.deactivate()
		_harbour = null


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_drive_active_crane(delta)
	if _focus_tool:
		_track_tool_focus()
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
			KEY_BRACKETLEFT, KEY_LEFT:
				_cycle_bay(-1)
			KEY_BRACKETRIGHT, KEY_RIGHT:
				_cycle_bay(1)
			KEY_HOME:
				_focus_tool = false
				_orbit_yaw = orbit_yaw_deg
				_orbit_pitch = orbit_pitch_deg
				orbit_distance = 72.0
				_focus = _bay_overview_focus()
				_update_camera()
			KEY_B:
				_focus_on_tool()
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


func _cycle_bay(delta: int) -> void:
	if BAYS.is_empty():
		return
	var next := (_bay_index + delta) % BAYS.size()
	if next < 0:
		next += BAYS.size()
	_set_bay(next, false)


func _set_bay(index: int, initial: bool) -> void:
	_bay_index = clampi(index, 0, maxi(BAYS.size() - 1, 0))
	_stop_auto()
	if initial:
		_focus_on_tool()
		_update_camera()
	else:
		_focus_tool = false
		_orbit_yaw = orbit_yaw_deg
		_orbit_pitch = orbit_pitch_deg
		orbit_distance = 72.0
		_focus = _bay_overview_focus()
		_update_camera()
	_refresh_hud()


func _active_bay() -> Dictionary:
	if _bay_index < 0 or _bay_index >= BAYS.size():
		return {}
	return BAYS[_bay_index]


func _active_bay_root() -> Node3D:
	if _bay_index < 0 or _bay_index >= _bay_roots.size():
		return null
	return _bay_roots[_bay_index]


func _bay_pitch_m() -> float:
	return QUAY_LENGTH_M + QUAY_GAP_M


func _bay_origin_z(index: int) -> float:
	return float(index) * _bay_pitch_m()


func _bay_overview_focus() -> Vector3:
	return Vector3(12.0, 8.0, _bay_origin_z(_bay_index))


func _drive_active_crane(delta: float) -> void:
	var bay := _active_bay()
	var kind := str(bay.get("crane", ""))
	if kind == "bulk" and _bulk_crane != null:
		if _auto == null or not _auto.is_active():
			_bulk_crane.playtest_input(delta)
	elif kind == "provision" and _provision_crane != null:
		_provision_crane.playtest_input(delta)


func _focus_on_tool() -> void:
	_focus_tool = true
	orbit_distance = 9.0
	_orbit_yaw = 40.0
	_orbit_pitch = -18.0
	_track_tool_focus()


func _track_tool_focus() -> void:
	var bay := _active_bay()
	var kind := str(bay.get("crane", ""))
	if kind == "bulk" and _bulk_crane != null:
		var bucket := _bulk_crane.get_bucket()
		if bucket != null and is_instance_valid(bucket):
			_focus = bucket.global_position + Vector3(0.0, -1.0, 0.0)
			return
	if kind == "provision" and _provision_crane != null:
		var hook := _provision_crane.get_hook()
		if hook != null and is_instance_valid(hook):
			_focus = hook.global_position + Vector3(0.0, -0.5, 0.0)
			return
		var talje := _provision_crane.get_talje()
		if talje != null and is_instance_valid(talje):
			_focus = talje.global_position
			return
	_focus = _bay_overview_focus() + Vector3(10.0, 0.0, -6.0)


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
	var bay := _active_bay()
	var mode := "TOOL FOCUS" if _focus_tool else "quay overview"
	var lines: PackedStringArray = PackedStringArray([
		"CRANE SHOWCASE — %s" % mode,
		"Bay %d/%d — %s" % [_bay_index + 1, BAYS.size(), str(bay.get("name", "?"))],
		"[ ] / ← →  cycle bays   ·   B  tool focus   ·   Home  overview",
		"RMB orbit · wheel zoom",
		"",
	])
	var kind := str(bay.get("crane", ""))
	if kind == "bulk":
		lines.append("Bulk grab  ·  docked %s" % _docked_vessel_label())
		lines.append("L  harbour load · O  harbour unload · X  stop")
		lines.append("Talk to crane operator  ·  A/D W/S Q/E Space")
		lines.append("")
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
			lines.append("")
		if _bulk_crane != null:
			lines.append_array(_bulk_crane.get_status_lines())
		var ship := _docked_ship()
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
	elif kind == "provision":
		lines.append("Container bay  ·  docked %s" % _docked_vessel_label())
		lines.append("A/D slew · W/S trolley · Q/E hoist · Space grab/drop")
		lines.append("")
		if _provision_crane != null:
			lines.append_array(_provision_crane.get_status_lines())
	_hud.text = "\n".join(lines)


func _spawn_quay_row() -> void:
	if get_node_or_null("QuayRow") != null:
		return
	var row := Node3D.new()
	row.name = "QuayRow"
	add_child(row)
	_bay_roots.clear()
	for i in range(BAYS.size()):
		var def: Dictionary = BAYS[i]
		var bay := Node3D.new()
		bay.name = "Bay_%s" % str(def.get("id", i))
		bay.position = Vector3(0.0, 0.0, _bay_origin_z(i))
		row.add_child(bay)
		_bay_roots.append(bay)
		_stamp_quay_pier(bay)
		match str(def.get("crane", "")):
			"bulk":
				_spawn_bay_bulk_ore(bay)
			"provision":
				_spawn_bay_provisions(bay)


func _spawn_bay_bulk_ore(bay: Node3D) -> void:
	_stamp_ore_yard(bay)
	_setup_harbour(bay)
	_spawn_bulk_crane(bay)
	_spawn_docked_ship(bay, DOCKED_PREBUILT_ID, true)


func _spawn_bay_provisions(bay: Node3D) -> void:
	_stamp_crate_yard(bay)
	_spawn_provision_crane(bay)
	_spawn_docked_ship(bay, PROVISION_DOCKED_PREBUILT_ID, false)
	var label := Label3D.new()
	label.name = "BayLabel"
	label.text = "PROVISIONS / GENERAL"
	label.font = HudStyle.font_display()
	label.font_size = 96
	label.pixel_size = 0.012
	label.position = Vector3(-20.0, QUAY_DECK_TOP_Y + 3.5, -50.0)
	label.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	label.modulate = Color(0.92, 0.86, 0.55)
	label.outline_modulate = Color(0.08, 0.07, 0.05, 0.85)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	bay.add_child(label)


func _spawn_provision_crane(bay: Node3D) -> void:
	if _provision_crane != null and is_instance_valid(_provision_crane):
		_provision_crane.queue_free()
		_provision_crane = null
	var mount := Node3D.new()
	mount.name = "CraneMount"
	mount.position = _crane_mount_position()
	bay.add_child(mount)
	_provision_crane = PROVISION_CRANE_SCRIPT.new() as ProvisionCrane
	_provision_crane.name = "ProvisionCrane"
	## Local −Z = jib outboard (same as BulkCrane).
	_provision_crane.rotation_degrees.y = -90.0
	mount.add_child(_provision_crane)


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


func _setup_harbour(bay: Node3D) -> void:
	if _harbour != null:
		_harbour.unregister_all()
		_harbour.deactivate()
		_harbour.queue_free()
		_harbour = null
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
	bay.add_child(slot)
	_harbour.register_berth(slot)
	var yard := bay.get_node_or_null("OreYard")
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


func _stamp_crate_yard(parent: Node3D) -> void:
	var yard := Node3D.new()
	yard.name = "ContainerYard"
	parent.add_child(yard)

	var half_w := QUAY_WIDTH_M * 0.5
	var lane_x := -(half_w - STORAGE_LANE_W * 0.5)
	var stripe := MeshBuilder.box(
		Vector3(1.1, 0.85, QUAY_LENGTH_M * 0.9),
		Color(0.18, 0.32, 0.48),
		0.85,
		0.08,
	)
	stripe.name = "ContainerStripe"
	stripe.position = Vector3(-(half_w - 0.55), QUAY_DECK_TOP_Y + 0.08, 0.0)
	yard.add_child(stripe)

	var stack_z := [-40.0, -18.0, 6.0, 30.0]
	for si in range(stack_z.size()):
		var stack := Node3D.new()
		stack.name = "ContainerStack_%d" % si
		stack.position = Vector3(lane_x, QUAY_DECK_TOP_Y, float(stack_z[si]))
		yard.add_child(stack)
		var cols := 2
		var rows := 2
		var tiers := 2
		for t in range(tiers):
			for r in range(rows):
				for c in range(cols):
					var unit := ContainerFactory.make_one()
					var node := ContainerNode.new()
					node.name = "Container_%d_%d_%d" % [si, t, c * rows + r]
					var gap := 0.12
					node.position = Vector3(
						(float(c) - float(cols - 1) * 0.5) * (ContainerUnit.DEFAULT_SIZE_M + gap),
						float(t) * (ContainerUnit.DEFAULT_HEIGHT_M + gap),
						(float(r) - float(rows - 1) * 0.5) * (ContainerUnit.DEFAULT_SIZE_M + gap),
					)
					stack.add_child(node)
					node.setup(unit)


func _crane_mount_position() -> Vector3:
	var half_w := QUAY_WIDTH_M * 0.5
	var storage_x := -(half_w - STORAGE_LANE_W * 0.5)
	var berth_edge_x := half_w - CRANE_LANE_W * 0.5
	var road_center_x := (storage_x + berth_edge_x) * 0.5
	return Vector3(road_center_x + 4.0, QUAY_DECK_TOP_Y, 0.0)


func _spawn_bulk_crane(bay: Node3D) -> void:
	if _bulk_crane != null and is_instance_valid(_bulk_crane):
		_bulk_crane.queue_free()
		_bulk_crane = null
	var mount := Node3D.new()
	mount.name = "CraneMount"
	mount.position = _crane_mount_position()
	bay.add_child(mount)
	_bulk_crane = BULK_CRANE_SCRIPT.new() as BulkCrane
	_bulk_crane.name = "BulkCrane"
	_bulk_crane.rotation_degrees.y = -90.0
	mount.add_child(_bulk_crane)
	_auto = BULK_CRANE_AUTO_SCRIPT.new() as BulkCraneAutoOperator
	_auto.name = "AutoOperator"
	_bulk_crane.add_child(_auto)
	_equip_id = HarbourController.make_equip_id(SHOWCASE_BERTH_ID, "equip_grab_unloader", 0)
	if _harbour != null:
		var job := BULK_EQUIP_JOB_SCRIPT.new() as BulkCraneEquipmentJob
		job.setup(_equip_id, "equip_grab_unloader", SHOWCASE_BERTH_ID)
		job.bind_crane(_bulk_crane)
		_bulk_crane.add_child(job)
		_harbour.register_equipment(job, SHOWCASE_BERTH_ID)
		var operator := CRANE_OPERATOR_SCRIPT.new() as CraneOperatorNpc
		operator.name = "CraneOperator"
		operator.position = Vector3(-2.2, 0.0, 3.5)
		operator.configure(_harbour, SHOWCASE_BERTH_ID, _equip_id)
		mount.add_child(operator)
	call_deferred("_pose_bulk_crane")


func _docked_ship() -> BoatBody:
	var bay := _bay_roots[0] if not _bay_roots.is_empty() else null
	if bay == null:
		return null
	return bay.get_node_or_null("DockedShip") as BoatBody


func _start_auto_load() -> void:
	if str(_active_bay().get("crane", "")) != "bulk":
		return
	_ensure_ship_plugged()
	if _harbour != null:
		_harbour.request_load(SHOWCASE_BERTH_ID, "iron_ore")
		return
	if _bulk_crane == null:
		return
	var ship := _docked_ship()
	if ship == null:
		return
	_bulk_crane.start_auto_load(ship, "iron_ore")


func _start_auto_unload() -> void:
	if str(_active_bay().get("crane", "")) != "bulk":
		return
	_ensure_ship_plugged()
	if _harbour != null:
		_harbour.request_unload(SHOWCASE_BERTH_ID)
		return
	if _bulk_crane == null:
		return
	var ship := _docked_ship()
	if ship == null:
		return
	_bulk_crane.start_auto_unload(ship)


func _stop_auto() -> void:
	if _harbour != null and not _equip_id.is_empty():
		_harbour.stop_equipment(_equip_id)
		return
	if _bulk_crane != null:
		_bulk_crane.stop_auto()


func _ensure_ship_plugged() -> void:
	if _harbour == null:
		return
	var ship := _docked_ship()
	if ship == null:
		return
	_harbour.plug_ship(SHOWCASE_BERTH_ID, ship)


func _pose_bulk_crane() -> void:
	if _bulk_crane == null:
		return
	_bulk_crane.boom_angle_deg = 42.0
	_bulk_crane.hoist_length_m = 18.0
	_bulk_crane.bucket_open = 0.0
	_bulk_crane.set_bucket_jaws_target(0.0)


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


func _spawn_docked_ship(bay: Node3D, prebuilt_id: String, plug_harbour: bool) -> void:
	if bay.get_node_or_null("DockedShip") != null:
		return
	var preset := _prebuilt_entry(prebuilt_id)
	if preset.is_empty():
		push_warning("CraneShowcase: missing prebuilt %s" % prebuilt_id)
		return
	var hull_id := str(preset.get("hull_id", ""))
	var hull_entry := HullRegistry.get_by_id(hull_id)
	var beam_m := float(hull_entry.get("beam_m", 10.0))
	var half_w := QUAY_WIDTH_M * 0.5
	var layout: Dictionary = preset.get("prebuilt_layout", {}) as Dictionary
	var registration_id := str(preset.get("registration_id", ""))
	var ship := VesselSpawn.instantiate(hull_id, layout, registration_id)
	if ship == null:
		push_warning("CraneShowcase: failed to spawn prebuilt %s" % prebuilt_id)
		return
	VesselSpawn.apply_propulsion_override(ship, preset)
	VesselSpawn.apply_identity(ship, {
		"name": str(preset.get("prebuilt_name", prebuilt_id)),
		"registration_id": registration_id,
		"uid": "showcase_%s" % prebuilt_id,
	})
	ship.name = "DockedShip"
	ship.set_meta("showcase_plug_harbour", plug_harbour)
	ship.freeze = true
	bay.add_child(ship)
	ship.position = Vector3(half_w + beam_m * 0.5 + 4.0, 0.0, 6.0)
	ship.rotation_degrees.y = 0.0
	call_deferred("_place_docked_ship", ship)


func _place_docked_ship(ship: BoatBody) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	ship.place_at_waterline(WaveSurface.WATER_LEVEL)
	ship.freeze = true
	if bool(ship.get_meta("showcase_plug_harbour", false)):
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
	panel.custom_minimum_size = Vector2(440, 0)
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
