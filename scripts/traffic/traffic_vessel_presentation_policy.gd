class_name TrafficVesselPresentationPolicy
extends RefCounted

## Pure-data interest selection for traffic presentation.
## The authority always keeps every vessel record; clients only materialize
## nearby records, with a hard full-vessel budget and deterministic ordering.


static func select(
		records: Array[Dictionary],
		observer: Vector2,
		full_radius_m: float,
		proxy_radius_m: float,
		maximum_full_vessels: int,
) -> Dictionary:
	var ranked: Array[Dictionary] = []
	for record in records:
		var point := record.get("position", Vector2.ZERO) as Vector2
		ranked.append({
			"id": str(record.get("id", "")),
			"distance_squared": point.distance_squared_to(observer),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if not is_equal_approx(float(a.distance_squared), float(b.distance_squared)):
			return float(a.distance_squared) < float(b.distance_squared)
		return str(a.id) < str(b.id)
	)
	var full_ids := PackedStringArray()
	var proxy_ids := PackedStringArray()
	var full_radius_squared := maxf(full_radius_m, 0.0) * maxf(full_radius_m, 0.0)
	var proxy_radius_squared := maxf(proxy_radius_m, full_radius_m) \
		* maxf(proxy_radius_m, full_radius_m)
	for candidate in ranked:
		var id := str(candidate.get("id", ""))
		var distance_squared := float(candidate.get("distance_squared", INF))
		if distance_squared <= full_radius_squared \
				and full_ids.size() < maxi(maximum_full_vessels, 0):
			full_ids.append(id)
		elif distance_squared <= proxy_radius_squared:
			proxy_ids.append(id)
	return {
		"full_ids": full_ids,
		"proxy_ids": proxy_ids,
		"data_only_count": maxi(records.size() - full_ids.size() - proxy_ids.size(), 0),
		"record_count": records.size(),
	}
