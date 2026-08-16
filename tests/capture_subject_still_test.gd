extends Node

## Lane B (a sibling `.tscn` exists): `VesselSpawn` reaches autoloads by bare
## identifier, so `--script` cannot run this file. Check the lane before
## diagnosing a failure here (CONVENTIONS §2).
##
## ── The guarantee this scores ───────────────────────────────────────────────
##
## Every capture rig in this repo photographs a vessel it believes it has
## stopped. **A capture of a moving subject is not evidence**: the difference
## between two runs is then the phase of a physics transient, not a change in
## the thing being photographed, and that is precisely the state
## `_small_hull_shot`, `_hull_iter_shot` and `_fittings_shot` were in — recorded
## in their own headers as a "sub-pixel edge race" of unknown origin.
##
## It is not a race and it is not sub-pixel by nature. `boat.freeze = true` is
## revoked by `BoatBody`'s own physics LOD one second after enter-tree; see
## `tests/support/capture_subject.gd` for the mechanism and the measurements.
##
## So the property is: **after `CaptureSubject.hold_still`, the subject's
## `global_transform` is unchanged in its exact float bits for longer than the
## capture takes** — and `freeze` is still true at the end, because the rig
## asked for it.
##
## Bits, not `is_equal_approx`: the whole defect is a 1.15 mm move that any
## tolerance a person would write down would pass, and which moves every
## silhouette edge by a pixel.
##
## ── Coverage ────────────────────────────────────────────────────────────────
##
## Both construction paths the three rigs use, because they are different code:
## `HullRegistry.build_hull` (`_small_hull_shot`, `_hull_iter_shot`) and
## `VesselSpawn.instantiate` (`_fittings_shot`). A fixture that fails to build
## is a recorded FAILURE naming what it wanted, never an early return
## (REALITY §4).

const TestReport := preload("res://tests/support/test_report.gd")
const CaptureSubject := preload("res://tests/support/capture_subject.gd")

## `BoatBody._physics_process` fires `_update_automatic_physics_quality()` when
## `_physics_lod_timer` reaches 1.0 s, i.e. after 60 physics ticks at 60 Hz.
## 150 crosses that threshold twice over, so a subject that is going to be
## un-frozen has had two chances to be.
const PHYSICS_FRAMES := 150

var _t: TestReport


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("capture_subject_still_test")
	await _hull_registry_path("hull_15x5")
	await _hull_registry_path("hull_28x10")
	await _vessel_spawn_path("hull_28x10")
	_t.finish(get_tree())


func _hull_registry_path(hull_id: String) -> void:
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var boat: BoatBody = HullRegistry.build_hull(hull_id)
	if not _t.check("%s: HullRegistry.build_hull returned a hull" % hull_id, boat != null):
		world.queue_free()
		return
	boat.freeze = true
	world.add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3(0.0, -1.5 - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	await _assert_still("%s (HullRegistry.build_hull)" % hull_id, boat)
	world.queue_free()
	await get_tree().process_frame


func _vessel_spawn_path(hull_id: String) -> void:
	var world := Node3D.new()
	get_tree().root.add_child(world)
	var plan := StructurePlan.new()
	plan.hull_id = hull_id
	plan.add_deck(Vector3(1.0, 0.0, 3.0), Vector2(8.0, 22.0))
	plan.add_item("bollard_pair", Vector3(1.6, 0.0, 5.0), 90.0)
	var boat: BoatBody = VesselSpawn.instantiate(hull_id, plan.to_dict(), "general_vessel")
	if not _t.check("%s: VesselSpawn.instantiate returned a vessel" % hull_id, boat != null):
		world.queue_free()
		return
	boat.freeze = true
	world.add_child(boat)
	CaptureSubject.hold_still(boat)
	boat.position = Vector3(0.0, -1.5 - boat.draft_m - boat.hull_stations.keel_y, 0.0)
	await _assert_still("%s (VesselSpawn.instantiate)" % hull_id, boat)
	world.queue_free()
	await get_tree().process_frame


## The property, in exact bits.
func _assert_still(label: String, boat: BoatBody) -> void:
	await get_tree().physics_frame
	var before := _bits(boat.global_transform)
	for _i in PHYSICS_FRAMES:
		await get_tree().physics_frame
	var after := _bits(boat.global_transform)
	if before != after:
		var moved_m: float = absf(boat.global_position.y - _origin_y(before))
		_t.check(
			"%s: subject held still for %d physics frames (moved %.6f m in y — %s -> %s)"
			% [label, PHYSICS_FRAMES, moved_m, before, after],
			false,
		)
	else:
		_t.check("%s: subject held still for %d physics frames" % [label, PHYSICS_FRAMES], true)
	_t.check("%s: freeze is still true after the LOD had its chance" % label, boat.freeze)
	_t.check(
		"%s: velocity is exactly zero" % label,
		boat.linear_velocity == Vector3.ZERO and boat.angular_velocity == Vector3.ZERO,
	)


func _bits(t: Transform3D) -> String:
	return PackedFloat32Array([
		t.basis.x.x, t.basis.x.y, t.basis.x.z,
		t.basis.y.x, t.basis.y.y, t.basis.y.z,
		t.basis.z.x, t.basis.z.y, t.basis.z.z,
		t.origin.x, t.origin.y, t.origin.z,
	]).to_byte_array().hex_encode()


func _origin_y(bits: String) -> float:
	var bytes := PackedByteArray()
	for i in range(bits.length() / 2):
		bytes.append(("0x" + bits.substr(i * 2, 2)).hex_to_int())
	return bytes.to_float32_array()[10]
