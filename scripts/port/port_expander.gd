class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → PortData.
## Same inputs always produce identical output on every machine.
## No randomness survives outside this class — all state is derived.

## Berth count per port tier (fixed). dock_length = count × slot width so
## growth is along the waterfront (+X), not inland into the town (+Z).
const BERTH_COUNT_BY_SIZE: Dictionary = {
	0: 1,
	1: 2,
	2: 3,
	3: 4,
	4: 5,
}

## Width (m) of each berth slot along the dock face — cranes/aprons scale with this.
const SLOT_WIDTH_BY_SIZE: Dictionary = {
	0:  40.0,
	1:  50.0,
	2:  62.0,
	3:  76.0,
	4:  92.0,
}

## Island land body width — wider than dock_length (T-shape along the shore).
const ISLAND_WIDTH_BY_SIZE: Dictionary = {
	0:  88.0,
	1:  120.0,
	2:  200.0,
	3:  320.0,
	4:  500.0,
}

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

## [name, min_size, probability]
const FEATURE_POOL: Array = [
	["Harbour Master",  0, 1.00],
	["Fuel Dock",       0, 1.00],
	["Tavern",          0, 0.70],
	["General Store",   1, 0.90],
	["Chandlery",       1, 0.75],
	["Shipwright",      1, 0.60],
	["Bank",            2, 0.70],
	["Warehouse",       2, 0.80],
	["Maintenance Bay", 2, 0.65],
	["Dry Dock",        3, 0.70],
	["Ship Supplier",   3, 0.75],
	["Exchange",        3, 0.65],
	["Naval Yard",      4, 0.80],
	["Customs House",   4, 0.90],
	["Lighthouse",      1, 0.30],
	["Fog Horn",        0, 0.40],
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

	var berth_n           := int(BERTH_COUNT_BY_SIZE[size])
	var slot_w            := float(SLOT_WIDTH_BY_SIZE[size])
	data.dock_length      = float(berth_n) * slot_w
	data.island_width     = float(ISLAND_WIDTH_BY_SIZE[size])
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
	data.rotation_y        = rng.randf() * TAU
	data.population        = _population(rng, size)
	data.features          = _features(rng, size)

	# Sync physical flags with features list — if the feature is listed, the building must exist.
	if "Lighthouse" in data.features:
		data.has_lighthouse = true
	if "Fog Horn" in data.features:
		data.has_fog_horn = true

	return data


static func _berth_types(
	rng:   RandomNumberGenerator,
	size:  int,
	count: int,
) -> Array[int]:
	var types: Array[int] = []

	# Specialization rolled once per port
	var spec := 0   # 0 = all general
	if size >= 1 and rng.randf() < 0.4:
		spec = 1    # bulk terminal — grab cranes
	if size >= 3 and rng.randf() < 0.3:
		spec = 2    # container terminal — gantry cranes

	for i in range(count):
		match spec:
			1: types.append(CargoBerthType.Type.BULK      if i == 0 else CargoBerthType.Type.GENERAL)
			2: types.append(CargoBerthType.Type.CONTAINER if i == 0 else CargoBerthType.Type.GENERAL)
			_: types.append(CargoBerthType.Type.GENERAL)

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


static func _features(rng: RandomNumberGenerator, size: int) -> Array[String]:
	var out: Array[String] = []
	for entry in FEATURE_POOL:
		var arr       := entry as Array
		var min_size  := int(arr[1])
		var chance    := float(arr[2])
		if size >= min_size and rng.randf() < chance:
			out.append(str(arr[0]))
	return out


static func _hash_id(s: String) -> int:
	var h := 5381
	for i in range(s.length()):
		h = ((h << 5) + h) ^ s.unicode_at(i)
	return h
