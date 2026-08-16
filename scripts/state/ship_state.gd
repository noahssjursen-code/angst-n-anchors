class_name ShipState
extends RefCounted

## `hull_changed(pct)` and `fuel_changed(pct)` were declared here beside
## `hull_health` and `fuel`, and the four of them were a complete wire with
## nothing at either end — deleted 2026-08-16. Neither field was ever assigned
## after construction (`GameState._on_helm_on` set them on the `ShipData`
## record, not on this state), nothing read either one, and the only subscriber
## was `debug_draw`, whose SHIP section draws Hull and Fuel as
## "— not implemented" stubs regardless. Fuel is not missing from the game: it
## is owned by `BoatBody`, which has its own `fuel_changed(fraction)` and feeds
## the HUD's FUEL cell through `instruments.fuel_fraction`. This was the second
## copy (REALITY §3b). Hull condition has no producer anywhere — no damage
## system exists — so there is nothing yet to publish; whether the game gets one,
## and whether it gets a readout, is the owner's call, not a field to leave
## standing as though it were wired.
signal boarded(data: ShipData)
signal exited()
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
