class_name ShipwrightPricing
extends RefCounted

## Catalog quotes in Marks (ℳ). The 13 m coastal trader is harbour-master only (StarterVessel).

static func quote_price_marks(stations: HullStations) -> int:
	if stations == null:
		return 5000
	var len_m := maxf(stations.length_m, 8.0)
	# Quadratic in length — small boats affordable, large hulls expensive.
	return int(1200.0 + len_m * len_m * 52.0)


static func commission_price(entry: Dictionary, stations: HullStations, _player: PlayerData) -> int:
	return quote_price_marks(stations)


static func price_label(price: int) -> String:
	if price <= 0:
		return "Complimentary (yard loaner)"
	return PlayerData.format_money(price)
