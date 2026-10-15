extends Node
## Bounded regression checks for reversible, owner-scoped forest cuts.
## Run natively: Godot's headless dummy renderer cannot read back MultiMesh transforms.
const PORT_STREAMER = preload("res://scripts/port/building/custom_port_streamer.gd")

class FlatLayout extends RefCounted:
	var half_extent_m := 2048.0
	var world_size_m := 4096.0
	var seed := 424242
	var layout_checksum := "custom-port-forest-fixture"
	func sample_signed_distance(_p: Vector2) -> float: return -500.0
	func sample_height(_p: Vector2) -> float: return 30.0

var failures := 0
var checks := 0

func _ready() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	assert(ShipyardPlaytestMode.active())
	get_tree().create_timer(90).timeout.connect(func(): get_tree().quit(1))
	ForestTreeMesh.request_assets()
	while not ForestTreeMesh.assets_ready(): await get_tree().process_frame
	_test_field_and_near()
	_test_owner_lifecycle()
	_test_distant()
	await _test_worker_upload()
	ForestField.clear()
	print("CUSTOM PORT FOREST ", "PASS" if failures == 0 else "FAIL", " checks=", checks, " failures=", failures)
	get_tree().quit(0 if failures == 0 else 1)

func zone(center: Vector2, half: Vector2) -> Dictionary:
	return {"polygon": PackedVector2Array([
		center + Vector2(-half.x, -half.y), center + Vector2(half.x, -half.y),
		center + Vector2(half.x, half.y), center + Vector2(-half.x, half.y)]),
		"forest_clear_only": true}

func _test_owner_lifecycle() -> void:
	var layout := FlatLayout.new()
	var base := zone(Vector2(-80, 0), Vector2(5, 5))
	var bridge := zone(Vector2(-40, 0), Vector2(5, 5))
	ForestField.initialize(layout, layout.seed, [base])
	ForestField.add_exclusions([bridge])
	var first := WorldForestStreamer.new()
	var other := WorldForestStreamer.new()
	add_child(first)
	add_child(other)
	first.set_process(false)
	other.set_process(false)
	first.set_custom_port_exclusions("first-owner", [zone(Vector2.ZERO, Vector2(5, 5))])
	other.set_custom_port_exclusions("other-owner", [zone(Vector2(40, 0), Vector2(5, 5))])
	first.free()
	check(not ForestField._inside_flatten_zone(Vector2.ZERO), "Forest-first teardown removes its shared field layer")
	check(ForestField._inside_flatten_zone(Vector2(40, 0)), "Forest teardown preserves another streamer's owner")
	check(ForestField._inside_flatten_zone(Vector2(-80, 0)) and ForestField._inside_flatten_zone(Vector2(-40, 0)), "Forest teardown preserves initial and late infrastructure")
	var replacement := WorldForestStreamer.new()
	add_child(replacement)
	replacement.set_process(false)
	# Deliberately exercise a shared key during replacement, including identical
	# geometry. The new renderer owns the layer even when no mask rebuild occurs.
	var shared := [zone(Vector2(80, 0), Vector2(5, 5))]
	other.set_custom_port_exclusions("shared-port", shared)
	replacement.set_custom_port_exclusions("shared-port", shared)
	other.set_custom_port_exclusions("shared-port", [])
	check(ForestField._inside_flatten_zone(Vector2(80, 0)), "Old renderer's late removal cannot clear replacement's identical layer")
	other.set_custom_port_exclusions("shared-port", shared)
	replacement.set_custom_port_exclusions("shared-port", [zone(Vector2(84, 0), Vector2(5, 5))])
	other.free()
	check(ForestField._inside_flatten_zone(Vector2(84, 0)), "Old renderer exit preserves newer replacement geometry")
	replacement.free()
	check(not ForestField._inside_flatten_zone(Vector2(84, 0)), "Replacement exit releases its own layer")

	# Real projection adapter: forest dies first, a record is removed while it
	# is unbound, and then a fresh forest is attached. Nothing can resurrect it.
	var world := {"seed": 73119, "generation_version": 1, "checksum": "forest-lifecycle"}
	var plots: Array = [{"id": "plot", "rect_m": [-200, -200, 400, 400], "owner_company_id": CustomPortExample.OWNER}]
	var record := CustomPortExample.build(Vector3(0, .5, 0), plots, world)
	record.erase("_site_yaw")
	var ports := PORT_STREAMER.new()
	add_child(ports)
	ports.configure(world)
	ports.loader.set_process(false)
	var old_forest := WorldForestStreamer.new()
	add_child(old_forest)
	old_forest.set_process(false)
	ports.bind_environment(null, old_forest)
	check(ports.upsert_record(record).ok, "Lifecycle fixture imports real validated port")
	var probe := Vector2(-2, 6)
	check(ForestField._inside_flatten_zone(probe), "Imported port installs its forest footprint")
	old_forest.free()
	check(not ForestField._inside_flatten_zone(probe), "Forest-first teardown cleans a still-bound custom port")
	check(ports.remove_record(record.id, 1).ok, "Port record can be removed after its forest is gone")
	var new_forest := WorldForestStreamer.new()
	add_child(new_forest)
	new_forest.set_process(false)
	ports.bind_environment(null, new_forest)
	check(not ForestField._inside_flatten_zone(probe), "Rebinding cannot restore a removed port's clearance")
	record.revision = 2
	check(ports.upsert_record(record).ok and ForestField._inside_flatten_zone(probe), "A newer retained record can install on the replacement forest")
	ports.bind_environment(null, null)
	check(not ForestField._inside_flatten_zone(probe), "Explicit unbind releases the previous forest layer")
	ports.bind_environment(null, new_forest)
	check(ForestField._inside_flatten_zone(probe), "Rebind restores only currently retained port records")
	ports.free()
	check(not ForestField._inside_flatten_zone(probe), "Projection-first teardown also releases forest layers")
	new_forest.free()

func _test_field_and_near() -> void:
	var layout := FlatLayout.new()
	ForestField.initialize(layout, layout.seed)
	var site := Vector2.ZERO
	var density := 0.0
	for z in range(-6, 7):
		for x in range(-6, 7):
			var p := Vector2(x, z) * 256 + Vector2(128, 128)
			if ForestField.sample(p) > density:
				site = p
				density = ForestField.sample(p)
	check(density > .5, "Fixture must be real dense deterministic ForestField coverage")
	var base := zone(site + Vector2(-82, -82), Vector2(18, 18))
	ForestField.initialize(layout, layout.seed, [base])
	var coverage := ForestField.coverage_texture()
	var pixels := coverage.get_image().get_data()
	var p := site + Vector2(-30, 0)
	var q := site + Vector2(30, 0)
	var original_p := ForestField.sample(p)
	var original_q := ForestField.sample(q)
	var a := zone(p, Vector2(40, 35))
	var b := zone(q, Vector2(40, 35))
	ForestField.set_custom_port_exclusions("alpha", [a])
	check(ForestField.sample(p) == 0, "Owner add clears supplied footprint")
	check(ForestField.sample(q) == original_q, "Owner add preserves outside footprint")
	ForestField.set_custom_port_exclusions("alpha", [b])
	check(ForestField.sample(p) == original_p and ForestField.sample(q) == 0, "Replacing an owner restores its old footprint")
	ForestField.set_custom_port_exclusions("beta", [a])
	ForestField.set_custom_port_exclusions("alpha", [])
	check(ForestField.sample(site) == 0 and ForestField.sample(q) == original_q, "Removing one overlapping owner retains the other")
	ForestField.add_exclusions([zone(p, Vector2(5, 5))])
	ForestField.set_custom_port_exclusions("beta", [])
	check(ForestField.sample(p) == 0, "Late bridge-style exclusions survive custom owner removal")
	check(ForestField.sample(site + Vector2(-82, -82)) == 0, "Initial exclusions survive custom owner removal")
	check(ForestField.sample(q) == original_q, "Custom removal restores natural density exactly")
	check(ForestField.coverage_texture() == coverage and coverage.get_image().get_data() == pixels, "Custom cuts preserve base coverage texture and pixels")

	# Streamer invalidation must preserve unrelated nodes and unfinished work.
	ForestField.initialize(layout, layout.seed)
	var streamer := WorldForestStreamer.new()
	add_child(streamer)
	streamer.set_process(false)
	streamer._layout = layout
	var coord := Vector2i(floori(site.x / 256), floori(site.y / 256))
	var other := coord + Vector2i(2, 0)
	streamer._build_chunk(coord, 0)
	streamer._build_chunk(other, 0)
	var original: Array = streamer._chunks[coord].transforms.duplicate()
	var untouched: Dictionary = streamer._chunks[other].duplicate()
	check(original.size() > 100, "Near fixture has enough production placements")
	var affected_job := WorldForestStreamer.create_placement_job(coord, 6.5, 1521)
	var untouched_job := WorldForestStreamer.create_placement_job(other, 6.5, 1521)
	WorldForestStreamer.advance_placement_job(layout, affected_job, [], 300)
	WorldForestStreamer.advance_placement_job(layout, untouched_job, [], 300)
	streamer._jobs.assign([{"coord": coord, "tier": 0, "placement": affected_job}, {"coord": other, "tier": 0, "placement": untouched_job}])
	streamer.set_custom_port_exclusions("port", [a])
	check(not streamer._chunks.has(coord), "Custom edit invalidates affected loaded near patch")
	check(streamer._chunks.has(other) and streamer._chunks[other] == untouched, "Custom edit preserves unrelated loaded near patch")
	check(not streamer._jobs[0].has("placement"), "Custom edit discards partially accepted affected roots")
	check(streamer._jobs[1].placement == untouched_job and int(untouched_job.cursor) == 300, "Custom edit preserves unrelated placement progress")
	streamer._build_chunk(coord, 0)
	var cut: Array = streamer._chunks[coord].transforms
	check(cut.size() < original.size(), "Affected patch rebuild removes actual trees")
	for xf: Transform3D in cut:
		check(not ForestField.inside_flatten_zones(Vector2(xf.origin.x, xf.origin.z), [a]), "Near rebuild contains no tree in footprint")
	streamer.set_custom_port_exclusions("port", [])
	streamer._build_chunk(coord, 0)
	check(streamer._chunks[coord].transforms == original, "Near undo restores exact deterministic transforms")
	check(streamer._chunks[other] == untouched, "Near undo still preserves unrelated loaded node")
	check(ForestField.sample(p) > 0, "Public streamer removal updates ForestField")
	streamer.set_custom_port_exclusions("whole-patch", [zone(site, Vector2(130, 130))])
	streamer._build_chunk(coord, 0)
	check(streamer._chunks[coord].instances == 0, "Fully cleared patches retain an empty cache entry")
	streamer.set_custom_port_exclusions("whole-patch", [])
	check(not streamer._chunks.has(coord), "Undo invalidates previously empty cleared patch")
	streamer._build_chunk(coord, 0)
	check(streamer._chunks[coord].transforms == original, "Previously empty cleared patch regrows exact original trees")
	streamer.free()

func _new_distant() -> DistantForest:
	var node := DistantForest.new()
	node.layout = FlatLayout.new()
	node.layout.half_extent_m = 200
	node.layout.world_size_m = 400
	node.cell_m = 100
	for species in 4: node.meshes.append(ForestTreeMesh.species_mesh(species, false))
	add_child(node)
	node.set_process(false)
	return node

func _groups(offset := Vector2.ZERO) -> Array:
	var data := PackedFloat32Array()
	for z in 30:
		for x in 30:
			data.append_array(PackedFloat32Array([-174.0 + x * 12 + offset.x, 27.5, -174.0 + z * 12 + offset.y, .8 + (x % 5) * .1]))
	return [data, PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]

func _upload(node: DistantForest, key: Vector2i, groups: Array) -> void:
	node.display_batches[key] = groups
	node.upload_batch(key)

func _snapshot(node: DistantForest) -> Dictionary:
	var result := {}
	for child in node.get_children():
		if not child is MultiMeshInstance3D: continue
		for i in child.multimesh.instance_count:
			var xf: Transform3D = child.multimesh.get_instance_transform(i)
			result[Vector2(xf.origin.x, xf.origin.z)] = {"transform": xf, "species": node.meshes.find(child.multimesh.mesh)}
	return result

func _filtered(original: Dictionary, zones: Array) -> Dictionary:
	var result := {}
	for point: Vector2 in original:
		if not ForestField.inside_flatten_zones(point, zones): result[point] = original[point]
	return result

func _drain(node: DistantForest) -> void:
	for attempt in 1000:
		if node.exclusion_jobs.is_empty(): return
		node._process_exclusions()
	check(false, "Distant exclusion work failed to converge")

func _test_distant() -> void:
	var a := zone(Vector2(-70, 0), Vector2(60, 130))
	var b := zone(Vector2(20, 0), Vector2(60, 130))
	var legacy := zone(Vector2(0, 120), Vector2(130, 15))
	var node := _new_distant()
	_upload(node, Vector2i.ZERO, _groups())
	_upload(node, Vector2i(1, 0), _groups(Vector2(400, 0)))
	var original := _snapshot(node)
	print("DISTANT FIXTURE initial roots=", original.size(), " trees=", node.trees)
	var unaffected := node.get_child(node.get_child_count() - 1)
	var unaffected_id := unaffected.get_instance_id()
	node.set_custom_port_exclusions("alpha", [a])
	_drain(node)
	check(node.retained_batches.size() == 1, "Only custom-affected distant batches retain undo data")
	check(_snapshot(node) == _filtered(original, [a]), "Distant owner add filters exact production transforms")
	node.set_custom_port_exclusions("alpha", [b])
	_drain(node)
	print("DISTANT FIXTURE replacement roots=", _snapshot(node).size(), " expected=", _filtered(original, [b]).size(), " trees=", node.trees)
	check(_snapshot(node) == _filtered(original, [b]), "Distant replacement restores old footprint")
	node.set_custom_port_exclusions("beta", [a])
	_drain(node)
	node.set_custom_port_exclusions("alpha", [])
	_drain(node)
	check(_snapshot(node) == _filtered(original, [a]), "Distant overlapping owner survives another owner removal")
	node.add_exclusions([legacy])
	_drain(node)
	node.set_custom_port_exclusions("beta", [])
	_drain(node)
	check(node.retained_batches.is_empty(), "Last owner removal releases distant undo storage")
	check(_snapshot(node) == _filtered(original, [legacy]), "Distant late legacy cut survives restoring original custom batch")
	check(is_instance_valid(unaffected) and unaffected.get_instance_id() == unaffected_id, "Distant edits preserve unrelated live node identity")
	check(node.trees == _snapshot(node).size(), "Distant tree counter matches visible placements")
	node.free()

	# Worker output first uploaded under an existing cut must retain its full source.
	var fresh := _new_distant()
	fresh.set_custom_port_exclusions("alpha", [a])
	_upload(fresh, Vector2i.ZERO, _groups())
	var cut_snapshot := _snapshot(fresh)
	check(cut_snapshot.size() < 900 and cut_snapshot.size() > 0, "First upload obeys already-active owner cut")
	fresh.set_custom_port_exclusions("alpha", [])
	_drain(fresh)
	print("DISTANT FIXTURE first-upload restored roots=", _snapshot(fresh).size(), " trees=", fresh.trees)
	check(_snapshot(fresh).size() == 900, "Undo restores source hidden on first upload")
	var pristine := _snapshot(fresh)
	fresh.set_custom_port_exclusions("alpha", [a])
	fresh._process_exclusions()
	check(not fresh.exclusion_jobs.is_empty(), "Fixture exercises partially processed exclusion work")
	fresh.set_custom_port_exclusions("alpha", [b])
	fresh._process_exclusions()
	fresh.set_custom_port_exclusions("alpha", [])
	_drain(fresh)
	check(_snapshot(fresh) == pristine, "Edit then undo during partial filtering cannot commit stale cuts")
	fresh.free()

	# Emulate a published worker batch waiting while the owner changes.
	var pending := _new_distant()
	pending.set_custom_port_exclusions("alpha", [a])
	pending.display_batches[Vector2i.ZERO] = _groups()
	pending.set_custom_port_exclusions("alpha", [b])
	pending.upload_batch(Vector2i.ZERO)
	check(_snapshot(pending) == _filtered(pristine, [b]), "Queued worker upload uses latest owner footprint")
	pending.set_custom_port_exclusions("alpha", [])
	_drain(pending)
	check(_snapshot(pending) == pristine, "Queued worker upload retains pristine undo data")
	pending.free()

func _test_worker_upload() -> void:
	var node := _new_distant()
	node.coverage = Image.create(4, 4, false, Image.FORMAT_R8)
	node.coverage.fill(Color.WHITE)
	node.prepare_density_pixels()
	for y in 4:
		for x in 4: node.jobs.append(Vector2i(x, y))
	var a := zone(Vector2(-70, 0), Vector2(60, 130))
	var b := zone(Vector2(20, 0), Vector2(60, 130))
	node.set_custom_port_exclusions("worker-port", [a])
	node.worker = Thread.new()
	node.worker.start(node.generate)
	node.set_custom_port_exclusions("worker-port", [b])
	while node.worker.is_alive(): await get_tree().process_frame
	# Drain the real production publication/worker-join path after the edit.
	node._process(0)
	var cut := _snapshot(node)
	print("DISTANT WORKER roots=", cut.size(), " trees=", node.trees, " uploads=", node.uploads.size(), " batches=", node.rendered_batches.size())
	check(cut.size() > 100, "Real worker produced a populated deterministic batch")
	var leaked := 0
	for point: Vector2 in cut:
		if ForestField.inside_flatten_zones(point, [b]): leaked += 1
	check(leaked == 0, "Real worker result uploaded after edit obeys latest owner zone")
	node.set_custom_port_exclusions("worker-port", [])
	_drain(node)
	var restored := _snapshot(node)
	check(restored.size() > cut.size(), "Real worker upload retains original placements for undo")
	check(_filtered(restored, [b]) == cut, "Worker upload/undo preserves exact positions, scales and species")
	node.free()
