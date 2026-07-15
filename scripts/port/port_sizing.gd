class_name PortSizing
extends RefCounted

## Shared physical contract for generated ports. Coast validation, terrain pads,
## dock construction, and settlement planning must all read dimensions here.
##
## Size class 0–8. Berth length / deck width / fairway are keyed to the design
## hull's catalog LOA×beam (already world metres) so a docked HullRegistry boat
## always fits its berth segment.
##
## Layout archetypes (morphology) define the SILHOUETTE — pier count, spacing,
## and length ratios. Trade families only decide quay/yard/gear colours.

const MIN_SIZE := 0
const MAX_SIZE := 8
const CATALOG_REFERENCE_SIZE := 2
## By this size every destiny import/export is unlocked. Larger sizes grow
## quay length / decks / fairway — not more commodities — and only if trade
## volume justifies a bigger harbour (see max_size_for_trade_products).
const TRADE_COMPLETE_SIZE := 5


## Largest harbour size a destiny with `product_count` unique commodities may reach.
## Sparse economies stop early; rich hubs can still grow past trade-complete.
static func max_size_for_trade_products(product_count: int) -> int:
	match clampi(product_count, 0, 99):
		0, 1:
			return 2
		2:
			return 3
		3:
			return 4
		4:
			return TRADE_COMPLETE_SIZE
		5:
			return 6
		6:
			return 7
		_:
			return MAX_SIZE

const PLOT_DEPTH_M := 140.0
const QUAY_DEPTH_M := 8.0
const CRANE_QUAY_GAP_M := 3.0
const CRANE_DEPTH_M := 6.0
const APRON_GAP_M := 2.0
const APRON_DEPTH_M := 14.0
const DOCK_REAR_BUFFER_M := 3.0
const DOCK_INLAND_DEPTH_M := QUAY_DEPTH_M + CRANE_QUAY_GAP_M + CRANE_DEPTH_M \
		+ APRON_GAP_M + APRON_DEPTH_M + DOCK_REAR_BUFFER_M
const PAD_SAFE_MARGIN_M := 8.0
const PAD_DEPTH_M := PLOT_DEPTH_M + PAD_SAFE_MARGIN_M * 4.0
const DOCK_OVERHANG_M := 14.0
const PAD_SEAWARD_SHIFT_M := DOCK_OVERHANG_M
const COASTAL_GRAPH_ROOT_Z_M := -(PLOT_DEPTH_M * 0.5 - DOCK_OVERHANG_M)

const SITE_FOOTPRINT_HALF_WIDTH_M := 46.0
const SITE_FOOTPRINT_SEAWARD_M := 18.0
const SITE_FOOTPRINT_INLAND_M := 76.0

const DESIGN_HULL_ID_BY_SIZE := [
	"hull_28x10", "hull_45x16_cat", "hull_70x18", "hull_90x24", "hull_100x24",
	"hull_120x28", "hull_130x28", "hull_150x32", "hull_150x32",
]
const DESIGN_HULL_LOA_BY_SIZE := [
	28.0, 45.0, 70.0, 90.0, 100.0, 120.0, 130.0, 150.0, 150.0,
]
const DESIGN_HULL_BEAM_BY_SIZE := [
	10.0, 16.0, 18.0, 24.0, 24.0, 28.0, 28.0, 32.0, 32.0,
]
const BERTH_COUNT_BY_SIZE := [1, 2, 2, 3, 4, 5, 6, 7, 8]
## Strictly increasing tier ladder. quay_half drives alongshore length; pad ≈ 5× quay_half.
const QUAY_HALF_LENGTH_BY_SIZE := [
	80.0, 110.0, 150.0, 200.0, 260.0, 330.0, 410.0, 500.0, 600.0,
]
const SLOT_WIDTH_BY_SIZE := [
	44.0, 58.0, 80.0, 100.0, 112.0, 132.0, 144.0, 166.0, 178.0,
]
const ISLAND_WIDTH_BY_SIZE := [
	280.0, 385.0, 525.0, 700.0, 910.0, 1155.0, 1435.0, 1750.0, 2100.0,
]
const TERRAIN_PAD_WIDTH_BY_SIZE := [
	400.0, 550.0, 750.0, 1000.0, 1300.0, 1650.0, 2050.0, 2500.0, 3000.0,
]
const TERRAIN_PAD_DEPTH_BY_SIZE := [
	360.0, 420.0, 480.0, 540.0, 620.0, 700.0, 800.0, 920.0, 1060.0,
]
## Wide enough for crane rail + roadway + on-deck storage.
## Grows slowly — pier *length* is the main size signal, not deck width.
const QUAY_DECK_WIDTH_BY_SIZE := [
	36.0, 40.0, 44.0, 48.0, 52.0, 56.0, 60.0, 64.0, 68.0,
]
const APRON_WIDTH_BY_SIZE := [
	56.0, 80.0, 120.0, 180.0, 260.0, 360.0, 480.0, 620.0, 780.0,
]
const APRON_DEPTH_BY_SIZE := [
	32.0, 48.0, 64.0, 80.0, 100.0, 120.0, 140.0, 160.0, 180.0,
]
const CARGO_YARD_WIDTH_BY_SIZE := [
	22.0, 26.0, 32.0, 40.0, 48.0, 56.0, 64.0, 72.0, 80.0,
]
const CARGO_YARD_DEPTH_BY_SIZE := [
	16.0, 18.0, 22.0, 26.0, 32.0, 38.0, 44.0, 50.0, 56.0,
]


static func normalized_size(size: int) -> int:
	return clampi(size, MIN_SIZE, MAX_SIZE)


static func design_hull_id(size: int) -> String:
	return str(DESIGN_HULL_ID_BY_SIZE[normalized_size(size)])


static func design_hull_loa_m(size: int) -> float:
	return float(DESIGN_HULL_LOA_BY_SIZE[normalized_size(size)])


static func design_hull_beam_m(size: int) -> float:
	return float(DESIGN_HULL_BEAM_BY_SIZE[normalized_size(size)])


static func berth_count(size: int) -> int:
	return int(BERTH_COUNT_BY_SIZE[normalized_size(size)])


static func slot_width_m(size: int) -> float:
	return float(SLOT_WIDTH_BY_SIZE[normalized_size(size)])


static func dock_length_m(size: int) -> float:
	return float(berth_count(size)) * slot_width_m(size)


static func quay_half_length_m(size: int) -> float:
	return float(QUAY_HALF_LENGTH_BY_SIZE[normalized_size(size)])


## Spine link count tracks quay length so landing tiers are not a 3-quad sliver.
static func foundation_min_spine_links(size: int) -> int:
	var spacing := foundation_spine_spacing_m(size)
	var quay_m := quay_half_length_m(size) * 2.0
	return maxi(12, int(ceil(quay_m / spacing)) + 2)


static func foundation_spine_spacing_m(size: int) -> float:
	var n := normalized_size(size)
	if n == 0:
		return 8.0
	return lerpf(10.0, 20.0, float(n) / float(MAX_SIZE))


static func island_width_m(size: int) -> float:
	return float(ISLAND_WIDTH_BY_SIZE[normalized_size(size)])


static func terrain_pad_width_m(size: int) -> float:
	return float(TERRAIN_PAD_WIDTH_BY_SIZE[normalized_size(size)])


static func terrain_pad_depth_m(size: int) -> float:
	return float(TERRAIN_PAD_DEPTH_BY_SIZE[normalized_size(size)])


static func quay_deck_width_m(size: int) -> float:
	return float(QUAY_DECK_WIDTH_BY_SIZE[normalized_size(size)])


## One working berth: design ship LOA + fender/approach margin.
static func min_ship_berth_m(size: int) -> float:
	return design_hull_loa_m(size) * 1.15 + 12.0


## Quay must fit one design ship per commodity zone sharing the pier.
static func min_quay_length_m(size: int, zone_count: int = 1) -> float:
	return min_ship_berth_m(size) * float(maxi(zone_count, 1))


## Hard cap on dedicated quay arms — by size 3 the harbour can host a full
## destiny (≤3 pads). Later sizes lengthen piers; they do not add pad types.
static func max_dedicated_quays(size: int) -> int:
	match normalized_size(size):
		0, 1:
			return 1
		2:
			return 2
		_:
			return 3


## Deck width keyed to how long a pier can actually run (basin / water), so
## size-up never fattens a finger that was soft-capped short.
static func quay_deck_width_for_arm_m(arm_length_m: float, size: int) -> float:
	var from_arm := max_size_for_arm_budget_m(arm_length_m)
	return quay_deck_width_m(mini(normalized_size(size), from_arm))


## Largest size whose minimum single-zone pier still fits `arm_budget_m`.
static func max_size_for_arm_budget_m(arm_budget_m: float) -> int:
	if arm_budget_m < 24.0:
		return MIN_SIZE
	for size in range(MAX_SIZE, MIN_SIZE - 1, -1):
		if min_quay_length_m(size, 1) <= arm_budget_m + 0.01:
			return size
	return MIN_SIZE


static func cargo_yard_size_m(size: int) -> Vector2:
	var n := normalized_size(size)
	return Vector2(CARGO_YARD_WIDTH_BY_SIZE[n], CARGO_YARD_DEPTH_BY_SIZE[n])


static func facilities_depth_m(dock_inland_depth_m: float) -> float:
	return maxf(PLOT_DEPTH_M - dock_inland_depth_m, 0.0)


static func design_ship_class(size: int) -> ShipClass.Type:
	match normalized_size(size):
		0:
			return ShipClass.Type.LAUNCH
		1:
			return ShipClass.Type.COASTAL_TRADER
		2, 3:
			return ShipClass.Type.SHORT_SEA_COASTER
		4, 5:
			return ShipClass.Type.HANDYSIZE_FEEDER
		_:
			return ShipClass.Type.DEEP_SEA_FREIGHTER


static func pier_fairway_m(size: int) -> float:
	var beam := design_hull_beam_m(size)
	return 2.0 * beam + maxf(beam * 1.35, 36.0)


static func parallel_pier_center_spacing_m(size: int) -> float:
	return quay_deck_width_m(size) + pier_fairway_m(size)


static func apron_width_m(size: int) -> float:
	var n := normalized_size(size)
	var base := float(APRON_WIDTH_BY_SIZE[n])
	var spacing := parallel_pier_center_spacing_m(n)
	var seaward_count := 2
	if n >= 7:
		seaward_count = 4
	elif n >= 4:
		seaward_count = 3
	elif n >= 2:
		seaward_count = 2
	else:
		seaward_count = 1
	var for_fingers := spacing * float(maxi(seaward_count - 1, 0)) + quay_deck_width_m(n) + 40.0
	return maxf(base, for_fingers)


static func apron_depth_m(size: int) -> float:
	return float(APRON_DEPTH_BY_SIZE[normalized_size(size)])


static func basin_width_m(size: int) -> float:
	return apron_width_m(size)


static func basin_depth_m(size: int) -> float:
	return apron_depth_m(size)


static func is_inland_side_slot(slot_id: String) -> bool:
	return slot_id == "arm_port" or slot_id == "arm_starboard"


static func is_seaward_harbour_slot(slot_id: String) -> bool:
	match slot_id:
		"arm_front", "finger_port", "finger_starboard", \
		"finger_outer_port", "finger_outer_starboard":
			return true
		_:
			return false


static func layout_arm_count_range(size: int) -> Vector2i:
	match normalized_size(size):
		0, 1:
			return Vector2i(1, 1)
		2, 3:
			return Vector2i(2, 2)
		4, 5:
			return Vector2i(3, 3)
		6, 7:
			return Vector2i(3, 4)
		_:
			return Vector2i(4, 4)


## Hard cap — piers longer than this read as absurd in the showcase.
static func max_quay_segments_per_arm(size: int) -> int:
	return clampi(2 + normalized_size(size) / 3, 2, 4)


## Per-pier berth multiplier baked into each archetype silhouette.
static func morphology_length_ratios(morphology: String) -> Array[float]:
	match morphology:
		"solo_jetty", "liquid_jetty":
			return [1.35]
		"solo_offset_port", "solo_offset_starboard":
			return [1.05]
		"twin_equal", "offset_pair":
			return [1.0, 1.0]
		"twin_stagger":
			return [1.4, 0.72]
		"main_and_spur":
			return [1.3, 0.58]
		"main_and_stub":
			return [1.45, 0.42]
		"comb_stagger":
			return [0.72, 1.38, 0.78]
		"comb_wide":
			return [0.88, 1.22, 0.88]
		"offset_liquid":
			return [1.42, 0.82]
		"quad_comb":
			return [0.62, 1.05, 1.05, 0.62]
		_:
			return [1.0]


static func morphology_display_name(morphology: String) -> String:
	match morphology:
		"solo_jetty":
			return "Solo jetty"
		"solo_offset_port":
			return "Offset pier (port)"
		"solo_offset_starboard":
			return "Offset pier (starboard)"
		"liquid_jetty":
			return "Liquid jetty"
		"offset_liquid":
			return "Liquid offset + dry pier"
		"twin_equal":
			return "Twin piers"
		"twin_stagger":
			return "Twin staggered"
		"offset_pair":
			return "Offset pair (no centre)"
		"main_and_spur":
			return "Main + spur"
		"main_and_stub":
			return "Main + stub"
		"comb_stagger":
			return "Comb staggered"
		"comb_wide":
			return "Comb wide"
		"quad_comb":
			return "Quad comb"
		_:
			return morphology.replace("_", " ").capitalize()


static func pick_layout_plan(
		size: int,
		trade_family_count: int,
		site_seed: int,
		has_liquid: bool = false,
) -> Dictionary:
	var n := normalized_size(size)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x4D4F5250 ^ (n * 7919) ^ (trade_family_count * 104729)

	var min_arms := layout_arm_count_range(n).x
	var pool := morphology_pool_for_arms(n, min_arms, has_liquid)
	var morphology := str(pool[rng.randi_range(0, pool.size() - 1)])

	var slots := Array(morphology_arm_slots(morphology))
	## Keep socket order — silhouette position is part of the archetype.
	var arm_slots: PackedStringArray = PackedStringArray()
	for slot_id in slots:
		var id := str(slot_id)
		if is_inland_side_slot(id) or not is_seaward_harbour_slot(id):
			continue
		arm_slots.append(id)

	if arm_slots.is_empty():
		arm_slots = PackedStringArray(["arm_front"])

	var length_scales: Array[float] = []
	for i in range(arm_slots.size()):
		length_scales.append(clampf(rng.randf_range(0.97, 1.03), 0.95, 1.05))

	return {
		"morphology": morphology,
		"morphology_display": morphology_display_name(morphology),
		"arm_slots": arm_slots,
		"length_scales": length_scales,
	}


static func morphology_pool(size: int) -> PackedStringArray:
	return morphology_pool_for_arms(size, 1, false)


static func morphology_pool_for_arms(
		size: int,
		min_arms: int,
		has_liquid: bool,
) -> PackedStringArray:
	var pool: PackedStringArray
	match normalized_size(size):
		0:
			pool = PackedStringArray([
				"solo_jetty", "solo_offset_port", "solo_offset_starboard",
			])
		1:
			pool = PackedStringArray([
				"solo_jetty", "solo_offset_port", "solo_offset_starboard", "twin_equal",
			])
		2, 3:
			pool = PackedStringArray([
				"twin_equal", "twin_stagger", "main_and_spur", "offset_pair",
			])
		4, 5:
			pool = PackedStringArray([
				"comb_stagger", "offset_pair", "main_and_stub", "twin_stagger",
			])
		6, 7:
			pool = PackedStringArray([
				"comb_stagger", "comb_wide", "quad_comb", "twin_stagger",
			])
		_:
			pool = PackedStringArray([
				"quad_comb", "comb_wide", "comb_stagger",
			])
	if has_liquid:
		if normalized_size(size) <= 2:
			pool.append("liquid_jetty")
		else:
			pool.append("offset_liquid")
	var filtered := PackedStringArray()
	for morph in pool:
		if morphology_arm_slots(morph).size() >= min_arms or morph in [
			"solo_jetty", "solo_offset_port", "solo_offset_starboard", "liquid_jetty",
		]:
			filtered.append(morph)
	return filtered if not filtered.is_empty() else pool


static func morphology_arm_slots(morphology: String) -> PackedStringArray:
	match morphology:
		"solo_jetty", "liquid_jetty":
			return PackedStringArray(["arm_front"])
		"solo_offset_port":
			return PackedStringArray(["finger_port"])
		"solo_offset_starboard":
			return PackedStringArray(["finger_starboard"])
		"twin_equal", "offset_pair", "twin_stagger":
			return PackedStringArray(["finger_port", "finger_starboard"])
		"main_and_spur":
			return PackedStringArray(["arm_front", "finger_port"])
		"main_and_stub":
			return PackedStringArray(["arm_front", "finger_starboard"])
		"comb_stagger", "comb_wide":
			return PackedStringArray(["finger_port", "arm_front", "finger_starboard"])
		"offset_liquid":
			return PackedStringArray(["finger_port", "finger_starboard"])
		"quad_comb":
			return PackedStringArray([
				"finger_outer_port", "finger_port", "finger_starboard", "finger_outer_starboard",
			])
		## Legacy aliases (old saves / tests).
		"jetty", "jetty_long", "single_mole":
			return PackedStringArray(["arm_front"])
		"offset_port":
			return PackedStringArray(["finger_port"])
		"offset_starboard":
			return PackedStringArray(["finger_starboard"])
		"twin_pier", "fingers_2", "staggered_twin":
			return PackedStringArray(["finger_port", "finger_starboard"])
		"fingers_3", "fingers_3_wide", "staggered_triple":
			return PackedStringArray(["finger_port", "arm_front", "finger_starboard"])
		"fingers_4", "mega_fingers":
			return PackedStringArray([
				"finger_outer_port", "finger_port", "finger_starboard", "finger_outer_starboard",
			])
		_:
			return PackedStringArray(["arm_front"])


static func harbour_root_module_id(size: int, morphology: String = "") -> String:
	var n := normalized_size(size)
	if morphology == "quad_comb" or n >= 7:
		return "harbour_root_mega"
	if morphology in ["solo_jetty", "solo_offset_port", "solo_offset_starboard"] and n <= 1:
		return "harbour_root_small"
	if n <= 1 and morphology in ["twin_equal", "main_and_spur", "offset_pair"]:
		return "harbour_root_large"
	if n <= 5:
		return "harbour_root_large"
	return "harbour_root_mega"


static func inland_road_segments(size: int) -> int:
	return clampi(2 + normalized_size(size) / 2, 2, 5)


## Pier lengths keyed to design hull LOA — not abstract dock_length fractions.
static func arm_target_lengths_m(
		size: int,
		morphology: String,
		arm_count: int,
		length_scales: Array = [],
) -> Array[float]:
	var loa := design_hull_loa_m(size)
	var berth := slot_width_m(size)
	var max_seg := float(max_quay_segments_per_arm(size))
	var ratios := morphology_length_ratios(morphology)
	var lengths: Array[float] = []

	for arm_index in range(maxi(arm_count, 1)):
		var ratio := ratios[arm_index] if arm_index < ratios.size() else 1.0
		if arm_index < length_scales.size():
			ratio *= float(length_scales[arm_index])
		var target_berths := clampf(1.0 + ratio * 1.15, 1.0, max_seg)
		var target := target_berths * berth
		target = clampf(target, loa * 1.08, loa * 2.35)
		lengths.append(target)
	return lengths


## One distinct trade family per pier where possible.
static func assign_families_to_arms(
		families: Array[String],
		arm_count: int,
		morphology: String,
		site_seed: int,
) -> Array[String]:
	var out: Array[String] = []
	if families.is_empty():
		for i in range(arm_count):
			out.append("general")
		return out

	var ordered: Array[String] = families.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = int(site_seed) ^ 0x46414D49 ^ arm_count

	if morphology == "liquid_jetty":
		for i in range(arm_count):
			out.append("liquid" if ordered.has("liquid") else ordered[0])
		return out

	if morphology == "offset_liquid":
		out.append("liquid" if ordered.has("liquid") else ordered[0])
		var dry_family := "general"
		for f in ordered:
			if f != "liquid":
				dry_family = f
				break
		for i in range(1, arm_count):
			out.append(dry_family)
		return out

	## Put liquid on its own offset pier when present — not shared with bulk ladder.
	if ordered.has("liquid") and arm_count >= 2:
		var liquid_first: Array[String] = ["liquid"]
		for f in ordered:
			if f != "liquid":
				liquid_first.append(f)
		ordered = liquid_first

	for i in range(ordered.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: String = ordered[i]
		ordered[i] = ordered[j]
		ordered[j] = tmp

	for arm_index in range(arm_count):
		out.append(ordered[arm_index % ordered.size()])
	return out
