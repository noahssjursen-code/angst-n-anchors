class_name PortFishingService
extends RefCounted

## Deterministic rule for ports that land fresh catch. Island ports always
## receive the service; other ports receive it when productive fishing water
## lies directly outside their harbour entrance.

const COMMODITY_ID := "fresh_groundfish"
const SAMPLE_DISTANCES_M := [350.0, 700.0, 1100.0]


static func is_eligible(definition: PortDefinition, world_seed: int) -> bool:
	if definition == null:
		return false
	if definition.region_kind in [
		PortDefinition.RegionKind.ARCHIPELAGO,
		PortDefinition.RegionKind.LEGACY_ISLAND,
	]:
		return true
	FishingField.initialize(world_seed)
	var seaward := Basis(Vector3.UP, definition.rotation_y) * Vector3.FORWARD
	for distance_m in SAMPLE_DISTANCES_M:
		var sample := FishingField.sample(
			definition.world_position + seaward * float(distance_m)
		)
		if bool(sample.get("open_water", false)) \
				and float(sample.get("catch_mul", 0.0)) >= 1.0:
			return true
	return false


static func apply_to_profile(profile: PortTradeProfile) -> void:
	if profile == null:
		return
	## Fish landing is a port facility, not an optional late trade unlock. Keep it
	## at the front of both lists so PortLayoutGenerator's size resync cannot trim
	## the advertised berth back out of a small harbour.
	_ensure_first(profile.destiny_import_slots, COMMODITY_ID)
	_ensure_first(profile.import_slots, COMMODITY_ID)


static func _ensure_first(slots: Array[String], commodity_id: String) -> void:
	slots.erase(commodity_id)
	slots.push_front(commodity_id)
