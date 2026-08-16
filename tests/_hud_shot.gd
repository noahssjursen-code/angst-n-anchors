extends Node

## SCRATCH capture rig (leading underscore — not a gate unit, and not one of the
## rigs another wave owns). Renders the ship HUD in the shape
## `BoatController._ensure_hud` builds it — a CanvasLayer under the real window
## viewport — because the toast's rect depends on the HUD's own rect and a
## SubViewport gets that wrong in the opposite direction.
##
## Not reproducible in the byte sense and does not claim to be: it is here so a
## person can look at the band and the toast (REALITY §1 — looking is for
## everything with a taste answer). No clock, no lights, no physics, so it does
## not carry the WorldClock dependency that moves the vessel rigs.

const OUT_DIR := "res://screenshots/hud"

var _hud: ShipHud


func _ready() -> void:
	await _run()
	get_tree().quit(0)


func _run() -> void:
	print(
		"TOAST FRAME IS GRABBED WHILE BrandMotion IS STILL SLIDING THE PANEL IN — "
		+ "ship_hud__toast.png MUST NOT BE DIFFED (CONVENTIONS §3). The other three "
		+ "carry no clock, no lights and no physics."
	)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = ShipHud.new()
	layer.add_child(_hud)
	await get_tree().process_frame
	print("hud rect ", _hud.get_rect(), "  viewport ", get_viewport().get_visible_rect())

	await _shot("underway", _snapshot("underway"), "")
	await _shot("autopilot_fishing", _snapshot("autopilot_fishing"), "")
	await _shot("hatch_shut", _snapshot("hatch_shut"), "")
	await _shot("toast", _snapshot("underway"), "MOORED - untie both quay lines before departure")


func _shot(case_name: String, snapshot: Dictionary, message: String) -> void:
	var state := get_node_or_null("/root/GameState")
	(state.ship as ShipState).publish_instruments(snapshot)
	if not message.is_empty():
		_hud.show_toast(message, 60.0)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png("%s/ship_hud__%s.png" % [OUT_DIR, case_name])
	var toast := _hud.get_child(1) as Control
	print("%-18s toast rect %s" % [case_name, toast.get_global_rect()])


func _snapshot(case_name: String) -> Dictionary:
	var snapshot := {
		"position": Vector3(120.0, 0.0, -48.0),
		"bow": Vector2(0.0, -1.0),
		"velocity": Vector3(3.0, 0.0, -4.0),
		"heading_deg": 143.0,
		"speed_knots": 9.7,
		"fuel_fraction": 0.42,
		"throttle_values": [-0.5, 0.0, 0.25, 0.5, 1.0],
		"throttle_index": 3,
		"throttle_value": 0.5,
		"thruster_mode": 1,
		"lights": "NAV",
		"autopilot_active": false,
		"target_bearing_deg": NAN,
		"destination_name": "",
		"remaining_distance_m": 0.0,
		"fishing": {},
		"wind_direction": Vector3(1.0, 0.0, 0.4),
		"wind_speed_ms": 8.3,
		"time_hours": 14.5,
	}
	if case_name in ["autopilot_fishing", "hatch_shut"]:
		snapshot["autopilot_active"] = true
		snapshot["destination_name"] = "Bornholm Fiskerihavn"
		snapshot["remaining_distance_m"] = 18450.0
		snapshot["target_bearing_deg"] = 91.0
		snapshot["fishing"] = {"status": "ACTIVE", "mass_t": 3.4, "capacity_t": 12.0}
	if case_name == "hatch_shut":
		snapshot["fishing"]["status"] = FishingSystem.STATUS_HATCH_SHUT
	return snapshot
