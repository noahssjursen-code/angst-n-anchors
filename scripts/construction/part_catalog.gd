class_name PartCatalog
extends RefCounted

## The kit. Turns the five construction primitives into named, parametric parts a
## player can place — and turns a placed part back into the handful of facts the
## rest of the game already asks a catalog for (mass, colour, compliance tags,
## live-or-baked).
##
## A part here is DATA, not code. `build[]` is a list of primitive steps whose
## numbers may be literals or `$param` tokens, so an A-frame gallows is exactly
## "two spars and a wire" — the same thing a player assembles by hand. Nothing in
## the catalog may name a vessel; a part earns its entry by being useful across
## unrelated ship types.
##
## SCALE (CONVENTIONS §3a): every dimension is in world units, sized against the
## 1.8-unit human figure — a guardrail is 1.1 because a person is 1.8. Never
## against a hull's "display metres", which are half its drawn length.
##
## ── The five primitives ─────────────────────────────────────────────────────
##   spar        from, to, radius, [sides], [taper]     mast/post/boom/leg/stack
##   railing     path[2..], height, [post_pitch], [rails], [toe_height]
##   wire        from, to, [sag], [radius]              rigging, stays, lifelines
##   plate       corners[4], thickness                  raked screen, chine facet
##   sheer_band  path[2..], width, thickness            bulwark cap carrying sheer
##
## ── Geometry is NOT emitted here ────────────────────────────────────────────
## This catalog resolves parts to primitive specs and stops. StructureBaker owns
## triangles. It cannot draw any of the five yet, so every part currently reports
## as declared-but-unbuildable — loudly, via unbuildable_report(), never by
## silently dropping the part.
##
## A later wave lands the emitters in StructureBaker as static functions named by
## PRIMITIVES[p].emitter — `spar_boxes`, `railing_boxes`, `wire_boxes`,
## `plate_boxes`, `sheer_band_boxes` — each taking one resolved spec and
## returning the same box dictionaries `wall_boxes()` already returns
## ({center, size, basis, color, material}). Nothing in this file changes when
## they land: baker_supports() re-reads the baker's method list, so a wave that
## ships spars alone flips exactly the spar-only parts to buildable.
##
## That call site, in full:
##
##     for spec in PartCatalog.expand("gallows_a_frame", {"height": 5.0}):
##         var emitter := PartCatalog.emitter_method_for(spec["primitive"])
##         boxes.append_array(StructureBaker.call(emitter, spec))
##
## (`Script.call("static_name", …)` on the baker is verified working in
## part_catalog_test.gd against the existing `wall_boxes`, so the seam is real
## rather than hoped-for.)

const CATALOG_PATH := "res://resources/data/parts/catalog.json"
const BAKER_PATH := "res://scripts/construction/structure_baker.gd"

const DEFAULT_COLOR := Color(0.69, 0.71, 0.73)
const DEFAULT_MATERIAL := "painted"
const DEFAULT_YAW_STEP := 15
## Used only if StructureBaker's constant map cannot be read.
const FALLBACK_MATERIALS: Array[String] = ["painted", "metal", "wood", "steel"]

## The whole geometric vocabulary. `fields` types every accepted key, so a typo
## ("radius_m") is a rejected entry rather than a silently ignored number.
const PRIMITIVES: Dictionary = {
	"spar": {
		"emitter": "spar_boxes",
		"fields": {
			"from": "point", "to": "point", "radius": "scalar",
			"sides": "int", "taper": "scalar",
		},
		"required": ["from", "to", "radius"],
		"defaults": {"sides": 8, "taper": 1.0},
	},
	"railing": {
		"emitter": "railing_boxes",
		"fields": {
			"path": "points", "height": "scalar", "post_pitch": "scalar",
			"rails": "int", "toe_height": "scalar",
		},
		"required": ["path", "height"],
		"defaults": {"post_pitch": 1.6, "rails": 3, "toe_height": 0.0},
		"min_points": 2,
	},
	"wire": {
		"emitter": "wire_boxes",
		"fields": {"from": "point", "to": "point", "sag": "scalar", "radius": "scalar"},
		"required": ["from", "to"],
		"defaults": {"sag": 0.0, "radius": 0.02},
	},
	"plate": {
		"emitter": "plate_boxes",
		"fields": {"corners": "points", "thickness": "scalar"},
		"required": ["corners", "thickness"],
		"defaults": {},
		"exact_points": 4,
	},
	"sheer_band": {
		"emitter": "sheer_band_boxes",
		"fields": {"path": "points", "width": "scalar", "thickness": "scalar"},
		"required": ["path", "width", "thickness"],
		"defaults": {},
		"min_points": 2,
	},
}

## Compliance identity: the only numeric attributes VesselCompliance reads off a
## catalog entry. An unlisted key in `compliance` is a typo and is rejected —
## a mis-spelled `passenger_capactiy` that quietly counts zero is exactly the
## failure this catalog exists to make impossible.
const COMPLIANCE_NUMERICS: Dictionary = {
	"equipment_rating": "int",
	"passenger_capacity": "int",
	"hold_depth_m": "float",
}

## Tags registrations and the skin baker currently key off. Not a closed set —
## an unlisted tag warns rather than failing, so a new registration can land its
## vocabulary first. Slot tags mirror VesselCompliance.outfit_slot_for_brick().
const KNOWN_TAGS: Array[String] = [
	"mooring", "nav_white", "helm", "fishing", "trommel", "crane", "tow",
	"bulk_hold", "cargo", "light", "door", "ladder", "text", "ship_only",
]

## tag -> outfit budget slot, in the priority order VesselCompliance uses.
const SLOT_TAGS: Array = [
	["fishing", "fishing"], ["trommel", "fishing"],
	["helm", "helm"], ["crane", "crane"], ["tow", "tow"],
]

static var _entries: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()
static var _errors: PackedStringArray = PackedStringArray()
static var _warnings: PackedStringArray = PackedStringArray()
static var _ready := false
static var _baker_methods: PackedStringArray = PackedStringArray()
static var _baker_materials: PackedStringArray = PackedStringArray()
static var _baker_probed := false


# ── Loading ─────────────────────────────────────────────────────────────────

static func reload() -> void:
	_entries.clear()
	_order = PackedStringArray()
	_errors = PackedStringArray()
	_warnings = PackedStringArray()
	_ready = false
	_baker_probed = false
	ensure_loaded()


static func ensure_loaded() -> void:
	if _ready:
		return
	_ready = true
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	if file == null:
		_errors.append("PartCatalog: cannot open %s" % CATALOG_PATH)
		push_error(_errors[_errors.size() - 1])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("PartCatalog: %s is not a JSON object" % CATALOG_PATH)
		push_error(_errors[_errors.size() - 1])
		return
	var result := parse_document(parsed as Dictionary)
	_entries = result["entries"]
	_order = result["order"]
	_errors = result["errors"]
	_warnings = result["warnings"]
	for message in _errors:
		push_error("PartCatalog: %s" % message)
	for message in _warnings:
		push_warning("PartCatalog: %s" % message)


## Pure function of a parsed document — the whole validator is reachable without
## touching the filesystem, so a malformed entry can be tested directly.
## Returns {"version", "entries", "order", "errors", "warnings"}.
## An entry with ANY error is rejected outright: never half-registered, always
## named in `errors`. One bad part does not take the rest of the kit down.
static func parse_document(doc: Dictionary) -> Dictionary:
	var entries: Dictionary = {}
	var order := PackedStringArray()
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var raw_parts: Variant = doc.get("parts", null)
	if not (raw_parts is Array):
		errors.append("catalog: \"parts\" must be an array of part objects")
		return {
			"version": int(doc.get("version", 0)), "entries": entries, "order": order,
			"errors": errors, "warnings": warnings,
		}
	var index := -1
	for raw in raw_parts as Array:
		index += 1
		if not (raw is Dictionary):
			errors.append("parts[%d]: expected an object, got %s" % [index, type_string(typeof(raw))])
			continue
		var src := raw as Dictionary
		var id := str(src.get("id", "")).strip_edges()
		if id.is_empty():
			errors.append("parts[%d]: missing \"id\"" % index)
			continue
		if entries.has(id):
			errors.append("part \"%s\": duplicate id at parts[%d]" % [id, index])
			continue
		var entry_errors := PackedStringArray()
		var entry := _build_entry(id, src, entry_errors, warnings)
		if entry_errors.size() > 0:
			for message in entry_errors:
				errors.append(message)
			continue
		entries[id] = entry
		order.append(id)
	return {
		"version": int(doc.get("version", 0)), "entries": entries, "order": order,
		"errors": errors, "warnings": warnings,
	}


static func _build_entry(
	id: String, src: Dictionary, errors: PackedStringArray, warnings: PackedStringArray
) -> Dictionary:
	var entry: Dictionary = {"id": id}
	entry["display"] = str(src.get("display", id))
	entry["description"] = str(src.get("description", ""))

	var material := str(src.get("material", DEFAULT_MATERIAL))
	if not baker_materials().has(material):
		errors.append(
			"part \"%s\": unknown material \"%s\" — StructureBaker.MATERIALS has %s"
			% [id, material, ", ".join(baker_materials())]
		)
	entry["material"] = material

	var color_text := str(src.get("color", "#b0b4b8"))
	if Color.html_is_valid(color_text):
		entry["color"] = Color(color_text)
	else:
		errors.append("part \"%s\": colour \"%s\" is not a valid #rrggbb value" % [id, color_text])
		entry["color"] = DEFAULT_COLOR

	var mass := float(src.get("mass_kg", 0.0))
	if mass <= 0.0:
		errors.append("part \"%s\": mass_kg must be a positive number (got %s)" % [id, str(src.get("mass_kg", "<missing>"))])
	entry["mass_kg"] = mass
	entry["yaw_step"] = maxi(int(src.get("yaw_step", DEFAULT_YAW_STEP)), 1)

	entry["params"] = _parse_params(id, src.get("params", {}), errors)

	var compliance := _parse_compliance(id, src.get("compliance", {}), errors, warnings)
	entry["compliance"] = compliance
	entry["tags"] = compliance["tags"]
	entry["slot"] = _slot_for_tags(compliance["tags"])

	## Live-or-baked is DERIVED from the tags via VesselSkinBaker.LIVE_TAGS —
	## one source of truth. A declared "live" that disagrees is a lie about the
	## part and is rejected rather than quietly overridden.
	var live := _live_for_tags(compliance["tags"])
	entry["live"] = live
	if src.has("live") and bool(src["live"]) != live:
		errors.append(
			"part \"%s\": declares live=%s but its tags %s make it %s (VesselSkinBaker.LIVE_TAGS)"
			% [id, str(bool(src["live"])), str(compliance["tags"]), "live" if live else "baked"]
		)

	var raw_build: Variant = src.get("build", null)
	if not (raw_build is Array) or (raw_build as Array).is_empty():
		errors.append("part \"%s\": \"build\" must list at least one primitive step" % id)
		entry["build"] = []
		entry["primitives"] = PackedStringArray()
		return entry
	entry["build"] = (raw_build as Array).duplicate(true)

	var primitives := PackedStringArray()
	for step_raw in entry["build"] as Array:
		if step_raw is Dictionary:
			var name := str((step_raw as Dictionary).get("primitive", ""))
			if not primitives.has(name):
				primitives.append(name)
	primitives.sort()
	entry["primitives"] = primitives

	## Expand once with defaults: unknown primitives, missing fields, typo'd
	## field names and unresolvable $tokens all surface here, at load, naming
	## the part — not at bake time on somebody's boat.
	var probe_errors := PackedStringArray()
	var specs := _expand_entry(entry, {}, probe_errors)
	for message in probe_errors:
		errors.append(message)
	if specs.is_empty() and probe_errors.is_empty():
		errors.append("part \"%s\": build expanded to no geometry" % id)
	return entry


static func _parse_params(id: String, raw: Variant, errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	if raw == null:
		return out
	if not (raw is Dictionary):
		errors.append("part \"%s\": \"params\" must be an object of name -> default" % id)
		return out
	for key in (raw as Dictionary).keys():
		var name := str(key)
		var value: Variant = (raw as Dictionary)[key]
		var spec: Dictionary = {}
		if value is float or value is int:
			spec["default"] = float(value)
		elif value is Dictionary:
			var dict := value as Dictionary
			if not dict.has("default"):
				errors.append("part \"%s\": parameter \"%s\" has no \"default\"" % [id, name])
				continue
			spec["default"] = float(dict["default"])
			if dict.has("min"):
				spec["min"] = float(dict["min"])
			if dict.has("max"):
				spec["max"] = float(dict["max"])
			if spec.has("min") and spec.has("max") and float(spec["min"]) > float(spec["max"]):
				errors.append("part \"%s\": parameter \"%s\" has min > max" % [id, name])
			if spec.has("min") and float(spec["default"]) < float(spec["min"]):
				errors.append("part \"%s\": parameter \"%s\" default is below its min" % [id, name])
			if spec.has("max") and float(spec["default"]) > float(spec["max"]):
				errors.append("part \"%s\": parameter \"%s\" default is above its max" % [id, name])
		else:
			errors.append(
				"part \"%s\": parameter \"%s\" must be a number or {default,min,max}" % [id, name]
			)
			continue
		out[name] = spec
	return out


static func _parse_compliance(
	id: String, raw: Variant, errors: PackedStringArray, warnings: PackedStringArray
) -> Dictionary:
	var out: Dictionary = {"tags": PackedStringArray()}
	for key in COMPLIANCE_NUMERICS.keys():
		out[key] = 0 if str(COMPLIANCE_NUMERICS[key]) == "int" else 0.0
	if raw == null:
		return out
	if not (raw is Dictionary):
		errors.append("part \"%s\": \"compliance\" must be an object" % id)
		return out
	var dict := raw as Dictionary
	for key in dict.keys():
		var name := str(key)
		if name == "tags":
			continue
		if not COMPLIANCE_NUMERICS.has(name):
			errors.append(
				"part \"%s\": compliance has no attribute \"%s\" — VesselCompliance reads %s"
				% [id, name, ", ".join(PackedStringArray(COMPLIANCE_NUMERICS.keys()))]
			)
			continue
		var value: Variant = dict[name]
		if not (value is float or value is int):
			errors.append("part \"%s\": compliance.%s must be a number" % [id, name])
			continue
		out[name] = int(value) if str(COMPLIANCE_NUMERICS[name]) == "int" else float(value)
	var raw_tags: Variant = dict.get("tags", [])
	if not (raw_tags is Array):
		errors.append("part \"%s\": compliance.tags must be an array of strings" % id)
		return out
	var tags := PackedStringArray()
	for tag_raw in raw_tags as Array:
		if not (tag_raw is String):
			errors.append("part \"%s\": compliance.tags entries must be strings" % id)
			continue
		var tag := (tag_raw as String).strip_edges()
		if tag.is_empty():
			errors.append("part \"%s\": compliance.tags has an empty tag" % id)
			continue
		if tags.has(tag):
			continue
		if not KNOWN_TAGS.has(tag):
			warnings.append(
				"part \"%s\": tag \"%s\" is not in KNOWN_TAGS — nothing counts it yet" % [id, tag]
			)
		tags.append(tag)
	out["tags"] = tags
	return out


static func _slot_for_tags(tags: PackedStringArray) -> String:
	for pair in SLOT_TAGS:
		if tags.has(str((pair as Array)[0])):
			return str((pair as Array)[1])
	return ""


static func _live_for_tags(tags: PackedStringArray) -> bool:
	for tag in VesselSkinBaker.LIVE_TAGS:
		if tags.has(str(tag)):
			return true
	return false


# ── Reading the kit ─────────────────────────────────────────────────────────

static func ids() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray(_order)
	out.sort()
	return out


static func has(part_id: String) -> bool:
	ensure_loaded()
	return _entries.has(part_id.strip_edges())


static func get_entry(part_id: String) -> Dictionary:
	ensure_loaded()
	var id := part_id.strip_edges()
	if not _entries.has(id):
		return {}
	return (_entries[id] as Dictionary).duplicate(true)


static func display_name(part_id: String) -> String:
	return str(get_entry(part_id).get("display", part_id))


static func mass_kg_of(part_id: String) -> float:
	return float(get_entry(part_id).get("mass_kg", 0.0))


static func material_of(part_id: String) -> String:
	return str(get_entry(part_id).get("material", DEFAULT_MATERIAL))


static func color_of(part_id: String) -> Color:
	var entry := get_entry(part_id)
	if entry.has("color"):
		return entry["color"] as Color
	return DEFAULT_COLOR


static func yaw_step_of(part_id: String) -> int:
	return maxi(int(get_entry(part_id).get("yaw_step", DEFAULT_YAW_STEP)), 1)


static func tags_of(part_id: String) -> PackedStringArray:
	var entry := get_entry(part_id)
	if entry.has("tags"):
		return entry["tags"] as PackedStringArray
	return PackedStringArray()


static func has_tag(part_id: String, tag: String) -> bool:
	return tags_of(part_id).has(tag)


## The exact bundle VesselCompliance._measure_equipment() reads off an entry.
static func compliance_of(part_id: String) -> Dictionary:
	var entry := get_entry(part_id)
	if entry.is_empty():
		return {}
	var out: Dictionary = (entry["compliance"] as Dictionary).duplicate(true)
	out["slot"] = str(entry.get("slot", ""))
	out["live"] = bool(entry.get("live", false))
	return out


## Outfit budget slot ("fishing" / "helm" / "crane" / "tow"), or "".
static func outfit_slot_of(part_id: String) -> String:
	return str(get_entry(part_id).get("slot", ""))


## True when the part must stay a live node — helm, doors, lights, mooring and
## fishing gear are inherently interactive. Mirrors VesselSkinBaker.is_baked_brick().
static func is_live(part_id: String) -> bool:
	return bool(get_entry(part_id).get("live", false))


static func is_baked(part_id: String) -> bool:
	return has(part_id) and not is_live(part_id)


static func load_errors() -> PackedStringArray:
	ensure_loaded()
	return PackedStringArray(_errors)


static func load_warnings() -> PackedStringArray:
	ensure_loaded()
	return PackedStringArray(_warnings)


# ── Expansion: part -> primitive specs ──────────────────────────────────────

## Resolved primitive specs for a part, or [] with the reason pushed as an
## error. `overrides` supplies player-set parameter values; each is clamped to
## the parameter's declared range.
static func expand(part_id: String, overrides: Dictionary = {}) -> Array:
	var result := expand_checked(part_id, overrides)
	for message in result["errors"] as PackedStringArray:
		push_error("PartCatalog: %s" % message)
	return result["specs"]


static func expand_checked(part_id: String, overrides: Dictionary = {}) -> Dictionary:
	var errors := PackedStringArray()
	var entry := get_entry(part_id)
	if entry.is_empty():
		errors.append("no part \"%s\" in the catalog" % part_id)
		return {"specs": [], "errors": errors}
	var specs := _expand_entry(entry, overrides, errors)
	if errors.size() > 0:
		return {"specs": [], "errors": errors}
	return {"specs": specs, "errors": errors}


static func _expand_entry(
	entry: Dictionary, overrides: Dictionary, errors: PackedStringArray
) -> Array:
	var id := str(entry.get("id", "?"))
	var params := _resolve_params(entry, overrides, errors)
	var out: Array = []
	var steps: Array = entry.get("build", [])
	for i in steps.size():
		var where := "part \"%s\" build[%d]" % [id, i]
		if not (steps[i] is Dictionary):
			errors.append("%s: expected an object" % where)
			continue
		var step := steps[i] as Dictionary
		var prim := str(step.get("primitive", "")).strip_edges()
		if not PRIMITIVES.has(prim):
			errors.append(
				"%s: unknown primitive \"%s\" — the kit is %s"
				% [where, prim, ", ".join(PackedStringArray(PRIMITIVES.keys()))]
			)
			continue
		var def := PRIMITIVES[prim] as Dictionary
		var fields := def["fields"] as Dictionary
		var spec: Dictionary = {
			"primitive": prim,
			"part_id": id,
			"step": i,
			"material": str(step.get("material", entry.get("material", DEFAULT_MATERIAL))),
			"color": entry.get("color", DEFAULT_COLOR),
		}
		if step.has("color"):
			var color_text := str(step["color"])
			if Color.html_is_valid(color_text):
				spec["color"] = Color(color_text)
			else:
				errors.append("%s: colour \"%s\" is not a valid #rrggbb value" % [where, color_text])
		if not baker_materials().has(str(spec["material"])):
			errors.append(
				"%s: unknown material \"%s\" — StructureBaker.MATERIALS has %s"
				% [where, str(spec["material"]), ", ".join(baker_materials())]
			)
		for key in step.keys():
			var name := str(key)
			if name in ["primitive", "material", "color"]:
				continue
			if not fields.has(name):
				errors.append(
					"%s: primitive \"%s\" has no field \"%s\" — it takes %s"
					% [where, prim, name, ", ".join(PackedStringArray(fields.keys()))]
				)
		for key in (def["required"] as Array):
			if not step.has(str(key)):
				errors.append("%s: primitive \"%s\" requires \"%s\"" % [where, prim, str(key)])
		var defaults := def.get("defaults", {}) as Dictionary
		for key in fields.keys():
			var name := str(key)
			var value: Variant = step.get(name, defaults.get(name, null))
			if value == null:
				continue
			match str(fields[name]):
				"scalar":
					spec[name] = _resolve_scalar(value, params, "%s.%s" % [where, name], errors)
				"int":
					spec[name] = roundi(
						_resolve_scalar(value, params, "%s.%s" % [where, name], errors)
					)
				"point":
					spec[name] = _resolve_point(value, params, "%s.%s" % [where, name], errors)
				"points":
					spec[name] = _resolve_points(
						value, params, "%s.%s" % [where, name], def, errors
					)
		out.append(spec)
	return out


static func _resolve_params(
	entry: Dictionary, overrides: Dictionary, errors: PackedStringArray
) -> Dictionary:
	var id := str(entry.get("id", "?"))
	var declared := entry.get("params", {}) as Dictionary
	var out: Dictionary = {}
	for key in declared.keys():
		var name := str(key)
		var spec := declared[key] as Dictionary
		var value := float(spec.get("default", 0.0))
		if overrides.has(name):
			value = float(overrides[name])
		if spec.has("min"):
			value = maxf(value, float(spec["min"]))
		if spec.has("max"):
			value = minf(value, float(spec["max"]))
		out[name] = value
	for key in overrides.keys():
		if not declared.has(str(key)):
			errors.append(
				"part \"%s\": no parameter \"%s\" (it declares %s)"
				% [id, str(key), ", ".join(PackedStringArray(declared.keys()))]
			)
	return out


## A number, a numeric string, or a `$param` token with one optional `* / + -`
## and a literal right-hand side: "$height", "$spread*-0.5", "$height+0.16".
static func _resolve_scalar(
	value: Variant, params: Dictionary, where: String, errors: PackedStringArray
) -> float:
	if value is float or value is int:
		return float(value)
	if not (value is String):
		errors.append(
			"%s: expected a number or $param token, got %s" % [where, type_string(typeof(value))]
		)
		return 0.0
	var text := (value as String).strip_edges()
	if not text.begins_with("$"):
		if text.is_valid_float():
			return text.to_float()
		errors.append("%s: \"%s\" is neither a number nor a $param token" % [where, text])
		return 0.0
	var body := text.substr(1)
	var op := ""
	var op_index := -1
	for i in body.length():
		var chr := body[i]
		if chr == "*" or chr == "/" or chr == "+" or chr == "-":
			op = chr
			op_index = i
			break
	var name := (body if op_index < 0 else body.substr(0, op_index)).strip_edges()
	if not params.has(name):
		errors.append(
			"%s: unknown parameter \"$%s\" (the part declares %s)"
			% [where, name, ", ".join(PackedStringArray(params.keys()))]
		)
		return 0.0
	var base := float(params[name])
	if op_index < 0:
		return base
	var rhs_text := body.substr(op_index + 1).strip_edges()
	if not rhs_text.is_valid_float():
		errors.append("%s: \"%s\" is not a number after \"%s\"" % [where, rhs_text, op])
		return base
	var rhs := rhs_text.to_float()
	match op:
		"*":
			return base * rhs
		"/":
			if is_zero_approx(rhs):
				errors.append("%s: division by zero" % where)
				return base
			return base / rhs
		"+":
			return base + rhs
		"-":
			return base - rhs
	return base


static func _resolve_point(
	value: Variant, params: Dictionary, where: String, errors: PackedStringArray
) -> Vector3:
	if not (value is Array) or (value as Array).size() != 3:
		errors.append("%s: expected a point [x, y, z]" % where)
		return Vector3.ZERO
	var list := value as Array
	return Vector3(
		_resolve_scalar(list[0], params, "%s.x" % where, errors),
		_resolve_scalar(list[1], params, "%s.y" % where, errors),
		_resolve_scalar(list[2], params, "%s.z" % where, errors),
	)


static func _resolve_points(
	value: Variant,
	params: Dictionary,
	where: String,
	def: Dictionary,
	errors: PackedStringArray,
) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not (value is Array):
		errors.append("%s: expected an array of points" % where)
		return out
	var list := value as Array
	for i in list.size():
		out.append(_resolve_point(list[i], params, "%s[%d]" % [where, i], errors))
	if def.has("exact_points") and out.size() != int(def["exact_points"]):
		errors.append("%s: expected exactly %d points, got %d" % [where, int(def["exact_points"]), out.size()])
	elif def.has("min_points") and out.size() < int(def["min_points"]):
		errors.append("%s: expected at least %d points, got %d" % [where, int(def["min_points"]), out.size()])
	return out


# ── Buildability: what the baker can actually draw today ────────────────────

static func emitter_method_for(primitive: String) -> String:
	if not PRIMITIVES.has(primitive):
		return ""
	return str((PRIMITIVES[primitive] as Dictionary)["emitter"])


static func baker_supports(primitive: String) -> bool:
	var emitter := emitter_method_for(primitive)
	if emitter.is_empty():
		return false
	_probe_baker()
	return _baker_methods.has(emitter)


static func baker_materials() -> PackedStringArray:
	_probe_baker()
	return PackedStringArray(_baker_materials)


## Primitives a part needs that StructureBaker cannot emit yet.
static func missing_primitives(part_id: String) -> PackedStringArray:
	var out := PackedStringArray()
	for prim in get_entry(part_id).get("primitives", PackedStringArray()):
		if not baker_supports(str(prim)) and not out.has(str(prim)):
			out.append(str(prim))
	return out


static func is_buildable(part_id: String) -> bool:
	return has(part_id) and missing_primitives(part_id).is_empty()


static func buildable_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for id in ids():
		if is_buildable(id):
			out.append(id)
	return out


## Every loaded part the baker cannot draw yet, with the reason. A declared
## part that nothing can emit is visible here — it is never dropped on the floor.
static func unbuildable_report() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in ids():
		var missing := missing_primitives(id)
		if missing.is_empty():
			continue
		var wanted := PackedStringArray()
		for prim in missing:
			wanted.append("StructureBaker.%s()" % emitter_method_for(str(prim)))
		out.append({
			"id": id,
			"missing_primitives": missing,
			"reason": "%s needs %s — not implemented yet" % [id, ", ".join(wanted)],
		})
	return out


static func _probe_baker() -> void:
	if _baker_probed:
		return
	_baker_probed = true
	_baker_methods = PackedStringArray()
	_baker_materials = PackedStringArray(FALLBACK_MATERIALS)
	var script := load(BAKER_PATH) as Script
	if script == null:
		push_error("PartCatalog: cannot load %s — buildability is unknown" % BAKER_PATH)
		return
	for method in script.get_script_method_list():
		_baker_methods.append(str((method as Dictionary).get("name", "")))
	var materials: Variant = script.get_script_constant_map().get("MATERIALS", null)
	if materials is Dictionary:
		_baker_materials = PackedStringArray()
		for key in (materials as Dictionary).keys():
			_baker_materials.append(str(key))
