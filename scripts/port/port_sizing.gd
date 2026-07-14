class_name PortSizing
extends RefCounted

## Shared physical contract for generated ports. Coast validation, terrain pads,
## dock construction, and settlement planning must all read dimensions here.

const MIN_SIZE := 0
const MAX_SIZE := 4

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

## Conservative site footprint used before a final port size is selected.
const SITE_FOOTPRINT_HALF_WIDTH_M := 46.0
const SITE_FOOTPRINT_SEAWARD_M := 18.0
const SITE_FOOTPRINT_INLAND_M := 76.0

const BERTH_COUNT_BY_SIZE := [1, 2, 3, 4, 5]
const SLOT_WIDTH_BY_SIZE := [40.0, 50.0, 62.0, 76.0, 92.0]
const QUAY_HALF_LENGTH_BY_SIZE := [20.0, 50.0, 93.0, 152.0, 230.0]
const ISLAND_WIDTH_BY_SIZE := [88.0, 120.0, 200.0, 320.0, 500.0]
const TERRAIN_PAD_WIDTH_BY_SIZE := [120.0, 152.0, 232.0, 352.0, 532.0]


static func normalized_size(size: int) -> int:
	return clampi(size, MIN_SIZE, MAX_SIZE)


static func berth_count(size: int) -> int:
	return int(BERTH_COUNT_BY_SIZE[normalized_size(size)])


static func slot_width_m(size: int) -> float:
	return float(SLOT_WIDTH_BY_SIZE[normalized_size(size)])


static func dock_length_m(size: int) -> float:
	return float(berth_count(size)) * slot_width_m(size)


static func quay_half_length_m(size: int) -> float:
	return float(QUAY_HALF_LENGTH_BY_SIZE[normalized_size(size)])


static func island_width_m(size: int) -> float:
	return float(ISLAND_WIDTH_BY_SIZE[normalized_size(size)])


static func terrain_pad_width_m(size: int) -> float:
	return float(TERRAIN_PAD_WIDTH_BY_SIZE[normalized_size(size)])


static func facilities_depth_m(dock_inland_depth_m: float) -> float:
	return maxf(PLOT_DEPTH_M - dock_inland_depth_m, 0.0)
