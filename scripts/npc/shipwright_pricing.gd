class_name ShipwrightPricing
extends RefCounted

## Catalog quotes in Marks (ℳ).

const STARTER_TRAWLER_ID := "fishing_trawler_small"


static func quote_price_marks(stations: HullStations) -> int:
	if stations == null:
		return 5000
	var len_m := maxf(stations.length_m, 8.0)
	# Quadratic in length — small boats affordable, large hulls expensive.
	return int(1200.0 + len_m * len_m * 52.0)


static func commission_price(_entry: Dictionary, stations: HullStations, _player: PlayerData) -> int:
	return quote_price_marks(stations)


static func price_label(price: int) -> String:
	return PlayerData.format_money(price)
