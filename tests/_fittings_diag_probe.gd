extends Node

## SCRATCH DIAGNOSTIC PROBE (leading underscore — the gate must not score it).
## Lane B (scene): res://tests/_fittings_diag_probe.tscn
##
## `tests/_fittings_shot.gd` records its residual 3.79% drift as a WEATHER
## dependency: "`CaptureClock.pin` pins the HOUR and not the WEATHER, and the
## weather is on the same wall clock by another route". That is a hypothesis the
## file itself says was "identified but NOT closed". This probe tests it.
##
## It stands up the same vessel through the same production path
## (`VesselSpawn.instantiate` -> `apply_plan`) and, on every rendered frame,
## prints the three quantities the hypothesis and its rival each predict:
##
##   * `fog`/`daylight`/`light_scale` — the WEATHER path. If the recorded
##     diagnosis is right these drift across the run and between runs.
##   * `boat_y` in exact float bits — the HULL path. `BoatBody` overwrites the
##     rig's `freeze = true` one second after enter-tree, via
##     `_update_automatic_physics_quality()` -> `set_physics_quality(FULL)`.
##   * the summed `light_energy` of every `ShipLight` on the vessel, which is
##     what `ShipLighting._apply_day_scales` actually moves.
##
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     res://tests/_fittings_diag_probe.tscn [-- --fix]

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const WL := -1.5
const HULL_ID := "hull_28x10"
const REGISTRATION := "general_vessel"
const SAMPLES := 45

var _boat: BoatBody
var _fix := false


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "--fix":
			_fix = true
	call_deferred("_run")


func _run() -> void:
	print("CLOCK PINNED time_of_day=%.3f" % CaptureClock.pin(get_tree()))
	var world := Node3D.new()
	get_tree().root.add_child(world)

	var plan := _vessel_plan()
	_boat = VesselSpawn.instantiate(HULL_ID, plan.to_dict(), REGISTRATION)
	if _boat == null:
		printerr("PROBE VesselSpawn returned null")
		get_tree().quit(1)
		return
	_boat.freeze = true
	world.add_child(_boat)
	if _fix:
		_boat.automatic_physics_lod = false
		_boat.set_physics_quality(BoatBody.PhysicsQuality.SLEEP)
	_boat.position = Vector3(0.0, WL - _boat.draft_m - _boat.hull_stations.keel_y, 0.0)
	await get_tree().physics_frame

	for i in range(SAMPLES):
		await get_tree().process_frame
		print("PROBE %3d frame=%d msec=%d boat_y=%s vy=%s %s"
			% [i, Engine.get_frames_drawn(), Time.get_ticks_msec(),
				_bits(_boat.global_position.y), _bits(_boat.linear_velocity.y),
				_weather()])
	print("PROBE DONE fix=%s" % _fix)
	get_tree().quit(0)


## Everything the recorded weather diagnosis says should be moving.
func _weather() -> String:
	var w := get_tree().root.get_node_or_null("WeatherLighting")
	var fog := -1.0
	var daylight := -1.0
	var scale := -1.0
	var tod := -1.0
	if w != null:
		fog = float(w.get("fog_density"))
		tod = float(w.get("time_of_day"))
		if w.has_method("daylight_factor"):
			daylight = float(w.call("daylight_factor"))
		if w.has_method("artificial_light_scale"):
			scale = float(w.call("artificial_light_scale"))
	var energy := 0.0
	var lights := 0
	for node in _walk(_boat):
		var l := node as Light3D
		if l != null:
			lights += 1
			energy += l.light_energy
	var clock := get_tree().root.get_node_or_null("WorldClock")
	var hours := -1.0
	if clock != null and clock.has_method("get_game_hours_elapsed"):
		hours = float(clock.call("get_game_hours_elapsed"))
	return ("tod=%s fog=%s daylight=%s light_scale=%s lights=%d energy=%s game_hours=%.6f"
		% [_bits(tod), _bits(fog), _bits(daylight), _bits(scale), lights, _bits(energy), hours])


func _bits(f: float) -> String:
	return PackedFloat32Array([f]).to_byte_array().hex_encode()


func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out


## Copied verbatim from `tests/_fittings_shot.gd` so the subject is the same.
func _vessel_plan() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = HULL_ID
	plan.add_deck(Vector3(1.0, 0.0, 3.0), Vector2(8.0, 22.0))
	for z in [5.0, 10.0, 18.0, 24.0]:
		plan.add_item("bollard_pair", Vector3(1.6, 0.0, float(z)), 90.0)
		plan.add_item("bollard_pair", Vector3(8.4, 0.0, float(z)), 90.0)
	plan.add_item("hold_coaming", Vector3(5.0, 0.0, 8.5), 0.0, {"length": 5.0, "width": 4.0})
	plan.add_item("mast_with_platform", Vector3(5.0, 0.0, 14.0), 0.0, {"height": 7.5})
	plan.add_item("lantern_all_round", Vector3(5.0, 7.5, 14.0))
	plan.add_item("funnel_tapered", Vector3(3.4, 0.0, 16.5))
	plan.add_item("helm_console", Vector3(5.0, 0.0, 20.0), 180.0)
	plan.add_item("bench_seat", Vector3(6.8, 0.0, 21.5), 180.0)
	plan.add_item("gallows_a_frame", Vector3(5.0, 0.0, 25.5), 0.0, {"height": 4.2, "spread": 4.6})
	plan.add_item("net_drum", Vector3(5.0, 0.0, 23.2), 90.0)
	plan.add_item("railing_run", Vector3(1.4, 0.0, 4.0), -90.0, {"length": 9.0})
	plan.add_item("railing_run", Vector3(8.6, 0.0, 4.0), -90.0, {"length": 9.0})
	return plan
