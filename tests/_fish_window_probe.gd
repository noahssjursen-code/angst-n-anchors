extends SceneTree

## Scratch probe (leading underscore — not a gate unit). Lane A.
##
## JOB 1. `PortExpander.expand_uncached` assigns
## `PortFishingService.is_eligible` into the PUBLIC `data.has_fish_landing`
## (:272) and overwrites it with `_has_realized_fish_landing` 28 lines later
## (:300). Two reads sit inside that window, both in the same function:
##
##   :273  if data.has_fish_landing:  PortFishingService.apply_to_profile(...)
##   :282  layout_attrs["has_fish_landing"] = data.has_fish_landing
##
## Question 1 — can anything OUTSIDE the function observe the field there? (A
## static question; answered by grep + the fact that `data` is a fresh local.)
##
## Question 2 — does the eligibility read at :273 leave RESIDUE that outlives the
## window and disagrees with the corrected flag? `apply_to_profile` pushes
## `fresh_groundfish` onto BOTH `import_slots` and `destiny_import_slots`, and
## only `import_slots` is rebuilt by the generator's resync. So:
##
##   a) does `data.commodity_imports` ever claim fresh groundfish at a port whose
##      `has_fish_landing` is false?  (player-visible: the harbour board)
##   b) does `destiny_import_slots` — which nothing resyncs — retain it?
##   c) do `chart_summary` and `expand` agree on the import list, given that
##      chart_summary gates `apply_to_profile` on REALIZED and expand_uncached
##      gates it on ELIGIBILITY?

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const PLACER := preload("res://scripts/world/coastal_port_placer.gd")
const PORT_COUNT := 35
const SEEDS := [424242, 20260817, 90210, 777, 20260816, 31337]
const FISH := "fresh_groundfish"


func _initialize() -> void:
	var total := 0
	var eligible := 0
	var realized := 0
	var diverged := 0
	var by_size: Dictionary = {}
	var imports_disagree_with_flag: Array[String] = []
	var destiny_retains_at_unrealized: Array[String] = []
	var summary_vs_world_imports: Array[String] = []
	var graph_attr_disagrees: Array[String] = []
	var gate_differs: Array[String] = []
	var extra_import_families: Dictionary = {}
	var field_diverge: Dictionary = {}
	var field_example: Dictionary = {}
	var gate_pass: Dictionary = {}

	for world_seed in SEEDS:
		var layout: WorldLayout = GENERATOR.generate(int(world_seed))
		var ports: Array[PortDefinition] = PLACER.place_ports(
			layout, PORT_COUNT, PackedStringArray(WorldPortNames.NAMES))
		LandField.initialize(layout)
		FishingField.initialize(int(world_seed))
		WeatherField.world_seed = int(world_seed)
		for port in ports:
			total += 1
			var tag := "%d/%s" % [int(world_seed), port.port_id]
			var elig := PortFishingService.is_eligible(
				PortDefinition.from_dict(port.to_dict()), int(world_seed))

			PortDataCache.clear()
			var data := PortExpander.expand_uncached(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			var flag: bool = data.has_fish_landing
			if elig:
				eligible += 1
			if flag:
				realized += 1
			if elig != flag:
				diverged += 1
				var key := "size %d" % data.size
				by_size[key] = int(by_size.get(key, 0)) + 1

			## (a) the flag against the player-visible import list
			if data.commodity_imports.has(FISH) != flag:
				imports_disagree_with_flag.append("%s flag=%s imports=%s" % [
					tag, str(flag), str(data.commodity_imports)])
			## (b) the un-resynced destiny list
			if elig != flag and data.trade_profile.destiny_import_slots.has(FISH):
				destiny_retains_at_unrealized.append(tag)
			## (e) the graph attribute the generator was handed, after correction
			var attr := bool(data.layout_graph.initial_attributes.get("has_fish_landing", false))
			if attr != flag:
				graph_attr_disagrees.append("%s attr=%s flag=%s" % [tag, str(attr), str(flag)])

			## (c) the two producers on the import list
			PortDataCache.clear()
			var summary := PortExpander.chart_summary(
				PortDefinition.from_dict(port.to_dict()), int(world_seed), layout)
			## (f) EVERY field the two producers both publish, not just imports.
			var world_chart := data.to_chart_dict()
			for key in world_chart:
				if not summary.has(key):
					continue
				if str(summary[key]) != str(world_chart[key]):
					field_diverge[key] = int(field_diverge.get(key, 0)) + 1
					if not field_example.has(key):
						field_example[key] = "%s summary=%s world=%s" % [
							tag, _clip(str(summary[key])), _clip(str(world_chart[key]))]
			var summary_imports: Array = summary.get("commodity_imports", []) as Array
			if str(summary_imports) != str(data.commodity_imports):
				summary_vs_world_imports.append("%s summary=%s world=%s" % [
					tag, str(summary_imports), str(data.commodity_imports)])
				for raw in summary_imports:
					if not data.commodity_imports.has(str(raw)):
						var fam := CommodityCatalog.commodity_terminal_family(str(raw))
						var fkey := "%s(%s)" % [str(raw), fam]
						extra_import_families[fkey] = int(extra_import_families.get(fkey, 0)) + 1
			## (d) the CONFIRM gate, both ways, for every starter family
			var world_info := data.to_chart_dict()
			world_info["export_slots"] = data.trade_profile.export_slots.duplicate()
			for family in ["fishing", "bulk", "general"]:
				var from_summary := _gate(summary, family)
				var from_world := _gate(world_info, family)
				var gk_s := "%d|%s|summary" % [int(world_seed), family]
				var gk_w := "%d|%s|world" % [int(world_seed), family]
				gate_pass[gk_s] = int(gate_pass.get(gk_s, 0)) + (1 if from_summary else 0)
				gate_pass[gk_w] = int(gate_pass.get(gk_w, 0)) + (1 if from_world else 0)
				if from_summary != from_world:
					gate_differs.append("%s family=%s summary=%s world=%s" % [
						tag, family, str(from_summary), str(from_world)])

	print("=== %d ports over %d seeds" % [total, SEEDS.size()])
	print("=== eligible %d   realized %d   diverged %d  %s" % [
		eligible, realized, diverged, str(by_size)])
	_report("(d) CONFIRM gate answer differs (summary vs world) for a starter family",
		gate_differs)
	_report("(a) commodity_imports disagrees with has_fish_landing", imports_disagree_with_flag)
	_report("(b) destiny_import_slots retains fish at an UNREALIZED port",
		destiny_retains_at_unrealized)
	_report("(c) chart_summary vs world commodity_imports", summary_vs_world_imports)
	_report("(e) graph initial_attributes.has_fish_landing vs flag", graph_attr_disagrees)
	print("--- extra imports the summary claims and the world does not: %s"
		% str(extra_import_families))
	print("--- CONFIRM-gate foundable ports per world (35 each): panel now / world truth")
	for family in ["fishing", "bulk", "general"]:
		var row := ""
		for world_seed in SEEDS:
			row += " %d:%d/%d" % [
				int(world_seed),
				int(gate_pass.get("%d|%s|summary" % [int(world_seed), family], 0)),
				int(gate_pass.get("%d|%s|world" % [int(world_seed), family], 0))]
		print("      %-8s%s" % [family, row])
	print("--- (f) EVERY published field, summary vs world, over %d ports:" % total)
	var fkeys := field_diverge.keys()
	fkeys.sort_custom(func(a, b) -> bool:
		return int(field_diverge[a]) > int(field_diverge[b]))
	for key in fkeys:
		print("      %3d/%d  %-22s %s" % [
			int(field_diverge[key]), total, str(key), str(field_example[key])])
	quit(0)


func _clip(s: String) -> String:
	return s if s.length() <= 110 else s.substr(0, 107) + "..."


## A copy of `MapOverlay._home_port_supports_required_family`, which is what the
## CONFIRM button is gated on. Copied deliberately: the production method is
## private on a Control and this probe must not build a UI.
func _gate(info: Dictionary, family: String) -> bool:
	if family.is_empty():
		return true
	if family == "fishing":
		return bool(info.get("has_fish_landing", false)) \
				and (info.get("features", []) as Array).has("Fish Landing")
	var ids: Array = []
	ids.append_array(info.get("export_slots", []) as Array)
	ids.append_array(info.get("commodity_imports", []) as Array)
	for raw in ids:
		var f := CommodityCatalog.commodity_terminal_family(str(raw))
		if f == family or (family == "bulk" and f.begins_with("bulk_")):
			return true
	return false


func _report(label: String, rows: Array[String]) -> void:
	print("--- %s: %d" % [label, rows.size()])
	for i in mini(rows.size(), 8):
		print("      %s" % rows[i])
