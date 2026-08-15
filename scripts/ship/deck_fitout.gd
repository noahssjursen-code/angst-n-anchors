class_name DeckFitout
extends RefCounted

## Rebuilds brick visuals + gameplay nodes on a BoatBody from a BrickLayout.
## New deck equipment = BrickCatalog tag + mount helper + BoatBody discovery.
## Only VesselOutfit-accepted slots become live systems (fair MP / UGC).

const FITOUT_ROOT := "DeckFitout"
const FITOUT_JOB := "DeckFitoutJob"
const FITOUT_JOB_SCRIPT := "res://scripts/ship/deck_fitout_job.gd"
const AUTO_UTILS := "AutoUtilities"
const LARGE_LAYOUT_THRESHOLD := 1000

## Preloaded rather than named. `plan_outfit.gd` declares `class_name PlanOutfit`,
## but a script that names a global the class cache has not caught up with fails
## to COMPILE — and this file is on the boot path of every vessel. Binding to the
## file is correct either way. Same reasoning as PlanOutfit's own `Parts`.
const PlanOutfitScript := preload("res://scripts/ship/plan_outfit.gd")

## When enabled, static bricks render as a merged VesselSkinBaker skin (culled
## faces + baked AO + edge trim) instead of one scene node per brick.
## Interactive bricks always stay live nodes. Toggle exists for the
## side-by-side showcase and as an escape hatch.
static var skin_enabled := true
const READINESS_HULL := 0
const READINESS_EXTERIOR := 1
const READINESS_FULL_VISUAL := 2
const READINESS_INTERACTIVE := 3

## THE FISH HOLD'S PROPORTIONS. Everything here is a fraction of the hull it is
## mounted on or an absolute walking margin; there is no metre constant standing
## in for a hull dimension, which is what the 2026-08-15 overhang was.
##
## Deck plane offset. `gear_local` is a CELL CENTRE, half a cell above the deck;
## the hold's own y = 0 is the deck plane, and the coaming stands proud of it.
const CELL_HALF_M := DeckGrid.CELL_M * 0.5
const HOLD_DECK_LIFT_M := 0.02
## Walking margin held clear on all four sides of the hold, between its coaming
## and whatever bounds the clear deck (a bulwark, a rail, a deckhouse).
const HOLD_DECK_CLEARANCE_M := 0.50
## Proportional ceilings, so a wide hull does not end up with its whole working
## deck replaced by hatch. Fractions of the hull's OWN beam and length, which is
## what makes them survive a hull nobody has authored yet.
const HOLD_MAX_BEAM_FRACTION := 0.60
const HOLD_MAX_LOA_FRACTION := 0.30
## Below this the rectangle is not a hold, it is a puddle.
const HOLD_MIN_SIDE_M := 1.00
## A hatch is roughly square. Without these the widest clear run on a beamy hull
## produces a 6.0 x 2.0 m coaming standing 0.26 m proud, which renders as a low
## ledge lying across the deck rather than as a hold — looked at on the 28 m
## trawler, which is why they are here (REALITY §1: describe what you SEE).
const HOLD_MAX_WIDTH_PER_LENGTH := 1.60
const HOLD_MAX_LENGTH_PER_WIDTH := 2.00
## Depth below the deck plane. Unchanged from the old drawing (1.16 m), and NOT
## derived from the hull: it is bounded by hull depth, not by deck area, and
## every hull that can carry a trawl winch has more than this under its deck.
const HOLD_DEPTH_M := 1.16


## Routes a layout dictionary to the right construction system: parametric
## StructurePlan documents (walls/decks/stairs/items/openings) or legacy voxel bricks.
static func apply_any(
	boat: BoatBody,
	layout_dict: Dictionary,
	grid: DeckGrid = null,
	registration_id: String = "",
) -> Dictionary:
	if StructurePlan.is_plan(layout_dict):
		## The declared registration is what the plan is judged against. Dropping
		## it here was how a plan reached the compliance pass with no licence and
		## came back "choose a registration before building".
		return apply_plan(boat, StructurePlan.from_dict(layout_dict), grid, registration_id)
	return apply(boat, BrickLayout.from_dict(layout_dict), grid, registration_id)


## Compliance for a layout DICTIONARY of either shape, so a caller holding a
## saved record does not have to know which construction system drew it. A
## `structure_plan_v1` document is measured by `PlanOutfit`; anything else is a
## brick layout and goes to `VesselCompliance`. Both return the same report.
##
## This exists because persistence and deployment used to run `BrickLayout.from_dict`
## on whatever they held: handed a plan, that yields an EMPTY layout, which fails
## the helm rule, so every plan-built vessel was refused a save and a spawn. The
## defect was in how the record's shape was detected, not in what was called —
## which is why the fix is one shape test, in one place, shared by both sites.
static func compliance_for_layout(
	layout_dict: Dictionary,
	hull_id: String,
	registration_id: String,
	grid: DeckGrid = null,
) -> Dictionary:
	if StructurePlan.is_plan(layout_dict):
		return PlanOutfitScript.compliance(
			StructurePlan.from_dict(layout_dict), hull_id, registration_id, grid
		)
	return VesselCompliance.validate(
		BrickLayout.from_dict(layout_dict), hull_id, registration_id, grid
	)


## Parametric construction path: merged bake + colliders from the same panel
## decomposition, then the SAME registration verdict the brick path gets — via
## `PlanOutfit`, which feeds `VesselCompliance`'s own rule evaluator.
static func apply_plan(
	boat: BoatBody,
	plan: StructurePlan,
	grid: DeckGrid = null,
	registration_id: String = "",
) -> Dictionary:
	if boat == null or plan == null:
		return {}
	clear(boat)
	var g := grid if grid != null else grid_for_boat(boat)
	var root := Node3D.new()
	root.name = FITOUT_ROOT
	boat.add_child(root)
	boat.ensure_walk_deck()
	boat.clear_walk_brick_colliders()
	## Plan coordinates are grid-corner space; shift into boat-local.
	var offset := Vector3(-g.half_beam, g.deck_y, -g.half_loa)
	root.add_child(StructureBaker.bake(plan, offset))
	var total_mass := 0.0
	var weighted := Vector3.ZERO
	var index := 0
	## Every shape added to a body that is IN a physics space makes Jolt rebuild
	## that body's whole compound shape, so a plan's colliders cost O(n²) — the
	## 150 m feeder's 3086 boxes were seconds of stall at spawn. The window puts
	## the WalkDeck out of its space for the loop and back in at the end; the
	## boxes, their sizes, their yaws and their order are untouched.
	## See BoatBody.begin_walk_collider_batch for the measurement.
	boat.begin_walk_collider_batch()
	for box_variant in StructureBaker.collect_colliders(plan, offset):
		var box := box_variant as Dictionary
		var size: Vector3 = box["size"]
		## `size` is read in the box's OWN frame, so the yaw the baker drew it
		## with has to travel with it — a diagonal bulwark collided flat is a
		## wall you walk through, the same bug class as a stair you fall into.
		boat.add_walk_brick_collider(
			"plan_%d" % index,
			box["center"] as Vector3,
			size,
			float(box.get("yaw_deg", 0.0)),
		)
		## Coarse structural mass: panel volume at light-plate density.
		var box_mass := size.x * size.y * size.z * 220.0
		total_mass += box_mass
		weighted += (box["center"] as Vector3) * box_mass
		index += 1
	boat.end_walk_collider_batch()
	if total_mass > 0.0:
		boat.set_mass_entry("structure_plan", total_mass, weighted / total_mass, "brick")

	## Same resolution order as apply_sync: the caller's declaration wins, the
	## boat's meta is the fallback the vessel scripts' `apply_brick_layout`
	## relies on (it calls apply_any without a registration).
	var hull_id := plan.hull_id
	if hull_id.is_empty() and boat.has_meta("editor_hull_id"):
		hull_id = str(boat.get_meta("editor_hull_id"))
	var declared := registration_id.strip_edges()
	if declared.is_empty() and boat.has_meta("registration_id"):
		declared = str(boat.get_meta("registration_id"))
	var report := PlanOutfitScript.compliance(plan, hull_id, declared, g)
	var caps: Dictionary = (report.get("capabilities", {}) as Dictionary).duplicate(true)
	## `outfit_ok` mirrors finish_fitout: it is the FULL verdict (physical outfit
	## AND declared registration), not the budget half of it.
	caps["outfit_ok"] = bool(report.get("ok", false))
	caps["structure_plan"] = true
	caps["plan_entities"] = plan.entity_count()
	if not bool(report.get("ok", false)):
		var errors: PackedStringArray = report.get("errors", PackedStringArray())
		push_warning(
			"DeckFitout: illegal outfit on %s — surplus gear not mounted. %s"
			% [boat.name, " · ".join(errors)]
		)
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("brick_layout", plan.to_dict())
	boat.set_meta("vessel_outfit", {
		"ok": report.get("ok", false),
		"budget": report.get("budget", {}),
		"usage": report.get("usage", {}),
		"registration_id": declared,
		"registration_ok": report.get("registration_ok", false),
	})
	boat.set_meta("fitout_readiness", READINESS_INTERACTIVE)
	return caps


static func apply(
	boat: BoatBody,
	layout: BrickLayout,
	grid: DeckGrid = null,
	registration_id: String = "",
) -> Dictionary:
	if boat == null:
		return {}
	if layout == null or layout.is_empty():
		clear(boat)
		return {}
	var g := grid
	if g == null:
		g = grid_for_boat(boat)
	var primary_items := layout.iter_primary_cells()
	if primary_items.size() > LARGE_LAYOUT_THRESHOLD:
		return apply_staged(boat, layout, g, registration_id, primary_items)
	return apply_sync(boat, layout, g, registration_id, primary_items)


static func apply_sync(
	boat: BoatBody,
	layout: BrickLayout,
	grid: DeckGrid = null,
	registration_id: String = "",
	primary_items: Array = [],
) -> Dictionary:
	## Immediate path retained for ordinary boats and parity tests.
	if boat == null or layout == null:
		return {}
	clear(boat)
	var g := grid if grid != null else grid_for_boat(boat)
	var all_items := primary_items if not primary_items.is_empty() else layout.iter_primary_cells()
	var partition := on_deck_items(g, all_items)
	var items: Array = partition["kept"]
	_warn_placement_faults(boat, g, partition["faults"] as Array)
	var hull_id := str(layout.hull_id)
	if hull_id.is_empty() and boat.has_meta("editor_hull_id"):
		hull_id = str(boat.get_meta("editor_hull_id"))
	var declared := registration_id.strip_edges()
	if declared.is_empty() and boat.has_meta("registration_id"):
		declared = str(boat.get_meta("registration_id"))
	var outfit := VesselCompliance.validate(layout, hull_id, declared, g)
	var accepted: Dictionary = outfit.get("accepted_slots", {})
	var accepted_fishing: Dictionary = _cell_set(accepted.get("fishing", []))
	var accepted_helm: Dictionary = _cell_set(accepted.get("helm", []))

	var root := Node3D.new()
	root.name = FITOUT_ROOT
	boat.add_child(root)
	boat.ensure_walk_deck()
	boat.clear_walk_brick_colliders()
	var visual_by_key := {}
	## Same three calls the staged job makes, in the same order, through the same
	## Session — register everything, then emit, then commit (REALITY.md 3b: one
	## derivation, so the two entry points cannot drift into different geometry).
	var skin := new_skin_session(g)
	if skin != null:
		for item_raw in items:
			skin.register_item(item_raw as Dictionary)
	for item_raw in items:
		var item := item_raw as Dictionary
		if skin != null and skin.emit_item(item):
			## Static brick: geometry goes into the merged skin; only mounted
			## sign/light fixtures on the cell still need individual nodes.
			create_cell_mounts(root, g, item)
			continue
		var visual := create_item_visual(root, g, item)
		if visual != null:
			visual_by_key[BrickLayout.cell_key(item["cell"] as Vector3i)] = visual
	if skin != null:
		skin.commit()
		attach_skin(root, skin)
	## `layout` rides in the mount state so `_mount_fishing` can see what is
	## already built on the deck. Both fit-out entry points thread the same dict,
	## so the immediate path and the staged job derive the same hold (REALITY 3b).
	var state := {"brick_i": 0, "ladder_n": 0, "layout": layout}
	boat.begin_mass_batch()
	## `mount_item_gameplay` emits walk colliders (one per brick, one per stair
	## tread, two per door jamb), and each one costs a Jolt compound rebuild of
	## everything already on the body. Same window as the plan path.
	boat.begin_walk_collider_batch()
	for item_raw in items:
		var item := item_raw as Dictionary
		var key := BrickLayout.cell_key(item["cell"] as Vector3i)
		var visual := visual_by_key.get(key, null) as Node3D
		mount_item_gameplay(
			boat, root, g, item, visual, accepted_fishing, accepted_helm, state
		)
	boat.end_walk_collider_batch()
	boat.end_mass_batch()
	return finish_fitout(boat, root, layout, g, outfit, declared, state)


static func apply_staged(
	boat: BoatBody,
	layout: BrickLayout,
	grid: DeckGrid = null,
	registration_id: String = "",
	primary_items: Array = [],
) -> Dictionary:
	if boat == null or layout == null:
		return {}
	clear(boat)
	var g := grid if grid != null else grid_for_boat(boat)
	var all_items := primary_items if not primary_items.is_empty() else layout.iter_primary_cells()
	## Same filter as `apply_sync`, and it must be here rather than inside the job:
	## the job is handed the item list and walks it through the SAME skin session,
	## so an unfiltered list would bake off-deck geometry a frame at a time
	## instead of all at once (REALITY.md §3b — the two entry points may not drift).
	var partition := on_deck_items(g, all_items)
	var items: Array = partition["kept"]
	_warn_placement_faults(boat, g, partition["faults"] as Array)
	var hull_id := str(layout.hull_id)
	if hull_id.is_empty() and boat.has_meta("editor_hull_id"):
		hull_id = str(boat.get_meta("editor_hull_id"))
	var declared := registration_id.strip_edges()
	if declared.is_empty() and boat.has_meta("registration_id"):
		declared = str(boat.get_meta("registration_id"))
	var root := Node3D.new()
	root.name = FITOUT_ROOT
	boat.add_child(root)
	boat.ensure_walk_deck()
	boat.clear_walk_brick_colliders()
	var job := load(FITOUT_JOB_SCRIPT).new() as Node
	job.name = FITOUT_JOB
	boat.add_child(job)
	var remote := bool(boat.get_meta("remote_replica", false))
	job.call("configure", boat, root, layout, g, hull_id, declared, items, not remote)
	var caps := {"staged": true, "outfit_ok": false}
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("fitout_readiness", READINESS_HULL)
	return caps


## The skin both entry points bake into, or null when merging is off. Held by the
## caller so a frame-budgeted one can spend it a few items per frame.
static func new_skin_session(grid: DeckGrid) -> VesselSkinBaker.Session:
	if not skin_enabled or grid == null:
		return null
	return VesselSkinBaker.Session.new(grid)


## Parents a session's bake once it has geometry. An empty SkinBake node is not
## attached at all: a vessel of nothing but doors and lights should leave no
## trace of the merger, and the fitout root's children are counted by tests.
static func attach_skin(root: Node3D, skin: VesselSkinBaker.Session) -> void:
	if root == null or skin == null or skin.root == null:
		return
	if skin.root.get_parent() != null or skin.root.get_child_count() == 0:
		return
	root.add_child(skin.root)


static func create_item_visual(
	root: Node3D,
	grid: DeckGrid,
	item: Dictionary,
) -> Node3D:
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var brick_id := str(item.get("brick_id", ""))
	var yaw := int(item.get("yaw", 0))
	if root == null or grid == null or not _item_is_valid(grid, cell, brick_id, yaw):
		return null
	var opts: Dictionary = {"color": BrickLayout.color_from_entry(item, brick_id)}
	if BrickCatalog.has_tag(brick_id, "text"):
		opts["text"] = str(item.get("text", ""))
	var visual := BrickCatalog.create_visual(brick_id, opts)
	visual.name = "%s_%d_%d_%d" % [brick_id, cell.x, cell.y, cell.z]
	visual.position = footprint_center_local(grid, cell, brick_id, yaw)
	visual.rotation_degrees = Vector3(0.0, float(yaw), 0.0)
	root.add_child(visual)
	create_cell_mounts(root, grid, item)
	return visual


## Sign plaques and light fixtures mounted ON a cell need their own nodes even
## when the base brick's geometry lives in the merged skin bake. Public because
## the staged job walks the same branch.
static func create_cell_mounts(root: Node3D, grid: DeckGrid, item: Dictionary) -> void:
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var yaw := int(item.get("yaw", 0))
	var sign_id := str(item.get("sign_id", ""))
	if BrickCatalog.has(sign_id) and BrickCatalog.has_tag(sign_id, "text"):
		var sign_yaw := int(item.get("sign_yaw", yaw))
		var sign := BrickCatalog.create_visual(sign_id, {"text": str(item.get("text", ""))})
		sign.name = "Sign_%d_%d_%d" % [cell.x, cell.y, cell.z]
		sign.position = grid.cell_center_local(cell)
		sign.rotation_degrees = Vector3(0.0, float(sign_yaw), 0.0)
		root.add_child(sign)
	var light_id := str(item.get("light_id", ""))
	if BrickCatalog.has(light_id) and BrickCatalog.has_tag(light_id, "light"):
		var light_yaw := int(item.get("light_yaw", yaw))
		_add_mounted_light_visual(root, grid, cell, light_id, light_yaw)


static func mount_item_gameplay(
	boat: BoatBody,
	root: Node3D,
	grid: DeckGrid,
	item: Dictionary,
	visual: Node3D,
	accepted_fishing: Dictionary,
	accepted_helm: Dictionary,
	state: Dictionary,
) -> void:
	## `visual` is null for skin-baked bricks — mass, colliders, and mounted
	## fixtures still apply; visual-dependent mounts only occur on live bricks,
	## which always carry an individual visual.
	if boat == null or root == null or grid == null:
		return
	var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var brick_id := str(item.get("brick_id", ""))
	var yaw := int(item.get("yaw", 0))
	if not _item_is_valid(grid, cell, brick_id, yaw):
		return
	var boat_local := footprint_center_local(grid, cell, brick_id, yaw)
	var brick_mass := float(BrickCatalog.get_entry(brick_id).get("mass_kg", 0.0))
	boat.set_mass_entry(
		"brick:%d:%d:%d" % [cell.x, cell.y, cell.z],
		brick_mass,
		boat_local,
		"brick"
	)
	var brick_i := int(state.get("brick_i", 0))
	if (
		not BrickCatalog.has_tag(brick_id, "text")
		and not BrickCatalog.has_tag(brick_id, "door")
		and not BrickCatalog.has_tag(brick_id, "stairs")
		and not BrickCatalog.has_tag(brick_id, "helm")
		and not BrickCatalog.has_tag(brick_id, "light")
	):
		_add_brick_collider(boat, brick_id, boat_local, yaw, brick_i)
		brick_i += 1
	if BrickCatalog.has_tag(brick_id, "door"):
		_add_brick_door(boat, visual, boat_local, yaw, brick_id)
	if BrickCatalog.has_tag(brick_id, "stairs"):
		_add_stairs_colliders(boat, boat_local, yaw, brick_id, brick_i)
		brick_i += 1
	if BrickCatalog.has_tag(brick_id, "helm") and accepted_helm.has(cell):
		_mount_helm(visual)
	if BrickCatalog.has_tag(brick_id, "light"):
		_mount_light(visual, brick_id)
	if BrickCatalog.has_tag(brick_id, "ladder"):
		_mount_ladder(visual)
		state["ladder_n"] = int(state.get("ladder_n", 0)) + 1
	if (
		(BrickCatalog.has_tag(brick_id, "trommel") or BrickCatalog.has_tag(brick_id, "fishing"))
		and accepted_fishing.has(cell)
	):
		_mount_fishing(root, visual, grid, item, boat_local, state.get("layout", null) as BrickLayout)
	if BrickCatalog.has_tag(brick_id, "mooring"):
		_mount_mooring(visual, brick_id)
	var light_id := str(item.get("light_id", ""))
	if BrickCatalog.has(light_id) and BrickCatalog.has_tag(light_id, "light"):
		var fixture := root.get_node_or_null(_mounted_light_name(cell)) as Node3D
		if fixture != null and fixture.get_node_or_null("ShipLight") == null:
			_mount_light(fixture, light_id)
	state["brick_i"] = brick_i


static func finish_fitout(
	boat: BoatBody,
	root: Node3D,
	layout: BrickLayout,
	grid: DeckGrid,
	outfit: Dictionary,
	declared: String,
	state: Dictionary,
) -> Dictionary:
	var accepted_bulk: Dictionary = {}
	var accepted_pads: Dictionary = {}
	var accepted_slots: Dictionary = outfit.get("accepted_slots", {})
	for idx in accepted_slots.get("bulk_hold_indices", []):
		accepted_bulk[int(idx)] = true
	for idx in accepted_slots.get("container_pad_indices", []):
		accepted_pads[int(idx)] = true
	var pad_i := 0
	for pad in layout.iter_container_pads():
		if accepted_pads.has(pad_i):
			_mount_container_pad(boat, root, grid, pad as Dictionary, pad_i)
		pad_i += 1
	var hold_i := 0
	for hold in layout.iter_bulk_holds():
		if accepted_bulk.has(hold_i):
			_mount_bulk_hold(boat, root, grid, hold as Dictionary, hold_i)
		hold_i += 1
	var ladder_n := int(state.get("ladder_n", 0))
	var caps: Dictionary = outfit.get("capabilities", {}).duplicate(true)
	caps["has_ladder"] = ladder_n > 0
	caps["ladders"] = ladder_n
	caps["outfit_ok"] = bool(outfit.get("ok", false))
	if not bool(outfit.get("ok", false)):
		var errors: PackedStringArray = outfit.get("errors", PackedStringArray())
		push_warning(
			"DeckFitout: illegal outfit on %s — surplus gear not mounted. %s"
			% [boat.name, " · ".join(errors)]
		)
	boat.set_meta("brick_capabilities", caps)
	boat.set_meta("brick_layout", layout.to_dict())
	boat.set_meta("vessel_outfit", {
		"ok": outfit.get("ok", false),
		"budget": outfit.get("budget", {}),
		"usage": outfit.get("usage", {}),
		"registration_id": declared,
		"registration_ok": outfit.get("registration_ok", false),
	})
	boat.set_meta("fitout_readiness", READINESS_INTERACTIVE)
	var lighting := boat.get_node_or_null("ShipLighting") as ShipLighting
	if lighting != null and lighting.has_method("_gather_lights"):
		lighting.call_deferred("_gather_lights")
	return caps


static func request_full_detail(boat: BoatBody) -> void:
	if boat == null:
		return
	var job := boat.get_node_or_null(FITOUT_JOB)
	if job != null and job.has_method("request_full_detail"):
		job.call("request_full_detail")


static func readiness_of(boat: BoatBody) -> int:
	if boat == null:
		return READINESS_HULL
	return int(boat.get_meta("fitout_readiness", READINESS_HULL))


## Was the only correct copy of "can this brick stand here" in the repo, and the
## only component that noticed the eight-off-grid-brick vessel — which it did by
## returning false and drawing nothing, destroying the evidence between an `if`
## and a `return null`. The predicate now lives on `BrickLayout` and is shared
## with the setter, `place_footprint` and `VesselOutfit` (REALITY.md §3b). This
## stays as a per-item guard because `create_item_visual` and
## `mount_item_gameplay` are public and the staged job calls them one at a time.
static func _item_is_valid(
	grid: DeckGrid,
	cell: Vector3i,
	brick_id: String,
	yaw: int,
) -> bool:
	return BrickLayout.cell_on_grid(grid, cell, brick_id, yaw)


## Splits a primary-cell list into what this deck can carry and what it cannot,
## BEFORE anything draws. Both fit-out entry points filter here, and that is the
## point of doing it here rather than at each drawing site:
##
## `_item_is_valid` gated `create_item_visual` and `mount_item_gameplay`, and
## those are NOT every drawing path. Measured 2026-08-15
## (`tests/_offgrid_facts.gd`, section B) on a 10 x 30 grid:
##
##     on-deck  block (3,0,5)    register=true emit=true  36 vertices
##     OFF-DECK block (19,0,55)  register=true emit=true  36 vertices
##
## `VesselSkinBaker.Session` never asks the grid, and MOST bricks on a vessel are
## baked (`is_baked_brick` is true for block and railing, false for helm,
## bollard and the nav lights). The survey's "0 of 8 drawn" held only because
## every brick `general_vessel` requires happens to be a live node — a hull of
## off-deck blocks and railings was drawn in full, hanging in the sea.
## `create_cell_mounts` was the third leak: it drew a nav light mounted on an
## off-deck block (1 node created, same probe, section C).
##
## Filtering the item list once closes all three, and leaves one place to change
## if a fourth consumer appears.
static func on_deck_items(grid: DeckGrid, items: Array) -> Dictionary:
	var kept: Array = []
	var faults: Array = []
	for raw in items:
		var item := raw as Dictionary
		var cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
		var brick_id := str(item.get("brick_id", ""))
		if _item_is_valid(grid, cell, brick_id, int(item.get("yaw", 0))):
			kept.append(item)
		elif BrickCatalog.has(brick_id):
			## An unknown brick id is a catalogue miss, not a placement fault —
			## every consumer already ignores it, and reporting it here would put
			## "cargo_tile at (3,0,5) is off the deck" in front of a player whose
			## deck is fine.
			faults.append({"cell": cell, "brick_id": brick_id})
	return {"kept": kept, "faults": faults}


## The refusal in the form a test or a tool can read: one line per brick this
## layout puts where this deck does not exist.
static func placement_faults(grid: DeckGrid, layout: BrickLayout) -> PackedStringArray:
	var out := PackedStringArray()
	if grid == null or layout == null:
		return out
	for raw in (on_deck_items(grid, layout.iter_primary_cells()).get("faults", []) as Array):
		var fault := raw as Dictionary
		out.append(BrickLayout.off_grid_reason(
			grid, fault.get("cell", Vector3i.ZERO) as Vector3i, str(fault.get("brick_id", ""))
		))
	return out


## Says out loud what used to vanish. The player-facing report is the compliance
## error (`VesselOutfit` raises it, the shipyard's rules panel prints it); this is
## the engine-log half, so a fit-out that quietly drops bricks leaves a trace even
## when nobody is looking at a rules panel.
static func _warn_placement_faults(boat: BoatBody, grid: DeckGrid, faults: Array) -> void:
	if faults.is_empty():
		return
	var lines := PackedStringArray()
	for raw in faults:
		var fault := raw as Dictionary
		lines.append(BrickLayout.off_grid_reason(
			grid, fault.get("cell", Vector3i.ZERO) as Vector3i, str(fault.get("brick_id", ""))
		))
	push_warning(
		"DeckFitout: %d brick(s) off the %d x %d deck on %s — not drawn, not mounted, not counted. %s"
		% [
			lines.size(), grid.width, grid.length,
			boat.name if boat != null else "<no boat>",
			" · ".join(lines),
		]
	)


static func _cell_set(cells: Variant) -> Dictionary:
	var out := {}
	if cells is Array:
		for c in cells as Array:
			if c is Vector3i:
				out[c] = true
	return out


static func clear(boat: BoatBody) -> void:
	if boat == null:
		return
	var job := boat.get_node_or_null(FITOUT_JOB)
	if job != null:
		boat.remove_child(job)
		job.free()
	boat.clear_mass_entries("brick:")
	var existing := boat.get_node_or_null(FITOUT_ROOT)
	if existing != null:
		boat.remove_child(existing)
		existing.free()
	boat.clear_walk_brick_colliders()
	if boat.has_meta("brick_capabilities"):
		boat.remove_meta("brick_capabilities")
	if boat.has_meta("brick_layout"):
		boat.remove_meta("brick_layout")
	if boat.has_meta("vessel_outfit"):
		boat.remove_meta("vessel_outfit")
	if boat.has_meta("fitout_readiness"):
		boat.remove_meta("fitout_readiness")


static func footprint_center_local(grid: DeckGrid, origin: Vector3i, brick_id: String, yaw: int) -> Vector3:
	## AABB centre of every cell the brick occupies (handles multi-cell + yaw).
	var fp := BrickCatalog.footprint_of(brick_id)
	var yaw_steps := int(round(float(yaw) / 90.0)) % 4
	if yaw_steps < 0:
		yaw_steps += 4
	var occupied := grid.footprint_cells(origin, fp, yaw_steps)
	if occupied.is_empty():
		return grid.cell_center_local(origin)
	var sum := Vector3.ZERO
	for c in occupied:
		sum += grid.cell_center_local(c)
	return sum / float(occupied.size())


static func grid_for_boat(boat: BoatBody) -> DeckGrid:
	if boat != null and boat.has_method("deck_grid"):
		var declared: Variant = boat.call("deck_grid")
		if declared is DeckGrid:
			return declared as DeckGrid
	var loa: float = boat.length_m if boat != null and boat.length_m > 0.1 else 28.0
	var beam: float = boat.beam_m if boat != null and boat.beam_m > 0.1 else 10.0
	var deck_y := 0.0
	if boat != null and boat.hull_stations != null:
		deck_y = boat.hull_stations.deck_y + 0.12
	elif boat != null and boat.depth_m > 0.0:
		deck_y = boat.depth_m * 0.85 + 0.12
	return DeckGrid.from_hull(loa, beam, deck_y)


static func capabilities_of(boat: BoatBody) -> Dictionary:
	if boat != null and boat.has_meta("brick_capabilities"):
		return boat.get_meta("brick_capabilities") as Dictionary
	return {}


static func _mount_ladder(visual: Node3D) -> void:
	var board := HullLadderBoard.new()
	board.name = "HullLadderBoard"
	visual.add_child(board)


static func _mount_fishing(
	root: Node3D,
	visual: Node3D,
	grid: DeckGrid,
	item: Dictionary,
	gear_local: Vector3,
	layout: BrickLayout,
) -> void:
	## Drop catalog preview meshes — FishingSystem owns the live trommel + net.
	for child in visual.get_children():
		visual.remove_child(child)
		child.free()
	var fishing := FishingSystem.new()
	fishing.name = "FishingSystem"
	fishing.anchored_to_brick = true
	visual.add_child(fishing)
	## THE HOLD IS SIZED AND PLACED BY THE BOAT, NOT BY A CONSTANT — 2026-08-15.
	##
	## It used to be `position = gear_local + inward_z * 6.1` at
	## `scale = Vector3(1.10, 1.0, 2.10)`, both hull-independent, which drew the
	## SAME 6.80 x 9.11 m hold on a 10 m beam and on a 5 m one. On the granted
	## starter (`hull_15x5`, half-beam 2.50) the pump flange stood 1.130 m
	## outboard of the deck edge over open water, the coaming overhung the bow by
	## 0.157 m, and both hulls put the hatch under their own wheelhouse.
	##
	## `_catch_hold_berth` answers the question the constants were standing in
	## for: which rectangle of THIS deck is clear, next to THIS gear brick. If the
	## deck has no room the hold is not mounted — a hold drawn over the sea is
	## worse than a boat that visibly cannot carry fish, and the absence is
	## loud (REALITY §7: red with a diagnosis beats green with a lie).
	var berth := _catch_hold_berth(grid, layout, item)
	if berth.is_empty():
		push_warning(
			"DeckFitout: no clear deck for a catch hold beside the gear at %v — hold not mounted"
			% [item.get("cell", Vector3i.ZERO)]
		)
		return
	var hold := CatchHoldComponent.new()
	hold.name = "CatchHold"
	var centre: Vector3 = berth["center"]
	hold.position = Vector3(centre.x, gear_local.y - CELL_HALF_M + HOLD_DECK_LIFT_M, centre.z)
	hold.configure_footprint(berth["size"] as Vector3)
	## Capacity is a declared gameplay number and is deliberately NOT derived
	## from the footprint: resizing the drawing must not silently re-balance how
	## much fish a boat carries (see catch_hold_component.gd's header).
	hold.configure("primary_catch_hold", 4000.0)
	root.add_child(hold)


## The clear rectangle of deck this hull offers for a fish hold, in vessel-local
## metres, or {} when it offers none.
##
## Derived, in order, from: which cells the grid says are FULL deck (so the bow
## taper and the deck ends bound it without being named), which columns the
## layout has already built on (so the hatch cannot land under the wheelhouse),
## and where the gear brick is (so the hold is beside its winch). The judgement
## in it is the HOLD_* block at the top of this file: a walking margin in metres,
## and four ratios — two against this hull's own beam and length, two against the
## hatch's own other side. None of them is a length standing in for a hull.
static func _catch_hold_berth(
	grid: DeckGrid, layout: BrickLayout, item: Dictionary
) -> Dictionary:
	if grid == null:
		return {}
	var built := _occupied_columns(layout)
	var gear_cell: Vector3i = item.get("cell", Vector3i(-1, -1, -1))
	var fp := BrickCatalog.footprint_of(str(item.get("brick_id", "")))
	var yaw_steps := int(round(float(int(item.get("yaw", 0))) / 90.0)) % 4
	if yaw_steps < 0:
		yaw_steps += 4
	var gear_z0 := gear_cell.z
	var gear_z1 := gear_cell.z
	for c in grid.footprint_cells(gear_cell, fp, yaw_steps):
		gear_z0 = mini(gear_z0, c.z)
		gear_z1 = maxi(gear_z1, c.z)

	## The clear deck immediately forward of the gear and the clear deck
	## immediately aft of it are the two candidates; the bigger one wins, and a
	## tie goes to the one nearer midships, because a full hold's payload belongs
	## near the pivot. Only if the winch is boxed in on both sides does this fall
	## back to the best clear run anywhere on the deck.
	var toward_midships := -1 if float(gear_z0 + gear_z1) * 0.5 >= float(grid.length) * 0.5 else 1
	var near := _berth_from_run(
		grid, built, _run_from(grid, built, gear_z0, gear_z1, toward_midships)
	)
	var far := _berth_from_run(
		grid, built, _run_from(grid, built, gear_z0, gear_z1, -toward_midships)
	)
	if not near.is_empty() and not far.is_empty():
		return near if _berth_area(near) >= _berth_area(far) else far
	if not near.is_empty():
		return near
	if not far.is_empty():
		return far
	for run in _maximal_runs(grid, built):
		var berth := _berth_from_run(grid, built, run as Vector2i)
		if not berth.is_empty():
			return berth
	return {}


static func _berth_area(berth: Dictionary) -> float:
	var size: Vector3 = berth["size"]
	return size.x * size.z


## Cell rows [z0, z1] of the maximal clear run starting one row beyond the given
## span and walking in `step`. Returns (-1, -1) when the very next row is blocked.
static func _run_from(
	grid: DeckGrid, built: Dictionary, from_z0: int, from_z1: int, step: int
) -> Vector2i:
	var iz := (from_z1 + 1) if step > 0 else (from_z0 - 1)
	var first := iz
	var last := iz
	var any := false
	while iz >= 0 and iz < grid.length:
		if _clear_half_beam(grid, built, iz) <= 0.0:
			break
		if not any:
			first = iz
			any = true
		last = iz
		iz += step
	if not any:
		return Vector2i(-1, -1)
	return Vector2i(mini(first, last), maxi(first, last))


## Every maximal run of rows whose centreline is clear, one pass, biggest first.
## The fallback when neither side of the gear brick has room — a vessel whose
## winch is boxed in still gets a hold if the deck has one anywhere.
static func _maximal_runs(grid: DeckGrid, built: Dictionary) -> Array:
	var runs: Array = []
	var start := -1
	for iz in range(grid.length + 1):
		var open := iz < grid.length and _clear_half_beam(grid, built, iz) > 0.0
		if open and start < 0:
			start = iz
		elif not open and start >= 0:
			runs.append(Vector2i(start, iz - 1))
			start = -1
	runs.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a.y - a.x) > (b.y - b.x))
	return runs


## Half-width of the clear, FULL-deck, unbuilt strip straddling the centreline on
## one cell row, in metres. Zero when the centreline itself is blocked.
static func _clear_half_beam(grid: DeckGrid, built: Dictionary, iz: int) -> float:
	var mid := grid.width / 2
	var left := mid
	while left - 1 >= 0 and _cell_is_clear(grid, built, left - 1, iz):
		left -= 1
	var right := mid - 1
	while right + 1 < grid.width and _cell_is_clear(grid, built, right + 1, iz):
		right += 1
	if right < left:
		return 0.0
	## Cell edges in local metres, then the symmetric half the centreline allows.
	var x_lo := -grid.half_beam + float(left) * DeckGrid.CELL_M
	var x_hi := -grid.half_beam + float(right + 1) * DeckGrid.CELL_M
	if x_lo > 0.0 or x_hi < 0.0:
		return 0.0
	return minf(absf(x_lo), absf(x_hi))


static func _cell_is_clear(grid: DeckGrid, built: Dictionary, ix: int, iz: int) -> bool:
	if grid.cell_shape(ix, iz) != DeckGrid.CellShape.FULL:
		return false
	return not built.has(Vector2i(ix, iz))


## Every (ix, iz) column the layout has anything standing on, at any height.
static func _occupied_columns(layout: BrickLayout) -> Dictionary:
	var out := {}
	if layout == null:
		return out
	for key in layout.cells:
		var cell := BrickLayout.parse_key(str(key))
		out[Vector2i(cell.x, cell.z)] = true
	return out


## Largest usable hold rectangle inside a clear run of rows, after the walking
## clearance and the proportional ceilings. Prefixes of the run are all tried
## because the far end of a run can be narrower than the near end (a bow taper),
## and a shorter, wider hold can beat a longer, thinner one.
static func _berth_from_run(
	grid: DeckGrid, built: Dictionary, run: Vector2i
) -> Dictionary:
	if run.x < 0:
		return {}
	var max_half_x := grid.half_beam * HOLD_MAX_BEAM_FRACTION
	var max_len := grid.half_loa * 2.0 * HOLD_MAX_LOA_FRACTION
	var best := {}
	var best_area := 0.0
	for anchor in [run.x, run.y]:
		var step := 1 if anchor == run.x else -1
		var half_x := 1e9
		var iz := int(anchor)
		while iz >= run.x and iz <= run.y:
			half_x = minf(half_x, _clear_half_beam(grid, built, iz))
			var z_lo := -grid.half_loa + float(mini(int(anchor), iz)) * DeckGrid.CELL_M
			var z_hi := -grid.half_loa + float(maxi(int(anchor), iz) + 1) * DeckGrid.CELL_M
			var w := minf(half_x - HOLD_DECK_CLEARANCE_M, max_half_x) * 2.0
			var l := minf(z_hi - z_lo - HOLD_DECK_CLEARANCE_M * 2.0, max_len)
			w = minf(w, l * HOLD_MAX_WIDTH_PER_LENGTH)
			l = minf(l, w * HOLD_MAX_LENGTH_PER_WIDTH)
			if w >= HOLD_MIN_SIDE_M and l >= HOLD_MIN_SIDE_M and w * l > best_area:
				best_area = w * l
				best = {
					"center": Vector3(0.0, 0.0, (z_lo + z_hi) * 0.5),
					"size": Vector3(w, HOLD_DEPTH_M, l),
				}
			iz += step
	return best


static func _add_brick_door(
	boat: BoatBody,
	visual: Node3D,
	boat_local: Vector3,
	yaw: int,
	brick_id: String,
) -> void:
	var sz := BrickCatalog.size_m(brick_id)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	## Static jambs stay solid; the swinging leaf is handled by BrickDoor.
	var post := Vector3(0.14, sz.y * 0.95, maxf(sz.z * 0.3, 0.2))
	boat.add_walk_brick_collider(
		"door_jamb_l_%d" % int(boat_local.length() * 100.0),
		boat_local + basis * Vector3(-sz.x * 0.5 + 0.07, 0.0, 0.0),
		post,
		float(yaw),
	)
	boat.add_walk_brick_collider(
		"door_jamb_r_%d" % int(boat_local.length() * 100.0),
		boat_local + basis * Vector3(sz.x * 0.5 - 0.07, 0.0, 0.0),
		post,
		float(yaw),
	)
	var door := BrickDoor.new()
	door.name = "BrickDoor"
	door.configure(
		boat,
		boat_local,
		float(yaw),
		Vector3(sz.x * 0.8, sz.y * 0.88, 0.12),
	)
	visual.add_child(door)


static func _add_stairs_colliders(
	boat: BoatBody,
	boat_local: Vector3,
	yaw: int,
	brick_id: String,
	index: int,
) -> void:
	## One walk box per tread so step-up works with player max_step_height (~0.45 m).
	if boat == null:
		return
	var entry := BrickCatalog.get_entry(brick_id)
	var n := maxi(int(entry.get("stair_steps", 4)), 2)
	var sz := BrickCatalog.size_m(brick_id)
	var riser := sz.y / float(n)
	var tread := sz.z / float(n)
	var hy := sz.y * 0.5
	var hz := sz.z * 0.5
	var overlap := 0.004
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	for k in range(n):
		var h := riser * float(k + 1)
		var local_off := Vector3(0.0, -hy + h * 0.5, hz - (float(k) + 0.5) * tread)
		boat.add_walk_brick_collider(
			"stairs_%d_%d" % [index, k],
			boat_local + basis * local_off,
			Vector3(sz.x, h, tread + overlap),
			float(yaw),
		)


static func _mount_mooring(visual: Node3D, brick_id: String = "bollard") -> void:
	## Keep the brick mesh (cell-centred, yaw from layout). Cleat sits on the cell floor
	## — MooringPoint meshes are base-origin and must not replace the brick visual.
	var cleat := MooringPoint.new()
	cleat.name = "MooringCleat"
	cleat.build_visual = false
	cleat.bollard_rotation_degrees = Vector3.ZERO
	if BrickCatalog.has_tag(brick_id, "railing"):
		## Railing stays on −Z; the mooring bit is cell-centred like a deck bollard.
		cleat.position = Vector3(0.0, -DeckGrid.CELL_M * 0.5, 0.0)
		cleat.anchor_local_position = Vector3(0.0, 0.45, 0.0)
	else:
		# Brick root = cell centre; drop to cell floor so the rope anchor matches the post base.
		cleat.position = Vector3(0.0, -DeckGrid.CELL_M * 0.5, 0.0)
		cleat.anchor_local_position = Vector3(0.0, 0.55, 0.0)
	cleat.station = "bow" if visual.position.z < 0.0 else "stern"
	cleat.side = "port" if visual.position.x < 0.0 else "starboard"
	visual.add_child(cleat)


static func _collider_spec(brick_id: String) -> Dictionary:
	## Returns { size: Vector3, offset: Vector3 } in brick-local space (visual origin).
	var sz := BrickCatalog.size_m(brick_id)
	match brick_id:
		"bollard":
			return {
				"size": Vector3(0.45, sz.y * 0.75, 0.45),
				"offset": Vector3(0.0, -sz.y * 0.1, 0.0),
			}
		"mast_base":
			return {
				"size": Vector3(sz.x * 0.9, 0.28, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.14, 0.0),
			}
		"mast_pole":
			return {
				"size": Vector3(0.22, sz.y * 0.95, 0.22),
				"offset": Vector3.ZERO,
			}
		"chimney_2x3x2", "chimney_4x5x4":
			return {
				"size": Vector3(sz.x * 0.72, sz.y * 0.96, sz.z * 0.72),
				"offset": Vector3.ZERO,
			}
		"light_mast_white":
			return {
				"size": Vector3(0.4, 0.7, 0.4),
				"offset": Vector3(0.0, -sz.y * 0.15, 0.0),
			}
		"ledge_45":
			## Box approx under the slope (lower half) — enough to stand / block.
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_slope":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_slope_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"roof_corner":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_corner_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"ledge_45_corner":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"ledge_45_corner_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"roof_corner_inner", "ledge_45_inner":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"roof_corner_inner_inv", "ledge_45_inner_inv":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, sz.y * 0.25, 0.0),
			}
		"block_window", "block_windshield":
			## Thin wall on the glazed −Z face.
			return {
				"size": Vector3(sz.x * 0.95, sz.y * 0.95, 0.14),
				"offset": Vector3(0.0, 0.0, -sz.z * 0.5 + 0.07),
			}
		"block_window_corner":
			## L-shaped approx: full cell thin enough to stand against.
			return {
				"size": Vector3(sz.x * 0.95, sz.y * 0.95, sz.z * 0.95),
				"offset": Vector3.ZERO,
			}
		"railing", "railing_mooring":
			## On the local −Z face so it meets 45° corner posts at cell corners.
			return {
				"size": Vector3(sz.x, sz.y * 0.94, 0.12),
				"offset": Vector3(0.0, 0.0, -sz.z * 0.5 + 0.06),
			}
		"railing_45":
			return {
				"size": Vector3(DeckGrid.CELL_M * sqrt(2.0), sz.y * 0.94, 0.12),
				"offset": Vector3.ZERO,
			}
		"crane_base":
			return {
				"size": Vector3(sz.x, sz.y * 0.55, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.22, 0.0),
			}
		"crane":
			return {
				"size": Vector3(sz.x * 0.75, sz.y * 0.9, sz.z * 0.75),
				"offset": Vector3(0.0, 0.0, 0.0),
			}
		"hull_ladder":
			## Deck pad only — hanging rungs stay non-colliding so quay approach is free.
			return {
				"size": Vector3(sz.x * 0.9, 0.12, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.06, 0.0),
			}
		"trommel_small":
			return {
				"size": Vector3(sz.x * 0.9, 0.14, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.5 + 0.07, 0.0),
			}
		"bench":
			## Full footprint volume.
			return {
				"size": Vector3(sz.x * 0.94, sz.y * 0.92, sz.z * 0.72),
				"offset": Vector3(0.0, -sz.y * 0.04, sz.z * 0.08),
			}
		"table":
			return {
				"size": Vector3(sz.x * 0.9, sz.y * 0.92, sz.z * 0.9),
				"offset": Vector3(0.0, -sz.y * 0.04, 0.0),
			}
		"deck_text", "wall_text_sm", "wall_text", "wall_text_lg":
			return {"size": Vector3.ZERO, "offset": Vector3.ZERO}
		"block_half", "block_45_half":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
			}
		"block_quarter", "block_45_quarter":
			return {
				"size": Vector3(sz.x, sz.y * 0.25, sz.z),
				"offset": Vector3(0.0, -sz.y * 0.375, 0.0),
			}
		"wall_panel":
			return {
				"size": Vector3(sz.x, sz.y, 0.18),
				"offset": Vector3(0.0, 0.0, -sz.z * 0.5 + 0.09),
			}
		"wall_panel_half":
			return {
				"size": Vector3(sz.x, sz.y * 0.5, 0.18),
				"offset": Vector3(0.0, -sz.y * 0.25, -sz.z * 0.5 + 0.09),
			}
		"wall_panel_quarter":
			return {
				"size": Vector3(sz.x, sz.y * 0.25, 0.18),
				"offset": Vector3(0.0, -sz.y * 0.375, -sz.z * 0.5 + 0.09),
			}
		"wall_panel_45":
			return {
				"size": Vector3(sqrt(2.0) * sz.x, sz.y, 0.18),
				"offset": Vector3.ZERO,
				"yaw_offset": -45.0,
			}
		"wall_panel_45_half":
			return {
				"size": Vector3(sqrt(2.0) * sz.x, sz.y * 0.5, 0.18),
				"offset": Vector3(0.0, -sz.y * 0.25, 0.0),
				"yaw_offset": -45.0,
			}
		"wall_panel_45_quarter":
			return {
				"size": Vector3(sqrt(2.0) * sz.x, sz.y * 0.25, 0.18),
				"offset": Vector3(0.0, -sz.y * 0.375, 0.0),
				"yaw_offset": -45.0,
			}
		_:
			return {"size": sz, "offset": Vector3.ZERO}


static func _add_brick_collider(
	boat: BoatBody,
	brick_id: String,
	boat_local: Vector3,
	yaw: int,
	index: int,
) -> void:
	if boat == null or not BrickCatalog.has(brick_id):
		return
	if BrickCatalog.has_tag(brick_id, "text"):
		return
	var spec := _collider_spec(brick_id)
	var size: Vector3 = spec["size"]
	if size.length_squared() < 1e-6:
		return
	var offset: Vector3 = spec["offset"]
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(yaw)), 0.0))
	var boat_point := boat_local + basis * offset
	## Bricks whose visual is rotated within the cell (diagonal panels) carry
	## the extra rotation in their collider spec.
	var spec_yaw := float(spec.get("yaw_offset", 0.0))
	if absf(spec_yaw) > 0.01:
		boat.add_walk_brick_collider(
			"%s_%d" % [brick_id, index],
			boat_point,
			size,
			float(yaw) + spec_yaw,
		)
		return
	if BrickCatalog.has_tag(brick_id, "diagonal_railing"):
		boat.add_walk_brick_collider(
			"%s_%d" % [brick_id, index],
			boat_point,
			size,
			float(yaw + 45),
		)
		return
	if BrickCatalog.has_tag(brick_id, "diagonal_plan"):
		var hx := size.x * 0.5
		var hy := size.y * 0.5
		var hz := size.z * 0.5
		boat.add_walk_brick_convex_collider(
			"%s_%d" % [brick_id, index],
			boat_point,
			PackedVector3Array([
				Vector3(-hx, -hy, -hz), Vector3(hx, -hy, -hz), Vector3(-hx, -hy, hz),
				Vector3(-hx, hy, -hz), Vector3(hx, hy, -hz), Vector3(-hx, hy, hz),
			]),
			float(yaw),
		)
		return
	boat.add_walk_brick_collider(
		"%s_%d" % [brick_id, index],
		boat_point,
		size,
		float(yaw),
	)


static func _mount_container_pad(
	_boat: BoatBody,
	root: Node3D,
	grid: DeckGrid,
	pad: Dictionary,
	index: int,
) -> void:
	var mn := BrickLayout.zone_min(pad)
	var mx := BrickLayout.zone_max(pad)
	var fp := ContainerUnit.DEFAULT_FOOTPRINT
	var cell_cols := mx.x - mn.x + 1
	var cell_rows := mx.z - mn.z + 1
	var slot_cols := cell_cols / fp.x
	var slot_rows := cell_rows / fp.y
	if slot_cols < 1 or slot_rows < 1:
		push_warning(
			"DeckFitout: container pad %d too small for %dx%d footprint (%dx%d cells)"
			% [index, fp.x, fp.y, cell_cols, cell_rows]
		)
		return
	var w := float(slot_cols * fp.x) * DeckGrid.CELL_M
	var l := float(slot_rows * fp.y) * DeckGrid.CELL_M
	var min_x := -grid.half_beam + float(mn.x) * DeckGrid.CELL_M
	var min_z := -grid.half_loa + float(mn.z) * DeckGrid.CELL_M
	var slot_pad := CargoSlotPadComponent.new()
	slot_pad.name = "CargoSlotPad_%d" % index
	slot_pad.deck_width_m = w
	slot_pad.deck_length_m = l
	slot_pad.cell_size_m = DeckGrid.CELL_M
	slot_pad.container_footprint = fp
	var center := Vector3(
		min_x + w * 0.5,
		grid.deck_y + 0.06,
		min_z + l * 0.5,
	)
	slot_pad.position = center
	root.add_child(slot_pad)


static func _mount_bulk_hold(
	boat: BoatBody,
	root: Node3D,
	grid: DeckGrid,
	hold: Dictionary,
	index: int,
) -> void:
	var mn := BrickLayout.zone_min(hold)
	var mx := BrickLayout.zone_max(hold)
	var w := float(mx.x - mn.x + 1) * DeckGrid.CELL_M
	var l := float(mx.z - mn.z + 1) * DeckGrid.CELL_M
	var sum := Vector3.ZERO
	var n := 0
	for ix in range(mn.x, mx.x + 1):
		for iz in range(mn.z, mx.z + 1):
			sum += grid.cell_center_local(Vector3i(ix, 0, iz))
			n += 1
	if n <= 0:
		return
	var brick_id := str(hold.get("brick_id", "bulk_hold_6x12"))
	var entry := BrickCatalog.get_entry(brick_id)
	var depth_m := float(entry.get("hold_depth_m", 2.5))
	var hold_node := BulkHoldComponent.new()
	hold_node.name = "BulkHold_%d" % index
	hold_node.configure(
		"hold_%d" % index,
		w,
		l,
		depth_m,
	)
	var center := sum / float(n)
	center.y = grid.deck_y + 0.04
	hold_node.position = center
	hold_node.rotation_degrees = Vector3(0.0, float(int(hold.get("yaw", 0))), 0.0)
	root.add_child(hold_node)


static func _mount_helm(visual: Node3D) -> void:
	## Player-placed console — F only when looking at this station.
	var helm := BridgeInteractable.new()
	helm.name = "BridgeInteractable"
	helm.position = Vector3.ZERO
	helm.interact_range = 2.8
	helm.look_distance = 4.0
	helm.exit_deck_offset = Vector2(0.0, 1.2)
	visual.add_child(helm)


static func _mount_light(visual: Node3D, brick_id: String) -> void:
	## Parent the beam under FloodHead (or at Lens) so throw matches the fixture.
	var entry := BrickCatalog.get_entry(brick_id)
	var light := ShipLight.new()
	light.name = "ShipLight"
	light.build_housing = false
	## Spot params before light_type / add_child so _ready rebuild uses them.
	if entry.has("spot_pitch_deg"):
		light.spot_pitch_deg = float(entry.get("spot_pitch_deg", 0.0))
	if entry.has("spot_range_m"):
		light.spot_range_m = float(entry.get("spot_range_m", 22.0))
	if entry.has("spot_energy"):
		light.spot_energy = float(entry.get("spot_energy", 55.0))
	if entry.has("spot_angle_deg"):
		light.spot_angle_deg = float(entry.get("spot_angle_deg", 48.0))
	light.light_type = int(entry.get("light_type", ShipLight.LightType.WORK)) as ShipLight.LightType

	var head := visual.get_node_or_null("FloodHead") as Node3D
	var emitter := visual.get_node_or_null("Emitter") as Node3D
	var lens := _find_lens_mesh(visual)
	if head != null:
		## Beam inherits housing pitch; sit at / just past the lens face.
		head.add_child(light)
		light.position = Vector3(0.0, 0.0, -0.34) if lens == null else lens.position
		light.rotation_degrees = Vector3.ZERO
	elif emitter != null:
		## All-round lanterns: emitter sits clear of solid housing mesh.
		visual.add_child(light)
		light.position = emitter.position
		light.rotation_degrees = Vector3.ZERO
	elif lens != null:
		visual.add_child(light)
		light.position = lens.position
		light.rotation_degrees = Vector3.ZERO
	else:
		visual.add_child(light)
		if BrickCatalog.has_tag(brick_id, "cabin_light"):
			light.position = Vector3(0.0, DeckGrid.CELL_M * 0.35, 0.0)
		else:
			light.position = Vector3(0.0, 0.0, -0.1)


static func _find_lens_mesh(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D and node.name == "Lens":
		return node as MeshInstance3D
	for child in node.get_children():
		var found := _find_lens_mesh(child)
		if found != null:
			return found
	return null


static func _mount_mounted_light(
	root: Node3D,
	grid: DeckGrid,
	cell: Vector3i,
	light_id: String,
	light_yaw: int,
) -> void:
	var visual := _add_mounted_light_visual(root, grid, cell, light_id, light_yaw)
	if visual != null:
		_mount_light(visual, light_id)


static func _add_mounted_light_visual(
	root: Node3D,
	grid: DeckGrid,
	cell: Vector3i,
	light_id: String,
	light_yaw: int,
) -> Node3D:
	if root == null or grid == null:
		return null
	var existing := root.get_node_or_null(_mounted_light_name(cell)) as Node3D
	if existing != null:
		return existing
	var visual := BrickCatalog.create_visual(light_id)
	visual.name = _mounted_light_name(cell)
	visual.position = grid.cell_center_local(cell) + light_mount_offset(light_yaw, light_id)
	visual.rotation_degrees = Vector3(0.0, float(light_yaw), 0.0)
	root.add_child(visual)
	return visual


static func _mounted_light_name(cell: Vector3i) -> String:
	return "Light_%d_%d_%d" % [cell.x, cell.y, cell.z]


static func light_mount_offset(light_yaw: int, light_id: String = "") -> Vector3:
	## Work / top-mount floods stand on the cell roof; attach lights hug the −Z face.
	if light_id != "" and (
		BrickCatalog.has_tag(light_id, "top_mount") or BrickCatalog.has_tag(light_id, "work")
	) and not BrickCatalog.has_tag(light_id, "attach"):
		return Vector3(0.0, DeckGrid.CELL_M * 0.5 + 0.02, 0.0)
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(light_yaw)), 0.0))
	var y_lift := 0.15 if light_id != "" and BrickCatalog.has_tag(light_id, "work") else 0.0
	return basis * Vector3(0.0, y_lift, -DeckGrid.CELL_M * 0.42)


static func ensure_auto_utilities(boat: BoatBody) -> void:
	## Cleats + nav lights — not player-placed bricks.
	if boat == null:
		return
	if boat.find_child(AUTO_UTILS, true, false) != null:
		return
	var root := Node3D.new()
	root.name = AUTO_UTILS
	var gameplay := boat.get_node_or_null("ShipGameplay")
	if gameplay == null:
		boat.add_child(root)
	else:
		gameplay.add_child(root)

	var loa := boat.length_m
	var beam := boat.beam_m
	var deck_y := DeckFitout.grid_for_boat(boat).deck_y

	var cleats := [
		{"name": "MooringPortFwd", "side": "port", "station": "bow", "pos": Vector3(-beam * 0.45, deck_y + 0.08, -loa * 0.35)},
		{"name": "MooringStbdFwd", "side": "starboard", "station": "bow", "pos": Vector3(beam * 0.45, deck_y + 0.08, -loa * 0.35)},
		{"name": "MooringPortAft", "side": "port", "station": "stern", "pos": Vector3(-beam * 0.45, deck_y + 0.08, loa * 0.35)},
		{"name": "MooringStbdAft", "side": "starboard", "station": "stern", "pos": Vector3(beam * 0.45, deck_y + 0.08, loa * 0.35)},
	]
	for spec in cleats:
		var cleat := MooringPoint.new()
		cleat.name = str(spec["name"])
		cleat.side = str(spec["side"])
		cleat.station = str(spec["station"])
		cleat.position = spec["pos"] as Vector3
		cleat.bollard_scale = 0.85
		root.add_child(cleat)

	var lights := [
		{"type": ShipLight.LightType.NAV_PORT, "pos": Vector3(-beam * 0.48, deck_y + 0.4, -loa * 0.2)},
		{"type": ShipLight.LightType.NAV_STARBOARD, "pos": Vector3(beam * 0.48, deck_y + 0.4, -loa * 0.2)},
		{"type": ShipLight.LightType.NAV_MASTHEAD, "pos": Vector3(0.0, deck_y + 1.8, -loa * 0.35)},
		{"type": ShipLight.LightType.NAV_STERN, "pos": Vector3(0.0, deck_y + 0.5, loa * 0.45)},
	]
	for spec in lights:
		var light := ShipLight.new()
		light.light_type = spec["type"]
		light.position = spec["pos"] as Vector3
		root.add_child(light)
