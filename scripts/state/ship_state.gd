class_name ShipState
extends RefCounted

signal boarded(data: ShipData)
signal exited()
signal hull_changed(pct: float)
signal fuel_changed(pct: float)
signal instruments_changed(snapshot: Dictionary)
signal notice_requested(message: String, duration_seconds: float)

## Null when the player is not helming any ship.
var data: ShipData = null:
	set(v):
		data = v
		if v != null:
			boarded.emit(v)
		else:
			exited.emit()

var hull_health: float = 1.0:
	set(v):
		hull_health = v
		hull_changed.emit(v)

var fuel: float = 1.0:
	set(v):
		fuel = v
		fuel_changed.emit(v)

var instruments: Dictionary = {}


func publish_instruments(snapshot: Dictionary) -> void:
	instruments = snapshot.duplicate(true)
	instruments_changed.emit(instruments)


func clear_instruments() -> void:
	if instruments.is_empty():
		return
	instruments = {}
	instruments_changed.emit(instruments)


func push_notice(message: String, duration_seconds: float = 3.0) -> void:
	notice_requested.emit(message, duration_seconds)
