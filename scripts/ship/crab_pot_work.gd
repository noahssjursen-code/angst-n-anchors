class_name CrabPotWork
extends RefCounted

## Grab, throw, then an unattended sink. Hauling is the hauler's travel, not a held key.
const GRAB_S := 0.45
const SETTLE_S := 0.2
const THROW_S := 0.65
const STOW_S := 0.45
const TRAVEL_M_S := 2.4
const MIN_DEPTH_M := 4.0
const MAX_DEPTH_M := 40.0
const ALONGSIDE_M := 14.0
const RELEASE_AT := 0.62

enum Phase { STOWED, CARRYING, THROWING, SINKING, DEPLOYED, HAULING, STOWING }

var phase := Phase.STOWED
var progress := 0.0
var settle := 0.0
var depth_m := 0.0


func begin_carry() -> void:
	phase = Phase.CARRYING
	progress = 0.0
	settle = 0.0


func advance_carry(dt: float) -> bool:
	if phase != Phase.CARRYING:
		return false
	if progress < 1.0:
		progress = minf(1.0, progress + maxf(dt, 0.0) / GRAB_S)
		return false
	settle += maxf(dt, 0.0)
	return settle >= SETTLE_S


func begin_throw(depth: float) -> void:
	depth_m = maxf(MIN_DEPTH_M, depth)
	phase = Phase.THROWING
	progress = 0.0


func advance_throw(dt: float) -> bool:
	if phase != Phase.THROWING:
		return false
	progress = minf(1.0, progress + maxf(dt, 0.0) / THROW_S)
	if progress >= 1.0:
		phase = Phase.SINKING
		progress = 0.0
		return true
	return false


func hands_bound() -> bool:
	if phase == Phase.CARRYING:
		return true
	return phase == Phase.THROWING and progress < RELEASE_AT


func finish_sink() -> void:
	phase = Phase.DEPLOYED
	progress = 0.0


func begin_haul() -> void:
	phase = Phase.HAULING
	progress = 0.0


func begin_stow() -> void:
	phase = Phase.STOWING
	progress = 0.0


func advance_stow(dt: float) -> bool:
	if phase != Phase.STOWING:
		return false
	progress = minf(1.0, progress + maxf(dt, 0.0) / STOW_S)
	if progress >= 1.0:
		phase = Phase.STOWED
		progress = 0.0
		settle = 0.0
		depth_m = 0.0
		return true
	return false


func cancel() -> void:
	phase = Phase.STOWED
	progress = 0.0
	settle = 0.0
	depth_m = 0.0
