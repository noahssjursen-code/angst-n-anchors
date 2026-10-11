extends Node

func _ready() -> void:
	var checks := 0
	for seed_value in range(40):
		for size in range(6):
			var definition := PortDefinition.new()
			definition.port_id = "active-generation-%d" % seed_value
			definition.site_seed = seed_value + 1
			definition.size = size
			var profile := PortTradeProfile.derive(definition, 424242)
			for cid in profile.destiny_export_slots + profile.destiny_import_slots + profile.all_slots():
				assert(CommodityCatalog.generates_port_facility(cid), "Unavailable trade must not reserve port space: " + cid)
			assert(profile.export_slots.has("provisions") and profile.import_slots.has("provisions"))
			checks += 1
	var development := DevelopmentHarbour.trade_profile()
	for cid in CommodityCatalog.GENERATED_PORT_COMMODITIES:
		assert(development.all_slots().has(cid), "Implemented cargo missing: " + cid)
	var asphalt: Array = []
	var families := {}
	var all_cargo: Array = []
	for commodity: Dictionary in CommodityCatalog.COMMODITIES:
		all_cargo.append(str(commodity.id))
	PortBerthPlan._collect_slot(all_cargo, "export", asphalt, families)
	var generated: Array[String] = []
	for group: Dictionary in families.values():
		for slot: Dictionary in group.trade_slots:
			generated.append(str(slot.commodity_id))
	for slot: Dictionary in asphalt:
		generated.append(str(slot.commodity_id))
	for cid: String in all_cargo:
		assert(generated.has(cid) == CommodityCatalog.generates_port_facility(cid), "Berth policy mismatch: " + cid)
		checks += 1
	assert(CommodityCatalog.COMMODITIES.size() == all_cargo.size(), "Keep future catalogue entries")
	print("ACTIVE PORT GENERATION PASS: ", checks, " profiles/commodity checks")
	get_tree().quit()
