extends SceneTree

## SCRATCH PROBE — leading underscore, so the gate skips it. Renamed from
## `tests/winding_probe.gd` on 2026-08-15.
##
## What it was: a dev note that prints whether Godot's front-face winding
## matches the right-hand rule (normal = cross(b-a, c-a)), by inspecting a
## built-in `BoxMesh` surface. What it had become: a gate unit. Without the
## underscore the gate discovered it and scored it PASS in 6 s, forever — it
## prints and calls `quit(0)` unconditionally, so it carries no `TestReport`, no
## assertion, and no way to go red (REALITY.md §4, "a scratch probe left in
## tests/", and §4d finding 6). Two production files then cited it as a
## verification, which it never was.
##
## It was NOT converted into a test in place, deliberately. Its subject is
## Godot's `BoxMesh` — a fact about the engine. The thing that can actually
## break is the vertex order in `StructureBaker._append_box` and
## `VesselSkinBaker._emit_face`, and asserting the engine's convention instead
## of ours is landing one layer below the bug, which is REALITY.md §3 exactly.
##
## The property is now asserted where it belongs: `tests/box_winding_test.gd`
## checks the meshes those emitters actually commit, and re-states the engine
## fact below as one of its checks so a Godot release that flips the convention
## reddens the gate instead of silently inverting every baked normal.
##
## This file stays because printing the raw numbers is still the fastest way to
## see what the engine is doing when that test goes red.

func _initialize() -> void:
	var box := BoxMesh.new()
	var arrays := box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var a := vertices[indices[0]]
	var b := vertices[indices[1]]
	var c := vertices[indices[2]]
	var stored := normals[indices[0]]
	var right_hand := (b - a).cross(c - a).normalized()
	print("stored normal: ", stored, " right-hand cross: ", right_hand)
	print("CONVENTION: ", "RIGHT_HAND (CCW front)" if stored.dot(right_hand) > 0.0 else "CLOCKWISE front")
	quit(0)
