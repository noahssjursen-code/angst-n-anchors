class_name WaveSurface
extends RefCounted

## Static wave height query. Any system that needs to know where the water
## surface is at a given world position calls WaveSurface.get_height_at(x, z).
##
## Parameters here are global — they must match the ocean shader when one exists.
## Two overlapping sine waves give a basic cross-chop without a shader.

## Sea level — must match the ocean plane y-position in starting_island.gd.
## Everything that floats reads this as the baseline water height.
const WATER_LEVEL: float = -1.5

const AMPLITUDE_1  := 0.30
const FREQUENCY_1  := 0.18
const SPEED_1      := 0.75
const DIR_1        := Vector2(1.0, 0.6)

const AMPLITUDE_2  := 0.12
const FREQUENCY_2  := 0.26
const SPEED_2      := 1.1
const DIR_2        := Vector2(-0.5, 1.0)


static func get_height_at(x: float, z: float) -> float:
	var t: float = Time.get_ticks_msec() * 0.001
	var d1: Vector2 = DIR_1.normalized()
	var d2: Vector2 = DIR_2.normalized()
	var wave1: float = sin((x * d1.x + z * d1.y) * FREQUENCY_1 + t * SPEED_1) * AMPLITUDE_1
	var wave2: float = sin((x * d2.x + z * d2.y) * FREQUENCY_2 + t * SPEED_2) * AMPLITUDE_2
	return WATER_LEVEL + wave1 + wave2
