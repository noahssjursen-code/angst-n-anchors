class_name CatchLot
extends RefCounted

## Serializable landed catch. This is the authority payload; deck visuals are derived.

const MASS_EPS_KG := 0.1

var lot_id: String = ""
var product_id: String = "fresh_groundfish"
var species_id: String = "mixed_groundfish"
var mass_kg: float = 0.0
var caught_game_hours: float = 0.0
var caught_position: Vector2 = Vector2.ZERO
var quality: float = 1.0
var ground_tier: String = "normal"
var price_multiplier: float = 1.0
var vessel_id: String = ""
var owner_id: String = ""


static func create(data: Dictionary = {}) -> CatchLot:
	var lot := CatchLot.new()
	lot.lot_id = str(data.get("lot_id", "")).strip_edges()
	lot.product_id = str(data.get("product_id", "fresh_groundfish")).strip_edges()
	lot.species_id = str(data.get("species_id", "mixed_groundfish")).strip_edges()
	lot.mass_kg = maxf(float(data.get("mass_kg", 0.0)), 0.0)
	lot.caught_game_hours = maxf(float(data.get("caught_game_hours", 0.0)), 0.0)
	lot.caught_position = _vector2_from(data.get("caught_position", Vector2.ZERO))
	lot.quality = clampf(float(data.get("quality", 1.0)), 0.0, 1.0)
	lot.ground_tier = str(data.get("ground_tier", "normal")).strip_edges()
	lot.price_multiplier = maxf(float(data.get("price_multiplier", 1.0)), 0.0)
	lot.vessel_id = str(data.get("vessel_id", "")).strip_edges()
	lot.owner_id = str(data.get("owner_id", "")).strip_edges()
	return lot


func is_empty() -> bool:
	return product_id.is_empty() or mass_kg <= MASS_EPS_KG


func duplicate_lot() -> CatchLot:
	return CatchLot.from_dict(to_dict())


func split(max_mass_kg: float) -> CatchLot:
	var taken := minf(maxf(max_mass_kg, 0.0), mass_kg)
	var out := duplicate_lot()
	out.mass_kg = taken
	mass_kg -= taken
	if mass_kg <= MASS_EPS_KG:
		mass_kg = 0.0
	return out


func can_merge(other: CatchLot) -> bool:
	return (
		other != null
		and product_id == other.product_id
		and species_id == other.species_id
		and ground_tier == other.ground_tier
		and absf(caught_game_hours - other.caught_game_hours) <= 0.25
	)


func merge_from(other: CatchLot) -> bool:
	if not can_merge(other):
		return false
	var combined := mass_kg + other.mass_kg
	if combined <= MASS_EPS_KG:
		return true
	quality = (quality * mass_kg + other.quality * other.mass_kg) / combined
	price_multiplier = (
		price_multiplier * mass_kg + other.price_multiplier * other.mass_kg
	) / combined
	mass_kg = combined
	return true


func to_dict() -> Dictionary:
	return {
		"lot_id": lot_id,
		"product_id": product_id,
		"species_id": species_id,
		"mass_kg": mass_kg,
		"caught_game_hours": caught_game_hours,
		"caught_position": [caught_position.x, caught_position.y],
		"quality": quality,
		"ground_tier": ground_tier,
		"price_multiplier": price_multiplier,
		"vessel_id": vessel_id,
		"owner_id": owner_id,
	}


static func from_dict(data: Dictionary) -> CatchLot:
	return CatchLot.create(data)


static func _vector2_from(value: Variant) -> Vector2:
	if value is Vector2:
		return value as Vector2
	if value is Array and (value as Array).size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO
