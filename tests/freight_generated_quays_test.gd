extends Node

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("run")

func run() -> void:
	var layout := WorldLayoutGenerator.generate(109858862)
	var definitions := CoastalPortPlacer.place_ports(layout, 35, PackedStringArray(WorldPortNames.NAMES))
	var suitable := 0
	var obsolete_rejections := 0
	for definition in definitions:
		var data := PortExpander.expand(definition, 109858862, layout)
		for berth in data.freight_berths():
			if berth.commodities.has("provisions") and berth.length_m >= 92.0:
				suitable += 1
				if ShipClass.max_length(data.max_ship_class) < 88.0: obsolete_rejections += 1
				break
	assert(suitable > 0, "Generated world must offer real general-cargo destinations for Northline")
	assert(obsolete_rejections > 0, "Reproduce categorical rejection of physically suitable destinations")
	print("GENERATED FREIGHT QUAYS PASS: ", suitable, " suitable Northline ports; ", obsolete_rejections, " incorrectly rejected by old class filter")
	get_tree().quit()
