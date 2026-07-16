class_name BulkCargoRules
extends RefCounted

## Shared bulk-mass rules for grabs, stockpiles, and ship holds.

const BASE_BUCKET_CAPACITY_T := 14.0
const PICKUP_TONNES_PER_S := 3.5

const BULK_DENSITY_T_M3 := {
	"iron_ore": 2.0,
	"coal": 0.9,
	"grain": 0.75,
}


static func bulk_density_t_m3(commodity_id: String) -> float:
	var cid := commodity_id.strip_edges()
	if BULK_DENSITY_T_M3.has(cid):
		return float(BULK_DENSITY_T_M3[cid])
	return 1.5


static func bucket_capacity_tonnes(bucket_scale: float = 1.0) -> float:
	return BASE_BUCKET_CAPACITY_T * maxf(bucket_scale, 0.01)


static func hold_capacity_tonnes(
		width_m: float,
		length_m: float,
		depth_m: float,
		commodity_id: String = "iron_ore",
) -> float:
	var volume_m3 := maxf(width_m, 0.1) * maxf(length_m, 0.1) * maxf(depth_m, 0.1)
	return volume_m3 * bulk_density_t_m3(commodity_id)


static func pickup_rate_tonnes_per_s(bucket_scale: float = 1.0) -> float:
	return PICKUP_TONNES_PER_S * maxf(bucket_scale, 0.01)


static func visual_scale_for_lot(lot: BulkCargoLot, reference_capacity_t: float) -> float:
	if lot == null or lot.is_empty() or reference_capacity_t <= BulkCargoLot.TONNES_EPS:
		return 0.35
	var ratio := clampf(lot.tonnes_t / reference_capacity_t, 0.15, 1.0)
	return lerpf(0.45, 1.0, ratio)
