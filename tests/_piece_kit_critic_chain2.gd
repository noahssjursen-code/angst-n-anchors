extends SceneTree

## SCRATCH PROBE — leading underscore, never a gate unit.
##
## piece_kit_test._check_diagonal_run's OWN chain construction, re-run with a
## rake on it. The shipped check builds the three facets with
## `{"span": span, "height": 5}` — rake_a and rake_b default to 0 — and asserts
## the joints are BIT-IDENTICAL. Its mutation slides a facet one cell sideways.
## It never varies a rake, and a rake is what probe_piece_house's own diagonal
## run carries.

func _initialize() -> void:
	print("\n=== piece_kit_test's chain construction, at every rake ===")
	var span := 8
	for rake in [0, 1, 2, 4, 8, -1, -4]:
		var facets: Array = []
		for i in 3:
			facets.append({
				"id": "facet %d" % i, "piece": "corner_45",
				"cell": [24 - span * i, 0, span * i], "facing": 0,
				"params": {"span": span, "height": 5, "rake_a": rake, "rake_b": rake},
			})
		var open := 0
		var worst := 0.0
		for i in 2:
			var here := PieceKit.placed_corners(facets[i] as Dictionary)
			var next := PieceKit.placed_corners(facets[i + 1] as Dictionary)
			if here.size() != 4 or next.size() != 4:
				open += 1
				continue
			if here[1] != next[0] or here[2] != next[3]:
				open += 1
			worst = maxf(worst, maxf(here[1].distance_to(next[0]), here[2].distance_to(next[3])))
		print("  rake_a = rake_b = %+d : %d of 2 joints open, worst %.4f m  (0.125*sqrt(2)*|rake| = %.4f)"
			% [rake, open, worst, 0.125 * sqrt(2.0) * absf(float(rake))])
	print("\n  The shipped check runs this at rake 0 only, and its mutation is a POSITION")
	print("  shift, not a rake. probe_piece_house's own diagonal run is at rake -1.")
	quit(0)
