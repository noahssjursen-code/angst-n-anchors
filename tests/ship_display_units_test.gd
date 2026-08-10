extends Node

## The in-world / display split: 1 world unit is 1 metre, and a vessel's DISPLAY
## dimensions are half its world ones, because a hull is built on 0.5 m deck
## cells and `hull_28x10` is 28 x 10 CELLS — a 14.0 x 5.0 m boat.
##
## ── Why this is a lane-B scene test and not a `--script` one ────────────────
## It was lane A, and it did not fail an assertion: it failed to COMPILE, on
## every gate run, reporting `Identifier not found: WorldGateway`. That is not a
## defect in this file or in what it measures. `HarbourDeploy` pulls in the
## networking chain and `--script` REGISTERS NO AUTOLOADS (CONVENTIONS §2), so a
## lane-A test can never reach `WorldGateway`, `HullRegistry`, `ShipClass` or
## `VesselSpawn`. The test was in the wrong lane from the day it was written and
## the compile error was the gate telling us so.
##
## A compile failure is worse than a failing assertion and reads the same in a
## results table — "FAIL(1)" — which is how it sat in the known-red list next to
## nine genuine failures. Booting a `.tscn` registers the autoloads; that is the
## whole of the fix, and the assertions are unchanged from the lane-A version.

const TestReport := preload("res://tests/support/test_report.gd")


func _ready() -> void:
	var t := TestReport.new("ship_display_units_test")
	var hull := HullRegistry.get_by_id("hull_28x10")
	t.check("hull loa_m is 28", is_equal_approx(float(hull.get("loa_m", 0.0)), 28.0))
	t.check("hull beam_m is 10", is_equal_approx(float(hull.get("beam_m", 0.0)), 10.0))
	t.check(
		"28x10 formats as display dimensions",
		ShipClass.format_display_dimensions(28.0, 10.0) == "14.0 × 5.0 m",
	)
	## ── The deck grid is counted in CELLS, and this used to assert metres ────
	## It read `grid.length == 28` and `grid.width == 10` under the label
	## "display conversion must not shrink deck length". Measured, on every hull
	## in the fleet, the grid is exactly twice the declared metres because a deck
	## cell is 0.5 m:
	##
	##     hull_28x10   loa 28 m  beam 10 m  ->  grid 56 x 20 cells
	##     hull_70x18   loa 70 m  beam 18 m  ->  grid 140 x 36
	##     hull_120x28  loa 120 m beam 28 m  ->  grid 240 x 56
	##     hull_150x32  loa 150 m beam 32 m  ->  grid 300 x 64
	##
	## So `grid.length == 28` on a 28 m hull is the HALVED value — the assertion
	## demanded exactly the shrinkage its own label forbids. Had the display
	## conversion ever leaked into the deck grid, this test would have gone green
	## on the bug.
	##
	## It never fired either way, because the file was in lane A and did not
	## compile. Two defects hiding each other: a test that could not run, and an
	## assertion that would have passed the thing it was written to catch.
	##
	## Restated as the PROPERTY (REALITY.md §3a), which needs no number of its
	## own and survives a change to the cell size: the grid must cover the hull's
	## declared length and beam at the deck cell size, whatever that size is.
	var grid := HullRegistry.make_grid("hull_28x10")
	var cell := float(WorldUnits.DECK_CELL_M)
	t.near(
		"the deck grid spans the hull's declared length (%d cells x %.2f m)"
		% [grid.length, cell],
		float(grid.length) * cell,
		float(hull.get("loa_m", 0.0)),
		1e-6,
	)
	t.near(
		"the deck grid spans the hull's declared beam (%d cells x %.2f m)"
		% [grid.width, cell],
		float(grid.width) * cell,
		float(hull.get("beam_m", 0.0)),
		1e-6,
	)
	## And the thing the old label was reaching for, stated so it can fail: the
	## grid is WORLD-sized, not display-sized. A display-converted grid would be
	## half this, and half is what the old assertion asked for.
	t.check(
		"display conversion has not leaked into the deck grid (%d cells, not %d)"
		% [grid.length, grid.length / 2],
		float(grid.length) * cell > float(hull.get("loa_m", 0.0)) * 0.75,
	)
	var req := HarbourDeploy.ship_requirements({"hull_id": "hull_28x10"})
	t.check("loa_world_m is 28", is_equal_approx(float(req.get("loa_world_m", 0.0)), 28.0))
	t.check("loa_display_m is 14", is_equal_approx(float(req.get("loa_display_m", 0.0)), 14.0))
	t.check(
		"vessel name is converted to display units",
		VesselSpawn.vessel_name_of({"name": "28x10 Cargo"}) == "14x5 Cargo",
	)
	t.finish(get_tree())
