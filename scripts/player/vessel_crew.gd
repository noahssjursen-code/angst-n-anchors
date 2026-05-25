class_name VesselCrew
extends RefCounted

## Crew slots, hire candidates, and autonomous-ready checks for owned vessels.
## Stored on each owned_vessel record under `crew` (array of slot dictionaries).

const ROLE_DEFS: Array[Dictionary] = [
	{"id": "captain", "label": "Captain", "wage": 120},
	{"id": "mate", "label": "First Mate", "wage": 90},
	{"id": "engineer", "label": "Engineer", "wage": 85},
	{"id": "deckhand", "label": "Deckhand", "wage": 48},
	{"id": "bosun", "label": "Bosun", "wage": 55},
	{"id": "cook", "label": "Cook", "wage": 42},
	{"id": "crane_op", "label": "Crane Operator", "wage": 62},
	{"id": "navigator", "label": "Navigator", "wage": 75},
]

const FIRST_NAMES: PackedStringArray = [
	"Einar", "Solveig", "Magnus", "Ingrid", "Leif", "Astrid", "Bjorn", "Freya",
	"Torsten", "Helga", "Sven", "Liv", "Oskar", "Maren", "Halvard", "Runa",
	"Gunnar", "Elsa", "Stig", "Nora",
]

const LAST_NAMES: PackedStringArray = [
	"Berg", "Haugen", "Strand", "Nordvik", "Solheim", "Fjeld", "Lund", "Vik",
	"Holm", "Aas", "Ruud", "Dahl", "Nygaard", "Eide", "Bakke", "Myhre",
]


static func slot_count_for_hull(hull_id: String) -> int:
	var entry := HullRegistry.get_by_id(hull_id)
	if entry.is_empty():
		return 3
	var ship_class: int = int(entry.get("ship_class", ShipClass.Type.COASTAL_TRADER))
	return ShipClass.crew_slots(ship_class as ShipClass.Type)


static func normalize_slots(record: Dictionary, slot_count: int) -> Array:
	var raw: Variant = record.get("crew", [])
	var out: Array = []
	if typeof(raw) == TYPE_ARRAY:
		for entry in raw as Array:
			if typeof(entry) == TYPE_DICTIONARY and not (entry as Dictionary).is_empty():
				out.append((entry as Dictionary).duplicate())
			else:
				out.append({})
	while out.size() < slot_count:
		out.append({})
	if out.size() > slot_count:
		out.resize(slot_count)
	return out


static func assigned_count(crew: Array) -> int:
	var n := 0
	for slot_raw in crew:
		if typeof(slot_raw) == TYPE_DICTIONARY and not (slot_raw as Dictionary).is_empty():
			n += 1
	return n


static func total_daily_wages(crew: Array) -> int:
	var total := 0
	for slot_raw in crew:
		if typeof(slot_raw) != TYPE_DICTIONARY:
			continue
		var slot := slot_raw as Dictionary
		if slot.is_empty():
			continue
		total += int(slot.get("wage_per_day", 0))
	return total


static func all_slots_filled(crew: Array, slot_count: int) -> bool:
	return assigned_count(crew) >= slot_count


static func all_crew_paid(crew: Array) -> bool:
	for slot_raw in crew:
		if typeof(slot_raw) != TYPE_DICTIONARY:
			continue
		var slot := slot_raw as Dictionary
		if slot.is_empty():
			continue
		if not bool(slot.get("paid_current_cycle", false)):
			return false
	return true


## Future server `autonomous_active` flag — fully crewed and wages settled.
static func compute_autonomous_active(crew: Array, slot_count: int) -> bool:
	return all_slots_filled(crew, slot_count) and all_crew_paid(crew)


static func mark_all_paid(crew: Array) -> Array:
	var out: Array = []
	for slot_raw in crew:
		if typeof(slot_raw) != TYPE_DICTIONARY:
			out.append({})
			continue
		var slot := (slot_raw as Dictionary).duplicate()
		if not slot.is_empty():
			slot["paid_current_cycle"] = true
		out.append(slot)
	return out


static func clear_paid_flags(crew: Array) -> Array:
	var out: Array = []
	for slot_raw in crew:
		if typeof(slot_raw) != TYPE_DICTIONARY:
			out.append({})
			continue
		var slot := (slot_raw as Dictionary).duplicate()
		if not slot.is_empty():
			slot["paid_current_cycle"] = false
		out.append(slot)
	return out


static func generate_candidates(count: int, seed: int = -1) -> Array:
	var rng := RandomNumberGenerator.new()
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	var out: Array = []
	var used_names: Dictionary = {}
	for _i in range(maxi(count, 1)):
		out.append(_generate_one(rng, used_names))
	return out


static func employee_from_candidate(candidate: Dictionary) -> Dictionary:
	return {
		"id": str(candidate.get("id", UuidUtil.generate())),
		"name": str(candidate.get("name", "Sailor")),
		"role": str(candidate.get("role", "Deckhand")),
		"role_id": str(candidate.get("role_id", "deckhand")),
		"wage_per_day": int(candidate.get("wage_per_day", 50)),
		"paid_current_cycle": false,
		"skin": _color_to_hex(candidate.get("skin", Color(0.72, 0.55, 0.40))),
		"coat": _color_to_hex(candidate.get("coat", Color(0.18, 0.20, 0.30))),
		"pants": _color_to_hex(candidate.get("pants", Color(0.18, 0.18, 0.20))),
	}


static func colors_from_employee(employee: Dictionary) -> Dictionary:
	return {
		"skin": Color.from_string(str(employee.get("skin", "")), Color(0.72, 0.55, 0.40)),
		"coat": Color.from_string(str(employee.get("coat", "")), Color(0.18, 0.20, 0.30)),
		"pants": Color.from_string(str(employee.get("pants", "")), Color(0.18, 0.18, 0.20)),
	}


static func _generate_one(rng: RandomNumberGenerator, used_names: Dictionary) -> Dictionary:
	var role_def: Dictionary = ROLE_DEFS[rng.randi_range(0, ROLE_DEFS.size() - 1)]
	var name := ""
	for _attempt in range(12):
		var candidate_name := "%s %s" % [
			FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
			LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
		]
		if not used_names.has(candidate_name):
			name = candidate_name
			used_names[candidate_name] = true
			break
	if name.is_empty():
		name = "Crew %d" % rng.randi_range(100, 999)
	var wage_jitter := rng.randi_range(-8, 12)
	return {
		"id": UuidUtil.generate(),
		"name": name,
		"role": str(role_def.get("label", "Deckhand")),
		"role_id": str(role_def.get("id", "deckhand")),
		"wage_per_day": maxi(int(role_def.get("wage", 50)) + wage_jitter, 20),
		"skin": _random_skin(rng),
		"coat": _random_coat(rng),
		"pants": _random_pants(rng),
	}


static func _random_skin(rng: RandomNumberGenerator) -> Color:
	return Color(
		rng.randf_range(0.55, 0.82),
		rng.randf_range(0.42, 0.62),
		rng.randf_range(0.32, 0.48),
	)


static func _random_coat(rng: RandomNumberGenerator) -> Color:
	var palette: Array[Color] = [
		Color(0.15, 0.45, 0.22), Color(0.18, 0.20, 0.30), Color(0.32, 0.22, 0.16),
		Color(0.22, 0.28, 0.38), Color(0.38, 0.18, 0.16),
	]
	return palette[rng.randi_range(0, palette.size() - 1)]


static func _random_pants(rng: RandomNumberGenerator) -> Color:
	return Color(
		rng.randf_range(0.12, 0.22),
		rng.randf_range(0.12, 0.22),
		rng.randf_range(0.14, 0.26),
	)


static func _color_to_hex(c: Color) -> String:
	return c.to_html(false)
