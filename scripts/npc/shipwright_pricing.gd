class_name ShipwrightPricing
extends RefCounted

## Catalog quotes in Marks (ℳ). Starter fishing trawler is free once per captain.

const STARTER_TRAWLER_ID := "fishing_trawler_small"


static func quote_price_marks(stations: HullStations) -> int:
	if stations == null:
		return 5000
	var len_m := maxf(stations.length_m, 8.0)
	# Quadratic in length — small boats affordable, large hulls expensive.
	return int(1200.0 + len_m * len_m * 52.0)


static func is_free_starter_trawler(entry: Dictionary, player: PlayerData) -> bool:
	if player == null:
		return false
	if player.starter_trawler_claimed:
		return false
	return str(entry.get("id", "")) == STARTER_TRAWLER_ID


static func commission_price(entry: Dictionary, stations: HullStations, player: PlayerData) -> int:
	if is_free_starter_trawler(entry, player):
		return 0
	return quote_price_marks(stations)


static func price_label(price: int) -> String:
	if price <= 0:
		return "First trawler — complimentary"
	return PlayerData.format_money(price)
