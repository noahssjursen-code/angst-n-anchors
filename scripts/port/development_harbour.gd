class_name DevelopmentHarbour
extends RefCounted

## Local development captain's home uses the normal terrain, facilities and
## authority. Only its trade budget and alongshore frontage are expanded.
const THEME := "development_all_facilities"
const SHORE_LENGTH_M := 1200.0
const PASSENGER_FRONTAGE_M := 120.0

static func trade_profile() -> PortTradeProfile:
	var profile := PortTradeProfile.new()
	profile.theme_id = THEME
	# Every existing commodity has its own terminal. General/container handling
	# supports both directions; specialised cargo keeps its normal one-way quay.
	for commodity: Dictionary in CommodityCatalog.COMMODITIES:
		var id := str(commodity.id)
		if id in ["fresh_groundfish", "crude_oil", "lng"]:
			profile.destiny_import_slots.append(id)
		else:
			profile.destiny_export_slots.append(id)
			if PortTradeProfile.is_bidirectional_trade(id):
				profile.destiny_import_slots.append(id)
	profile.export_slots = profile.destiny_export_slots.duplicate()
	profile.import_slots = profile.destiny_import_slots.duplicate()
	return profile
