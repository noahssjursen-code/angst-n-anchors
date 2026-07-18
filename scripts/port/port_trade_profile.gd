class_name PortTradeProfile
extends RefCounted

## Deterministic import/export for one port.
## Destiny is rolled once as if the port were fully grown (max size), then the
## current size only *unlocks* a prefix of that fixed list. Growing a port never
## re-rolls trade — player upgrades reveal more of the same destiny.

var export_slots: Array[String] = []
var import_slots: Array[String] = []
## Full mature trade list (fixed for this port seed). Active slots are prefixes.
var destiny_export_slots: Array[String] = []
var destiny_import_slots: Array[String] = []
var theme_id: String = ""


## Coherent destinies. Slot order = unlock order (first unlocked earliest).
## Weights are by region only — size no longer picks a different economy.
const THEMES: Array[Dictionary] = [
	{
		"id": "provisions_depot",
		"exports": ["provisions"],
		"imports": ["grain", "diesel"],
		"w_mainland": 4.0, "w_fjord": 3.0, "w_archipelago": 5.0,
	},
	{
		"id": "farm_harbour",
		"exports": ["grain", "provisions"],
		"imports": ["diesel"],
		"w_mainland": 7.0, "w_fjord": 3.0, "w_archipelago": 1.0,
	},
	{
		"id": "mining_outpost",
		"exports": ["iron_ore"],
		"imports": ["provisions", "diesel"],
		"w_mainland": 5.0, "w_fjord": 4.0, "w_archipelago": 2.0,
	},
	{
		"id": "coal_port",
		"exports": ["coal"],
		"imports": ["provisions", "containers"],
		"w_mainland": 4.0, "w_fjord": 3.0, "w_archipelago": 1.5,
	},
	{
		"id": "refinery",
		"exports": ["diesel"],
		"imports": ["crude_oil", "provisions"],
		"w_mainland": 1.5, "w_fjord": 2.0, "w_archipelago": 7.0,
	},
	{
		"id": "lng_terminal",
		"exports": ["lng"],
		"imports": ["provisions", "containers"],
		"w_mainland": 2.0, "w_fjord": 3.0, "w_archipelago": 5.0,
	},
	{
		"id": "container_feeder",
		"exports": ["containers"],
		"imports": ["containers", "provisions"],
		"w_mainland": 6.0, "w_fjord": 3.0, "w_archipelago": 4.0,
	},
	{
		"id": "industrial_hub",
		"exports": ["containers", "iron_ore"],
		"imports": ["coal", "provisions"],
		"w_mainland": 8.0, "w_fjord": 3.0, "w_archipelago": 3.0,
	},
	{
		"id": "bulk_hub",
		"exports": ["grain", "coal"],
		"imports": ["provisions", "containers"],
		"w_mainland": 6.0, "w_fjord": 2.0, "w_archipelago": 2.0,
	},
]


static func derive(definition: PortDefinition, world_seed: int) -> PortTradeProfile:
	assert(definition != null, "PortTradeProfile requires a port definition")
	var profile := PortTradeProfile.new()
	var size := PortSizing.normalized_size(definition.size)
	var rng := RandomNumberGenerator.new()
	var initial_seed := definition.site_seed if definition.site_seed != 0 \
			else world_seed ^ _hash_id(definition.port_id)
	## Destiny seed ignores current size — upgrades must not re-roll the economy.
	rng.seed = initial_seed ^ _hash_id(definition.port_id) ^ 0x54524144

	var theme := _pick_theme(rng, definition.region_kind)
	profile.theme_id = str(theme.get("id", ""))
	profile.destiny_export_slots = _unique_list(theme.get("exports", []) as Array)
	profile.destiny_import_slots = _unique_list(theme.get("imports", []) as Array)
	## Every harbour handles ordinary mixed freight in both directions. Themes
	## describe the specialist economy layered on top of this universal service.
	_ensure_list_starts_with(profile.destiny_export_slots, "provisions")
	_ensure_list_starts_with(profile.destiny_import_slots, "provisions")
	_strip_duplicate_one_way_lists(profile.destiny_export_slots, profile.destiny_import_slots)
	if profile.destiny_export_slots.has("containers") \
			or profile.destiny_import_slots.has("containers"):
		_ensure_list_has(profile.destiny_export_slots, "containers")
		_ensure_list_has(profile.destiny_import_slots, "containers")

	## Mature pier budget — destiny must fit a fully grown harbour.
	_trim_lists_to_quay_budget(
		profile.destiny_export_slots,
		profile.destiny_import_slots,
		PortSizing.max_dedicated_quays(PortSizing.MAX_SIZE),
	)

	## Reveal destiny prefix for this size. Growing never drops a slot.
	_apply_size_unlock(profile, size)
	return profile


## Unique commodities in the mature destiny (containers count once).
static func destiny_product_count(profile: PortTradeProfile) -> int:
	if profile == null:
		return 0
	var seen: Dictionary = {}
	for id in profile.destiny_export_slots:
		if not str(id).is_empty():
			seen[str(id)] = true
	for id in profile.destiny_import_slots:
		if not str(id).is_empty():
			seen[str(id)] = true
	return seen.size()


## Growth ceiling from economy size — small trade destinies stay small ports.
static func max_size_for_profile(profile: PortTradeProfile) -> int:
	return PortSizing.max_size_for_trade_products(destiny_product_count(profile))


## Re-apply the size unlock ladder (e.g. after site_max_size clamps growth).
static func resync_for_size(profile: PortTradeProfile, size: int) -> void:
	if profile == null:
		return
	_apply_size_unlock(profile, PortSizing.normalized_size(size))


## Reveal a monotonic destiny prefix for this size. Growing never drops a slot.
## Pier count is handled by the berth plan — do not re-lock commodities here.
## Sparse destinies fully unlock at their own trade ceiling (not only at size 5).
static func _apply_size_unlock(profile: PortTradeProfile, size: int) -> void:
	var mature_at := mini(
		PortSizing.TRADE_COMPLETE_SIZE,
		max_size_for_profile(profile),
	)
	var export_n := _export_count(size)
	var import_n := _import_count(size)
	if size >= mature_at:
		export_n = profile.destiny_export_slots.size()
		import_n = profile.destiny_import_slots.size()
	profile.export_slots = _take_head(profile.destiny_export_slots, export_n)
	profile.import_slots = _take_head(profile.destiny_import_slots, import_n)
	_strip_duplicate_one_way(profile)
	_force_bidirectional_commodity(profile, "provisions")
	if profile.export_slots.has("containers") or profile.import_slots.has("containers"):
		_force_bidirectional_commodity(profile, "containers")


## Box terminals load and unload the same quay — never one-way containers.
static func is_bidirectional_trade(commodity_id: String) -> bool:
	return str(commodity_id) in ["provisions", "containers"]


static func _force_bidirectional_commodity(profile: PortTradeProfile, commodity_id: String) -> void:
	_ensure_list_has(profile.export_slots, commodity_id)
	_ensure_list_has(profile.import_slots, commodity_id)


static func _ensure_list_has(slots: Array[String], commodity_id: String) -> void:
	if not slots.has(commodity_id):
		slots.append(commodity_id)


static func _ensure_list_starts_with(slots: Array[String], commodity_id: String) -> void:
	slots.erase(commodity_id)
	slots.push_front(commodity_id)


## Region-weighted destiny pick — independent of current harbour size.
static func _pick_theme(
		rng: RandomNumberGenerator,
		region: PortDefinition.RegionKind,
) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var weights: Array[float] = []
	var total := 0.0
	var mature_quays := PortSizing.max_dedicated_quays(PortSizing.MAX_SIZE)
	for raw in THEMES:
		var theme: Dictionary = raw
		var w := _theme_weight(theme, region)
		if w <= 0.0:
			continue
		var trial_exports := _unique_list(theme.get("exports", []) as Array)
		var trial_imports := _unique_list(theme.get("imports", []) as Array)
		_strip_duplicate_one_way_lists(trial_exports, trial_imports)
		var quay_n := _quay_group_count(trial_exports, trial_imports)
		if quay_n > mature_quays:
			w *= 0.2
		candidates.append(theme)
		weights.append(w)
		total += w
	if candidates.is_empty():
		return {
			"id": "fallback_provisions",
			"exports": ["provisions"],
			"imports": ["diesel"],
		}
	var roll := rng.randf() * total
	var acc := 0.0
	for index in range(candidates.size()):
		acc += weights[index]
		if roll <= acc:
			return candidates[index]
	return candidates[candidates.size() - 1]


static func _theme_weight(theme: Dictionary, region: PortDefinition.RegionKind) -> float:
	match region:
		PortDefinition.RegionKind.FJORD:
			return float(theme.get("w_fjord", 1.0))
		PortDefinition.RegionKind.ARCHIPELAGO:
			return float(theme.get("w_archipelago", 1.0))
		PortDefinition.RegionKind.MAINLAND, PortDefinition.RegionKind.LEGACY_ISLAND:
			return float(theme.get("w_mainland", 1.0))
		_:
			return float(theme.get("w_mainland", 1.0))


static func _unique_list(source: Array) -> Array[String]:
	var out: Array[String] = []
	for raw in source:
		var id := str(raw)
		if id.is_empty() or out.has(id):
			continue
		out.append(id)
	return out


static func _take_head(source: Array, count: int) -> Array[String]:
	var out: Array[String] = []
	for raw in source:
		if out.size() >= count:
			break
		var id := str(raw)
		if id.is_empty() or out.has(id):
			continue
		out.append(id)
	return out


static func _strip_duplicate_one_way(profile: PortTradeProfile) -> void:
	_strip_duplicate_one_way_lists(profile.export_slots, profile.import_slots)


static func _strip_duplicate_one_way_lists(
		exports: Array[String],
		imports: Array[String],
) -> void:
	## Same commodity as both import and export only allowed for containers.
	var cleaned: Array[String] = []
	for id in imports:
		if is_bidirectional_trade(id) or not exports.has(id):
			cleaned.append(id)
	imports.clear()
	imports.append_array(cleaned)


## Drop lowest-priority quay commodities until we fit the size's pier budget.
static func _trim_to_quay_budget(profile: PortTradeProfile, max_quays: int) -> void:
	_trim_lists_to_quay_budget(profile.export_slots, profile.import_slots, max_quays)


static func _trim_lists_to_quay_budget(
		exports: Array[String],
		imports: Array[String],
		max_quays: int,
) -> void:
	while _quay_group_count(exports, imports) > max_quays:
		if not _drop_lowest_from_lists(exports, imports):
			break


static func _quay_group_count(exports: Array, imports: Array) -> int:
	var groups: Dictionary = {}
	for raw in exports:
		var id := str(raw)
		if id.is_empty() or CommodityCatalog.uses_asphalt_dock(id):
			continue
		groups[CommodityCatalog.berth_group_id(id, "export")] = true
	for raw in imports:
		var id := str(raw)
		if id.is_empty() or CommodityCatalog.uses_asphalt_dock(id):
			continue
		groups[CommodityCatalog.berth_group_id(id, "import")] = true
	return groups.size()


static func _drop_lowest_from_lists(exports: Array[String], imports: Array[String]) -> bool:
	for index in range(imports.size() - 1, -1, -1):
		var id := imports[index]
		if CommodityCatalog.uses_asphalt_dock(id):
			continue
		imports.remove_at(index)
		if is_bidirectional_trade(id) and exports.has(id):
			if exports.size() > 1 and exports[0] != id:
				exports.erase(id)
		return true
	for index in range(exports.size() - 1, 0, -1):
		var id := exports[index]
		if CommodityCatalog.uses_asphalt_dock(id):
			continue
		exports.remove_at(index)
		if is_bidirectional_trade(id):
			imports.erase(id)
		return true
	return false


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


func locked_export_slots() -> Array[String]:
	var out: Array[String] = []
	for id in destiny_export_slots:
		if not export_slots.has(id):
			out.append(id)
	return out


func locked_import_slots() -> Array[String]:
	var out: Array[String] = []
	for id in destiny_import_slots:
		if not import_slots.has(id):
			out.append(id)
	return out


static func export_slot_count_for_size(size: int) -> int:
	var n := PortSizing.normalized_size(size)
	if n >= PortSizing.TRADE_COMPLETE_SIZE:
		return 99
	return _export_count(n)


static func import_slot_count_for_size(size: int) -> int:
	var n := PortSizing.normalized_size(size)
	if n >= PortSizing.TRADE_COMPLETE_SIZE:
		return 99
	return _import_count(n)


## Unlock ladder — prefixes of the fixed destiny list (always grows with size).
## Full destiny is visible by TRADE_COMPLETE_SIZE; larger sizes only grow geometry.
static func _export_count(size: int) -> int:
	match size:
		0, 1:
			return 1
		2, 3:
			return 2
		4:
			return 2
		_:
			return 99


static func _import_count(size: int) -> int:
	match size:
		0:
			return 0
		1:
			return 1
		2:
			return 1
		3, 4:
			return 2
		_:
			return 99


static func _hash_id(port_id: String) -> int:
	return port_id.hash()
