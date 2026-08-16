extends Node

## SCRATCH PROBE — leading underscore so the gate does not discover it.
##
## REALITY §7: suspect the instrument before the subject. `screenshots/hulls/*` is
## shot on a near-black field at 960x540. The claim under attack is that the hull
## "has a curve in it that a person can see". Three things could each explain a flat
## read, so they are varied ONE AT A TIME (§4e) rather than all at once:
##
##   A  dark  960x540   — replica of the shipped rig (control)
##   B  dark 1600x900   — RESOLUTION only
##   C  sky  1600x900   — BACKGROUND only, on top of B
##   D  sky  1600x900   — GEOMETRY: the same frame as C with the strake band's
##                        sheer rise multiplied by SHEER_GAIN, applied to the drawn
##                        mesh only. If D reads as curved where C does not, the
##                        limit is amplitude and not the rig.
##
## Writes to `screenshots/sheer_probe/` — a NEW directory. Nothing under
## `screenshots/hulls/` is read, written or re-shot.

const OUT_DIR := "res://screenshots/sheer_probe"
const CaptureClock := preload("res://tests/support/capture_clock.gd")
const DARK := Color(0.055, 0.075, 0.095)
const SKY := Color(0.62, 0.72, 0.82)
const SHEER_GAIN := 3.0

const HULL_IDS := ["hull_15x5", "hull_28x10", "hull_130x28"]

var _viewport: SubViewport
var _world: Node3D
var _env: Environment
var _camera: Camera3D


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	CaptureClock.pin(get_tree())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.55, 0.62, 0.70)
	_env.ambient_light_energy = 0.85
	we.environment = _env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -32.0, 0.0)
	sun.light_energy = 1.4
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 145.0, 0.0)
	fill.light_energy = 0.55
	_world.add_child(fill)
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 48.0
	_world.add_child(_camera)

	for hull_id in HULL_IDS:
		await _shoot(hull_id, "A_dark_960", DARK, Vector2i(960, 540), 1.0)
		await _shoot(hull_id, "B_dark_1600", DARK, Vector2i(1600, 900), 1.0)
		await _shoot(hull_id, "C_sky_1600", SKY, Vector2i(1600, 900), 1.0)
		await _shoot(hull_id, "D_sky_1600_sheer3x", SKY, Vector2i(1600, 900), SHEER_GAIN)

	print("=== SHEER LOOK: done ===")
	get_tree().quit()


func _shoot(
	hull_id: String, case: String, bg: Color, size: Vector2i, gain: float
) -> void:
	var boat := HullRegistry.build_hull(hull_id)
	if boat == null:
		print("%s: null" % hull_id)
		return
	boat.freeze = true
	if gain != 1.0:
		_regain_sheer(boat, gain)
	_world.add_child(boat)
	_env.background_color = bg
	_viewport.size = size
	var height := maxf(boat.depth_m, 3.0)
	var length := maxf(boat.length_m, 10.0)
	var beam := maxf(boat.beam_m, 5.0)
	boat.rotation_degrees.y = 0.0
	_camera.position = Vector3(
		beam * 0.5 + maxf(length * 0.76, height * 5.0), height * 0.68, 0.0
	)
	_camera.look_at_from_position(
		_camera.position, Vector3(0.0, height * 0.48, 0.0), Vector3.UP
	)
	await CaptureClock.settle(get_tree(), 4)
	var image := _viewport.get_texture().get_image()
	var path := "%s/%s__%s.png" % [OUT_DIR, hull_id, case]
	image.save_png(ProjectSettings.globalize_path(path))
	print("wrote %s (%dx%d)" % [path, size.x, size.y])
	_world.remove_child(boat)
	boat.free()


## Multiply the DRAWN strake rise by `gain` and re-loft the shell. Display only —
## nothing else on the boat reads the mutated sections, and the boat is freed after
## the frame. This exists to answer "what would a visible curve look like here",
## not to propose a fix.
func _regain_sheer(boat: Node, gain: float) -> void:
	var s: HullStations = boat.hull_stations
	if s == null or s.strake_level < 0:
		return
	var mid_rise := 1e18
	var mid_abs := 1e18
	for station in s.stations:
		if absf(float(station["z"])) < mid_abs:
			mid_abs = absf(float(station["z"]))
			mid_rise = s.sheer_rise_at(float(station["z"]))
	for station in s.stations:
		var z := float(station["z"])
		var extra := (s.sheer_rise_at(z) - mid_rise) * (gain - 1.0)
		var section: Array = station["section"]
		for j in [s.strake_level, s.strake_level + 1]:
			if j >= section.size():
				continue
			var v: Vector2 = section[j]
			section[j] = Vector2(minf(v.x + extra, s.deck_y - 0.02), v.y)
	var visual := boat.get_node_or_null("HullVisual")
	if visual == null:
		return
	var old := visual.get_node_or_null("HullShell")
	if old != null:
		visual.remove_child(old)
		old.free()
	var hull := MeshBuilder.lofted_hull_shell(s, Color(0.14, 0.16, 0.18), 0.9, 0.05)
	hull.name = "HullShell"
	visual.add_child(hull)
	HullLivery.apply_to_boat(boat, {})
