extends Node

## F6 visual inspection scene for company management. It uses inert preview
## data and never reads or mutates the active captain save.


func _ready() -> void:
	var background := ColorRect.new()
	background.color = Color(0.025, 0.05, 0.065)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var panel := CompanyPanel.new()
	panel.preview_mode = true
	add_child(panel)
	panel.call_deferred("set_preview_snapshot", _sample())


func _sample() -> Dictionary:
	var now := int(Time.get_unix_time_from_system())
	var route := {
		"id": "showcase-route",
		"origin_name": "Grønnvik",
		"destination_name": "Egersund",
		"distance_m": 14200.0,
		"pay_marks": 680,
		"outbound_commodity_id": "provisions",
		"return_commodity_id": "frozen_fish",
	}
	var underway := {
		"status": "underway",
		"route": route,
		"crew_ids": PackedStringArray(["crew-1", "crew-2", "crew-3"]),
		"completed_legs": 7,
		"revenue_marks": 4760,
		"wages_marks": 810,
		"first_departure_pending": false,
		"commodity_id": "provisions",
		"projection": {"progress": 0.43, "eta_seconds": 1140},
	}
	return {
		"name": "NORTH SEA COASTAL",
		"marks": 12840,
		"employees": [
			{"id": "crew-1", "name": "Astrid Berg", "role": "Mate", "wage_per_hour": 31},
			{"id": "crew-2", "name": "Elias Vik", "role": "Deck crew", "wage_per_hour": 24},
			{"id": "crew-3", "name": "Runa Eide", "role": "Deck crew", "wage_per_hour": 22},
		],
		"crew_candidates": [
			{"id": "crew-4", "name": "Henrik Dahl", "role": "Mate", "wage_per_hour": 29},
			{"id": "crew-5", "name": "Liv Moen", "role": "Deck crew", "wage_per_hour": 20},
		],
		"fleet": {"showcase-vessel": underway},
		"owned_vessels": [
			{
				"uid": "showcase-vessel", "name": "MS Havgast", "display": "MS Havgast",
				"required_crew": 3, "supported_route_ids": PackedStringArray(["showcase-route"]),
				"company_assignment": underway,
			},
			{
				"uid": "showcase-spare", "name": "MS Skarv", "display": "MS Skarv",
				"required_crew": 2, "supported_route_ids": PackedStringArray(["showcase-route"]),
				"company_assignment": {},
			},
		],
		"route_templates": [route],
		"ledger": [
			{"timestamp_unix": now, "amount": 680, "memo": "MS Havgast completed a freight leg"},
			{"timestamp_unix": now - 1200, "amount": -116, "memo": "MS Havgast crew paid for next leg"},
			{"timestamp_unix": now - 7200, "amount": 0, "memo": "Hired Astrid Berg"},
		],
	}
