class_name FishLandingLayout
extends RefCounted

## Canonical fish-landing composition shared by the F6 crane showcase and
## generated ports. Local +X is the working berth face; local Z follows the
## quay length. These values reproduce the approved 72 m showcase quay.

const REFERENCE_QUAY_WIDTH_M := 72.0
const BERTH_EDGE_INSET_M := 6.5
const TANK_STORAGE_INSET_M := 15.0
const PUMP_Z_M := 9.0
const TANK_Z_M := 10.0
const TANK_SCALE := 3.0


static func pump_position(quay_width_m: float, berth_sign: float = 1.0) -> Vector3:
	var x := maxf(quay_width_m * 0.5 - BERTH_EDGE_INSET_M, 4.0)
	return Vector3(berth_sign * x, 0.0, PUMP_Z_M)


static func tank_position(quay_width_m: float, berth_sign: float = 1.0) -> Vector3:
	var x := maxf(quay_width_m * 0.5 - TANK_STORAGE_INSET_M, 3.0)
	return Vector3(-berth_sign * x, 0.0, TANK_Z_M)


static func pump_yaw_degrees(berth_sign: float = 1.0) -> float:
	return 0.0 if berth_sign >= 0.0 else 180.0
