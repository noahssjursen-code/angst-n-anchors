extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	var ports: Array[Dictionary] = [{"id":"origin", "position":Vector3.ZERO, "commodity_exports":["provisions", "iron_ore"]}]
	# Reverse alphabetical IDs reproduce the old distant-first failure.
	for i in range(1, 10):
		ports.append({"id":"port-%02d" % (10-i), "position":Vector3(i*1000,0,0), "commodity_imports":["provisions", "iron_ore"]})
	for day in [0, 1, 42]:
		var offers := FreightOfferGenerator.generate("origin", ports, day)
		assert(offers.size() == 6)
		for i in 6:
			assert(offers[i].distance_m == (i+1)*1000, "Nearest six distinct destinations must survive cargo duplicates and daily rotation")
		assert(offers == FreightOfferGenerator.generate("origin", ports, day))
	var candidates := FreightOfferGenerator.generate("origin", ports, 0, 0)
	var compatible: Array[Dictionary] = []
	for offer in candidates:
		if offer.handling_mode == "general" and offer.distance_m > 1000:
			compatible.append(offer)
	assert(FreightOfferGenerator.select_offers(compatible)[0].distance_m == 2000, "Filter ship compatibility before taking nearest offers")
	assert(FreightOfferGenerator.payment_for(2000, "general", 2) == 1780)
	assert(FreightOfferGenerator.payment_for(10000, "general", 2) == 3700)
	assert(FreightOfferGenerator.payment_for(10000, "general", 40) == 62600)
	assert(FreightOfferGenerator.payment_for(10000, "bulk", 80) == 4760)
	assert(FreightOfferGenerator.payment_for(10000, "general", 0) == 0)
	for offer in candidates:
		assert(offer.pay_marks == FreightOfferGenerator.payment_for(offer.distance_m, offer.handling_mode, offer.quantity), "Small and standard bookings share one tariff")
	for size in range(1, 6):
		for seed in range(20):
			var definition := PortDefinition.new()
			definition.port_id = "trade-%d" % seed
			definition.size = size
			var profile := PortTradeProfile.derive(definition, seed)
			assert(profile.import_slots.has("provisions") and profile.export_slots.has("provisions"), "Every town supports two-way general freight regardless of specialist theme")
	print("FREIGHT LOCALITY PASS: nearest distinct destinations, compatibility ordering, quantity-distance tariff, and 100 general-cargo port profiles")
	get_tree().quit()
