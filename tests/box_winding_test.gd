extends SceneTree

## Lane A. Holds the project's triangle-winding convention to the emitter that
## actually draws with it.
##
## WHY THIS FILE EXISTS. `tests/winding_probe.gd` used to sit in this directory
## without a leading underscore, so the gate discovered it and scored it PASS in
## 6 s. It printed the convention it found in a built-in `BoxMesh` and called
## `quit(0)` unconditionally: no `TestReport`, no assertion, no way to go red.
## `structure_baker.gd` and `vessel_skin_baker.gd` both cited it — "verified in
## tests/winding_probe.gd", "see winding_probe" — for a claim about THEIR
## geometry, which it never touched (REALITY.md §4 and §4d.6, and the corollary:
## a citation is not a verification).
##
## It was also pointed one layer below the bug (REALITY.md §3). What can break
## is `StructureBaker._append_box`'s vertex order; what the probe inspected was
## Godot's `BoxMesh`. So the probe has been renamed `_winding_probe.gd` — it is
## a dev note about the engine, and it is kept because the engine's convention
## is the input to ours — and the property it was standing in for is asserted
## here, on the mesh the baker emits, through `SurfaceTool.commit()`.
##
## The two claims are stated as PROPERTIES, not as the numbers in the header:
##
##   1. every stored normal points AWAY from the box centre;
##   2. the right-hand cross of every triangle's vertex order is MINUS that
##      stored normal — which is what "Godot's clockwise-front winding" means.
##
## MUTATION VERIFIED, twice, against a pristine copy of the tree (the working
## tree's `structure_baker.gd` was never edited — it belongs to another agent):
##
##   control                                          PASS (18 checks)
##   -Z face emitted [0,2,1]+[0,3,2] instead of
##     [0,1,2]+[0,2,3]                                3/18 FAILED, 10 of 12
##   +X face declared with normal Vector3(-1, 0, 0)   6/18 FAILED, 10 of 12
##   control again, after restoring                   PASS (18 checks)
##
## The second mutation reddens BOTH properties, which is the point of stating
## two: a flipped normal is caught by the outward test and by the winding test
## independently, so neither is standing in for the other.

const TestReport := preload("res://tests/support/test_report.gd")

## Counts boxes that reached the END of `_check_appended_box`. A GDScript
## runtime error aborts the enclosing function but leaves the caller running, so
## without this a broken sub-check would silently contribute NOTHING and the run
## would still report PASS on whatever ran before it — which is what the first
## draft of this file did (5 checks, three aborted boxes, green).
var _measured := 0


func _initialize() -> void:
	var t := TestReport.new("box_winding_test")
	_check_engine_convention(t)
	_check_appended_box(t, "axis-aligned", Vector3(3.0, 2.0, 5.0), Vector3(2.0, 4.0, 6.0), Basis.IDENTITY)
	_check_appended_box(
		t,
		"rotated 37 deg about Y",
		Vector3(-11.0, 0.5, 4.0),
		Vector3(1.5, 3.0, 8.0),
		Basis(Vector3.UP, deg_to_rad(37.0)),
	)
	_check_appended_box(
		t,
		"rotated about all three axes",
		Vector3.ZERO,
		Vector3(2.0, 2.0, 2.0),
		Basis.from_euler(Vector3(deg_to_rad(20.0), deg_to_rad(-50.0), deg_to_rad(15.0))),
	)
	t.equal("all three boxes were measured end to end", _measured, 3)
	t.finish(self)


## The engine's own convention, which is the INPUT to ours: this is the fact
## `winding_probe.gd` printed. Stated as a check so that a Godot release which
## flips it reddens here instead of silently inverting every baked normal.
func _check_engine_convention(t: TestReport) -> void:
	var box := BoxMesh.new()
	var arrays := box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if not t.check("BoxMesh surface has vertices, normals and indices",
			vertices.size() > 0 and normals.size() == vertices.size() and indices.size() >= 3):
		return
	var agreeing := 0
	var triangles := indices.size() / 3
	for tri in range(triangles):
		var a := vertices[indices[tri * 3]]
		var b := vertices[indices[tri * 3 + 1]]
		var c := vertices[indices[tri * 3 + 2]]
		var stored := normals[indices[tri * 3]]
		if (b - a).cross(c - a).normalized().dot(stored) < 0.0:
			agreeing += 1
	t.equal(
		"every BoxMesh triangle winds clockwise-front (right-hand cross is MINUS the stored normal) over %d triangles" % triangles,
		agreeing,
		triangles,
	)


## The real subject: the boxes this project draws.
func _check_appended_box(t: TestReport, label: String, center: Vector3, size: Vector3, basis: Basis) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	StructureBaker._append_box(st, center, size, basis, Color.WHITE)
	var mesh := st.commit()
	if not t.check("%s: SurfaceTool committed a mesh" % label, mesh != null and mesh.get_surface_count() == 1):
		return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	## `commit()` leaves this surface UNINDEXED — `arrays[Mesh.ARRAY_INDEX]` is
	## `null`, not an empty PackedInt32Array, and assigning that to a typed
	## variable is a runtime error that aborts this whole function. Read it as a
	## Variant and resolve both shapes into one flat triangle list, so the checks
	## below do not depend on which one `commit()` chose.
	var raw_indices: Variant = arrays[Mesh.ARRAY_INDEX]
	var order := PackedInt32Array()
	if raw_indices is PackedInt32Array and (raw_indices as PackedInt32Array).size() >= 3:
		order = raw_indices as PackedInt32Array
	else:
		order.resize(vertices.size())
		for i in range(vertices.size()):
			order[i] = i
	if not t.check("%s: normals array matches the vertex array (%d vs %d)"
			% [label, normals.size(), vertices.size()], normals.size() == vertices.size()):
		return
	var triangles := order.size() / 3
	if not t.check("%s: emitted 12 triangles (6 faces x 2), got %d" % [label, triangles], triangles == 12):
		return

	var outward_ok := 0
	var winding_ok := 0
	var worst_outward := 1.0
	var worst_winding := -1.0
	for tri in range(triangles):
		var ia := order[tri * 3]
		var ib := order[tri * 3 + 1]
		var ic := order[tri * 3 + 2]
		var a := vertices[ia]
		var b := vertices[ib]
		var c := vertices[ic]
		var stored: Vector3 = normals[ia]
		## PROPERTY 1: the stored normal points away from the box centre. Uses
		## the triangle's own centroid rather than the declared face normal, so
		## the check does not restate the table `_append_box` is built from.
		var centroid := (a + b + c) / 3.0
		var outward := (centroid - center).normalized()
		var away: float = stored.normalized().dot(outward)
		worst_outward = minf(worst_outward, away)
		if away > 0.0:
			outward_ok += 1
		## PROPERTY 2: right-hand cross of the vertex order is MINUS the stored
		## normal. This is the whole of "Godot's clockwise-front winding".
		var right_hand := (b - a).cross(c - a)
		var alignment: float = right_hand.normalized().dot(stored.normalized())
		worst_winding = maxf(worst_winding, alignment)
		if alignment < 0.0:
			winding_ok += 1

	t.equal(
		"%s: every stored normal points out of the box (worst centroid dot = %.4f)" % [label, worst_outward],
		outward_ok,
		triangles,
	)
	t.equal(
		"%s: every triangle winds clockwise-front — right-hand cross opposes the stored normal (worst dot = %.4f)" % [label, worst_winding],
		winding_ok,
		triangles,
	)
	_measured += 1
