extends Node

## Photographs a vessel built from a `structure_plan_v1` data object.
##
## This is the instrument the ship-parts work runs on: a plan goes in, a set of
## canonical-angle PNGs and a set of machine-checkable claims come out. No UI,
## no clicking, no display — the loop an agent can run and a human can review.
##
##   tools/capture.sh                       # every fixture
##   tools/capture.sh demo_workboat         # one, by stem
##
## Runs in the SCENE lane, not `--script`. `VesselSpawn` reaches BoatBody, which
## transitively names the WorldGateway autoload, and `--script` registers no
## autoloads — so this must boot as a main scene or it cannot compile.
##
## Views use the project's vessel orientation: bow -Z, stern +Z, port -X,
## starboard +X.

const TestReport := preload("res://tests/support/test_report.gd")

const OUT_DIR := "res://screenshots/studio"
const SETTLE_FRAMES := 6

## Fixture plans. A capture is only evidence if the same input always produces
## the same framing, so the angles are fixed and the names are stable —
## re-running overwrites rather than accumulating, which is what makes two runs
## diffable.
const FIXTURES: Array[String] = [
	"res://resources/data/structures/demo_workboat.json",
	"res://resources/data/structures/probe_trawler_bulwark.json",
	"res://resources/data/structures/probe_trawler_bow_bulwark.json",
	"res://resources/data/structures/probe_ferry_catamaran.json",
	"res://resources/data/structures/probe_spar_kit.json",
	"res://resources/data/structures/probe_ferry_catamaran_trim.json",
]

## A long lens rather than a wide one: 35° keeps the perspective flat enough
## that a hull's sheer and proportions read true, which is the whole point of a
## reference comparison. Framing is then solved from the lens, not guessed.
const FOV_DEGREES := 35.0
const FRAME_MARGIN := 1.12

## azimuth (deg, 0 = dead astern looking forward), elevation (deg).
const VIEWS: Array[Dictionary] = [
	# Port is -X, so a port profile needs the camera at -X: azimuth 270, not 90.
	# At 90 this shot was labelled "port" while showing the starboard side — a
	# reference photograph that lies about which side you are looking at is worse
	# than no photograph.
	{"name": "profile_port", "azimuth": 270.0, "elevation": 3.0},
	{"name": "bow_quarter", "azimuth": 145.0, "elevation": 16.0},
	{"name": "stern_quarter", "azimuth": 35.0, "elevation": 16.0},
	{"name": "plan", "azimuth": 90.0, "elevation": 88.0},
]

## Where the 1.8 m figure stands, in PLAN space, per fixture stem.
##
## A fixed spot is not safe across fixtures and this is the proof: (2.5, 7.0) is
## clear open deck on the 28 m hulls, but on the catamaran it lands at plan
## (10.5, 29.5) — inside the main saloon, under deck plate 30. The figure
## rendered perfectly and appeared in NONE of the four ferry frames, which is
## exactly the failure mode CONVENTIONS §3a says a scale reference must not
## have. Both ferry fixtures shipped that way. A capture with no visible figure
## has no absolute scale, so the spot is data now, one entry per fixture.
const FIGURE_SPOT := {
	"probe_ferry_catamaran": Vector3(12.0, 0.0, 39.0),
	"probe_ferry_catamaran_trim": Vector3(12.0, 0.0, 39.0),
}
const FIGURE_SPOT_DEFAULT := Vector3(2.5, 0.0, 7.0)

var _t: RefCounted
var _camera: Camera3D
var _stage: Node3D

## Renderer counters for the fixture currently on the stage. A MeshInstance3D is
## NOT a draw call — these come off RenderingServer's own per-frame counters,
## sampled after frame_post_draw so the frame they describe is the frame that was
## just photographed. Max over the four canonical views: culling makes the number
## view-dependent, and the worst view is the one a budget has to survive.
var _draw_calls := 0
var _primitives := 0


func _ready() -> void:
	call_deferred("_run")


func _run() -> void:
	_t = TestReport.new("vessel_render_capture")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_hide_autoload_ui()

	var wanted := _requested_stems()
	var ran := 0
	for fixture in FIXTURES:
		var stem := fixture.get_file().get_basename()
		if not wanted.is_empty() and not wanted.has(stem):
			continue
		await _capture_plan(fixture, stem)
		ran += 1

	if ran == 0:
		_t.fail("no fixture matched %s" % [wanted])
	_t.finish(get_tree())


## The scene lane boots the real autoloads, and several of them (GameMenu,
## DebugHud, LoadingGate) draw a HUD over everything. That HUD landed in the
## first captures — a currency chip floating over the vessel. A reference
## comparison must contain the vessel and nothing else.
func _hide_autoload_ui() -> void:
	for child in get_tree().root.get_children():
		if child == self:
			continue
		_hide_canvas_items(child)


func _hide_canvas_items(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
		return
	if node is CanvasItem:
		(node as CanvasItem).visible = false
		return
	for child in node.get_children():
		_hide_canvas_items(child)


## `-- <stem> <stem>` selects a subset; no args means everything.
func _requested_stems() -> PackedStringArray:
	var stems := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if not text.begins_with("--"):
			stems.append(text)
	return stems


func _capture_plan(path: String, stem: String) -> void:
	print("[capture] %s" % stem)

	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(raw) != TYPE_DICTIONARY:
		_t.fail("%s: plan is not a JSON object" % stem)
		return
	var data := raw as Dictionary
	if not _t.check("%s: is a structure plan" % stem, StructurePlan.is_plan(data)):
		return

	var plan := StructurePlan.from_dict(data)
	_t.check("%s: plan has entities" % stem, plan.entity_count() > 0)

	_stage = Node3D.new()
	add_child(_stage)
	_light_the_stage()

	# The plan is authored in grid-corner space; the studio centres it on the
	# hull with this offset, and a capture that used a different one would be
	# photographing something the builder never sees.
	var offset := Vector3.ZERO
	var deck_y := 0.0
	if plan.context == "vessel" and plan.hull_id != "":
		var grid := HullRegistry.make_grid(plan.hull_id)
		if grid != null:
			offset = Vector3(-grid.half_beam, 0.0, -grid.half_loa)
			deck_y = grid.deck_y
			var boat: Node3D = VesselSpawn.instantiate(plan.hull_id, {}, "")
			if _t.check("%s: hull %s instantiates" % [stem, plan.hull_id], boat != null):
				_stage.add_child(boat)
				boat.position = Vector3(0.0, -deck_y, 0.0)
				if boat is PhysicsBody3D:
					(boat as PhysicsBody3D).freeze = true
				boat.process_mode = Node.PROCESS_MODE_DISABLED

	_add_scale_figure(offset, stem)

	var built: Node3D = StructureBaker.bake(plan, offset)
	if not _t.check("%s: plan bakes to a node" % stem, built != null):
		return
	_stage.add_child(built)

	var meshes := _count_meshes(built)
	_t.check("%s: bake produced geometry (%d surfaces)" % [stem, meshes], meshes > 0)

	# Draw-call budget is the governing constraint — harbours are full of these.
	# A merged bake should stay in the tens, not the hundreds. If this trips,
	# something stopped merging.
	_t.check("%s: bake stays merged (%d mesh instances)" % [stem, meshes], meshes <= 64)

	var bounds := _world_bounds(_stage)
	_t.check("%s: vessel has a real extent" % stem, bounds.size.length() > 1.0)

	_check_fittings(plan, stem)
	_check_rigging_attaches(plan, stem)
	_check_fall_protection(plan, stem)

	_draw_calls = 0
	_primitives = 0
	for view in VIEWS:
		await _shoot(bounds, "%s__%s" % [stem, view["name"]], view)
	print("  [cost] %s  draw_calls=%d  triangles=%d  surfaces=%d" % [
		stem, _draw_calls, _primitives, meshes,
	])
	_check_cost(stem, meshes)

	_stage.queue_free()
	_stage = null
	await get_tree().process_frame


## ── Cost ────────────────────────────────────────────────────────────────────
##
## `draw_calls` is the number this fixture drew BEFORE it carried a single
## fitting, measured on the renderer's own counter. Dressing a vessel must not
## move it: the baker buckets on MATERIAL ALONE and every fitting in these
## fixtures is painted / steel / wood, the three buckets each plan already had.
## Introduce a fourth material and this goes red by exactly one — which is the
## whole point of asserting the pre-dressing number rather than a round budget.
##
## `triangles` is the dressed measurement plus ~8%: geometry is what a rig
## actually costs, and the number is here so the cost is visible in the diff
## rather than discovered in a harbour.
const COST_BUDGET := {
	"demo_workboat": {"draw_calls": 8, "triangles": 12600},
	"probe_trawler_bulwark": {"draw_calls": 8, "triangles": 12100},
	"probe_trawler_bow_bulwark": {"draw_calls": 8, "triangles": 12200},
	"probe_ferry_catamaran": {"draw_calls": 10, "triangles": 19000},
	"probe_spar_kit": {"draw_calls": 9, "triangles": 9400},
	"probe_ferry_catamaran_trim": {"draw_calls": 10, "triangles": 19600},
}


func _check_cost(stem: String, meshes: int) -> void:
	if not COST_BUDGET.has(stem):
		return
	var budget := COST_BUDGET[stem] as Dictionary
	## x2 for the same reason as triangles: the shadow pass issues its own draw
	## calls over the same surfaces. The vessel did not get more expensive when
	## the sun learned to cast.
	var calls := int(budget["draw_calls"]) * 2
	_t.check(
		"%s: %d draw calls against the %d it drew undressed" % [stem, _draw_calls, calls],
		_draw_calls <= calls
	)
	## Budgets are x2 because the sun now casts shadows, and a shadow map is a
	## second pass over the same geometry — RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	## counts a triangle once per pass, not once per mesh. The scene did not get
	## heavier; the counter started telling the truth about what is drawn.
	var tris := int(budget["triangles"]) * 2
	_t.check("%s: %d triangles, budget %d" % [stem, _primitives, tris], _primitives <= tris)
	## A `meshes <= 4` check was written here and deleted after it survived its
	## own mutant. Retinting a mast into a fourth material bucket took this
	## fixture from 3 surfaces to 4 and from 8 draw calls to 9: the draw-call
	## line above went red, this one did not, because MATERIALS has exactly four
	## entries and every unknown name falls back to "painted" — so no plan can
	## ever push it over. It would only fail if the BAKER regressed, which no
	## fixture edit can provoke. That is a blind check, not a cheap one, and the
	## draw-call assertion already covers the same regression with a number that
	## moves. `meshes <= 64` above still catches a total loss of merging.
	print("  [cost] %s  bake surfaces=%d (bounded by MATERIALS, not asserted)" % [stem, meshes])


## ── Every fitting draws ─────────────────────────────────────────────────────
##
## An items[] entry whose primitive the baker cannot read emits nothing at all,
## silently — the baker's own note records `polyline_of` once drawing every wire
## as nothing because a PackedVector3Array is not an Array. A fixture full of
## fittings that renders as a bare hull is the failure this catches.
func _check_fittings(plan: StructurePlan, stem: String) -> void:
	var drawable := 0
	var mute := 0
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var primitive := StructureBaker.item_primitive(item)
		if primitive != "spar" and primitive != "wire":
			mute += 1
			continue
		if StructureBaker.spar_path(StructurePlan.item_props(item)).size() >= 2:
			drawable += 1
		else:
			mute += 1
	if plan.items.is_empty():
		return
	_t.check(
		"%s: all %d fittings resolve to a drawn tube (%d mute)" % [stem, plan.items.size(), mute],
		mute == 0 and drawable == plan.items.size()
	)


## ── Rigging is made fast to something ───────────────────────────────────────
##
## A stay whose end floats in mid-air renders as a line to nowhere, and at
## capture resolution it looks exactly like a stay that is made fast. Every wire
## end must land on a spar's own polyline or inside plan geometry. Caught three
## real ones: a forestay ending on empty centreline (the plan has no bow
## fitting — it got a samson post), a davit fall hanging free, and a backstay
## 0.15 m short of the transom cap.
##
## probe_spar_kit is out of scope and stays that way: it is the PRIMITIVE
## exerciser, not a vessel, and five of its ten wire ends are deliberately made
## fast to nothing — a stowed mooring line running off the plan, shrouds landing
## where no fitting exists. That is correct for a fixture whose job is to prove
## sag reaches zero, and it would be a defect on a ship. Naming the exemption is
## the honest version of scoping; silently skipping it is not.
const RIG_TOL := 0.3
const RIG_EXEMPT := ["probe_spar_kit"]


func _check_rigging_attaches(plan: StructurePlan, stem: String) -> void:
	if RIG_EXEMPT.has(stem):
		print("  [rig] %s: primitive probe, wire ends deliberately free — not checked" % stem)
		return
	var spar_paths: Array = []
	var wire_ends: Array = []
	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var primitive := StructureBaker.item_primitive(item)
		if primitive != "spar" and primitive != "wire":
			continue
		var path := StructureBaker.spar_path(StructurePlan.item_props(item))
		if path.size() < 2:
			continue
		var xform := plan.item_transform(item)
		var world := PackedVector3Array()
		for point in path:
			world.append(xform * point)
		if primitive == "wire":
			wire_ends.append(world[0])
			wire_ends.append(world[world.size() - 1])
		else:
			spar_paths.append(world)
	if wire_ends.is_empty():
		print("  [rig] %s: no wire in this fixture — nothing checked" % stem)
		return
	var colliders := StructureBaker.collect_colliders(plan)
	var loose := 0
	var first := Vector3.ZERO
	for end_variant in wire_ends:
		var end := end_variant as Vector3
		if _near_polyline(spar_paths, end) or _near_solid(colliders, end):
			continue
		if loose == 0:
			first = end
		loose += 1
	_t.check(
		"%s: all %d wire ends made fast (%d loose, first %v)" % [
			stem, wire_ends.size(), loose, first,
		],
		loose == 0
	)


func _near_polyline(paths: Array, point: Vector3) -> bool:
	for path_variant in paths:
		var path := path_variant as PackedVector3Array
		for index in range(path.size() - 1):
			if Geometry3D.get_closest_point_to_segment(
				point, path[index], path[index + 1]
			).distance_to(point) <= RIG_TOL:
				return true
	return false


func _near_solid(colliders: Array, point: Vector3) -> bool:
	for collider_variant in colliders:
		var collider := collider_variant as Dictionary
		var size := (collider["size"] as Vector3) * 0.5 + Vector3.ONE * RIG_TOL
		if _in_box(collider, point, size):
			return true
	return false


## `yaw_deg` follows wall_yaw_deg: a +Y rotation of theta takes +X to
## (cos, 0, -sin), which is Godot's own `rotated(Vector3.UP, theta)`. So world
## to box-local is a rotation by MINUS the stored yaw.
func _in_box(collider: Dictionary, point: Vector3, half: Vector3) -> bool:
	var centre := collider["center"] as Vector3
	var delta := point - centre
	var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
	if not is_zero_approx(yaw):
		delta = delta.rotated(Vector3.UP, -yaw)
	return absf(delta.x) <= half.x and absf(delta.y) <= half.y and absf(delta.z) <= half.z


## ── Fall protection ─────────────────────────────────────────────────────────
##
## The complaint this answers is literal: a passenger walks off the ferry's
## upper deck. Each run below is an EXPOSED EDGE in plan space — `a` to `b` with
## `in` pointing to the guarded side — walked at 0.1 m stations. A station is
## guarded when some collider the baker actually emits covers a point within
## GUARD_REACH inboard, at a height between GUARD_LO and GUARD_HI above the deck
## the person is standing on. A bulwark satisfies it, a guardrail satisfies it,
## a painted stripe does not.
##
## Stairwell holes are edges too, with `in` pointing AWAY from the hole.
##
## Deliberately not listed: the trawlers' stems. probe_trawler_bulwark's bow is
## open BY DESIGN — closing it is the entire difference between that fixture and
## probe_trawler_bow_bulwark, whose own note already carries a 20 001-station
## measurement of the same claim. Restating it here would be duplicate coverage
## dressed up as new coverage.
const GUARD_REACH := 0.6
const GUARD_LO := 0.85
const GUARD_HI := 1.25
const GUARD_STATION := 0.1
const GUARD_PROBE := 0.05

const FALL_EDGES := {
	"demo_workboat": [
		# Upper deck plate 5: x 1..9, z 8..16, top face y 3.0.
		{"y": 3.0, "a": [1.0, 8.0], "b": [9.0, 8.0], "in": [0.0, 1.0]},
		{"y": 3.0, "a": [9.0, 8.0], "b": [9.0, 16.0], "in": [-1.0, 0.0]},
		{"y": 3.0, "a": [9.0, 16.0], "b": [1.0, 16.0], "in": [0.0, -1.0]},
		{"y": 3.0, "a": [1.0, 16.0], "b": [1.0, 8.0], "in": [1.0, 0.0]},
		# Stairwell hole x 4..5.5, z 10..13. Stair 8 runs +z and tops out at
		# z = 13, so that edge is the arrival and carries no rail.
		{"y": 3.0, "a": [4.0, 10.0], "b": [4.0, 13.0], "in": [-1.0, 0.0]},
		{"y": 3.0, "a": [4.0, 10.0], "b": [5.5, 10.0], "in": [0.0, -1.0]},
		{"y": 3.0, "a": [5.5, 10.0], "b": [5.5, 13.0], "in": [1.0, 0.0]},
	],
	"probe_ferry_catamaran": [],
	"probe_ferry_catamaran_trim": [],
}

## Both ferry fixtures are the same vessel below id 100, so they share one list.
const FERRY_FALL_EDGES: Array = [
	# Main deck, hull edge. Bulwarks 1/2/3 only run z 4..41; the bow and stern
	# bridging decks carry the new guardrail runs instead.
	{"y": 0.0, "a": [0.2, 0.4], "b": [0.2, 44.6], "in": [1.0, 0.0]},
	{"y": 0.0, "a": [15.8, 0.4], "b": [15.8, 44.6], "in": [-1.0, 0.0]},
	{"y": 0.0, "a": [0.2, 0.4], "b": [15.8, 0.4], "in": [0.0, 1.0]},
	{"y": 0.0, "a": [0.2, 44.6], "b": [15.8, 44.6], "in": [0.0, -1.0]},
	# Promenade, deck plate 30: x 1.2..14.8, z 7..37, top face y 3.0.
	{"y": 3.0, "a": [1.2, 7.0], "b": [14.8, 7.0], "in": [0.0, 1.0]},
	{"y": 3.0, "a": [14.8, 7.0], "b": [14.8, 37.0], "in": [-1.0, 0.0]},
	{"y": 3.0, "a": [14.8, 37.0], "b": [1.2, 37.0], "in": [0.0, -1.0]},
	{"y": 3.0, "a": [1.2, 37.0], "b": [1.2, 7.0], "in": [1.0, 0.0]},
	# Stairwell hole, realigned onto stair 50: x 11.4..13.2, z 32.6..36.6. The
	# stair tops out at z = 32.6, so THAT edge is the arrival.
	{"y": 3.0, "a": [11.4, 32.6], "b": [11.4, 36.6], "in": [-1.0, 0.0]},
	{"y": 3.0, "a": [11.4, 36.6], "b": [13.2, 36.6], "in": [0.0, 1.0]},
	{"y": 3.0, "a": [13.2, 32.6], "b": [13.2, 36.6], "in": [1.0, 0.0]},
	# Sun deck, deck plate 31: x 1.6..14.4, z 9..33, top face y 6.0.
	{"y": 6.0, "a": [1.6, 9.0], "b": [14.4, 9.0], "in": [0.0, 1.0]},
	{"y": 6.0, "a": [14.4, 9.0], "b": [14.4, 33.0], "in": [-1.0, 0.0]},
	{"y": 6.0, "a": [14.4, 33.0], "b": [1.6, 33.0], "in": [0.0, -1.0]},
	{"y": 6.0, "a": [1.6, 33.0], "b": [1.6, 9.0], "in": [1.0, 0.0]},
]


func _fall_edges(stem: String) -> Array:
	if stem.begins_with("probe_ferry_catamaran"):
		return FERRY_FALL_EDGES
	return FALL_EDGES.get(stem, []) as Array


func _check_fall_protection(plan: StructurePlan, stem: String) -> void:
	var runs := _fall_edges(stem)
	if runs.is_empty():
		return
	var colliders := StructureBaker.collect_colliders(plan)
	var stations := 0
	var bare := 0
	var first := Vector3.ZERO
	for run_variant in runs:
		var run := run_variant as Dictionary
		var deck_y := float(run["y"])
		var a := _xz(run["a"])
		var b := _xz(run["b"])
		var inward := _xz(run["in"]).normalized()
		var length := a.distance_to(b)
		var steps := maxi(1, int(ceil(length / GUARD_STATION)))
		for index in steps + 1:
			var here := a.lerp(b, float(index) / float(steps))
			stations += 1
			if _guarded(colliders, here, inward, deck_y):
				continue
			if bare == 0:
				first = Vector3(here.x, deck_y, here.y)
			bare += 1
	_t.check(
		"%s: %d/%d exposed-edge stations unguarded (first %v)" % [
			stem, bare, stations, first,
		],
		bare == 0
	)


func _xz(value: Variant) -> Vector2:
	var list := value as Array
	return Vector2(float(list[0]), float(list[1]))


func _guarded(colliders: Array, at: Vector2, inward: Vector2, deck_y: float) -> bool:
	var y_lo := deck_y + GUARD_LO
	var y_hi := deck_y + GUARD_HI
	var probes := int(GUARD_REACH / GUARD_PROBE)
	for step in range(1, probes + 1):
		var offset := inward * (GUARD_PROBE * float(step))
		var point := Vector3(at.x + offset.x, 0.0, at.y + offset.y)
		for collider_variant in colliders:
			var collider := collider_variant as Dictionary
			var centre := collider["center"] as Vector3
			var size := collider["size"] as Vector3
			if centre.y + size.y * 0.5 < y_lo or centre.y - size.y * 0.5 > y_hi:
				continue
			var flat := Vector3(point.x - centre.x, 0.0, point.z - centre.z)
			var yaw := deg_to_rad(float(collider.get("yaw_deg", 0.0)))
			if not is_zero_approx(yaw):
				flat = flat.rotated(Vector3.UP, -yaw)
			if absf(flat.x) <= size.x * 0.5 and absf(flat.z) <= size.z * 0.5:
				return true
	return false


## A 1.8 m figure on deck, in every frame.
##
## Without one, a capture has no absolute scale and a superstructure can be
## proportioned entirely wrong while looking plausible — which is exactly what
## happened. `scenes/shared/player.tscn` is a 1.8-tall capsule with its eye at
## 1.6, so world units are real metres FOR A HUMAN. Hull geometry is not on that
## scale: the catalog calls `hull_28x10` "14.0 × 5.0 m" but draws it 28 units
## long, so next to a 1.8 m player it reads as a 28 m vessel. Anything built on a
## hull must be sized against the figure, not against the catalog's display name.
##
## Matches the studio's own `_build_scale_mannequin` so a plan looks the same
## height in a capture as it does while you are drawing it.
func _add_scale_figure(offset: Vector3, stem: String) -> void:
	var figure := Node3D.new()
	figure.name = "ScaleFigure"

	var body := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.22
	capsule.height = 1.5
	body.mesh = capsule
	body.position = Vector3(0.0, 0.75, 0.0)
	var suit := StandardMaterial3D.new()
	suit.albedo_color = Color(0.95, 0.55, 0.1)
	body.material_override = suit
	figure.add_child(body)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 1.66, 0.0)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.85, 0.70, 0.55)
	head.material_override = skin
	figure.add_child(head)

	# Stand it on the open forward working deck. The first attempt put it at
	# z = 18, which is inside the wheelhouse on the trawler fixtures — the figure
	# rendered and was invisible in every frame, which is the one failure mode a
	# scale reference must not have. This spot is clear of the bow bulwark run,
	# the hatch coaming and the deckhouse on all three fixtures; a plan that
	# builds over it will need the figure placed from the plan rather than fixed.
	#
	# The deck plane is y = 0 in stage space: this rig bakes the plan at the
	# origin and lowers the HULL by deck_y to meet it, rather than raising the
	# plan the way `DeckFitout.apply_plan` does. Adding deck_y here left the
	# figure hanging in the air above the mast.
	figure.position = offset + (FIGURE_SPOT.get(stem, FIGURE_SPOT_DEFAULT) as Vector3)
	_stage.add_child(figure)


func _light_the_stage() -> void:
	# DirectionalLight3D defaults shadow_enabled to FALSE. Every capture before
	# 2026-08-10 shipped with no shadows at all — no mast on the deck, no
	# deckhouse on the hull, nothing self-shadowing — which is most of why the
	# vessels read as flat grey blocks pasted onto a hull. Shadow is not a
	# finishing touch on a low-poly model; it is the only thing separating two
	# untextured surfaces that meet at an angle.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 38.0, 0.0)
	sun.light_energy = 1.15
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.4
	_stage.add_child(sun)

	# The fill deliberately casts nothing: two shadow sets from opposing angles
	# read as dirt, not as light.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-18.0, -125.0, 0.0)
	fill.light_energy = 0.35
	_stage.add_child(fill)

	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.09, 0.13, 0.16)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.55, 0.62, 0.70)
	environment.ambient_light_energy = 0.45
	env.environment = environment
	_stage.add_child(env)

	_camera = Camera3D.new()
	_camera.current = true
	_stage.add_child(_camera)


func _shoot(bounds: AABB, name: String, view: Dictionary) -> void:
	var centre := bounds.get_center()
	var azimuth := deg_to_rad(float(view["azimuth"]))
	var elevation := deg_to_rad(float(view["elevation"]))

	var dir := Vector3(
		cos(elevation) * sin(azimuth),
		sin(elevation),
		cos(elevation) * cos(azimuth),
	)
	# Straight down would make `look_at` degenerate against UP.
	var up_hint := Vector3.UP if float(view["elevation"]) < 85.0 else Vector3.FORWARD
	var right := dir.cross(up_hint).normalized()
	var up := right.cross(dir).normalized()

	# Fitting the bounding SPHERE to the vertical FOV wastes most of a 16:9 frame
	# on a hull that is three times longer than it is tall. Project the eight
	# corners onto the camera's own right/up axes, then solve each axis against
	# its own field of view and take whichever needs more room.
	var half_v := deg_to_rad(FOV_DEGREES) * 0.5
	var aspect := float(get_viewport().size.x) / maxf(1.0, float(get_viewport().size.y))
	var tan_v := tan(half_v)
	var tan_h := tan_v * aspect

	var half_w := 0.0
	var half_h := 0.0
	var half_d := 0.0
	for i in 8:
		var corner := bounds.position + Vector3(
			bounds.size.x * float(i & 1),
			bounds.size.y * float((i >> 1) & 1),
			bounds.size.z * float((i >> 2) & 1),
		)
		var local := corner - centre
		half_w = maxf(half_w, absf(local.dot(right)))
		half_h = maxf(half_h, absf(local.dot(up)))
		half_d = maxf(half_d, absf(local.dot(dir)))

	var distance := maxf(half_h / tan_v, half_w / tan_h) * FRAME_MARGIN + half_d

	_camera.fov = FOV_DEGREES
	_camera.near = maxf(0.05, distance * 0.005)
	_camera.far = distance * 4.0
	_camera.position = centre + dir * distance
	_camera.look_at(centre, up_hint)

	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	_draw_calls = maxi(_draw_calls, int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)))
	_primitives = maxi(_primitives, int(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
	)))

	var image := get_viewport().get_texture().get_image()
	var out := "%s/%s.png" % [OUT_DIR, name]
	var err := image.save_png(out)
	_t.check("%s: capture written" % name, err == OK)

	# A capture that is a flat field of one colour is a failed render that looks
	# exactly like a successful one in a file listing. Refuse it.
	_t.check("%s: capture is not blank" % name, _distinct_colours(image) >= 8)
	print("  %s  %dx%d" % [out, image.get_width(), image.get_height()])


func _distinct_colours(image: Image) -> int:
	var seen := {}
	var step := maxi(1, image.get_width() / 96)
	for y in range(0, image.get_height(), step):
		for x in range(0, image.get_width(), step):
			seen[image.get_pixel(x, y).to_rgba32()] = true
			if seen.size() >= 64:
				return seen.size()
	return seen.size()


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _world_bounds(node: Node) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, boxes)
	if boxes.is_empty():
		return AABB()
	var out := boxes[0]
	for i in range(1, boxes.size()):
		out = out.merge(boxes[i])
	return out


## Lights and the environment are VisualInstance3Ds with their own AABBs; letting
## them into the merge blows the bounds up and pushes every camera miles back.
func _collect_bounds(node: Node, into: Array[AABB]) -> void:
	if node is GeometryInstance3D:
		var gi := node as GeometryInstance3D
		if gi.visible:
			into.append(gi.global_transform * gi.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, into)
