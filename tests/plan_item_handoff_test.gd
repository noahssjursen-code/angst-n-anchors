extends SceneTree

## Lane A contract test for the items/catalog hand-off — the three seams a
## critic found broken between `structure_plan.gd`, `part_catalog.gd` and
## `plan_outfit.gd`. Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/plan_item_handoff_test.gd
##
## 1. THE HAND-OFF COMPILES. The documented call site named `ItemCatalog` and a
##    `parts()` API; neither exists, so the paragraph two waves were told to
##    paste into StructureBaker does not parse. Both halves are compiled here at
##    runtime — the broken one must fail, the corrected one must succeed — so
##    this cannot rot back into prose that only looks right.
##
## 2. FREE ROTATION STAYS FREE. `item_footprint_cells` took the world-space AABB
##    of the rotated part box, so an 8 x 4 m hold cost 128 cells at yaw 0 and
##    324 at 45° — 2.53x the deck it covers, charged for an angle. The item
##    schema exists to allow free yaw; a rule that fines it hands the
##    quantisation back.
##
## 3. A MIS-TYPED PROP IS REPORTED. `param_overrides` dropped every prop that
##    named no parameter, which also swallowed `expand_checked`'s own
##    "no parameter X" error — `{"lenght": 8}` silently became the default.
##
## A script error aborts the enclosing function and lets _initialize carry on,
## so this file could report "ALL PASS" having asserted nothing. The check count
## is pinned for exactly that reason.

const PC := preload("res://scripts/construction/part_catalog.gd")
const PO := preload("res://scripts/ship/plan_outfit.gd")
const HULL := "hull_28x10"
const EXPECTED_CHECKS := 43

## An 8 x 4 m hold covers 32 m². Its coaming skin adds 0.06 m per face, so the
## measured box is 4.12 x 8.12 = 33.5 m² — 134 cells at 0.5 m. Anything above
## this is the builder paying for an angle.
const TRUE_CELLS := 134

var _failures := 0
var _checks := 0


func _check(label: String, ok: bool) -> void:
	_checks += 1
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _initialize() -> void:
	_test_the_documented_call_site_compiles()
	_test_expand_props_is_the_seam()
	_test_rotation_is_not_taxed()
	_test_rotated_holds_are_still_measured_honestly()
	_test_a_mistyped_prop_is_reported()
	_test_the_report_reaches_the_builder()
	print("---")
	if _checks != EXPECTED_CHECKS:
		print(
			"FAIL ran %d checks, expected %d — a check aborted before asserting"
			% [_checks, EXPECTED_CHECKS]
		)
		_failures += 1
	print(
		"plan_item_handoff_test: %d checks, %s"
		% [_checks, "ALL PASS" if _failures == 0 else "%d FAILURES" % _failures]
	)
	quit(0 if _failures == 0 else 1)


# ── 1. The hand-off compiles ────────────────────────────────────────────────

## Compiles a snippet in isolation and returns the parse result.
func _compiles(body: String) -> bool:
	var script := GDScript.new()
	script.source_code = (
		"extends RefCounted\n\nstatic func run(\n"
		+ "\tplan: StructurePlan, buckets: Dictionary, offset: Vector3, ghost: bool\n"
		+ ") -> void:\n%s\n"
	) % body
	return script.reload() == OK


func _test_the_documented_call_site_compiles() -> void:
	## The superseded hand-off, verbatim from structure_plan.gd's header.
	var broken := """	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var xform := plan.item_transform(item)
		var props := StructurePlan.item_props(item)
		for part in ItemCatalog.parts(str(item["item_id"]), props):
			pass"""
	_check("the ItemCatalog hand-off does not compile", not _compiles(broken))
	_check("...because there is no ItemCatalog class", not ClassDB.class_exists("ItemCatalog"))
	var catalog_script: Script = PC
	_check(
		"...and PartCatalog is the class that does exist",
		catalog_script.get_global_name() == "PartCatalog"
	)

	## The second half of the same defect, and the one that survived the first
	## rewrite of this hand-off: a global class NAME is a compile-time class
	## reference, not a Script value, so the dynamic dispatch cannot be spelled
	## on it. `part_catalog.gd` and `structure_edge.gd` both documented this line.
	_check(
		"StructureBaker.call(emitter, spec) does not compile either",
		not _compiles("\treturn StructureBaker.call(\"wall_boxes\", {})")
	)
	_check(
		"...but the same call on a Script VALUE does",
		_compiles("\tvar s := StructureBaker as Script\n\treturn s.call(\"wall_boxes\", {})")
	)

	## The corrected hand-off, verbatim from part_catalog.gd's header.
	var fixed := """	for item_variant in plan.items:
		var item := item_variant as Dictionary
		var xform := plan.item_transform(item)
		var resolved := PartCatalog.expand_props(
			str(item.get("item_id", "")), StructurePlan.item_props(item)
		)
		for message in resolved["errors"] as PackedStringArray:
			push_error("StructureBaker: item %d: %s" % [int(item["id"]), message])
		for message in resolved["warnings"] as PackedStringArray:
			push_warning("StructureBaker: item %d: %s" % [int(item["id"]), message])
		for spec_variant in resolved["specs"] as Array:
			var spec := spec_variant as Dictionary
			for box_variant in PartCatalog.emit_boxes(spec):
				var box := box_variant as Dictionary
				box["center"] = xform * (box["center"] as Vector3)
				box["basis"] = xform.basis * (box["basis"] as Basis)
				print(box)"""
	_check("the corrected PartCatalog hand-off compiles", _compiles(fixed))


func _test_expand_props_is_the_seam() -> void:
	## One call: plan props in, resolved primitive specs out.
	var resolved := PC.expand_props("hold_coaming", {"length": 8.0, "width": 4.0})
	var specs: Array = resolved["specs"]
	_check("expand_props resolves a part from its props bag", specs.size() == 4)
	_check("expand_props reports no error for good props", (
		resolved["errors"] as PackedStringArray
	).is_empty())
	_check("expand_props carries a warnings channel", resolved.has("warnings"))

	## The props actually reach the geometry — an 8 m hold is 8 m long.
	var span := 0.0
	for spec_variant in specs:
		for point in (spec_variant as Dictionary).get("corners", PackedVector3Array()):
			span = maxf(span, absf((point as Vector3).z) * 2.0)
	_check("the props reach the geometry (hold is %.1f m long)" % span, is_equal_approx(span, 8.0))

	## Every spec names an emitter, and the baker is asked rather than assumed.
	var named := true
	for spec_variant in specs:
		var primitive := str((spec_variant as Dictionary)["primitive"])
		if PC.emitter_method_for(primitive).is_empty():
			named = false
	_check("every resolved spec names an emitter method", named)
	_check(
		"plate is declared-but-unbuildable, and says so",
		not PC.baker_supports("plate") and not PC.is_buildable("hold_coaming")
	)
	## emit_boxes owns the dispatch: [] for a primitive the baker cannot draw,
	## never a crash and never a silently invented box.
	_check("emit_boxes returns nothing for an unimplemented primitive",
		PC.emit_boxes(specs[0] as Dictionary).is_empty())
	## ...and the dispatch really does reach a static by name, proved on the one
	## emitter the baker already has.
	var baker: Script = load("res://scripts/construction/structure_baker.gd")
	var boxes: Variant = baker.call("wall_boxes", {
		"start": [0.0, 0.0, 0.0], "axis": "x", "length": 2.0, "height": 2.0,
		"thickness": 0.2, "openings": [],
	})
	_check(
		"dispatch by emitter name is a real seam",
		boxes is Array and (boxes as Array).size() > 0
	)


# ── 2. Free rotation stays free ─────────────────────────────────────────────

func _hold(yaw: float) -> Array:
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var item := plan.add_item(
		"hold_coaming", Vector3(5.0, 0.0, 14.0), yaw, {"length": 8.0, "width": 4.0}
	)
	return [plan, item]


func _footprint(yaw: float, grid: DeckGrid) -> int:
	var pair := _hold(yaw)
	return PO.item_footprint_cells(pair[0] as StructurePlan, pair[1] as Dictionary, grid).size()


func _test_rotation_is_not_taxed() -> void:
	var grid := HullRegistry.make_grid(HULL)
	_check("axis-aligned is unchanged: 8 x 4 m is 128 cells", _footprint(0.0, grid) == 128)
	_check("a quarter turn is the same hold", _footprint(90.0, grid) == 128)
	_check("half a turn is the same hold", _footprint(180.0, grid) == 128)
	## The AABB reading charged 216 at 15°, 288 at 30°, 324 at 45°.
	for yaw in [15.0, 22.5, 30.0, 45.0, 60.0, 75.0]:
		var cells := _footprint(float(yaw), grid)
		_check(
			"yaw %.1f costs %d cells, within a tenth of its %d-cell area"
			% [yaw, cells, TRUE_CELLS],
			absf(float(cells - TRUE_CELLS)) <= float(TRUE_CELLS) * 0.1
		)
	## The sharpest form of the claim: no angle costs more than the worst
	## axis-aligned reading by more than rasterisation noise.
	var worst := 0
	for step in 24:
		worst = maxi(worst, _footprint(float(step) * 15.0, grid))
	_check("no yaw in a full turn costs more than 140 cells (worst %d)" % worst, worst <= 140)


func _test_rotated_holds_are_still_measured_honestly() -> void:
	var grid := HullRegistry.make_grid(HULL)
	## A hold twice as long covers twice the deck, at any angle.
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var small := plan.add_item(
		"hold_coaming", Vector3(5.0, 0.0, 14.0), 30.0, {"length": 4.0, "width": 4.0}
	)
	var large := plan.add_item(
		"hold_coaming", Vector3(5.0, 0.0, 14.0), 30.0, {"length": 8.0, "width": 4.0}
	)
	var small_cells := PO.item_footprint_cells(plan, small, grid).size()
	var large_cells := PO.item_footprint_cells(plan, large, grid).size()
	_check(
		"a rotated hold still grows with its parameters (%d -> %d)" % [small_cells, large_cells],
		float(large_cells) / float(small_cells) > 1.7
	)
	## Every reported cell really is under the part: its centre, taken back into
	## part-local metres, lies inside the part's own box.
	var box := PO.part_local_aabb("hold_coaming", {"length": 8.0, "width": 4.0})
	var inverse := plan.item_transform(large).affine_inverse()
	var outside := 0
	for cell in PO.item_footprint_cells(plan, large, grid):
		var centre := StructurePlan.cell_base_plan(cell)
		var local := inverse * Vector3(centre.x, 0.0, centre.z)
		var mn: Vector3 = box["min"]
		var mx: Vector3 = box["max"]
		if local.x < mn.x - 0.001 or local.x > mx.x + 0.001 \
			or local.z < mn.z - 0.001 or local.z > mx.z + 0.001:
			outside += 1
	_check("every charged cell centre is under the part (%d strays)" % outside, outside == 0)
	## And the rotated hold is still cargo the hull will accept.
	var rotated := StructurePlan.new()
	rotated.hull_id = HULL
	rotated.add_item("hold_coaming", Vector3(5.0, 0.0, 14.0), 45.0, {"length": 8.0, "width": 4.0})
	var outfit := PO.validate(rotated, HULL, grid)
	_check("a hold turned 45° is accepted cargo", bool(outfit["ok"]))
	_check(
		"and is charged what it covers (%d cells)"
		% int((outfit["usage"] as Dictionary)["accepted_cargo_cells"]),
		int((outfit["usage"] as Dictionary)["accepted_cargo_cells"]) <= 140
	)


# ── 3. A mis-typed prop is reported ─────────────────────────────────────────

func _test_a_mistyped_prop_is_reported() -> void:
	var typo := " | ".join(PO.prop_warnings("hold_coaming", {"lenght": 8.0}))
	_check("a mis-typed numeric prop is reported", not typo.is_empty())
	_check("the report names the prop", typo.contains("lenght"))
	_check("and lists what the part does declare", typo.contains("length") and typo.contains("width"))
	_check(
		"the geometry still resolves on defaults rather than vanishing",
		bool(PO.part_local_aabb("hold_coaming", {"lenght": 8.0}).get("ok", false))
	)
	_check(
		"a mis-typed prop changes nothing about the part",
		PO.param_overrides("hold_coaming", {"lenght": 8.0}).is_empty()
	)
	## A declared parameter handed the wrong type is the same silence.
	var wrong_type := " | ".join(PO.prop_warnings("hold_coaming", {"length": "8"}))
	_check("a declared parameter given a string is reported", wrong_type.contains("length"))
	_check("...and says it needs a number", wrong_type.contains("number"))
	## The bag is free-form for everything that is not a parameter attempt.
	_check(
		"non-numeric bag entries stay silent",
		PO.prop_warnings("hold_coaming", {"paint_region": "boot_top", "label": "FISH"}).is_empty()
	)
	_check(
		"a good prop is not reported",
		PO.prop_warnings("hold_coaming", {"length": 8.0, "width": 4.0}).is_empty()
	)
	_check(
		"props for a part that does not exist are reported, not ignored",
		not PO.prop_warnings("winch_of_the_gods", {"length": 8.0}).is_empty()
	)


func _test_the_report_reaches_the_builder() -> void:
	var grid := HullRegistry.make_grid(HULL)
	var plan := StructurePlan.new()
	plan.hull_id = HULL
	var item := plan.add_item(
		"hold_coaming", Vector3(5.0, 0.0, 14.0), 0.0, {"lenght": 8.0, "width": 4.0}
	)
	var outfit := PO.validate(plan, HULL, grid)
	var warnings := " | ".join(outfit["warnings"] as PackedStringArray)
	_check("validate() reports the typo to the builder", warnings.contains("lenght"))
	_check(
		"and names the item it is on (item %d)" % int(item["id"]),
		warnings.contains("Plan item %d" % int(item["id"]))
	)
	## The silence had a consequence worth naming: the hold is its 12 m default,
	## not the 8 m the builder typed, and it is charged for the difference.
	var defaulted := StructurePlan.new()
	defaulted.hull_id = HULL
	var full := defaulted.add_item(
		"hold_coaming", Vector3(5.0, 0.0, 14.0), 0.0, {"length": 12.0, "width": 4.0}
	)
	_check(
		"the silent fallback really is the 12 m default (%d cells)"
		% PO.item_footprint_cells(plan, item, grid).size(),
		PO.item_footprint_cells(plan, item, grid).size()
			== PO.item_footprint_cells(defaulted, full, grid).size()
	)
	_check(
		"which is half again the hold that was asked for",
		PO.item_footprint_cells(plan, item, grid).size() > 190
	)
	## A clean plan stays quiet — the report is not noise.
	var clean := StructurePlan.new()
	clean.hull_id = HULL
	clean.add_item("hold_coaming", Vector3(5.0, 0.0, 14.0), 0.0, {"length": 8.0, "width": 4.0})
	_check(
		"a plan with good props raises nothing",
		(PO.validate(clean, HULL, grid)["warnings"] as PackedStringArray).is_empty()
	)
