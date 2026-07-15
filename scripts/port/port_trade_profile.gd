class_name PortTradeProfile
extends RefCounted

## Deterministic import/export slots for one port. Derived from world seed +
## port id + size class — never authored as metre geometry.
## Larger sizes prefer one commodity per terminal family so berths stay distinct.

var export_slots: Array[String] = []
var import_slots: Array[String] = []


static func derive(definition: PortDefinition, world_seed: int) -> PortTradeProfile:
	assert(definition != null, "PortTradeProfile requires a port definition")
	var profile := PortTradeProfile.new()
	var size := PortSizing.normalized_size(definition.size)
	var rng := RandomNumberGenerator.new()
	var initial_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	rng.seed = initial_seed ^ _hash_id(definition.port_id) ^ 0x54524144

	var export_n := _export_count(size)
	var import_n := _import_count(size)
	var pool := CommodityCatalog.PLAYABLE_TRADE.duplicate()
	# Fishing harbours and small landings bias toward fish when coastal/fjord.
	if size <= 1 and (
			definition.region_kind == PortDefinition.RegionKind.FJORD
			or definition.region_kind == PortDefinition.RegionKind.ARCHIPELAGO
	):
		pool = ["fish", "timber", "provisions"]

	## Large ports: spread across terminal families first, then fill leftovers.
	if size >= 4:
		profile.export_slots = _pick_family_diverse(rng, pool, export_n)
	else:
		profile.export_slots = _pick_unique(rng, pool, export_n)

	var import_pool: Array = []
	for commodity in pool:
		if not profile.export_slots.has(str(commodity)):
			import_pool.append(commodity)
	for commodity in CommodityCatalog.PLAYABLE_TRADE:
		if not import_pool.has(commodity):
			import_pool.append(commodity)
	if size >= 4:
		profile.import_slots = _pick_family_diverse(rng, import_pool, import_n)
	else:
		profile.import_slots = _pick_unique(rng, import_pool, import_n)
	if profile.import_slots.size() < import_n:
		profile.import_slots = _pick_unique(
			rng,
			CommodityCatalog.PLAYABLE_TRADE.duplicate(),
			import_n,
		)
	return profile


func primary_export() -> String:
	return export_slots[0] if not export_slots.is_empty() else ""


func all_slots() -> Array[String]:
	var out: Array[String] = []
	for commodity in export_slots:
		out.append(commodity)
	for commodity in import_slots:
		if not out.has(commodity):
			out.append(commodity)
	return out


static func _export_count(size: int) -> int:
	match size:
		0, 1:
			return 1
		2, 3:
			return 2
		4:
			return 3
		5:
			return 4
		6:
			return 5
		_:
			return 6


static func _import_count(size: int) -> int:
	match size:
		0:
			return 1
		1:
			return 2
		2, 3:
			return 3
		4:
			return 4
		5:
			return 5
		6:
			return 5
		_:
			return 6


## Prefer one commodity from each unused terminal family before doubling up.
static func _pick_family_diverse(
		rng: RandomNumberGenerator,
		pool: Array,
		count: int,
) -> Array[String]:
	var by_family: Dictionary = {}
	for raw in pool:
		var id := str(raw)
		if id.is_empty():
			continue
		var family := CommodityCatalog.commodity_terminal_family(id)
		if not by_family.has(family):
			by_family[family] = []
		(by_family[family] as Array).append(id)
	var family_keys: Array[String] = []
	for key in by_family.keys():
		family_keys.append(str(key))
	family_keys.sort()
	## Shuffle family order deterministically.
	for i in range(family_keys.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := family_keys[i]
		family_keys[i] = family_keys[j]
		family_keys[j] = tmp

	var out: Array[String] = []
	var used: Dictionary = {}
	for family in family_keys:
		if out.size() >= count:
			break
		var options: Array = by_family[family] as Array
		if options.is_empty():
			continue
		var pick := str(options[rng.randi_range(0, options.size() - 1)])
		out.append(pick)
		used[pick] = true

	## Fill remaining slots from leftovers (same families ok).
	var leftovers: Array = []
	for raw in pool:
		var id := str(raw)
		if id.is_empty() or used.has(id):
			continue
		leftovers.append(id)
	while out.size() < count and not leftovers.is_empty():
		var index := rng.randi_range(0, leftovers.size() - 1)
		out.append(str(leftovers[index]))
		leftovers.remove_at(index)
	return out


static func _pick_unique(
		rng: RandomNumberGenerator,
		pool: Array,
		count: int,
		exclude: Array[String] = [],
) -> Array[String]:
	var available: Array[String] = []
	for raw in pool:
		var id := str(raw)
		if id.is_empty() or exclude.has(id) or available.has(id):
			continue
		available.append(id)
	var out: Array[String] = []
	while out.size() < count and not available.is_empty():
		var index := rng.randi_range(0, available.size() - 1)
		out.append(available[index])
		available.remove_at(index)
	return out


static func _hash_id(port_id: String) -> int:
	return port_id.hash()
