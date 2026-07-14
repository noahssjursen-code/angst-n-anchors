class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → PortData.
## Same inputs always produce identical output on every machine.
## No randomness survives outside this class — all state is derived.

const SHIP_CLASS_BY_SIZE: Dictionary = {
	0: ShipClass.Type.COASTAL_TRADER,
	1: ShipClass.Type.COASTAL_TRADER,
	2: ShipClass.Type.SHORT_SEA_COASTER,
	3: ShipClass.Type.HANDYSIZE_FEEDER,
	4: ShipClass.Type.DEEP_SEA_FREIGHTER,
}

const COMMODITIES: Array[String] = [
	"grain", "timber", "iron_ore", "coal", "provisions",
]

const CORE_SERVICES: Array[String] = [
	"Harbour Master", "Contractor", "Shipwright", "Fuel Dock",
]

const POPULATION_RANGE: Dictionary = {
	0: [50,    300],
	1: [300,   1500],
	2: [1500,  6000],
	3: [6000,  25000],
	4: [25000, 100000],
}


static func expand(definition: PortDefinition, world_seed: int) -> PortData:
	var data           := PortData.new()
	data.port_id       = definition.port_id
	data.display_name  = definition.display_name
	data.world_position = definition.world_position
	data.size          = definition.size

	var size := clampi(definition.size, 0, 4)

	var berth_n           := PortSizing.berth_count(size)
	data.dock_length      = PortSizing.dock_length_m(size)
	data.island_width     = PortSizing.island_width_m(size)
	data.berth_count      = berth_n
	data.max_ship_class = SHIP_CLASS_BY_SIZE[size] as ShipClass.Type
	data.has_fuel_point = true

	var rng      := RandomNumberGenerator.new()
	rng.seed     = world_seed ^ _hash_id(definition.port_id)

	data.has_lighthouse = definition.has_lighthouse or (size >= 1 and rng.randf() < 0.3)
	data.has_fog_horn   = definition.has_fog_horn or (size >= 0 and rng.randf() < 0.4)

	data.berth_types       = _berth_types(rng, size, berth_n)
	data.commodity_export  = COMMODITIES[rng.randi() % COMMODITIES.size()]
	data.commodity_imports = _imports(rng, size, data.commodity_export)
	data.layout_seed       = rng.randi()
	var legacy_rotation := rng.randf() * TAU
	data.rotation_y = definition.rotation_y if definition.has_explicit_rotation else legacy_rotation
	data.region_kind = definition.region_kind
	data.ground_mode = definition.ground_mode
	data.population        = _population(rng, size)
	data.features = CORE_SERVICES.duplicate()
	if data.has_lighthouse:
		data.features.append("Lighthouse")
	if data.has_fog_horn:
		data.features.append("Fog Horn")

	return data


static func _berth_types(_rng: RandomNumberGenerator, _size: int, count: int) -> Array[int]:
	var types: Array[int] = []
	for i in range(count):
		types.append(CargoBerthType.Type.GENERAL)
	return types


static func _imports(
	rng:    RandomNumberGenerator,
	size:   int,
	export: String,
) -> Array[String]:
	var count   := 1 + (1 if size >= 2 else 0)
	var imports: Array[String] = []
	var attempts := 0
	while imports.size() < count and attempts < 20:
		attempts += 1
		var c := COMMODITIES[rng.randi() % COMMODITIES.size()]
		if c != export and not imports.has(c):
			imports.append(c)
	return imports


static func _population(rng: RandomNumberGenerator, size: int) -> int:
	var range_arr := POPULATION_RANGE[clampi(size, 0, 4)] as Array
	var lo := int(range_arr[0])
	var hi := int(range_arr[1])
	return lo + rng.randi() % (hi - lo)


static func _hash_id(s: String) -> int:
	var h := 5381
	for i in range(s.length()):
		h = ((h << 5) + h) ^ s.unicode_at(i)
	return h
