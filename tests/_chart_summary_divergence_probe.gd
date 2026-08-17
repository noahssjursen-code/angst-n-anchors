extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## TWO QUESTIONS the fish-landing fix depends on.
##
## 1. WHY does realization fail, mechanically? `_fish_landing_realization_probe`
##    says the cause is uniform — `fresh_groundfish` is absent from the port's
##    trade slots by the time `PortBerthPlan.build` reads them — and that every
##    divergent port is size 0. `PortFishingService.apply_to_profile`'s own
##    comment claims it puts the commodity "at the front of both lists so
##    PortLayoutGenerator's size resync cannot trim the advertised berth back out
##    of a small harbour". This prints the destiny list, the unlocked list and the
##    size ladder's slot count so the claim can be believed or not.
##
## 2. IS `has_fish_landing` THE ONLY FIELD the two producers disagree on?
##    `chart_summary` and `expand_uncached` derive the SAME port summary twice
##    (REALITY §3b). If the fix touches one field it must not be reported as
##    "the panel now agrees with the world" if three other fields still differ.
##    Every field the pick panel PRINTS is compared here.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817]


func _initialize() -> void:
	_ladder()
	_fields()
	quit(0)


func _ladder() -> void:
	print("── the size ladder, which is where the fish landing is lost ──")
	for size in range(5):
		print("   size %d: export slots %d · IMPORT SLOTS %d" % [
			size,
			PortTradeProfile.export_slot_count_for_size(size),
			PortTradeProfile.import_slot_count_for_size(size),
		])
	var layout: WorldLayout = GENERATOR.generate(20260817)
	var ports: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT)
	var shown := 0
	for port in ports:
		if not PortFishingService.is_eligible(port, 20260817):
			continue
		var def := PortDefinition.from_dict(port.to_dict())
		var trade := PortTradeProfile.derive(def, 20260817)
		PortFishingService.apply_to_profile(trade)
		var before_import: Array = trade.import_slots.duplicate()
		var before_destiny: Array = trade.destiny_import_slots.duplicate()
		var n := PortSizing.normalized_size(mini(def.size, def.site_max_size if def.site_max_size > 0 else PortSizing.MAX_SIZE))
		PortTradeProfile.resync_for_size(trade, n)
		print("   %-10s size %d  destiny_import=%s" % [port.port_id, n, str(before_destiny)])
		print("              apply_to_profile → import_slots=%s" % str(before_import))
		print("              resync_for_size(%d) → import_slots=%s   fish kept: %s" % [
			n, str(trade.import_slots),
			"YES" if trade.import_slots.has(PortFishingService.COMMODITY_ID) else "NO — TRIMMED",
		])
		shown += 1
		if shown >= 4:
			break


func _fields() -> void:
	print("")
	print("── every field the pick panel prints, from both producers ──")
	var mismatches: Dictionary = {}
	var total := 0
	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(layout, PORT_COUNT)
		for port in ports:
			total += 1
			var summary := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed))
			PortDataCache.clear()
			var data := PortExpander.expand_uncached(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			_cmp(mismatches, "size", summary.get("size"), data.size)
			_cmp(mismatches, "region", summary.get("region"), _region(data))
			_cmp(mismatches, "berth_count", summary.get("berth_count"), data.berth_count)
			_cmp(mismatches, "population", summary.get("population"), data.population)
			_cmp(mismatches, "commodity_export",
				summary.get("commodity_export"), data.commodity_export)
			_cmp(mismatches, "commodity_imports (IMPORTS line)",
				str(summary.get("commodity_imports")), str(data.commodity_imports))
			_cmp(mismatches, "max_ship_class_name",
				summary.get("max_ship_class_name"),
				str(ShipClass.DISPLAY_NAME.get(data.max_ship_class, "Vessel")))
			_cmp(mismatches, "has_lighthouse",
				summary.get("has_lighthouse"), data.has_lighthouse)
			_cmp(mismatches, "has_fog_horn", summary.get("has_fog_horn"), data.has_fog_horn)
			_cmp(mismatches, "has_fish_landing",
				summary.get("has_fish_landing"), data.has_fish_landing)
			_cmp(mismatches, "features (FACILITIES line, Export: stripped)",
				str(_panel_features(summary.get("features", []) as Array)),
				str(_panel_features(data.features)))
	print("   %d ports compared over seeds %s" % [total, str(SEEDS)])
	var keys: Array = mismatches.keys()
	keys.sort()
	for key in keys:
		var row: Array = mismatches[key]
		print("   %-46s %3d/%d disagree   e.g. summary=%s world=%s" % [
			key, int(row[0]), total, str(row[1]), str(row[2]),
		])
	for key in [
		"size", "region", "berth_count", "population", "commodity_export",
		"commodity_imports (IMPORTS line)", "max_ship_class_name",
		"has_lighthouse", "has_fog_horn", "has_fish_landing",
		"features (FACILITIES line, Export: stripped)",
	]:
		if not mismatches.has(key):
			print("   %-46s   0/%d — the two producers agree" % [key, total])


static func _panel_features(features: Array) -> Array:
	var out: Array = []
	for raw in features:
		var f := str(raw)
		if f.begins_with("Export:"):
			continue
		out.append(f)
	out.sort()
	return out


static func _region(data: PortData) -> String:
	match data.region_kind:
		PortDefinition.RegionKind.MAINLAND:
			return "mainland"
		PortDefinition.RegionKind.FJORD:
			return "fjord"
		PortDefinition.RegionKind.ARCHIPELAGO:
			return "archipelago"
		_:
			return "coastal"


func _cmp(out: Dictionary, key: String, a: Variant, b: Variant) -> void:
	if str(a) == str(b):
		return
	if not out.has(key):
		out[key] = [0, a, b]
	var row: Array = out[key]
	row[0] = int(row[0]) + 1
