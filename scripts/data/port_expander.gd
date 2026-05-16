class_name PortExpander
extends RefCounted

## Deterministic converter: PortDefinition + world_seed → PortData.
## Same inputs always produce identical output on every machine.
## No randomness survives outside this class — all state is derived.

## Dock lengths chosen so berth_count(dock, ship_class, gap=3) gives the target
## number of berths per port size (1 / 2 / 3 / 4 / 5).
## slot sizes: CT=18 m, SSC=28 m, HF=43 m, DSF=63 m (max_length + 3 m gap)
const DOCK_LENGTH_BY_SIZE: Dictionary = {
	0:  22.0,   # 1 berth  — coastal trader
	1:  40.0,   # 2 berths — coastal trader
	2:  90.0,   # 3 berths — short sea coaster
	3: 175.0,   # 4 berths — handysize feeder
	4: 320.0,   # 5 berths — deep sea freighter
}

## Island land body width — always wider than the dock, giving the T-shape.
## Buildings are placed within island_width regardless of dock_length.
## Each entry is noticeably wider than the corresponding DOCK_LENGTH so the
## dock visibly "sticks out" from a wider land mass.
const ISLAND_WIDTH_BY_SIZE: Dictionary = {
	0:  60.0,   # dock=22 m  — compact fishing hamlet
	1:  80.0,   # dock=40 m  — small working port
	2: 120.0,   # dock=90 m  — decent T visible
	3: 200.0,   # dock=175 m — moderate T
	4: 340.0,   # dock=320 m — dock just narrower than island
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


static func expand(definition: PortDefinition, world_seed: int) -> PortData:
	var data           := PortData.new()
	data.port_id       = definition.port_id
	data.display_name  = definition.display_name
	data.world_position = definition.world_position
	data.size          = definition.size

	var size := clampi(definition.size, 0, 4)

	data.dock_length    = float(DOCK_LENGTH_BY_SIZE[size])
	data.island_width   = float(ISLAND_WIDTH_BY_SIZE[size])
	data.max_ship_class = SHIP_CLASS_BY_SIZE[size] as ShipClass.Type
	data.has_fuel_point = true

	var rng      := RandomNumberGenerator.new()
	rng.seed     = world_seed ^ _hash_id(definition.port_id)

	data.berth_types      = _berth_types(rng, size, data.dock_length, data.max_ship_class)
	data.commodity_export = COMMODITIES[rng.randi() % COMMODITIES.size()]
	data.commodity_imports = _imports(rng, size, data.commodity_export)
	data.layout_seed      = rng.randi()

	return data


static func _berth_types(
	rng:       RandomNumberGenerator,
	size:      int,
	dock_len:  float,
	max_class: ShipClass.Type,
) -> Array[int]:
	var count  := ShipClass.berth_count(dock_len, max_class, 3.0)
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


static func _hash_id(s: String) -> int:
	var h := 5381
	for i in range(s.length()):
		h = ((h << 5) + h) ^ s.unicode_at(i)
	return h
