extends SceneTree

## SCRATCH PROBE — leading underscore, never a gate unit.
##
## The shipped fixture's own diagonal wall run, measured. probe_piece_house.json
## carries three chained corner_45 facets and its _note calls them "the piece
## doing the job version 1 said the kit had no piece for". structure_pieces.json
## claims "facets CHAIN into a diagonal wall run of any length".
##
## Measured through PieceKit.resolve_placement + PieceKit.placed_corners, the
## same pair tests/piece_kit_test.gd's seam report uses.

const HOUSE := "res://resources/data/structures/probe_piece_house.json"


func _initialize() -> void:
	var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(HOUSE))
	var chain: Array = []
	for p_variant in (doc as Dictionary).get("pieces", []) as Array:
		var p := p_variant as Dictionary
		if str(p.get("_is", "")).begins_with("diagonal wall run"):
			chain.append(p)
	print("\n=== THE SHIPPED FIXTURE'S OWN DIAGONAL WALL RUN ===")
	print("  %d chained corner_45 in probe_piece_house.json" % chain.size())
	for i in chain.size() - 1:
		var a := chain[i] as Dictionary
		var b := chain[i + 1] as Dictionary
		var ca := PieceKit.placed_corners(a)
		var cb := PieceKit.placed_corners(b)
		## OUT edge is local corners 0 (foot) and 3 (head); IN is 1 and 2.
		## The chain may run either way round the cycle; take the pairing that
		## actually butts (foot distance 0) rather than assuming a direction.
		var foot := ca[0].distance_to(cb[1])
		var head := ca[3].distance_to(cb[2])
		if cb[0].distance_to(ca[1]) < foot:
			foot = cb[0].distance_to(ca[1])
			head = cb[3].distance_to(ca[2])
		var ra := int((a["params"] as Dictionary).get("rake_a", 0))
		var rb := int((b["params"] as Dictionary).get("rake_b", 0))
		print("  joint %d->%d  rake_a %+d meets rake_b %+d:  FOOT %.4f m   HEAD %.4f m   (0.125*sqrt(ra^2+rb^2) = %.4f)"
			% [i + 1, i + 2, ra, rb, foot, head, 0.125 * sqrt(float(ra * ra + rb * rb))])
		print("     A OUT head %s" % str(ca[3]))
		print("     B IN  head %s" % str(cb[2]))
	print("\n  The same chain at every rake, span 4, height 3:")
	for rake in [-8, -4, -2, -1, 0, 1, 2, 4, 8]:
		var a := {"id": "a", "piece": "corner_45", "cell": [12, 0, 24], "facing": 0,
			"params": {"span": 4, "height": 3, "rake_a": rake, "rake_b": rake}}
		var b := {"id": "b", "piece": "corner_45", "cell": [8, 0, 28], "facing": 0,
			"params": {"span": 4, "height": 3, "rake_a": rake, "rake_b": rake}}
		var ca := PieceKit.placed_corners(a)
		var cb := PieceKit.placed_corners(b)
		print("    rake %+d: foot %.4f m, head %.4f m" % [rake, ca[0].distance_to(cb[1]), ca[3].distance_to(cb[2])])
	print("\n  And with the interior joint forced plumb (rake_a=0 on A, rake_b=0 on B),")
	print("  which is the only setting that closes — the facet is then vertical in the middle:")
	var a2 := {"id": "a", "piece": "corner_45", "cell": [12, 0, 24], "facing": 0,
		"params": {"span": 4, "height": 3, "rake_a": 0, "rake_b": -1}}
	var b2 := {"id": "b", "piece": "corner_45", "cell": [8, 0, 28], "facing": 0,
		"params": {"span": 4, "height": 3, "rake_a": -1, "rake_b": 0}}
	var ca2 := PieceKit.placed_corners(a2)
	var cb2 := PieceKit.placed_corners(b2)
	print("    foot %.4f m, head %.4f m" % [ca2[0].distance_to(cb2[1]), ca2[3].distance_to(cb2[2])])

	## And the same question for the OTHER new parameters: does `fall` chain?
	print("\n=== DOES `fall` CHAIN ACROSS TWO WALL PANELS? ===")
	for fall in [0, 1, 2, 4]:
		var w1 := {"id": "1", "piece": "wall_panel", "cell": [0, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5, "fall": fall}}
		var w2 := {"id": "2", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5, "fall": fall}}
		var c1 := PieceKit.placed_corners(w1)
		var c2 := PieceKit.placed_corners(w2)
		print("  fall %d, second panel at the same lift: head gap %.4f m (the drop is %.3f m)"
			% [fall, c1[3].distance_to(c2[2]), float(fall) * 0.125])
		var w3 := {"id": "3", "piece": "wall_panel", "cell": [4, 0, 0], "facing": 0,
			"params": {"span": 4, "height": 5, "fall": fall, "lift": -fall}}
		var c3 := PieceKit.placed_corners(w3)
		print("     with lift = -fall on the second panel: head gap %.4f m, FOOT gap %.4f m"
			% [c1[3].distance_to(c3[2]), c1[0].distance_to(c3[1])])
	quit(0)
