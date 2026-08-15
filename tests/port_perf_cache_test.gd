extends Node

## LANE B. This file reaches `BuildingCache`, which preloads
## `scripts/port/building_fitout.gd` -> `scripts/ship/brick_door.gd`, and
## `brick_door.gd:96` names the `WorldGateway` autoload as a bare compile-time
## identifier. Under `--script` that is `Identifier not found`, the failure
## cascades to the test itself, and Godot then loads and runs it anyway — so the
## unit reported `FAIL(2)` in the results table with no way to tell a compile
## failure from an assertion failure. `REALITY.md` §4a: fix the compile before
## trusting one word of what a unit asserts. Booted as a scene the autoloads
## exist and the cascade is gone.

const TestReport := preload("res://tests/support/test_report.gd")

## The apron pad role `warehouse.json` exists to fill. Named here, from
## `PortApronPadCatalog.ROLES`, so the pad check below cannot be satisfied by the
## blueprint agreeing with itself — see the note beside it.
const APRON_ROLE := "general_warehouse"


func _ready() -> void:
	var t := TestReport.new("port_perf_cache_test")
	var layout := WorldLayoutGenerator.generate(424242)
	var definition := PortDefinition.new()
	definition.port_id = "perf-cache-test"
	definition.display_name = "Cache Test"
	definition.world_position = Vector3(1200.0, 0.0, -800.0)
	definition.size = 2
	definition.site_seed = 9911
	definition.rotation_y = 0.4
	definition.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION

	PortDataCache.clear()
	var first := PortExpander.expand(definition, 424242, layout)
	var second := PortExpander.expand(definition, 424242, layout)
	t.check("PortDataCache should return the same PortData instance", first == second)
	t.check("cached PortData must retain layout graph", first.layout_graph != null)
	t.equal("cached PortData must retain port id", first.port_id, "perf-cache-test")

	## `resources/data/buildings/` held only `.gitkeep` from `aabdf198` — which
	## wiped `BrickCatalog.BRICKS` to `{}` — until `warehouse.json` landed. This
	## used to `return` on the missing blueprint, which buried the six unrelated
	## checks below behind a catalogue that has nothing to do with land decor or
	## materials; it records and carries on instead.
	##
	## ── WHAT THE TWO STAMP CHECKS USED TO SAY, AND WHY THEY WERE WORTH NOTHING ──
	## Both read `building.get_child_count() > 0`, under the same label, twice.
	## `BuildingCache.instance` adds `Visual`, `BuildingLighting` and `Collision`
	## unconditionally, before it looks at a single brick — so that check is
	## `3 > 0` for a blueprint of 64 bricks, of one brick, or of NONE. It is the
	## bare `assert(true)` of REALITY.md §4: it could not fail, and it would have
	## reported success against the empty catalogue that made this unit red in the
	## first place, had the early return not got there first.
	##
	## What is asserted instead is the two properties that can break. (1) The bake
	## DRAWS the blueprint: at least one mesh per primary cell, which is the strip
	## test — delete the bricks and the count follows. (2) The cache is a CACHE:
	## the second stamp reuses the first's baked `Mesh` resources rather than
	## rebuilding them, which is the only reason this class exists and the same
	## sharing property the two checks either side of it assert for `PortDataCache`
	## and `MeshBuilder`.
	##
	## MUTATION-VERIFIED, both numbers, measured while the unit stood at 13 checks:
	## bake the layout with the content loop stripped, PASS (13) -> 1/13 with
	## "240 meshes, 516 bricks"; make `_stamp_node` duplicate each mesh instead of
	## sharing it, PASS (13) -> 1/13 with "0 of 645"; empty the blueprint's
	## `cells`, PASS (13) -> 2/13. Note what that last one shows — "warehouse
	## blueprint must load" still PASSES on an EMPTY blueprint, so an empty file is
	## the cheapest possible way to turn this unit green, and the brick guard is
	## the only thing that stops it counting.
	##
	## WHAT THESE CHECKS CANNOT SEE, and it is the point of REALITY.md §1: every
	## one of them is green on a building you can see straight through.
	## `BuildingGrid.CELL_M` is 1.0 and `BrickCatalog.size_m` measures in
	## `DeckGrid.CELL_M`, which `a70bdbc` halved to 0.5 — so every 1x1x1 brick is
	## DRAWN at 0.5 m on a 1.0 m lattice and leaves 0.50 m of daylight to its
	## neighbour. Counts, caches and validation cannot tell. Look at
	## `screenshots/buildings/warehouse__door.png`, which is a wall you can see the
	## sky through. Open owner decision, STATE.md #1, land-side half.
	BuildingCache.clear()
	var warehouse := BuildingBlueprintCatalog.by_id("warehouse")
	if t.check("warehouse blueprint must load", warehouse != null):
		## A player opens this blueprint in the brick editor and saves it again:
		## nothing about the building may change. `building_brick_editor.gd` writes
		## `JSON.stringify(to_dict(), "\t")` and a newline, so a save of what was
		## loaded is compared against the file it was loaded from.
		##
		## AS DOCUMENTS, NOT AS BYTES, and the difference is a defect this check
		## found on its first run. `BuildingLayout.from_dict` copies `cells`
		## verbatim, so a `"yaw": 0` written by the editor comes back from JSON as
		## a FLOAT and re-serialises as `"yaw": 0.0` — measured on this blueprint,
		## 98,821 characters become 100,501, two per cell, over 840 yaws.
		## `StructurePlan.from_dict` pins exactly this back to int for entity ids
		## and says why; `BuildingLayout` has no equivalent, so a blueprint is not
		## byte-stable across a visit to its own editor and every visit is a diff.
		## Reported rather than fixed: `building_layout.gd` is not this wave's, and
		## it is the file already carrying an open owner decision.
		##
		## Both sides therefore go through `JSON.parse_string`, which applies that
		## float conversion to BOTH — so what is compared is the DOCUMENT.
		##
		## BE PRECISE ABOUT WHAT THAT CAN CATCH, because the first mutation tried on
		## it PASSED (REALITY.md §8). Editing a `yaw` in the file does NOT redden
		## this: the layout was loaded FROM that file, so both sides move together.
		## It is invariant to the file's contents by construction, and what it holds
		## is the ROUND TRIP — that `from_dict` -> `to_dict` is the identity on this
		## document. Mutation that does redden it: make `from_dict` drop
		## `pad_template_id`, PASS (14) -> 1/14.
		var on_disk: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(BuildingBlueprintCatalog.path_for("warehouse"))
		)
		var resaved: Variant = JSON.parse_string(JSON.stringify(warehouse.to_dict(), "\t"))
		t.check(
			"saving the blueprint back out of the editor changes nothing in it",
			on_disk is Dictionary and resaved == on_disk,
		)
		var bricks := warehouse.iter_primary_cells().size()
		## Guards everything below against a blueprint that loads and is empty —
		## `BuildingRules` passes one of those with a warning, and every count
		## check below is trivially true of it.
		t.check("the warehouse blueprint carries bricks (%d primary cells)" % bricks, bricks > 0)
		var building_a := BuildingCache.instance(warehouse, true)
		var building_b := BuildingCache.instance(warehouse, true)
		var meshes_a := _mesh_instances(building_a)
		var meshes_b := _mesh_instances(building_b)
		t.check(
			"the stamped building draws at least one mesh per brick (%d meshes, %d bricks)"
			% [meshes_a.size(), bricks],
			meshes_a.size() >= bricks and bricks > 0,
		)
		t.equal("stamping it twice draws the same number of meshes",
			meshes_b.size(), meshes_a.size())
		## Resource IDENTITY, not equality: a rebuilt mesh with identical vertices
		## would compare equal by content and would still mean the bake ran twice.
		var shared := 0
		for index in mini(meshes_a.size(), meshes_b.size()):
			if meshes_a[index].mesh == meshes_b[index].mesh and meshes_a[index].mesh != null:
				shared += 1
		t.equal(
			"the second stamp SHARES the baked meshes rather than re-baking them (%d of %d)"
			% [shared, meshes_a.size()],
			shared, meshes_a.size(),
		)
		building_a.free()
		building_b.free()
		## The game's own path onto this blueprint. `port_layout_graph_visualizer`
		## asks `find_for_pad(role, template)` for every apron pad and stamps a grey
		## placeholder box when it gets null, so a blueprint the catalogue can load
		## but that no pad role resolves to is a blueprint the game never builds
		## (REALITY.md §3d).
		##
		## THE ROLE IS NAMED FROM THE APRON CATALOGUE, NOT READ OFF THE BLUEPRINT.
		## The first version of this check asked `find_for_pad(warehouse.role, …)`,
		## and it PASSED when the blueprint's role was mutated to "decorative" —
		## a role no apron pad ever asks for. Of course it did: it was asking
		## whether the file resolves for whatever role the file claims, which is
		## true of any role at all. REALITY.md §8 — a mutation that passes is a
		## blind check, not a safe one.
		t.check(
			"%s is a pad role the port places on every harbour" % APRON_ROLE,
			PortApronPadCatalog.UNIVERSAL_V1.has(APRON_ROLE),
		)
		var pad_template := str(PortApronPadCatalog.role(APRON_ROLE).get("pad_template_id", ""))
		var for_pad := BuildingBlueprintCatalog.find_for_pad(APRON_ROLE, pad_template)
		t.check(
			"the apron pad path resolves that role to this blueprint: find_for_pad(%s, %s)"
			% [APRON_ROLE, pad_template],
			for_pad != null and for_pad.blueprint_id == warehouse.blueprint_id,
		)

	LandDecorCache.clear()
	var house_a := LandDecorCache.house_instance(3, 0.2, 0.5)
	var house_b := LandDecorCache.house_instance(3, 0.2, 0.5)
	t.check("land decor cache must stamp house meshes", house_a.get_child_count() > 0)
	t.equal(
		"same variant should match child count",
		house_b.get_child_count(),
		house_a.get_child_count(),
	)

	MeshBuilder.clear_material_cache()
	var mat_a := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	var mat_b := MeshBuilder.make_material(Color(0.2, 0.3, 0.4))
	t.check("MeshBuilder material cache should reuse materials", mat_a == mat_b)

	t.finish(get_tree())


## Every `MeshInstance3D` under a node, depth first — the drawn output of a bake,
## counted where it lands rather than where it was declared.
func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		out.append(node as MeshInstance3D)
	for child in node.get_children():
		out.append_array(_mesh_instances(child))
	return out
