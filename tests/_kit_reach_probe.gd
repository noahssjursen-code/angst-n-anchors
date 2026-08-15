extends SceneTree

## Scratch probe (leading underscore — NOT a gate unit). Lane A.
##
## Two questions the wheelhouse job turns on, answered by measurement:
##
##   1. CAN A BRICK-LAYOUT VESSEL CARRY PIECE-KIT STRUCTURE AT ALL?
##      Strip test, run backwards (REALITY §3d): take the shipped starter's
##      layout, ADD piece placements to it, and see whether anything downstream
##      changes. If the numbers are identical the pieces contributed nothing.
##
##   2. CAN A PLAYER AUTHOR THE BRICKS THIS WAVE USED?
##      §5. The shipyard brick editor's palette is whatever `BrickCatalog.ids()`
##      returns; a brick that is not in it can only be placed by a generator.
##
## Run:
##   xvfb-run -a --server-args="-screen 0 1280x720x24" godot \
##     --rendering-driver opengl3 --audio-driver Dummy --script res://tests/_kit_reach_probe.gd

const PRESET := "res://resources/data/vessels/prebuilt/sjark_15m.json"
const USED := [
	"block", "block_window", "block_windshield", "block_door",
	"roof_flat", "roof_slope", "roof_corner",
	"railing", "railing_mooring", "helm", "mast_base", "mast_pole", "trommel_small",
]
## Considered and not used, but they were candidates and a player would want them.
const CONSIDERED := ["block_45", "block_window_45", "block_window_corner", "ledge_45", "ledge_45_corner"]


func _initialize() -> void:
	_q1_can_pieces_reach_a_brick_vessel()
	_q2_can_a_player_place_these()
	quit(0)


func _q1_can_pieces_reach_a_brick_vessel() -> void:
	print("\n══ 1 · CAN PIECE-KIT STRUCTURE REACH A BRICK-LAYOUT VESSEL? ══")
	var f := FileAccess.open(PRESET, FileAccess.READ)
	var preset: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	var layout_dict: Dictionary = preset["brick_layout"]

	print("  the shipped record's top-level keys: %s" % str(preset.keys()))
	print("  StructurePlan.is_plan(record)        = %s" % str(StructurePlan.is_plan(preset)))
	print("  StructurePlan.is_plan(brick_layout)  = %s" % str(StructurePlan.is_plan(layout_dict)))
	print("  -> DeckFitout.apply_any routes on that ONE test, so a record is")
	print("     EITHER a plan OR a brick layout. There is no mixed path.")

	## Now the strip test, backwards: bolt piece placements onto the brick layout
	## and re-measure everything downstream.
	PieceKit.ensure_loaded()
	print("\n  PieceKit.ids() -> %s" % str(PieceKit.ids()))

	var plain := BrickLayout.from_dict(layout_dict)
	var doped_dict := layout_dict.duplicate(true)
	doped_dict["pieces"] = []
	for i in range(40):
		(doped_dict["pieces"] as Array).append({
			"id": 9000 + i,
			"piece": "wall_panel",
			"cell": [4, 0, 9 + i % 8],
			"level": 4,
			"facing": 0,
		})
	doped_dict["format"] = ""
	var doped := BrickLayout.from_dict(doped_dict)

	print("\n  %-42s %10s %10s" % ["", "as shipped", "+40 pieces"])
	print("  %-42s %10d %10d" % ["cells in the BrickLayout", plain.count(), doped.count()])
	print("  %-42s %10d %10d" % [
		"primary cells", plain.iter_primary_cells().size(), doped.iter_primary_cells().size(),
	])
	var rt_plain: Dictionary = plain.to_dict()
	var rt_doped: Dictionary = doped.to_dict()
	print("  %-42s %10s %10s" % [
		"round-trip keeps a `pieces` key",
		str(rt_plain.has("pieces")), str(rt_doped.has("pieces")),
	])
	var same := JSON.stringify(rt_plain, "", true) == JSON.stringify(rt_doped, "", true)
	print("  round-trips are byte-identical: %s" % str(same))
	print("\n  VERDICT: %s" % (
		"the 40 placements contributed NOTHING — `BrickLayout` has no `pieces` field, so a piece placement on a brick vessel is dropped at parse."
		if same else "the placements changed something — re-examine."
	))

	## And the other direction: could the sjark be re-authored AS a plan instead?
	print("\n  Could the vessel be re-authored as a structure_plan_v1 instead?")
	var rules := VesselRegistrationCatalog.get_registration("general_vessel")
	var brick_addressed := PackedStringArray()
	for raw in (rules.get("rules", []) as Array):
		var rule := raw as Dictionary
		if rule.has("brick_id"):
			brick_addressed.append("%s (%s -> %s)" % [
				str(rule.get("id", "")), str(rule.get("kind", "")), str(rule["brick_id"]),
			])
	print("    `general_vessel` rules that address a BRICK ID: %d" % brick_addressed.size())
	for r in brick_addressed:
		print("      " + str(r))
	print("    -> a plan carries no brick ids, so these rules cannot be satisfied by one.")


func _q2_can_a_player_place_these() -> void:
	print("\n══ 2 · CAN A PLAYER PLACE THESE BRICKS WITH A MOUSE? ══")
	var palette := BrickCatalog.ids()
	print("  shipyard brick editor palette = BrickCatalog.ids() -> %d entries" % palette.size())
	var missing := PackedStringArray()
	print("\n  %-24s %-9s %-6s %s" % ["brick used by the house", "in palette", "yaw", "footprint"])
	for id_variant in USED + CONSIDERED:
		var brick_id := str(id_variant)
		var present := palette.has(brick_id)
		if not present:
			missing.append(brick_id)
		var fp := BrickCatalog.footprint_of(brick_id)
		print("  %-24s %-9s %-6d %dx%dx%d" % [
			brick_id, "yes" if present else "NO", BrickCatalog.yaw_step_of(brick_id),
			fp.x, fp.y, fp.z,
		])
	print("\n  bricks used or considered that a player CANNOT reach: %d %s" % [
		missing.size(), str(missing),
	])
	## The control: a brick id that does not exist must come back absent, or the
	## check above is measuring "is this a string" (REALITY §4).
	print("  CONTROL — a brick id that does not exist is reported absent: %s" % str(
		not palette.has("block_definitely_not_a_brick")
	))
