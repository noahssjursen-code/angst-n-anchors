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
	##
	## ⚠ THAT SENTENCE IS FALSE AT SIZE 0, AND THAT IS THE WHOLE OF THE
	## ADVERTISED-BUT-UNBUILT FISH LANDING — measured 2026-08-17 over six world
	## seeds, 210 ports (`tests/_fish_landing_realization_probe.gd`). Being first
	## in the list survives a resync that KEEPS a prefix; `_apply_size_unlock`
	## takes `_take_head(destiny_import_slots, _import_count(size))` and
	## `_import_count(0)` is **0**, so a size-0 port's import list is emptied and
	## then refilled with `provisions` alone by `_force_bidirectional_commodity`.
	## `fresh_groundfish` is gone before `PortBerthPlan.build` reads the slots, so
	## no fishing quay is planned and `_has_realized_fish_landing` is correctly
	## false. Sizes 1-4 keep it in every one of the 210 ports measured: the
	## divergence is 52 ports and all 52 are size 0.
	##
	## WHETHER A HAMLET SHOULD HAVE A FISH LANDING IS THE OWNER'S CALL, not a slip
	## to patch here — `_import_count(0) == 0` is a deliberate trade ladder and
	## exempting one commodity from it is a world-building decision. Until it is
	## made, the panel no longer advertises what the ladder trims (see
	## `PortExpander.realized_fish_landing`).
	_ensure_first(profile.destiny_import_slots, COMMODITY_ID)
	_ensure_first(profile.import_slots, COMMODITY_ID)


static func _ensure_first(slots: Array[String], commodity_id: String) -> void:
	slots.erase(commodity_id)
	slots.push_front(commodity_id)
