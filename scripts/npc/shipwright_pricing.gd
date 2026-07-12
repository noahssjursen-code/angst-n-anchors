class_name ShipwrightPricing
extends RefCounted

## Catalog quotes in Marks (ℳ).


static func quote_price_marks(stations: HullStations) -> int:
	if stations == null:
		return 5000
	var len_m := maxf(stations.length_m, 8.0)
	return int(1200.0 + len_m * len_m * 52.0)


static func commission_price(entry: Dictionary, stations: HullStations, _player: PlayerData) -> int:
	var listed := int(entry.get("price_marks", 0))
	if listed > 0:
		return listed
	return quote_price_marks(stations)


static func price_label(price: int) -> String:
	return PlayerData.format_money(price)
