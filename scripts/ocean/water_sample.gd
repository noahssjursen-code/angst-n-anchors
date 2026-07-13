class_name WaterSample
extends RefCounted

var height: float = -1.5
var velocity: Vector3 = Vector3.ZERO
var gradient_xz: Vector2 = Vector2.ZERO
var normal: Vector3 = Vector3.UP
var shelter: float = 1.0
var snapshot_time: float = -1.0
var age_seconds: float = INF
var stale: bool = true
var valid: bool = false


static func flat() -> WaterSample:
	return WaterSample.new()
