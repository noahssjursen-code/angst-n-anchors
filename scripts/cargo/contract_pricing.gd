class_name ContractPricing
extends RefCounted

## Contract payout and size — tuned for short coastal runs in Marks (ℳ).
## Distance is in nautical miles; pay is per cargo unit (one grid cell).

const NAUTICAL_MILE_M := 1852.0

## Per commodity `value`: handling fee + distance premium (× value × nm).
const PAY_HANDLING_MULT := 2.0
const PAY_DISTANCE_MULT := 2.5

const PAY_PER_UNIT_MIN := 8
const PAY_PER_UNIT_MAX := 350

## Same-port crane practice — flat per unit, no distance premium.
const SAME_PORT_PAY_MULT := 3.0

## Contract size by origin port tier (size 0–4): [min_units, max_units].
const QUANTITY_RANGE_BY_PORT_SIZE: Array = [
	[8, 14],
	[10, 18],
	[14, 24],
	[20, 32],
	[28, 45],
]


static func route_distance_nm(from_pos: Vector3, to_pos: Vector3) -> float:
	return maxf(from_pos.distance_to(to_pos), 0.0) / NAUTICAL_MILE_M


static func quantity_for_port(origin_size: int, rng: RandomNumberGenerator) -> int:
	var tier := clampi(origin_size, 0, QUANTITY_RANGE_BY_PORT_SIZE.size() - 1)
	var band: Array = QUANTITY_RANGE_BY_PORT_SIZE[tier]
	return rng.randi_range(int(band[0]), int(band[1]))


static func reward_per_unit(value_per: int, distance_nm: float, same_port: bool) -> int:
	var v := maxi(value_per, 1)
	if same_port:
		return clampi(int(v * SAME_PORT_PAY_MULT), PAY_PER_UNIT_MIN, PAY_PER_UNIT_MAX)
	var pay := float(v) * (PAY_HANDLING_MULT + distance_nm * PAY_DISTANCE_MULT)
	return clampi(int(round(pay)), PAY_PER_UNIT_MIN, PAY_PER_UNIT_MAX)


static func total_reward(value_per: int, quantity: int, distance_nm: float, same_port: bool) -> int:
	return reward_per_unit(value_per, distance_nm, same_port) * maxi(quantity, 1)
