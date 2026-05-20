class_name ShipwrightPricing
extends RefCounted

## Catalog quotes in Marks (ℳ). Coastal trader is free once per account.

const STARTER_HULL_ID := "coastal_trader"


static func quote_price_marks(stations: HullStations) -> int:
	if stations == null:
		return 5000
	var len_m := maxf(stations.length_m, 8.0)
	# Quadratic in length — small boats affordable, large hulls expensive.
	return int(1200.0 + len_m * len_m * 52.0)


static func commission_price(entry: Dictionary, stations: HullStations, player: PlayerData) -> int:
	if player != null and str(entry.get("id", "")) == STARTER_HULL_ID:
		if not player.owns_hull_id(STARTER_HULL_ID):
			return 0
	return quote_price_marks(stations)


static func price_label(price: int) -> String:
	if price <= 0:
		return "Complimentary (yard loaner)"
	return PlayerSession.format_money(price)
