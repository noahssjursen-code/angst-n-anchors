extends Node

const Berths = preload("res://scripts/port/state/custom_port_berths.gd")
const CATALOG := {
	"quay": {"kind": "platform", "footprint_m": [4.0, 4.0]},
	"bollard": {"kind": "bollard"},
	"crane": {"kind": "crane", "reach_min_m": 2.0, "reach_max_m": 55.0},
}

var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_test_two_berths_and_vessel_fit()
	_test_exposed_edges_and_gaps()
	_test_water_coverage()
	_test_physical_obstructions()
	_test_crane_reach()
	_test_crane_handling_modes()
	_test_polygon_quays()
	_test_rotations_and_serialization()
	_test_invalid_geometry()
	if failures.is_empty(): print("CUSTOM PORT BERTHS PASS (%d checks)" % checks)
	else:
		for failure in failures: push_error(failure)
		print("CUSTOM PORT BERTHS FAILED (%d/%d)" % [failures.size(), checks])
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_two_berths_and_vessel_fit() -> void:
	var port := _port()
	var before := JSON.stringify(port)
	var berths := Berths.derive(port, CATALOG)
	_check(berths.size() == 2, "three bollards make two adjacent berths across the tiled quay")
	_check(JSON.stringify(port) == before, "derivation never mutates the saved port")
	if berths.size() != 2: return
	var first: Dictionary = berths[0]
	var second: Dictionary = berths[1]
	_check(is_equal_approx(first.max_length_m, 26.0), "30m bollard spacing leaves two 2m end clearances")
	_check(first.water_verified and first.depth_m == 8.0, "full approach survey establishes real 8m depth")
	_check(first.max_beam_m == 20.0, "20m configured maximum beam needs surveyed approach width")
	_check(Berths.fit(first, _ship()).ok, "24x8m ship with 4m draft fits")
	_check(_reason(first, {"length_m": 27.0}, "insufficient_length"), "ship longer than safe mooring space is rejected")
	_check(_reason(first, {"beam_m": 21.0}, "insufficient_beam"), "ship wider than clear water envelope is rejected")
	_check(_reason(first, {"draft_m": 7.6}, "insufficient_depth"), "under-keel safety margin is enforced")
	var occupancy := [{"berth_id": first.id, "vessel_id": "other-ship"}]
	_check(not Berths.fit(first, _ship(), occupancy).ok, "occupied berth cannot be claimed by another ship")
	_check(Berths.fit(second, _ship(), occupancy).ok, "neighboring berth remains usable at the same time")
	occupancy[0].vessel_id = "ship"
	_check(Berths.fit(first, _ship(), occupancy).ok, "own reservation is idempotent")
	for dimension in ["length_m", "beam_m", "draft_m"]:
		for invalid in [0.0, -1.0, INF, NAN, "8"]:
			_check(_reason(first, {dimension: invalid}, "invalid_vessel_dimensions"), "nonphysical %s %s is rejected" % [dimension, str(invalid)])


func _test_exposed_edges_and_gaps() -> void:
	var port := _port()
	port.placements.append(_placement("inner-a", "bollard", 10.0, 8.0))
	port.placements.append(_placement("inner-b", "bollard", 42.0, 8.0))
	_check(Berths.derive(port, CATALOG).size() == 2, "bollards on interior tile seams do not create phantom water berths")
	var disconnected := _port()
	disconnected.placements = []
	disconnected.placements.append(_placement("left", "quay", 6.0, 4.0, {"footprint_m": [12.0, 8.0]}))
	disconnected.placements.append(_placement("right", "quay", 26.0, 4.0, {"footprint_m": [12.0, 8.0]}))
	disconnected.placements.append(_placement("a", "bollard", 2.0, 0.5))
	disconnected.placements.append(_placement("b", "bollard", 30.0, 0.5))
	_check(Berths.derive(disconnected, CATALOG).is_empty(), "bollards cannot span an 8m hole between separate quays")
	var corner := _port()
	corner.placements = [_placement("deck", "quay", 16.0, 16.0, {"footprint_m": [32.0, 32.0]}), _placement("a", "bollard", 10.0, 0.5), _placement("b", "bollard", 0.5, 24.0)]
	_check(Berths.derive(corner, CATALOG).is_empty(), "bollards around a corner cannot make a diagonal berth")
	var overlap := _port()
	overlap.placements.append(_placement("duplicate-deck", "quay", 32.0, 8.0, {"footprint_m": [64.0, 16.0]}))
	_check(Berths.derive(overlap, CATALOG).size() == 2, "overlapping deck rectangles do not duplicate edge berths")


func _test_water_coverage() -> void:
	var port := _port()
	port.water_regions = []
	port.water_probes = [{"position_m": [16.0, 0.0, -10.0], "depth_m": 100.0}]
	var absent := Berths.derive(port, CATALOG)
	_check(absent.size() == 2 and not absent[0].water_verified, "isolated depth reading cannot certify an unsurveyed approach")
	_check(not Berths.fit(absent[0], _ship()).ok, "unsurveyed berth cannot accept a vessel")
	port = _port()
	port.water_regions.append({"rect_m": [10.0, -5.0, 0.02, 0.02], "depth_m": 2.0})
	var shoal := Berths.derive(port, CATALOG)
	_check(shoal[0].depth_m == 2.0 and not Berths.fit(shoal[0], _ship()).ok, "2cm shoal patch is caught without relying on coarse point sampling")
	port = _port()
	port.water_regions = [{"rect_m": [0.0, -80.0, 20.0, 80.0], "depth_m": 8.0}, {"rect_m": [20.02, -80.0, 44.0, 80.0], "depth_m": 8.0}]
	var gap := Berths.derive(port, CATALOG)
	_check(not gap[0].water_verified and gap[1].water_verified, "2cm missing survey strip invalidates only the affected berth")
	port = _port()
	port.water_regions = [{"rect_m": [0.0, -12.0, 64.0, 12.0], "depth_m": 8.0}]
	var narrow := Berths.derive(port, CATALOG)
	_check(narrow[0].water_verified and narrow[0].max_beam_m > 5.0 and narrow[0].max_beam_m < 5.2, "narrow surveyed basin yields a correspondingly narrow safe berth")
	_check(not Berths.fit(narrow[0], _ship()).ok, "8m vessel cannot claim shallow approach clearance by its hull center")
	port = _port()
	port.water_regions.append({"rect_m": [10.0, -5.0, 1.0, 1.0], "depth_m": 0.0})
	_check(not Berths.derive(port, CATALOG)[0].water_verified, "dry patch in an approach is not treated as deep surrounding water")


func _test_physical_obstructions() -> void:
	var port := _port()
	port.placements.append(_placement("opposite-finger", "quay", 16.0, -15.0, {"footprint_m": [28.0, 4.0]}))
	var berths := Berths.derive(port, CATALOG)
	_check(berths[0].max_beam_m < 6.0 and berths[1].max_beam_m == 20.0, "opposite pier narrows only the berth whose approach it obstructs")
	_check(not Berths.fit(berths[0], _ship()).ok, "declared deep water cannot override a physical pier in the approach")
	port.placements.back().position_m[2] = -3.0
	_check(not Berths.derive(port, CATALOG)[0].water_verified, "completely blocked entrance is unavailable")
	var inner := _port()
	inner.placements = [
		_placement("horizontal", "quay", 24.0, 2.0, {"footprint_m": [48.0, 4.0]}),
		_placement("vertical", "quay", 2.0, -20.0, {"footprint_m": [4.0, 40.0]}),
		_placement("h-a", "bollard", 6.0, 0.5), _placement("h-b", "bollard", 34.0, 0.5),
		_placement("v-a", "bollard", 3.5, -34.0), _placement("v-b", "bollard", 3.5, -6.0),
	]
	inner.water_regions = [{"rect_m": [0.0, -80.0, 80.0, 80.0], "depth_m": 8.0}]
	var conflict := Berths.derive(inner, CATALOG)
	_check(conflict.size() == 2, "inside corner exposes two legitimate mooring faces")
	if conflict.size() == 2:
		_check(conflict[0].conflicting_berth_ids.has(conflict[1].id), "intersecting hull envelopes are linked as reservation conflicts")
		_check(not Berths.fit(conflict[1], _ship(), [{"berth_id": conflict[0].id, "vessel_id": "other"}]).ok, "an occupied corner berth blocks overlapping second berth")


func _test_crane_reach() -> void:
	var port := _port()
	port.placements.append(_placement("crane-near", "crane", 16.0, 6.0, {"pad_size_m": [8.0, 8.0], "pad_offset_m": [0.0, 10.0], "store_ids": ["remote-yard"]}))
	port.placements.append(_placement("crane-far", "crane", 140.0, 6.0))
	port.placements.append(_placement("crane-short", "crane", 16.0, 6.0, {"reach_max_m": 12.0}))
	port.placements.append(_placement("crane-dead-zone", "crane", 16.0, 6.0, {"reach_min_m": 20.0}))
	port.placements.append(_placement("remote-pad", "yard", 200.0, 20.0, {"footprint_m": [8.0, 8.0]}))
	port.stores = [{"id": "cargo-yard", "placement_id": "crane-near"}, {"id": "far-yard", "placement_id": "crane-far"}, {"id": "remote-yard", "placement_id": "remote-pad"}]
	var first: Dictionary = Berths.derive(port, CATALOG)[0]
	_check(Berths.services_for_vessel(first, _ship()).crane_ids == ["crane-near"], "only a crane covering the actual moored vessel can serve it")
	_check(first.store_ids == ["cargo-yard"], "cargo routing exposes only a reachable crane's paired store")
	_check(not first.store_ids.has("remote-yard"), "declared store link cannot bypass physical reach to its cargo pad")
	port.placements.append(_placement("offset-crane", "crane", 140.0, 6.0, {"crane_offset_m": [-124.0, 0.0], "pad_size_m": [8.0, 8.0], "pad_offset_m": [-124.0, 10.0], "store_ids": ["offset-yard", "nonexistent-yard"]}))
	port.stores.append({"id": "offset-yard", "placement_id": "offset-crane"})
	first = Berths.derive(port, CATALOG)[0]
	_check(first.crane_ids.has("offset-crane") and first.store_ids.has("offset-yard"), "crane pivot offset, not an assembly's center, determines reach")
	_check(not first.store_ids.has("nonexistent-yard"), "listed but nonexistent storage cannot be served")
	var pose := Berths.docking_pose(first, _ship())
	_check(is_equal_approx(float(pose.center_m[2]), -4.75), "vessel center uses its own 8m beam instead of maximum berth beam")
	var little := _ship()
	little.length_m = 8.0
	little.beam_m = 2.0
	_check(Berths.services_for_vessel(first, little).crane_ids.has("crane-short"), "short crane serves a small hull even when it cannot cover maximum berth capacity")
	port.placements.back().yaw_degrees = 90.0
	_check(not Berths.derive(port, CATALOG)[0].crane_ids.has("offset-crane"), "rotating a bundled crane rotates its pivot offset")


func _test_crane_handling_modes() -> void:
	var port := _port()
	port.placements.append(_placement("shared-pad", "yard", 16.0, 16.0, {"footprint_m": [8.0, 8.0]}))
	port.placements.append(_placement("bulk-crane", "crane", 16.0, 6.0, {"cargo_types": ["bulk"], "store_ids": ["shared-yard"]}))
	port.placements.append(_placement("box-crane", "crane", 24.0, 6.0, {"cargo_types": ["container", "general"], "store_ids": ["shared-yard"]}))
	port.placements.append(_placement("untyped-crane", "crane", 8.0, 6.0, {"store_ids": ["shared-yard"]}))
	port.stores = [{"id": "shared-yard", "placement_id": "shared-pad"}]
	var berth: Dictionary = Berths.derive(port, CATALOG)[0]
	var inspected := Berths.services_for_vessel(berth, _ship())
	_check(inspected.crane_ids.size() == 3, "geometry inspection includes all reachable cranes")
	var boxes := Berths.services_for_vessel(berth, _ship(), "container")
	_check(boxes.crane_ids == ["box-crane"], "bulk and untyped cranes cannot handle containers")
	_check(boxes.store_ids == ["shared-yard"], "valid cross-linked storage remains reachable")
	_check(boxes.crane_services.size() == 1 and boxes.crane_services[0].crane_id == "box-crane" and boxes.crane_services[0].store_ids.has("shared-yard"), "authority receives the actual compatible crane and its linked stores")
	_check(boxes.crane_services[0].cargo_types == ["container", "general"], "service details preserve supported handling modes")
	_check(Berths.services_for_vessel(berth, _ship(), "bulk").crane_ids == ["bulk-crane"], "bulk handling chooses the grab crane")
	_check(Berths.services_for_vessel(berth, _ship(), "general").crane_ids == ["box-crane"], "declared general cargo mode is supported")
	_check(Berths.services_for_vessel(berth, _ship(), "liquid").store_ids.is_empty(), "unavailable handling type grants no cargo access")
	boxes.crane_services[0].store_ids.clear()
	_check(Berths.services_for_vessel(berth, _ship(), "container").store_ids == ["shared-yard"], "returned service details cannot mutate berth capabilities")
	port.placements.reverse()
	_check(Berths.services_for_vessel(Berths.derive(port, CATALOG)[0], _ship(), "container").crane_ids == ["box-crane"], "crane choice remains deterministic after placement order changes")


func _test_rotations_and_serialization() -> void:
	var original := _port()
	var expected := Berths.derive(original, CATALOG)
	for turns in range(4):
		var rotated := original.duplicate(true)
		for placement in rotated.placements:
			var p := Vector2(placement.position_m[0], placement.position_m[2]).rotated(-turns * PI * 0.5)
			placement.position_m = [snappedf(p.x, 0.001), 0.0, snappedf(p.y, 0.001)]
			placement.yaw_degrees = turns * 90.0
		var water_corners: Array[Vector2] = []
		for p in [Vector2(0.0, -80.0), Vector2(64.0, -80.0), Vector2(0.0, 0.0), Vector2(64.0, 0.0)]: water_corners.append(p.rotated(-turns * PI * 0.5))
		var bounds := Rect2(water_corners[0], Vector2.ZERO)
		for p in water_corners: bounds = bounds.expand(p)
		rotated.water_regions[0].rect_m = [snappedf(bounds.position.x, 0.001), snappedf(bounds.position.y, 0.001), snappedf(bounds.size.x, 0.001), snappedf(bounds.size.y, 0.001)]
		var result := Berths.derive(rotated, CATALOG)
		_check(result.size() == 2, "quay rotation %d preserves berth count" % (turns * 90))
		if result.size() == 2:
			_check(Berths.fit(result[0], _ship()).ok and Berths.fit(result[1], _ship()).ok, "quay rotation %d preserves vessel fit" % (turns * 90))
			_check(result[0].id == expected[0].id and result[1].id == expected[1].id, "quay rotation %d preserves berth identity" % (turns * 90))
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(original))
	_check(JSON.stringify(Berths.derive(decoded, CATALOG)) == JSON.stringify(expected), "JSON save/load reconstructs identical berth geometry")
	original.placements.reverse()
	original.origin_m = [900000.0, -1.5, -300000.0]
	_check(JSON.stringify(Berths.derive(original, CATALOG)) == JSON.stringify(expected), "placement order and world-origin translation do not change local berths")
	var embedded := original.duplicate(true)
	for placement in embedded.placements:
		var attributes: Dictionary = CATALOG[placement.asset_id].duplicate(true)
		attributes.merge(placement.get("attributes", {}), true)
		placement.attributes = attributes
	_check(JSON.stringify(Berths.derive(embedded)) == JSON.stringify(expected), "catalog metadata and resolved placement metadata agree")


func _test_polygon_quays() -> void:
	var port := _port()
	port.placements = []
	port.water_regions = [{"rect_m": [-100.0, -100.0, 200.0, 200.0], "depth_m": 8.0}]
	var triangle := {"footprint_m": [4.0, 4.0], "footprint_polygon_m": [[-2.0, -2.0], [2.0, 2.0], [-2.0, 2.0]]}
	for z in range(8):
		for x in range(z + 1):
			port.placements.append(_placement("tile-%d-%d" % [x,z], "quay", x*4.0, z*4.0, triangle if x == z else {}))
	port.placements.append(_placement("diagonal-a", "bollard", -0.5, 0.5))
	port.placements.append(_placement("diagonal-b", "bollard", 27.5, 28.5))
	port.placements.append(_placement("diagonal-crane", "crane", 10.0, 18.0, {"reach_max_m": 40.0, "pad_size_m": [4.0, 4.0], "pad_offset_m": [0.0, 6.0]}))
	port.stores = [{"id": "diagonal-yard", "placement_id": "diagonal-crane"}]
	var berth_ids: Array[String] = []
	for turn in range(4):
		var rotated := port.duplicate(true)
		for placement in rotated.placements:
			var point := Vector2(placement.position_m[0], placement.position_m[2]).rotated(-turn * PI * 0.5)
			placement.position_m = [snappedf(point.x, 0.001), 0.0, snappedf(point.y, 0.001)]
			placement.yaw_degrees = turn * 90.0
		var berths := Berths.derive(rotated, CATALOG)
		_check(berths.size() == 1, "triangle tiles merge into one exposed 45-degree mooring edge at rotation %d" % turn)
		if berths.size() != 1: continue
		var berth: Dictionary = berths[0]
		berth_ids.append(berth.id)
		_check(berth.water_verified and Berths.fit(berth, _ship()).ok, "angled hull and approach remain outside actual quay despite overlapping its bounding box")
		_check(is_equal_approx(float(berth.max_length_m), sqrt(28.0*28.0*2.0)-4.0), "diagonal berth length is measured along the edge in metres")
		_check(absf(float(berth.outward_normal[0])) > 0.7 and absf(float(berth.outward_normal[2])) > 0.7, "diagonal outward normal is preserved")
		_check(Berths.services_for_vessel(berth, _ship()).store_ids.has("diagonal-yard"), "crane reach follows the rotated hull and paired yard")
		var pose := Berths.docking_pose(berth, _ship())
		_check(absf(fposmod(float(pose.yaw_degrees), 90.0) - 45.0) < 0.01, "docked vessel aligns to the actual diagonal quay")
	_check(berth_ids.size() == 4 and berth_ids[0] == berth_ids[1] and berth_ids[0] == berth_ids[2] and berth_ids[0] == berth_ids[3], "diagonal berth identity survives rotation")
	var paired := port.duplicate(true)
	paired.placements = [
		_placement("lower-half", "quay", 0.0, 0.0, {"footprint_m": [40.0,40.0], "footprint_polygon_m": [[-20.0,-20.0],[20.0,20.0],[-20.0,20.0]]}),
		_placement("upper-half", "quay", 0.0, 0.0, {"footprint_m": [40.0,40.0], "footprint_polygon_m": [[-20.0,-20.0],[20.0,20.0],[-20.0,20.0]]}),
		_placement("inside-a", "bollard", -10.5, -9.5), _placement("inside-b", "bollard", 9.5, 10.5),
	]
	paired.placements[1].yaw_degrees = 180.0
	paired.stores = []
	_check(Berths.derive(paired, CATALOG).is_empty(), "complementary triangles cancel their internal diagonal seam")
	var chamfer := {"placements": [_placement("chamfer", "quay", 0.0, 0.0, {"footprint_polygon_m": [[-2.0,-2.0],[1.0,-2.0],[2.0,-1.0],[2.0,2.0],[-2.0,2.0]]})]}
	var edges := Berths._exposed_edges(Berths._platforms(chamfer, CATALOG))
	var diagonal_count := 0
	for edge in edges:
		if absf(edge.normal.x) > 0.5 and absf(edge.normal.y) > 0.5: diagonal_count += 1
	_check(edges.size() == 5 and diagonal_count == 1, "1m chamfer cut exposes five true edges, including its short diagonal")


func _test_invalid_geometry() -> void:
	var port := _port()
	for placement in port.placements:
		if placement.asset_id == "quay": placement.yaw_degrees = 45.0
	_check(Berths.derive(port, CATALOG).is_empty(), "unsupported diagonal decks do not create unsafe bounding-box berths")
	port = _port()
	for placement in port.placements:
		if placement.asset_id == "quay": placement.position_m[1] = 4.0
	_check(Berths.derive(port, CATALOG).is_empty(), "building upper floors do not create sea-level berths")
	port = _port()
	for placement in port.placements:
		if placement.asset_id == "quay": placement.attributes.footprint_polygon_m = [[0,0],[1,1]]
	_check(Berths.derive(port, CATALOG).is_empty(), "malformed authored polygon cannot silently become a rectangular quay")
	_check(Berths.derive({}).is_empty(), "empty record produces no invented berths")


func _port() -> Dictionary:
	var placements: Array = []
	for x in range(16):
		for z in range(4): placements.append(_placement("tile-%d-%d" % [x, z], "quay", x * 4.0 + 2.0, z * 4.0 + 2.0))
	placements.append(_placement("bollard-a", "bollard", 2.0, 0.5))
	placements.append(_placement("bollard-b", "bollard", 32.0, 0.5))
	placements.append(_placement("bollard-c", "bollard", 62.0, 0.5))
	return {"id": "test-port", "origin_m": [0.0, 0.0, 0.0], "placements": placements,
		"berth_rules": {"maximum_beam_m": 20.0}, "water_regions": [{"rect_m": [0.0, -80.0, 64.0, 80.0], "depth_m": 8.0}]}


func _placement(id: String, asset_id: String, x: float, z: float, attributes: Dictionary = {}) -> Dictionary:
	return {"id": id, "asset_id": asset_id, "position_m": [x, 0.0, z], "yaw_degrees": 0.0, "attributes": attributes}


func _ship() -> Dictionary:
	return {"id": "ship", "length_m": 24.0, "beam_m": 8.0, "draft_m": 4.0}


func _reason(berth: Dictionary, changes: Dictionary, reason: String) -> bool:
	var ship := _ship()
	ship.merge(changes, true)
	return Berths.fit(berth, ship).reasons.has(reason)


func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failures.append(message)
