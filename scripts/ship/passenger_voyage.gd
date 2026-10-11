class_name PassengerVoyage
extends Node3D

## Opt-in local operating component. No new singleton or per-passenger physics.
## Installed by PassengerOperations for owned ferries in the live world.
signal changed(manifest: Dictionary, status: String)
var service: PassengerService
var boat: ImportedDraftVessel
var status := "No passenger sailing"
var _elapsed := 0.0
var cabin_visual: PassengerCabinVisual

func setup(owner_boat: ImportedDraftVessel, authority: PassengerService) -> void:
	boat = owner_boat
	service = authority
	cabin_visual = PassengerCabinVisual.new()
	add_child(cabin_visual)

func _ready() -> void:
	boat.departure_checks.append(departure_reason)
	boat.departure_requested.connect(prepare_departure)
	service.restore_mass(boat)
	cabin_visual.sync(service.active_for(boat))

func _exit_tree() -> void:
	if is_instance_valid(boat):
		boat.departure_checks.erase(departure_reason)
		if boat.departure_requested.is_connected(prepare_departure):
			boat.departure_requested.disconnect(prepare_departure)

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < .25: return
	_elapsed = 0.0
	var item := service.active_for(boat)
	if item.is_empty(): return
	status = service.advance(str(item.id),boat)
	service.restore_mass(boat)
	var updated := service.record(str(item.id))
	cabin_visual.sync(updated)
	changed.emit(updated,status)

func departure_reason() -> String:
	return service.departure_reason(boat)

func prepare_departure() -> void:
	var item := service.active_for(boat)
	if not item.is_empty() and item.phase in ["ready", "underway"]:
		var door := PassengerAccommodation.boarding_door(boat)
		if door != null: door.request("door_open",false)
