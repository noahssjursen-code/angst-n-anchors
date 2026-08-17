extends Node

## SCRATCH PROBE (underscore-prefixed, not a gate unit). Lane B (scene).
##
## PHOTOGRAPHS THE THREE ORPHANED HARBOUR FEATURES BESIDE A 1.8 m FIGURE.
## `entry_reach_test` proved `fuel_station.tscn`, `lighthouse_building.tscn` and
## `fog_horn_building.tscn` have no referrer anywhere. Whether that is a loss
## depends entirely on what they look like: a grey box and a finished model with
## a working light are different findings and no static scan can tell them
## apart. CONVENTIONS §3a — without the figure nothing in the frame has an
## absolute size.
##
## REPRODUCIBILITY, stated rather than assumed (CONVENTIONS §3):
##
##  * The clock is pinned via `CaptureClock.pin` and every grab settles with
##    `CaptureClock.settle`, i.e. N idle frames THEN `RenderingServer.frame_post_draw`.
##  * `LighthouseBuilding._process` rotates the beam by `TAU * sweep_speed_hz *
##    delta` every frame and rescales three lights from live `WeatherLighting`
##    fog — which `CaptureClock.pin` does NOT pin (see its header). So this rig
##    calls `set_process(false)` on the lighthouse the instant it enters the
##    tree, freezing the rotor at yaw 0 and leaving every light at its
##    CONSTRUCTION default (BEAM_LIGHT_ENERGY 220, LANTERN_ENERGY 12, beam
##    shader energy 1.0). The frame therefore shows the lighthouse's declared
##    full-power state, not a sampled instant of a sweep.
##  * There is no `BoatBody` in any of these scenes, so `CaptureSubject.hold_still`
##    has no subject here; it is imported and asserted-inapplicable rather than
##    silently skipped.
##
## No scene is modified. Nothing is wired into the world.

const CaptureClock := preload("res://tests/support/capture_clock.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")

const OUT_DIR := "res://screenshots/buildings"
const BACKGROUND := Color(0.42, 0.52, 0.60)

const SUBJECTS := {
	"fuel_station": {
		"scene": "res://scenes/systems/fuel_station.tscn",
		"views": {
			"three_quarter": {"eye": Vector3(9.0, 4.2, 9.0), "at": Vector3(0.0, 1.4, 0.0)},
			"pump_side": {"eye": Vector3(-1.0, 2.0, 7.5), "at": Vector3(-1.0, 1.3, 0.0)},
		},
		"figure": Vector3(2.6, 0.0, 2.4),
	},
	"fog_horn": {
		"scene": "res://scenes/systems/fog_horn_building.tscn",
		"views": {
			"three_quarter": {"eye": Vector3(13.0, 7.0, 13.0), "at": Vector3(0.0, 3.6, 0.0)},
			"eye_level": {"eye": Vector3(0.5, 1.6, 12.0), "at": Vector3(0.0, 4.0, 0.0)},
		},
		"figure": Vector3(3.4, 0.0, 2.6),
	},
	"lighthouse": {
		"scene": "res://scenes/systems/lighthouse_building.tscn",
		"views": {
			"full_height": {"eye": Vector3(34.0, 16.0, 34.0), "at": Vector3(0.0, 12.0, 0.0)},
			"base_eye_level": {"eye": Vector3(2.0, 1.6, 16.0), "at": Vector3(0.0, 9.0, 0.0)},
			"lantern": {"eye": Vector3(9.0, 24.0, 9.0), "at": Vector3(0.0, 21.0, 0.0)},
		},
		"figure": Vector3(4.2, 0.0, 3.4),
	},
}

var _failures := 0
var _viewport: SubViewport


func _check(label: String, ok: bool) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	var pinned := CaptureClock.pin(get_tree(), CaptureClock.NOON)
	print("[clock] pinned time_of_day = %.4f" % pinned)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1280, 720)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	get_tree().root.add_child(_viewport)

	var world := _stage()
	_viewport.add_child(world)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 55.0
	camera.far = 6000.0
	world.add_child(camera)

	for key in SUBJECTS.keys():
		var spec := SUBJECTS[key] as Dictionary
		var packed := load(str(spec["scene"])) as PackedScene
		if packed == null:
			_check("%s: scene loads" % key, false)
			continue
		var subject := packed.instantiate() as Node3D
		world.add_child(subject)
		## Freeze anything that animates itself off the wall clock. There is no
		## BoatBody here, so CaptureSubject.hold_still has no subject — asserted,
		## not assumed, so a future BoatBody in one of these scenes trips it.
		subject.set_process(false)
		_check("%s: contains no BoatBody, so hold_still is inapplicable" % key,
			subject.find_children("*", "BoatBody", true, false).is_empty())
		CaptureSubject.hold_still(null)

		var figure := _mannequin(spec["figure"] as Vector3)
		world.add_child(figure)

		var model_box := _model_aabb(subject)
		print("[%s] drawn model AABB (beam meshes excluded): pos %s size %s"
			% [key, str(model_box.position.snapped(Vector3.ONE * 0.01)),
				str(model_box.size.snapped(Vector3.ONE * 0.01))])

		for view in (spec["views"] as Dictionary).keys():
			var v := (spec["views"] as Dictionary)[view] as Dictionary
			camera.look_at_from_position(v["eye"] as Vector3, v["at"] as Vector3, Vector3.UP)
			await CaptureClock.settle(get_tree(), 4)
			var image := _viewport.get_texture().get_image()
			var stats := _stats(image)
			var path := "%s/orphan_%s__%s.png" % [OUT_DIR, key, view]
			var err := image.save_png(path)
			_check("wrote %s (subject covers %.1f%% of frame, mean luma %.4f, %d distinct colours)"
				% [path.get_file(), float(stats["coverage"]) * 100.0, stats["mean"], stats["colours"]],
				err == OK and float(stats["coverage"]) > 0.02)
			## A grey box and a modelled building differ in one machine-readable
			## way: how many distinct colours the silhouette carries.
			print("    [%s/%s] distinct quantised colours in subject pixels: %d"
				% [key, view, stats["colours"]])

		world.remove_child(subject)
		subject.free()
		world.remove_child(figure)
		figure.free()

	print("---")
	print("_harbour_feature_shot: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


## The lighthouse's two 3000 m beam cylinders swamp any bounds measurement, so
## the building's own size is measured over meshes that are not under LightRotor.
func _model_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var m := n as MeshInstance3D
		if m.mesh == null:
			continue
		var under_rotor := false
		var p: Node = m
		while p != null and p != root:
			if p.name == "LightRotor":
				under_rotor = true
			p = p.get_parent()
		if under_rotor:
			continue
		var local := m.get_aabb()
		var world_box := AABB(
			m.global_transform * local.position,
			(m.global_transform.basis * local.size).abs(),
		)
		if first:
			box = world_box
			first = false
		else:
			box = box.merge(world_box)
	return box


func _stage() -> Node3D:
	var world := Node3D.new()
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.74, 0.82)
	env.ambient_light_energy = 0.9
	environment.environment = env
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48.0, -34.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	world.add_child(sun)
	## A ground plate, so the figure and the buildings share a floor and the
	## frame reads as a quayside rather than as objects in a void.
	var ground := MeshInstance3D.new()
	ground.name = "Quay"
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 120.0)
	ground.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.36, 0.34)
	mat.roughness = 0.95
	ground.material_override = mat
	ground.position = Vector3(0, -0.02, 0)
	world.add_child(ground)
	return world


func _mannequin(at: Vector3) -> Node3D:
	var node := MeshInstance3D.new()
	node.name = "ScaleFigure_1m8"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.45, 1.8, 0.28)
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.88, 0.28, 0.14)
	material.roughness = 0.9
	node.material_override = material
	node.position = at + Vector3(0, 0.9, 0)
	return node


func _stats(image: Image) -> Dictionary:
	var lumas := PackedFloat32Array()
	var colours := {}
	var samples := 0
	for y in range(0, image.get_height(), 2):
		for x in range(0, image.get_width(), 2):
			samples += 1
			var c := image.get_pixel(x, y)
			if (absf(c.r - BACKGROUND.r) < 0.02
				and absf(c.g - BACKGROUND.g) < 0.02
				and absf(c.b - BACKGROUND.b) < 0.02):
				continue
			lumas.append(c.r * 0.2126 + c.g * 0.7152 + c.b * 0.0722)
			var key := "%d_%d_%d" % [int(c.r * 24.0), int(c.g * 24.0), int(c.b * 24.0)]
			colours[key] = true
	if lumas.is_empty():
		return {"mean": 0.0, "coverage": 0.0, "colours": 0}
	var total := 0.0
	for v in lumas:
		total += v
	return {
		"mean": total / float(lumas.size()),
		"coverage": float(lumas.size()) / float(maxi(samples, 1)),
		"colours": colours.size(),
	}
