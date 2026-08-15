extends SceneTree

## Contract test for PartCatalog — the kit loader. Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/part_catalog_test.gd
##
## Every check here has been shown to go RED against a deliberately broken
## loader; the mutants are listed in the wave report. A check with no failing
## control is not evidence.
##
## The loader is deliberately reachable as a pure function of a parsed document
## (PartCatalog.parse_document), so a malformed entry is testable without
## shipping malformed JSON.

const PC := preload("res://scripts/construction/part_catalog.gd")
const BAKER_PATH := "res://scripts/construction/structure_baker.gd"

var _failures := 0


func _check(label: String, ok: bool) -> void:
	print("%s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _initialize() -> void:
	_test_catalog_loads_clean()
	_test_every_part_is_built_from_the_five_primitives()
	_test_compliance_identity()
	_test_live_or_baked_follows_the_skin_baker()
	_test_parameters_and_clamping()
	_test_token_arithmetic()
	_test_unknown_primitive_is_reported_not_skipped()
	_test_malformed_entries_are_rejected_by_name()
	_test_one_bad_entry_does_not_take_the_kit_down()
	_test_materials_come_from_the_baker()
	_test_unbuildable_parts_are_declared()
	_test_emitter_call_site_is_real()
	print("---")
	print("part_catalog_test: %s" % ("ALL PASS" if _failures == 0 else "%d FAILURES" % _failures))
	quit(0 if _failures == 0 else 1)


# ── Fixtures built in code, so a mutation has nowhere to hide ────────────────

func _good_part(id: String) -> Dictionary:
	return {
		"id": id,
		"display": "Probe",
		"material": "steel",
		"color": "#808080",
		"mass_kg": 10.0,
		"params": {"length": {"default": 4.0, "min": 1.0, "max": 9.0}},
		"build": [{
			"primitive": "spar",
			"from": [0, 0, 0],
			"to": [0, "$length", 0],
			"radius": 0.1,
		}],
	}


## Applies `mutate` to a copy of a known-good part and parses it alone.
func _parse_mutated(id: String, mutate: Callable) -> Dictionary:
	var part := _good_part(id)
	mutate.call(part)
	return PC.parse_document({"version": 1, "parts": [part]})


func _errors_mention(result: Dictionary, needles: Array) -> bool:
	var blob := " | ".join(result["errors"] as PackedStringArray)
	for needle in needles:
		if not blob.contains(str(needle)):
			print("    missing %s in: %s" % [str(needle), blob])
			return false
	return true


func _spec_for(specs: Array, index: int) -> Dictionary:
	if index < 0 or index >= specs.size():
		return {}
	return specs[index] as Dictionary


# ── The shipped catalog ─────────────────────────────────────────────────────

func _test_catalog_loads_clean() -> void:
	PC.reload()
	var errors := PC.load_errors()
	var warnings := PC.load_warnings()
	print("  ids=%d errors=%d warnings=%d" % [PC.ids().size(), errors.size(), warnings.size()])
	for message in errors:
		print("    error: %s" % message)
	for message in warnings:
		print("    warning: %s" % message)
	_check("shipped catalog loads with no errors", errors.is_empty())
	_check("shipped catalog loads with no warnings", warnings.is_empty())
	_check("catalog has a workable kit (>= 12 parts)", PC.ids().size() >= 12)
	_check("ids are unique and sorted", PC.ids() == _sorted_unique(PC.ids()))


func _sorted_unique(ids: PackedStringArray) -> PackedStringArray:
	var seen := PackedStringArray()
	for id in ids:
		if not seen.has(id):
			seen.append(id)
	seen.sort()
	return seen


func _test_every_part_is_built_from_the_five_primitives() -> void:
	var kit := PackedStringArray(PC.PRIMITIVES.keys())
	_check("the kit is exactly five primitives", kit.size() == 5)
	var all_ok := true
	var seen: Dictionary = {}
	var composites := 0
	for id in PC.ids():
		var entry := PC.get_entry(id)
		var specs := PC.expand(id)
		var build: Array = entry.get("build", [])
		if specs.size() != build.size() or specs.is_empty():
			print("    %s expanded %d of %d steps" % [id, specs.size(), build.size()])
			all_ok = false
		var distinct: Dictionary = {}
		for spec_raw in specs:
			var prim := str((spec_raw as Dictionary)["primitive"])
			seen[prim] = true
			distinct[prim] = true
			if not kit.has(prim):
				print("    %s uses non-kit primitive %s" % [id, prim])
				all_ok = false
		if build.size() > 1:
			composites += 1
		if float(PC.mass_kg_of(id)) <= 0.0:
			print("    %s has no mass" % id)
			all_ok = false
	_check("every part expands to one spec per build step, all from the kit", all_ok)
	_check("every primitive in the kit is exercised by some part", seen.size() == 5)
	_check("composites exist (parts assembled from several primitives)", composites >= 5)


func _test_compliance_identity() -> void:
	## The identities VesselCompliance counts: tag, slot, numeric attribute.
	_check("mooring part carries the mooring tag", PC.has_tag("bollard_pair", "mooring"))
	_check("nav_white part carries the nav_white tag", PC.has_tag("lantern_all_round", "nav_white"))
	_check("helm part fills the helm slot", PC.outfit_slot_of("helm_console") == "helm")
	_check("fishing part fills the fishing slot", PC.outfit_slot_of("net_drum") == "fishing")
	_check("bulk hold part carries the bulk_hold tag", PC.has_tag("hold_coaming", "bulk_hold"))
	_check("a part with no slot tag has no slot", PC.outfit_slot_of("spar_run") == "")
	var seat := PC.compliance_of("bench_seat")
	_check("passenger_capacity survives the load", int(seat.get("passenger_capacity", 0)) == 3)
	var drum := PC.compliance_of("net_drum")
	_check("equipment_rating survives the load", int(drum.get("equipment_rating", 0)) == 2)
	var hold := PC.compliance_of("hold_coaming")
	_check("hold_depth_m survives the load", absf(float(hold.get("hold_depth_m", 0.0)) - 2.5) < 1e-5)
	_check("an untagged part reports zero capacity",
		int(PC.compliance_of("spar_run").get("passenger_capacity", -1)) == 0)


func _test_live_or_baked_follows_the_skin_baker() -> void:
	var agree := true
	for id in PC.ids():
		var expected := false
		for tag in VesselSkinBaker.LIVE_TAGS:
			if PC.has_tag(id, str(tag)):
				expected = true
				break
		if PC.is_live(id) != expected:
			print("    %s live=%s but tags %s say %s"
				% [id, str(PC.is_live(id)), str(PC.tags_of(id)), str(expected)])
			agree = false
	_check("live/baked is derived from VesselSkinBaker.LIVE_TAGS for every part", agree)
	_check("helm stays live", PC.is_live("helm_console"))
	_check("mooring gear stays live", PC.is_live("bollard_pair"))
	_check("lights stay live", PC.is_live("lantern_all_round"))
	_check("fishing gear stays live", PC.is_live("net_drum"))
	_check("plain structure bakes into the skin", PC.is_baked("gallows_a_frame"))
	_check("a hold coaming bakes into the skin", PC.is_baked("hold_coaming"))
	_check("is_baked is false for an unknown part", not PC.is_baked("no_such_part"))

	## A declared `live` that contradicts the tags is a lie about the part.
	var lying := _parse_mutated("liar", func(p): p["compliance"] = {"tags": ["helm"]}; p["live"] = false)
	_check("a part declaring live=false while tagged helm is rejected",
		not (lying["entries"] as Dictionary).has("liar")
			and _errors_mention(lying, ["liar", "live"]))
	var honest := _parse_mutated("honest", func(p): p["compliance"] = {"tags": ["helm"]}; p["live"] = true)
	_check("a part whose declared live agrees with its tags loads",
		(honest["entries"] as Dictionary).has("honest"))


func _test_parameters_and_clamping() -> void:
	var default_specs := PC.expand("spar_run")
	var top := (_spec_for(default_specs, 0).get("to", Vector3.ZERO) as Vector3).y
	_check("a parameter default drives the geometry", absf(top - 6.0) < 1e-4)

	var tall := PC.expand("spar_run", {"length": 12.0})
	var tall_top := (_spec_for(tall, 0).get("to", Vector3.ZERO) as Vector3).y
	_check("an override drives the geometry", absf(tall_top - 12.0) < 1e-4)

	var silly := PC.expand("spar_run", {"length": 900.0})
	var clamped := (_spec_for(silly, 0).get("to", Vector3.ZERO) as Vector3).y
	_check("an out-of-range override is clamped to the declared max", absf(clamped - 30.0) < 1e-4)

	var typo := PC.expand_checked("spar_run", {"lenght": 12.0})
	_check("an override of a parameter that does not exist is refused, not ignored",
		(typo["specs"] as Array).is_empty()
			and _errors_mention(typo, ["lenght", "spar"]))

	var defaults_applied := _spec_for(PC.expand("railing_run"), 0)
	_check("an omitted optional field takes the primitive's default",
		int(defaults_applied.get("rails", -1)) == 3
			and absf(float(defaults_applied.get("toe_height", -1.0))) < 1e-6)


func _test_token_arithmetic() -> void:
	var gallows := PC.expand("gallows_a_frame")
	var leg := _spec_for(gallows, 0)
	var foot := leg.get("from", Vector3.ZERO) as Vector3
	_check("$param*-0.5 resolves to a negative offset", absf(foot.x - (-1.6)) < 1e-4)
	_check("both legs meet at one head",
		(_spec_for(gallows, 0).get("to", Vector3.ONE) as Vector3)
			.is_equal_approx(_spec_for(gallows, 1).get("to", Vector3.ZERO) as Vector3))
	_check("the A-frame is two spars and a wire",
		str(_spec_for(gallows, 0)["primitive"]) == "spar"
			and str(_spec_for(gallows, 1)["primitive"]) == "spar"
			and str(_spec_for(gallows, 2)["primitive"]) == "wire")

	var funnel := PC.expand("funnel_tapered")
	var cap_top := (_spec_for(funnel, 1).get("to", Vector3.ZERO) as Vector3).y
	_check("$param+literal resolves", absf(cap_top - 3.38) < 1e-4)

	var bulwark := PC.expand("bulwark_capped")
	var band := _spec_for(bulwark, 1).get("path", PackedVector3Array()) as PackedVector3Array
	_check("a sheer band carries per-station height",
		band.size() == 3 and absf(band[0].y - 2.1) < 1e-4
			and absf(band[1].y - 1.55) < 1e-4 and absf(band[2].y - 1.2) < 1e-4)


# ── Rejection: loudly, by name, never silently ──────────────────────────────

func _test_unknown_primitive_is_reported_not_skipped() -> void:
	var result := _parse_mutated("bad_prim", func(p): (p["build"][0] as Dictionary)["primitive"] = "gantry")
	var entries := result["entries"] as Dictionary
	_check("a part naming an unknown primitive is rejected", not entries.has("bad_prim"))
	_check("the error names the part, the bogus primitive and the real kit",
		_errors_mention(result, ["bad_prim", "gantry", "spar", "railing", "wire", "plate", "sheer_band"]))

	## The distinction that matters: unknown primitive = rejected outright;
	## known primitive with no baker emitter yet = loaded, and reported as
	## unbuildable. Both are visible; neither is silent.
	var known := PC.parse_document({"version": 1, "parts": [_good_part("known_prim")]})
	_check("a known primitive with no emitter still loads",
		(known["entries"] as Dictionary).has("known_prim")
			and (known["errors"] as PackedStringArray).is_empty())

	## A PART ID MAY NOT SPELL A PRIMITIVE, and this is the check for a defect
	## that shipped: the catalog held parts named `spar` and `wire`, and
	## `StructureBaker.item_primitive` falls back to a plan item's `item_id`, so
	## a `{item_id: "spar"}` item resolved to the baker primitive and the part's
	## build[] was never reached. Both drew exactly nothing when placed as parts
	## while the other thirteen drew. They are `spar_run` and `wire_run` now, and
	## a shadowed id can no longer load in silence.
	var shadowed := PC.parse_document({"version": 1, "parts": [_good_part("spar")]})
	_check("a part id that spells a primitive is rejected, not shadowed",
		not (shadowed["entries"] as Dictionary).has("spar")
			and _errors_mention(shadowed, ["spar", "primitive"]))
	var every_id_ok := true
	for id in PC.ids():
		if PC.PRIMITIVES.has(str(id)):
			print("    shipped part %s shadows a primitive" % str(id))
			every_id_ok = false
	_check("no shipped part id spells a primitive", every_id_ok)


func _test_malformed_entries_are_rejected_by_name() -> void:
	var cases: Array = [
		["missing required field", "no_radius", ["no_radius", "radius"],
			func(p): (p["build"][0] as Dictionary).erase("radius")],
		["typo'd primitive field", "typo_field", ["typo_field", "radius_m"],
			func(p): (p["build"][0] as Dictionary)["radius_m"] = 0.1],
		["unknown $param token", "bad_token", ["bad_token", "girth"],
			func(p): (p["build"][0] as Dictionary)["to"] = [0, "$girth", 0]],
		["non-numeric literal", "bad_literal", ["bad_literal", "tall"],
			func(p): (p["build"][0] as Dictionary)["to"] = [0, "tall", 0]],
		["material the baker cannot render", "bad_material", ["bad_material", "brass"],
			func(p): p["material"] = "brass"],
		["invalid colour", "bad_color", ["bad_color", "nope"],
			func(p): p["color"] = "nope"],
		["missing mass", "no_mass", ["no_mass", "mass_kg"],
			func(p): p.erase("mass_kg")],
		["zero mass", "zero_mass", ["zero_mass", "mass_kg"],
			func(p): p["mass_kg"] = 0.0],
		["empty build", "no_build", ["no_build", "build"],
			func(p): p["build"] = []],
		["build is not an array", "build_scalar", ["build_scalar", "build"],
			func(p): p["build"] = 3],
		["compliance attribute that nothing reads", "bad_attr", ["bad_attr", "passenger_capactiy"],
			func(p): p["compliance"] = {"passenger_capactiy": 4}],
		["compliance tags not an array", "bad_tags", ["bad_tags", "tags"],
			func(p): p["compliance"] = {"tags": "mooring"}],
		["parameter without a default", "no_default", ["no_default", "length"],
			func(p): p["params"] = {"length": {"min": 1.0}}],
		["parameter default outside its own range", "bad_range", ["bad_range", "length"],
			func(p): p["params"] = {"length": {"default": 40.0, "max": 9.0}}],
		["a quad that is not four points", "bad_quad", ["bad_quad", "4"],
			func(p): p["build"] = [{
				"primitive": "plate",
				"corners": [[0, 0, 0], [1, 0, 0], [1, 1, 0]],
				"thickness": 0.1,
			}]],
		["a railing with a single station", "short_path", ["short_path", "at least 2"],
			func(p): p["build"] = [{
				"primitive": "railing", "path": [[0, 0, 0]], "height": 1.1,
			}]],
	]
	var all_ok := true
	for case in cases:
		var label := str((case as Array)[0])
		var id := str((case as Array)[1])
		var needles: Array = (case as Array)[2]
		var result := _parse_mutated(id, (case as Array)[3] as Callable)
		var rejected := not (result["entries"] as Dictionary).has(id)
		var named := _errors_mention(result, needles)
		if not (rejected and named):
			print("    case failed: %s (rejected=%s named=%s)" % [label, str(rejected), str(named)])
			all_ok = false
	_check("every malformed entry is rejected with a message naming it (%d cases)" % cases.size(), all_ok)

	var no_id := PC.parse_document({"version": 1, "parts": [{"mass_kg": 1.0}]})
	_check("an entry with no id is reported by index",
		(no_id["entries"] as Dictionary).is_empty() and _errors_mention(no_id, ["parts[0]", "id"]))

	var dupe := PC.parse_document({"version": 1, "parts": [_good_part("twin"), _good_part("twin")]})
	_check("a duplicate id is reported instead of silently replacing the first",
		(dupe["entries"] as Dictionary).size() == 1 and _errors_mention(dupe, ["twin", "duplicate"]))

	var not_a_doc := PC.parse_document({"version": 1})
	_check("a document with no parts array is reported",
		_errors_mention(not_a_doc, ["parts"]))


func _test_one_bad_entry_does_not_take_the_kit_down() -> void:
	var bad := _good_part("rotten")
	(bad["build"][0] as Dictionary)["primitive"] = "gantry"
	var result := PC.parse_document({
		"version": 1,
		"parts": [_good_part("sound_a"), bad, _good_part("sound_b")],
	})
	var entries := result["entries"] as Dictionary
	_check("the good parts either side of a rejected one still load",
		entries.has("sound_a") and entries.has("sound_b") and not entries.has("rotten"))
	_check("exactly one failure is reported", (result["errors"] as PackedStringArray).size() == 1)
	_check("load order is preserved for the survivors",
		(result["order"] as PackedStringArray) == PackedStringArray(["sound_a", "sound_b"]))


func _test_materials_come_from_the_baker() -> void:
	var script := load(BAKER_PATH) as Script
	var declared := PackedStringArray((script.get_script_constant_map()["MATERIALS"] as Dictionary).keys())
	declared.sort()
	var seen := PC.baker_materials()
	seen.sort()
	_check("the catalog validates materials against StructureBaker.MATERIALS", declared == seen)
	var every_material_real := true
	for id in PC.ids():
		if not declared.has(PC.material_of(id)):
			print("    %s uses %s" % [id, PC.material_of(id)])
			every_material_real = false
	_check("every shipped part names a material the baker can render", every_material_real)


# ── Buildability: declared, not silently dropped ────────────────────────────

## THIS SUB-TEST USED TO ASSERT THE DEFECT (REALITY.md §4c). It read
##
##     _check("no primitive is bakeable yet, so no part is buildable yet",
##         PC.buildable_ids().is_empty() and report.size() == PC.ids().size())
##
## — green, honest about what it measured, and it would have gone RED for anyone
## who landed the five emitters `part_catalog.gd`'s own header says a later wave
## lands. It cemented "no catalog part draws" as correct behaviour, next to a
## strip test showing 18 fittings contributing 0 triangles and 0 colliders
## through the production path.
##
## What replaces it is the property rather than the state: buildability AGREES
## with the baker's method list, in both directions, and the report is empty
## exactly when nothing is missing.
func _test_unbuildable_parts_are_declared() -> void:
	var report := PC.unbuildable_report()
	print("  unbuildable: %d of %d parts" % [report.size(), PC.ids().size()])
	if report.size() > 0:
		print("    e.g. %s" % str((report[0] as Dictionary)["reason"]))
	var baker_methods := _baker_method_names()
	## Direction 1: a primitive is supported exactly when the baker holds the
	## method PRIMITIVES names for it. Nothing here restates "five" or "true" —
	## delete an emitter and this reddens on that primitive.
	var supports_ok := true
	for prim in PC.PRIMITIVES.keys():
		var emitter := PC.emitter_method_for(str(prim))
		if PC.baker_supports(str(prim)) != baker_methods.has(emitter):
			print("    %s: baker_supports=%s but StructureBaker.%s exists=%s"
				% [str(prim), str(PC.baker_supports(str(prim))), emitter,
					str(baker_methods.has(emitter))])
			supports_ok = false
	_check("a primitive is supported exactly when StructureBaker holds its emitter",
		supports_ok)
	## Direction 2: a part is buildable exactly when none of its primitives is
	## missing, and the report holds exactly the parts that are not.
	var buildable_ok := true
	for id in PC.ids():
		var missing := PC.missing_primitives(str(id))
		if PC.is_buildable(str(id)) != missing.is_empty():
			buildable_ok = false
	_check("a part is buildable exactly when none of its primitives is missing",
		buildable_ok)
	_check("the unbuildable report holds exactly the parts that are not buildable",
		report.size() == PC.ids().size() - PC.buildable_ids().size())
	## Every part is buildable today, so this loop has nothing to iterate — and a
	## check over an empty universe is a vacuous PASS (REALITY.md §4), so it only
	## counts when there is something to say. It goes live again the moment an
	## emitter is removed, which is the only state it was ever about.
	if report.is_empty():
		print("  (no unbuildable parts — the reason-text check has nothing to run over)")
	else:
		var reasons_ok := true
		for row_raw in report:
			var row := row_raw as Dictionary
			var missing := row["missing_primitives"] as PackedStringArray
			if missing.is_empty():
				reasons_ok = false
				continue
			for prim in missing:
				var emitter := PC.emitter_method_for(str(prim))
				if emitter.is_empty() or not str(row["reason"]).contains(emitter):
					print("    %s reason does not name %s" % [str(row["id"]), emitter])
					reasons_ok = false
		_check("each unbuildable part names the emitter it is waiting on", reasons_ok)
	## The real negative, and it can fail: an id the catalog does not hold is not
	## buildable however many emitters exist.
	_check("an id the catalog does not hold is not buildable",
		not PC.is_buildable("gantry_crane_of_theseus"))
	## Every shipped part draws today. This is the strip test's finding as an
	## assertion — before the emitters landed it was 0 of 15.
	_check("every shipped part is buildable (%d of %d)"
		% [PC.buildable_ids().size(), PC.ids().size()],
		PC.buildable_ids().size() == PC.ids().size())


func _baker_method_names() -> PackedStringArray:
	var script := load(BAKER_PATH) as Script
	var names := PackedStringArray()
	if script == null:
		return names
	for method in script.get_script_method_list():
		names.append(str((method as Dictionary).get("name", "")))
	return names


func _test_emitter_call_site_is_real() -> void:
	_check("emitter names follow <primitive>_boxes",
		PC.emitter_method_for("spar") == "spar_boxes"
			and PC.emitter_method_for("railing") == "railing_boxes"
			and PC.emitter_method_for("wire") == "wire_boxes"
			and PC.emitter_method_for("plate") == "plate_boxes"
			and PC.emitter_method_for("sheer_band") == "sheer_band_boxes")
	_check("an unknown primitive has no emitter", PC.emitter_method_for("gantry") == "")

	## THIS USED TO BE `_check("StructureBaker has none of the five emitters yet
	## (this test's premise)", none_yet)` — the second assertion in this file
	## that would go red when the feature it describes arrived. Replaced by the
	## thing it was standing in for: the dispatch reaches a real method and comes
	## back with geometry, for EVERY primitive in the kit.
	var script := load(BAKER_PATH) as Script
	var names := _baker_method_names()
	var missing := PackedStringArray()
	for prim in PC.PRIMITIVES.keys():
		if not names.has(PC.emitter_method_for(str(prim))):
			missing.append(str(prim))
	_check("StructureBaker holds an emitter for every primitive in the kit (missing: %s)"
		% ("none" if missing.is_empty() else ", ".join(missing)), missing.is_empty())

	## The documented call site, driven through the primitive it was written for.
	var boxes: Variant = script.call("wall_boxes", {
		"start": [0, 0, 0], "axis": "x", "length": 4.0, "height": 3.0, "thickness": 0.2,
	})
	_check("StructureBaker.call(<emitter>, spec) dispatches a static by name",
		boxes is Array and (boxes as Array).size() > 0)

	## And `emit_boxes` — the seam a consumer is told to use — returns geometry
	## for a spec of EVERY primitive, not just the one this test remembered.
	var emitted := {}
	for prim in PC.PRIMITIVES.keys():
		emitted[str(prim)] = 0
	for id in PC.ids():
		for spec_variant in PC.expand(str(id)):
			var one := spec_variant as Dictionary
			var prim := str(one.get("primitive", ""))
			emitted[prim] = int(emitted.get(prim, 0)) + PC.emit_boxes(one).size()
	var silent := PackedStringArray()
	for prim in emitted.keys():
		if int(emitted[prim]) <= 0:
			silent.append(str(prim))
	_check("emit_boxes returns geometry for every primitive the kit uses (silent: %s)"
		% ("none" if silent.is_empty() else ", ".join(silent)), silent.is_empty())

	## And the spec handed to that call is complete: primitive, owner, surface.
	var spec := _spec_for(PC.expand("net_drum"), 0)
	_check("a resolved spec carries primitive, part_id, material and colour",
		str(spec.get("primitive", "")) == "spar"
			and str(spec.get("part_id", "")) == "net_drum"
			and str(spec.get("material", "")) == "steel"
			and spec.get("color", null) is Color)
	_check("a resolved spec carries typed geometry, not raw JSON",
		spec.get("from", null) is Vector3 and spec.get("to", null) is Vector3
			and typeof(spec.get("sides", null)) == TYPE_INT)
