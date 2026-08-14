class_name PieceKit
extends RefCounted

## THE AUTHORING LAYER. Turns a PLACED PIECE into the primitives StructureBaker
## already bakes, and nothing else. `PartCatalog` does exactly this for fittings;
## this is the same idea applied to structure, and it is deliberately a sibling
## rather than an extension — a fitting is placed with float coordinates in the
## world and a piece is placed on the deck grid, and that difference is the whole
## reason both files exist.
##
## ── The split, and why it is the load-bearing idea ──────────────────────────
##
## BAKING layer: `plate`, `spar`, `wire`, `sheer_band`. Four corners, a swept
## tube, a catenary, a swept section. General, proven, and NOT CHANGED BY THIS
## FILE. `plate` is the right RENDERING primitive.
##
## AUTHORING layer: this. `plate` is the WRONG AUTHORING UNIT, because a player
## will never type four 3D corners, and a deckhouse written as forty hand-solved
## quads is CAD however good the quads are. So a player places PIECES — standard,
## named, footprinted in cells — and the structure emerges from many placements.
## The baker only ever sees the primitives it already knows.
##
## ── The rule that makes this Minecraft and not CAD ──────────────────────────
##
##   EVERY PARAMETER TAKES ITS VALUE FROM A DECLARED FINITE SET, AND EVERY
##   GEOMETRIC PARAMETER IS COUNTED IN GRID UNITS.
##
## Extents — span, depth, height, sill, band — are whole CELLS (0.5 m). The five
## parameters that TRIM a piece off that lattice — `rake`, `head`, `fall`,
## `lift`, `offset` — are whole EIGHTH-CELLS (0.125 m), which is where the fleet's
## worst wall-rake quantisation error (0.062 m) first falls under the kit's own
## 0.10 m plating; see the kit file's `_what_this_is` for the measurement and for
## why the next halving is not taken. Everything else is a named choice. NOTE the
## inherited naming defect: `quarter_cells` counted 0.25 m, which is HALF a cell —
## the ordinals count fractions of a METRE, and `eighth_cells` keeps the series.
## A value off the declared set is
## REJECTED, not clamped: clamping a 7 to a 6 silently builds something the
## player did not ask for, and a kit whose pieces quietly change size is worse
## than one that refuses.
##
## The pay-off is mechanical and it is what `piece_kit_test.gd` checks: two
## pieces placed side by side on the same line at the same rake have IDENTICAL
## shared corners, to the bit. No slot of daylight can open between them, ever,
## because there is no float for a player to get slightly wrong.
##
## ── Placement ───────────────────────────────────────────────────────────────
##
## A piece is placed at a grid NODE, not in a cell. Cells are 0.5 m volumes;
## walls stand on the LINES BETWEEN them. `cell` is [x, y, z] in whole cells and
## resolves to plan metres by multiplying by `WorldUnits.DECK_CELL_M`.
##
## The piece-local frame is: +X along the run, +Y up, and THE OUTWARD FACE
## TOWARD -Z. `facing` yaws it by 0/90/180/270 degrees, so:
##
##     facing   0 -> outward -Z (forward)      90 -> outward -X (port)
##            180 -> outward +Z (aft)         270 -> outward +X (starboard)
##
## Nothing is ever placed at 45 degrees. `corner_45` carries its own 45-degree
## chord internally, which is why the placement grid stays square. A wall run at
## 45 degrees in plan is a declared gap, not an oversight.
##
## ── What comes out ──────────────────────────────────────────────────────────
##
## `resolve_placement()` returns plan `items[]` dictionaries — `at` in plan
## metres, `yaw` in degrees, `props.primitive == "plate"` and `props.corners` in
## PIECE-LOCAL metres. `StructureBaker._item_layers` multiplies the two exactly
## as it already does for a hand-authored plate. No baker change, no plan change.
##
## `resolve_document()` does the same for a whole `structure_plan_v1` document
## carrying a `pieces[]` array: pieces in, `items[]` out, and the document that
## comes back is an ordinary plan `StructurePlan.from_dict()` reads unchanged.
##
## ── Two general mechanisms, and no third ────────────────────────────────────
##
## The kit is DATA. `piece_kit.gd` contains no piece names and no `if id == ...`;
## everything a piece needs to say, it says in `structure_pieces.json` through:
##
##   1. LINEAR EXPRESSIONS over the numeric parameters — "span*0.5",
##      "rake*-0.25*sill/height", "span*0.25-0.425". A tiny recursive-descent
##      parser, not `Expression`, because `Expression` would let a piece run
##      arbitrary code out of a data file.
##   2. `{"$choice": "<param>", "<value>": <data>}` ANYWHERE in the build tree —
##      resolves to the branch the parameter selects. A whole build step list may
##      be a $choice, which is how one `trim_band` carries four profiles.
##
## plus `"repeat": "<expr>"` on a step, which emits it N times with `i` bound to
## 0..N-1. That is what draws N-1 mullions across a window band without the kit
## needing a mullion piece.
##
## …and `derived`, which is NOT a third mechanism but the deletion of a second
## copy. A piece may name sub-expressions — `"v_plate": "(v_top+v_far)*0.5"` —
## and use the name anywhere an expression is legal. It exists because
## `wall_panel`'s door has to say the SAME formula twice: once as the opening's
## own height and once as the constraint that keeps that height inside the plate.
## Two copies of a formula drift, and this project has deleted the second
## derivation four times already (REALITY.md §3b). Derived names are evaluated in
## declaration order, may refer to earlier ones, and may not shadow a parameter.
##
## The expression language grew `sqrt()` and `abs()` for the same door. A raked
## wall's surface length is Pythagorean — `sqrt(rise² + rake²)` — and an opening
## is measured ALONG that surface, so the vertical clearance under a 1.95 m hole
## in a wall raked 1.0 m over 2.5 m is 1.81 m, not 1.95 m. Without a square root
## the kit could not say that, and what it could not say it did not check: the
## door's own stepper ran to a rake whose doorway a 1.8 m player cannot enter.
## The same gap is why `corner_45` carries the literal 0.08838834764831845
## (= 0.125/√2) instead of writing what it means.
##
## A piece may also declare `constraints`: relationships BETWEEN its parameters
## that a per-parameter value set cannot say. Two legal values can still make an
## illegal piece — a glazed panel whose coaming and glass together fill its whole
## height has no header left and resolves to a zero-height quad. That is refused
## in the piece's own words rather than drawn as a degenerate plate.

const KIT_PATH := "res://resources/data/parts/structure_pieces.json"
const BAKER_PATH := "res://scripts/construction/structure_baker.gd"

const DEFAULT_MATERIAL := "painted"
const DEFAULT_COLOR := Color(0.89, 0.88, 0.83)
## Used only if StructureBaker's constant map cannot be read.
const FALLBACK_MATERIALS: Array[String] = ["painted", "metal", "wood", "steel"]

## Facings a piece may be placed at. Multiples of 90 only — see the header.
const FACINGS: Array[int] = [0, 90, 180, 270]

## The geometry a piece may resolve to. A piece emits BAKING-LAYER primitives and
## nothing else; `fields` types every accepted key so a typo ("thicknes") is a
## rejected piece rather than a silently defaulted plate.
const PRIMITIVES: Dictionary = {
	"plate": {
		"fields": {
			"corners": "points", "thickness": "scalar", "segments": "int",
			"openings": "openings",
		},
		"required": ["corners", "thickness"],
		"exact_points": 4,
	},
}

## Opening rectangles on a plate surface, in metres. Same four names the baker's
## `plate_openings` reads, plus the `type` it uses to pick a casing.
const OPENING_FIELDS: Dictionary = {
	"type": "text", "offset": "scalar", "width": "scalar",
	"sill": "scalar", "height": "scalar",
}
const OPENING_TYPES: Array[String] = ["door", "window", "hatch"]

## Parameter units. `cells` (0.5 m), `quarter_cells` (0.25 m, version 1's misnamed
## half-cell, kept so an old document still reads) and `eighth_cells` (0.125 m)
## are the grid; `count` is a plain integer; `choice` is a named string. There is
## no "float" unit and there will not be one — see the header.
const PARAM_UNITS: Array[String] = ["cells", "quarter_cells", "eighth_cells", "count", "choice"]

## The only functions an expression may call. One argument each, no side effects,
## no engine reach — the same reason the parser is hand-written rather than
## Godot's `Expression`. `sqrt` is here because a raked wall's surface length is
## Pythagorean and an opening is measured along that surface; `abs` because
## `fall` is signed and what a falling head costs a doorway does not care which
## way it falls.
const FUNCTIONS: Array[String] = ["sqrt", "abs"]

static var _pieces: Dictionary = {}
static var _order: PackedStringArray = PackedStringArray()
static var _errors: PackedStringArray = PackedStringArray()
static var _warnings: PackedStringArray = PackedStringArray()
static var _ready := false
static var _baker_materials: PackedStringArray = PackedStringArray()
static var _baker_probed := false


# ── Loading ─────────────────────────────────────────────────────────────────

static func reload() -> void:
	_pieces.clear()
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
	var file := FileAccess.open(KIT_PATH, FileAccess.READ)
	if file == null:
		_errors.append("PieceKit: cannot open %s" % KIT_PATH)
		push_error(_errors[_errors.size() - 1])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		_errors.append("PieceKit: %s is not a JSON object" % KIT_PATH)
		push_error(_errors[_errors.size() - 1])
		return
	var result := parse_document(parsed as Dictionary)
	_pieces = result["pieces"]
	_order = result["order"]
	_errors = result["errors"]
	_warnings = result["warnings"]
	for message in _errors:
		push_error("PieceKit: %s" % message)
	for message in _warnings:
		push_warning("PieceKit: %s" % message)


## Pure function of a parsed document, so a malformed kit is testable without
## touching the filesystem. Returns {"version","cell_m","pieces","order",
## "errors","warnings"}. A piece with ANY error is rejected outright and named;
## one bad piece never takes the rest of the kit down.
static func parse_document(doc: Dictionary) -> Dictionary:
	var pieces: Dictionary = {}
	var order := PackedStringArray()
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var cell_m := float(doc.get("cell_m", WorldUnits.DECK_CELL_M))
	if not is_equal_approx(cell_m, WorldUnits.DECK_CELL_M):
		errors.append(
			"kit: cell_m is %.4f but WorldUnits.DECK_CELL_M is %.4f — the kit and the grid must agree"
			% [cell_m, WorldUnits.DECK_CELL_M]
		)
	var raw: Variant = doc.get("pieces", null)
	if not (raw is Array):
		errors.append("kit: \"pieces\" must be an array of piece objects")
		return {
			"version": int(doc.get("version", 0)), "cell_m": cell_m, "pieces": pieces,
			"order": order, "errors": errors, "warnings": warnings,
		}
	var index := -1
	for entry_raw in raw as Array:
		index += 1
		if not (entry_raw is Dictionary):
			errors.append("pieces[%d]: expected an object" % index)
			continue
		var src := entry_raw as Dictionary
		var id := str(src.get("id", "")).strip_edges()
		if id.is_empty():
			errors.append("pieces[%d]: missing \"id\"" % index)
			continue
		if pieces.has(id):
			errors.append("piece \"%s\": duplicate id at pieces[%d]" % [id, index])
			continue
		var piece_errors := PackedStringArray()
		var piece := _build_piece(id, src, piece_errors, warnings)
		if piece_errors.size() > 0:
			for message in piece_errors:
				errors.append(message)
			continue
		pieces[id] = piece
		order.append(id)
	return {
		"version": int(doc.get("version", 0)), "cell_m": cell_m, "pieces": pieces,
		"order": order, "errors": errors, "warnings": warnings,
	}


static func _build_piece(
	id: String, src: Dictionary, errors: PackedStringArray, warnings: PackedStringArray
) -> Dictionary:
	var piece: Dictionary = {"id": id}
	piece["display"] = str(src.get("display", id))
	piece["description"] = str(src.get("description", ""))

	var material := str(src.get("material", DEFAULT_MATERIAL))
	if not baker_materials().has(material):
		errors.append(
			"piece \"%s\": unknown material \"%s\" — StructureBaker.MATERIALS has %s"
			% [id, material, ", ".join(baker_materials())]
		)
	piece["material"] = material

	var color_text := str(src.get("color", "#e3e0d4"))
	if Color.html_is_valid(color_text):
		piece["color"] = Color(color_text)
	else:
		errors.append("piece \"%s\": colour \"%s\" is not a valid #rrggbb value" % [id, color_text])
		piece["color"] = DEFAULT_COLOR

	piece["params"] = _parse_params(id, src.get("params", {}), errors)
	piece["derived"] = _parse_derived(id, src.get("derived", null), piece["params"], errors)
	piece["footprint"] = _parse_footprint(
		id, src.get("footprint", {}), piece["params"], piece["derived"], errors
	)
	piece["constraints"] = _parse_constraints(
		id, src.get("constraints", []), piece["params"], piece["derived"], errors
	)

	var build: Variant = src.get("build", null)
	if build == null:
		errors.append("piece \"%s\": missing \"build\"" % id)
		return piece
	piece["build"] = build

	## Expand once at EVERY combination of choice values, numerics at their
	## defaults. An unresolvable name, a mistyped field, an unknown primitive or a
	## degenerate plate surfaces HERE, at load, naming the piece — never at bake
	## time on somebody's boat. Walking all the choices is the point: a
	## `trim_band` profile that resolves to a zero-area quad cannot hide behind a
	## default that happens to be fine.
	var probes := _choice_combinations(piece["params"] as Dictionary)
	for probe in probes:
		var probe_errors := PackedStringArray()
		var specs := _expand(piece, probe as Dictionary, probe_errors)
		for message in probe_errors:
			errors.append(message)
		if specs.is_empty() and probe_errors.is_empty():
			errors.append("piece \"%s\": build expanded to no geometry at %s" % [id, str(probe)])
		for spec_variant in specs:
			var problem := _plate_problem(spec_variant as Dictionary)
			if not problem.is_empty():
				errors.append("piece \"%s\" at %s: %s" % [id, str(probe), problem])
	return piece


static func _parse_params(id: String, raw: Variant, errors: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	if raw == null:
		return out
	if not (raw is Dictionary):
		errors.append("piece \"%s\": \"params\" must be an object of name -> spec" % id)
		return out
	for key in (raw as Dictionary).keys():
		var name := str(key)
		if name.begins_with("_"):
			continue
		var value: Variant = (raw as Dictionary)[key]
		if not (value is Dictionary):
			errors.append(
				"piece \"%s\": parameter \"%s\" must be {unit, values, default} — a bare number"
				% [id, name] + " would be a free value, and the kit has none"
			)
			continue
		var dict := value as Dictionary
		var unit := str(dict.get("unit", ""))
		if not PARAM_UNITS.has(unit):
			errors.append(
				"piece \"%s\": parameter \"%s\" has unit \"%s\" — the kit knows %s"
				% [id, name, unit, ", ".join(PackedStringArray(PARAM_UNITS))]
			)
			continue
		var raw_values: Variant = dict.get("values", null)
		if not (raw_values is Array) or (raw_values as Array).is_empty():
			errors.append(
				"piece \"%s\": parameter \"%s\" must declare a non-empty \"values\" set"
				% [id, name]
			)
			continue
		var values: Array = []
		var numeric := unit != "choice"
		for item in raw_values as Array:
			if numeric:
				if not (item is float or item is int):
					errors.append(
						"piece \"%s\": parameter \"%s\" is %s, so its values must be whole numbers"
						% [id, name, unit]
					)
					continue
				var as_int := int(item)
				if not is_equal_approx(float(as_int), float(item)):
					errors.append(
						"piece \"%s\": parameter \"%s\" value %s is not a whole %s"
						% [id, name, str(item), unit]
					)
					continue
				values.append(as_int)
			else:
				if not (item is String):
					errors.append(
						"piece \"%s\": parameter \"%s\" is a choice, so its values must be strings"
						% [id, name]
					)
					continue
				values.append(str(item))
		if values.is_empty():
			continue
		var default_value: Variant = dict.get("default", values[0])
		if numeric:
			default_value = int(default_value) if (default_value is float or default_value is int) else null
		else:
			default_value = str(default_value) if default_value is String else null
		if default_value == null or not values.has(default_value):
			errors.append(
				"piece \"%s\": parameter \"%s\" default %s is not in its values %s"
				% [id, name, str(dict.get("default", "<missing>")), str(values)]
			)
			continue
		out[name] = {"unit": unit, "values": values, "default": default_value, "numeric": numeric}
	return out


## NAMED SUB-EXPRESSIONS, evaluated in declaration order and usable anywhere an
## expression is legal. This is not a new way for a piece to say something — it
## is the way to say something ONCE. `wall_panel`'s door needs its opening height
## and the constraint that keeps that opening inside the plate to be the same
## formula; written twice they drift, and a drifted constraint stops guarding the
## clamp it was written for while still passing (REALITY.md §3b, §4a).
##
## A derived name may not shadow a parameter — a reader seeing `rake` in an
## expression must be able to trust it is the stepper value — and may not be
## `i`, which belongs to `repeat`.
static func _parse_derived(
	id: String, raw: Variant, params: Dictionary, errors: PackedStringArray
) -> Array:
	var out: Array = []
	if raw == null:
		return out
	if not (raw is Dictionary):
		errors.append("piece \"%s\": \"derived\" must be an object of name -> expression" % id)
		return out
	var scope := _numeric_defaults(params)
	for key in (raw as Dictionary).keys():
		var name := str(key)
		if name.begins_with("_"):
			continue
		if params.has(name):
			errors.append(
				"piece \"%s\": derived \"%s\" shadows a parameter of the same name" % [id, name]
			)
			continue
		if name == "i" or FUNCTIONS.has(name):
			errors.append("piece \"%s\": derived \"%s\" is a reserved name" % [id, name])
			continue
		if not _is_name_start(name[0]):
			errors.append("piece \"%s\": derived \"%s\" is not a legal name" % [id, name])
			continue
		var expr: Variant = (raw as Dictionary)[key]
		if expr is Dictionary:
			errors.append(
				"piece \"%s\": derived \"%s\" must be a plain expression — $choice belongs in"
				% [id, name] + " \"build\" or in a constraint, where the branch is what varies"
			)
			continue
		var where := "piece \"%s\" derived.%s" % [id, name]
		scope[name] = _eval(expr, scope, where, errors)
		out.append({"name": name, "expr": expr})
	return out


## `numeric` plus every derived value, in order. Every place that builds a
## parameter bag runs through here, so a derived name resolves identically at
## load, in a constraint, in a footprint and in the build tree.
static func _with_derived(
	derived: Array, numeric: Dictionary, where: String, errors: PackedStringArray
) -> Dictionary:
	if derived.is_empty():
		return numeric
	var out := numeric.duplicate()
	for entry_variant in derived:
		var entry := entry_variant as Dictionary
		var name := str(entry["name"])
		out[name] = _eval(entry["expr"], out, "%s derived.%s" % [where, name], errors)
	return out


## A piece's size on the grid, in CELLS, as expressions over its own parameters.
## Declared rather than derived so a placement tool can reserve the footprint
## before any geometry is resolved.
static func _parse_footprint(
	id: String, raw: Variant, params: Dictionary, derived: Array, errors: PackedStringArray
) -> Dictionary:
	var out: Dictionary = {"run": 0, "depth": 0, "rise": 0}
	if not (raw is Dictionary):
		errors.append("piece \"%s\": \"footprint\" must be {run, depth, rise} in cells" % id)
		return out
	var numeric := _with_derived(
		derived, _numeric_defaults(params), "piece \"%s\" footprint" % id, errors
	)
	for key in ["run", "depth", "rise"]:
		var value: Variant = (raw as Dictionary).get(key, 0)
		## Stored RAW — a footprint is an expression over the piece's own
		## parameters, so `wall_panel` at span 8 must report 8 and not the 4 its
		## default happens to be. Evaluated here only to reject a bad expression.
		var _probe := _eval(value, numeric, "piece \"%s\" footprint.%s" % [id, key], errors)
		out[key] = value
	return out


## Relationships BETWEEN a piece's parameters, which a per-parameter value set
## cannot express: a glazed panel whose coaming and glass band together fill its
## whole height has no header left, and that is a legal pick of two legal values.
## Each entry is {expr, min, _is}; a setting whose expression falls under `min`
## is refused with the piece's own words.
##
## An `expr` may itself be a `{"$choice": ...}` — the SAME mechanism the build
## tree carries, and it is here for the case a per-parameter set cannot reach at
## all: what a legal `span` is DEPENDS on which `opening` was picked. A 1.20 m
## door needs three cells and a 0.40 m scuttle needs one, and neither the span
## set nor the opening set can say so alone. Every choice combination is walked
## at load, so a branch that names a parameter the piece does not have, or that
## is violated by the piece's own defaults, is a rejected piece rather than a
## clamp on somebody's boat.
static func _parse_constraints(
	id: String, raw: Variant, params: Dictionary, derived: Array, errors: PackedStringArray
) -> Array:
	var out: Array = []
	if raw == null:
		return out
	if not (raw is Array):
		errors.append("piece \"%s\": \"constraints\" must be an array" % id)
		return out
	var numeric := _with_derived(
		derived, _numeric_defaults(params), "piece \"%s\" constraints" % id, errors
	)
	var index := -1
	for entry_raw in raw as Array:
		index += 1
		if not (entry_raw is Dictionary):
			errors.append("piece \"%s\": constraints[%d] must be an object" % [id, index])
			continue
		var entry := entry_raw as Dictionary
		if not entry.has("expr"):
			errors.append("piece \"%s\": constraints[%d] needs an \"expr\"" % [id, index])
			continue
		var where := "piece \"%s\" constraints[%d].expr" % [id, index]
		var probe_errors := PackedStringArray()
		for probe_variant in _choice_combinations(params):
			var choices: Dictionary = {}
			for key in (probe_variant as Dictionary).keys():
				var value: Variant = (probe_variant as Dictionary)[key]
				if value is String:
					choices[str(key)] = str(value)
			var branch: Variant = _choose(entry["expr"], choices, where, probe_errors)
			var _probe := _eval(branch, numeric, where, probe_errors)
		for message in probe_errors:
			errors.append(message)
		var default_choices: Dictionary = {}
		for key in params.keys():
			var spec := params[key] as Dictionary
			if not bool(spec.get("numeric", false)):
				default_choices[str(key)] = str(spec["default"])
		var at_defaults := _eval(
			_choose(entry["expr"], default_choices, where, probe_errors), numeric, where,
			PackedStringArray()
		)
		if at_defaults < float(entry.get("min", 0.0)) - 1e-6:
			errors.append(
				"piece \"%s\": constraints[%d] is already violated by the piece's own defaults"
				% [id, index]
			)
		out.append({
			"expr": entry["expr"],
			"min": float(entry.get("min", 0.0)),
			"why": str(entry.get("_is", "")),
		})
	return out


static func _numeric_defaults(params: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key in params.keys():
		var spec := params[key] as Dictionary
		if bool(spec.get("numeric", false)):
			out[str(key)] = float(spec["default"])
	return out


## Every combination of the piece's CHOICE parameters, numerics at default. The
## load-time probe walks all of them, so a `trim_band` profile that resolves to a
## degenerate plate cannot hide behind a default that happens to be fine.
static func _choice_combinations(params: Dictionary) -> Array:
	var base: Dictionary = {}
	for key in params.keys():
		var numeric_spec := params[key] as Dictionary
		if bool(numeric_spec.get("numeric", false)):
			base[str(key)] = numeric_spec["default"]
	var combos: Array = [base]
	for key in params.keys():
		var spec := params[key] as Dictionary
		if bool(spec.get("numeric", false)):
			continue
		var grown: Array = []
		for combo_variant in combos:
			for value in spec["values"] as Array:
				var next := (combo_variant as Dictionary).duplicate()
				next[str(key)] = value
				grown.append(next)
		combos = grown
	return combos


# ── Reading the kit ─────────────────────────────────────────────────────────

static func ids() -> PackedStringArray:
	ensure_loaded()
	var out := PackedStringArray(_order)
	out.sort()
	return out


static func has(piece_id: String) -> bool:
	ensure_loaded()
	return _pieces.has(piece_id.strip_edges())


static func get_piece(piece_id: String) -> Dictionary:
	ensure_loaded()
	var id := piece_id.strip_edges()
	if not _pieces.has(id):
		return {}
	return (_pieces[id] as Dictionary).duplicate(true)


static func display_name(piece_id: String) -> String:
	return str(get_piece(piece_id).get("display", piece_id))


## Declared parameters: name -> {unit, values, default, numeric}.
static func params_of(piece_id: String) -> Dictionary:
	return get_piece(piece_id).get("params", {}) as Dictionary


static func load_errors() -> PackedStringArray:
	ensure_loaded()
	return PackedStringArray(_errors)


static func load_warnings() -> PackedStringArray:
	ensure_loaded()
	return PackedStringArray(_warnings)


static func baker_materials() -> PackedStringArray:
	if not _baker_probed:
		_baker_probed = true
		_baker_materials = PackedStringArray(FALLBACK_MATERIALS)
		var script := load(BAKER_PATH) as Script
		if script != null:
			var materials: Variant = script.get_script_constant_map().get("MATERIALS", null)
			if materials is Dictionary:
				_baker_materials = PackedStringArray()
				for key in (materials as Dictionary).keys():
					_baker_materials.append(str(key))
	return PackedStringArray(_baker_materials)


# ── Parameters: a value is on the declared set or it is refused ─────────────

## Player-supplied values -> the resolved parameter bag, or errors naming what
## was refused. NOT clamped: see the header.
static func resolve_params(piece_id: String, given: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var out: Dictionary = {}
	var piece := get_piece(piece_id)
	if piece.is_empty():
		errors.append("no piece \"%s\" in the kit" % piece_id)
		return {"params": out, "errors": errors}
	var declared := piece["params"] as Dictionary
	for key in declared.keys():
		var spec := declared[key] as Dictionary
		out[str(key)] = spec["default"]
	for key in given.keys():
		var name := str(key)
		if name.begins_with("_"):
			continue
		if not declared.has(name):
			errors.append(
				"piece \"%s\": no parameter \"%s\" (it declares %s)"
				% [piece_id, name, ", ".join(PackedStringArray(declared.keys()))]
			)
			continue
		var spec := declared[name] as Dictionary
		var values := spec["values"] as Array
		var value: Variant = given[key]
		if bool(spec["numeric"]):
			if not (value is float or value is int):
				errors.append(
					"piece \"%s\": parameter \"%s\" is %s and needs a whole number, got %s"
					% [piece_id, name, str(spec["unit"]), type_string(typeof(value))]
				)
				continue
			value = int(value)
		else:
			if not (value is String):
				errors.append(
					"piece \"%s\": parameter \"%s\" is a choice and needs a string, got %s"
					% [piece_id, name, type_string(typeof(value))]
				)
				continue
			value = str(value)
		if not values.has(value):
			errors.append(
				"piece \"%s\": parameter \"%s\" = %s is not one of %s — the kit has no free values"
				% [piece_id, name, str(value), str(values)]
			)
			continue
		out[name] = value
	if errors.is_empty():
		var numeric: Dictionary = {}
		var picked: Dictionary = {}
		for key in out.keys():
			var value: Variant = out[key]
			if value is int or value is float:
				numeric[str(key)] = float(value)
			elif value is String:
				picked[str(key)] = str(value)
		numeric = _with_derived(
			piece.get("derived", []) as Array, numeric, "piece \"%s\"" % piece_id, errors
		)
		for constraint_variant in piece.get("constraints", []) as Array:
			var constraint := constraint_variant as Dictionary
			var where := "piece \"%s\" constraint" % piece_id
			## $choice FIRST: WHICH relationship applies can itself depend on a
			## choice parameter — see _parse_constraints.
			var expr: Variant = _choose(constraint["expr"], picked, where, errors)
			var value := _eval(expr, numeric, where, errors)
			if value < float(constraint["min"]) - 1e-6:
				errors.append(
					"piece \"%s\": %s = %s, which is under %s — %s"
					% [
						piece_id, str(expr), str(value), str(constraint["min"]),
						str(constraint["why"]),
					]
				)
	return {"params": out, "errors": errors}


## Footprint in CELLS at a given parameter setting, as (run, rise, depth) — the
## same axis order as the piece-local frame, so a placement tool can reserve the
## grid a piece will occupy before any geometry is resolved.
static func footprint_cells(piece_id: String, given: Dictionary = {}) -> Vector3i:
	var piece := get_piece(piece_id)
	if piece.is_empty():
		return Vector3i.ZERO
	var resolved := resolve_params(piece_id, given)
	var numeric: Dictionary = {}
	for key in (resolved["params"] as Dictionary).keys():
		var value: Variant = (resolved["params"] as Dictionary)[key]
		if value is int or value is float:
			numeric[str(key)] = float(value)
	var errors := PackedStringArray()
	numeric = _with_derived(
		piece.get("derived", []) as Array, numeric, "piece \"%s\" footprint" % piece_id, errors
	)
	var foot := piece["footprint"] as Dictionary
	return Vector3i(
		roundi(_eval(foot["run"], numeric, "footprint.run", errors)),
		roundi(_eval(foot["rise"], numeric, "footprint.rise", errors)),
		roundi(_eval(foot["depth"], numeric, "footprint.depth", errors))
	)


# ── Resolution: a piece -> primitive specs in PIECE-LOCAL metres ────────────

## Primitive specs for one piece at one parameter setting. Returns
## {"specs", "errors"}; `specs` is empty when anything was refused.
static func resolve(piece_id: String, given: Dictionary = {}) -> Dictionary:
	var piece := get_piece(piece_id)
	if piece.is_empty():
		return {"specs": [], "errors": PackedStringArray(["no piece \"%s\" in the kit" % piece_id])}
	var resolved := resolve_params(piece_id, given)
	var errors := resolved["errors"] as PackedStringArray
	if errors.size() > 0:
		return {"specs": [], "errors": errors}
	var specs := _expand(piece, resolved["params"] as Dictionary, errors)
	for spec_variant in specs:
		var problem := _plate_problem(spec_variant as Dictionary)
		if not problem.is_empty():
			errors.append("piece \"%s\": %s" % [piece_id, problem])
	if errors.size() > 0:
		return {"specs": [], "errors": errors}
	return {"specs": specs, "errors": errors}


static func _expand(piece: Dictionary, params: Dictionary, errors: PackedStringArray) -> Array:
	var id := str(piece.get("id", "?"))
	var numeric: Dictionary = {}
	var choices: Dictionary = {}
	for key in params.keys():
		var value: Variant = params[key]
		if value is int or value is float:
			numeric[str(key)] = float(value)
		else:
			choices[str(key)] = str(value)
	numeric = _with_derived(
		piece.get("derived", []) as Array, numeric, "piece \"%s\" build" % id, errors
	)
	var steps_raw: Variant = _choose(
		piece.get("build", null), choices, "piece \"%s\" build" % id, errors
	)
	if not (steps_raw is Array):
		errors.append("piece \"%s\": build must resolve to an array of steps" % id)
		return []
	var out: Array = []
	var steps := steps_raw as Array
	for i in steps.size():
		var where := "piece \"%s\" build[%d]" % [id, i]
		var step_raw: Variant = _choose(steps[i], choices, where, errors)
		if not (step_raw is Dictionary):
			errors.append("%s: expected an object" % where)
			continue
		var step := step_raw as Dictionary
		var count := 1
		if step.has("repeat"):
			count = roundi(_eval(step["repeat"], numeric, "%s.repeat" % where, errors))
			if count < 0:
				errors.append("%s: repeat resolved to %d" % [where, count])
				count = 0
		for index in count:
			var scope := numeric.duplicate()
			if step.has("repeat"):
				scope["i"] = float(index)
			var spec := _expand_step(id, step, scope, choices, where, errors)
			if not spec.is_empty():
				out.append(spec)
	return out


static func _expand_step(
	id: String,
	step: Dictionary,
	numeric: Dictionary,
	choices: Dictionary,
	where: String,
	errors: PackedStringArray,
) -> Dictionary:
	var prim := str(step.get("primitive", "")).strip_edges()
	if not PRIMITIVES.has(prim):
		errors.append(
			"%s: unknown primitive \"%s\" — a piece may only resolve to %s"
			% [where, prim, ", ".join(PackedStringArray(PRIMITIVES.keys()))]
		)
		return {}
	var def := PRIMITIVES[prim] as Dictionary
	var fields := def["fields"] as Dictionary
	var spec: Dictionary = {"primitive": prim, "piece_id": id}
	spec["material"] = str(step.get("material", DEFAULT_MATERIAL))
	if not baker_materials().has(str(spec["material"])):
		errors.append(
			"%s: unknown material \"%s\" — StructureBaker.MATERIALS has %s"
			% [where, str(spec["material"]), ", ".join(baker_materials())]
		)
	if step.has("color"):
		var color_text := str(_choose(step["color"], choices, "%s.color" % where, errors))
		if Color.html_is_valid(color_text):
			spec["color"] = Color(color_text)
		else:
			errors.append("%s: colour \"%s\" is not a valid #rrggbb value" % [where, color_text])
	for key in step.keys():
		var name := str(key)
		if name.begins_with("_") or name in ["primitive", "material", "color", "repeat"]:
			continue
		if not fields.has(name):
			errors.append(
				"%s: primitive \"%s\" has no field \"%s\" — it takes %s"
				% [where, prim, name, ", ".join(PackedStringArray(fields.keys()))]
			)
	for key in def["required"] as Array:
		if not step.has(str(key)):
			errors.append("%s: primitive \"%s\" requires \"%s\"" % [where, prim, str(key)])
			return {}
	for key in fields.keys():
		var name := str(key)
		if not step.has(name):
			continue
		var raw: Variant = _choose(step[name], choices, "%s.%s" % [where, name], errors)
		match str(fields[name]):
			"scalar":
				spec[name] = _eval(raw, numeric, "%s.%s" % [where, name], errors)
			"int":
				spec[name] = roundi(_eval(raw, numeric, "%s.%s" % [where, name], errors))
			"points":
				spec[name] = _eval_points(raw, numeric, def, "%s.%s" % [where, name], errors)
			"openings":
				spec[name] = _eval_openings(raw, numeric, choices, "%s.%s" % [where, name], errors)
	return spec


static func _eval_points(
	raw: Variant, numeric: Dictionary, def: Dictionary, where: String, errors: PackedStringArray
) -> PackedVector3Array:
	var out := PackedVector3Array()
	if not (raw is Array):
		errors.append("%s: expected an array of points" % where)
		return out
	var list := raw as Array
	for i in list.size():
		var point: Variant = list[i]
		if not (point is Array) or (point as Array).size() != 3:
			errors.append("%s[%d]: expected [x, y, z]" % [where, i])
			continue
		var triple := point as Array
		out.append(Vector3(
			_eval(triple[0], numeric, "%s[%d].x" % [where, i], errors),
			_eval(triple[1], numeric, "%s[%d].y" % [where, i], errors),
			_eval(triple[2], numeric, "%s[%d].z" % [where, i], errors),
		))
	if def.has("exact_points") and out.size() != int(def["exact_points"]):
		errors.append(
			"%s: expected exactly %d points, got %d" % [where, int(def["exact_points"]), out.size()]
		)
	return out


static func _eval_openings(
	raw: Variant, numeric: Dictionary, choices: Dictionary, where: String, errors: PackedStringArray
) -> Array:
	var out: Array = []
	if not (raw is Array):
		errors.append("%s: expected an array of opening objects" % where)
		return out
	var list := raw as Array
	for i in list.size():
		var entry_raw: Variant = _choose(list[i], choices, "%s[%d]" % [where, i], errors)
		if not (entry_raw is Dictionary):
			errors.append("%s[%d]: expected an object" % [where, i])
			continue
		var entry := entry_raw as Dictionary
		var opening: Dictionary = {}
		for key in entry.keys():
			var name := str(key)
			if name.begins_with("_"):
				continue
			if not OPENING_FIELDS.has(name):
				errors.append(
					"%s[%d]: an opening has no field \"%s\" — it takes %s"
					% [where, i, name, ", ".join(PackedStringArray(OPENING_FIELDS.keys()))]
				)
				continue
			if str(OPENING_FIELDS[name]) == "text":
				var text := str(entry[key])
				if not OPENING_TYPES.has(text):
					errors.append(
						"%s[%d]: opening type \"%s\" is not one of %s"
						% [where, i, text, ", ".join(PackedStringArray(OPENING_TYPES))]
					)
				opening[name] = text
			else:
				opening[name] = _eval(entry[key], numeric, "%s[%d].%s" % [where, i, name], errors)
		for key in ["offset", "width", "sill", "height"]:
			if not opening.has(key):
				errors.append("%s[%d]: an opening requires \"%s\"" % [where, i, key])
		if float(opening.get("width", 0.0)) <= 0.0 or float(opening.get("height", 0.0)) <= 0.0:
			errors.append("%s[%d]: an opening must have positive width and height" % [where, i])
		out.append(opening)
	return out


# ── $choice: one branch of a data tree, chosen by a choice parameter ────────

static func _choose(
	value: Variant, choices: Dictionary, where: String, errors: PackedStringArray
) -> Variant:
	if not (value is Dictionary):
		return value
	var dict := value as Dictionary
	if not dict.has("$choice"):
		return value
	var name := str(dict["$choice"])
	if not choices.has(name):
		errors.append(
			"%s: $choice names \"%s\", which is not a choice parameter of this piece" % [where, name]
		)
		return null
	var picked := str(choices[name])
	if not dict.has(picked):
		errors.append("%s: $choice on \"%s\" has no branch for \"%s\"" % [where, name, picked])
		return null
	## A branch may itself be a $choice, so profiles can nest.
	return _choose(dict[picked], choices, where, errors)


# ── The expression language: linear arithmetic over numeric parameters ──────
#
# expr  := term (('+' | '-') term)*
# term  := unary (('*' | '/') unary)*
# unary := '-'* primary
# prim  := NUMBER | NAME | '(' expr ')'
#
# Parentheses exist for exactly one reason and it is worth naming: a rake has to
# be distributed over a wall's TOTAL height, and once `head` trims that height in
# eighth-cells the total is a SUM — `height*0.5+head*0.125`. Without grouping,
# `rake*-0.125*sill*0.5/height*0.5+head*0.125` divides by `height` and then
# multiplies by 0.5, which is a different number that looks right.
#
# Deliberately NOT Godot's `Expression`: a kit is data, and data must not be able
# to call into the engine. Names resolve only against this piece's own numeric
# parameters plus `i` inside a repeat; anything else is an error that names the
# piece, not a silent zero.

static func _eval(
	value: Variant, params: Dictionary, where: String, errors: PackedStringArray
) -> float:
	if value is float or value is int:
		return float(value)
	if not (value is String):
		errors.append(
			"%s: expected a number or an expression, got %s" % [where, type_string(typeof(value))]
		)
		return 0.0
	var tokens := _tokenise((value as String), where, errors)
	if tokens.is_empty():
		return 0.0
	var cursor: Array = [0]
	var result := _parse_expr(tokens, cursor, params, where, errors)
	if int(cursor[0]) < tokens.size():
		errors.append(
			"%s: trailing \"%s\" in expression \"%s\""
			% [where, str((tokens[int(cursor[0])] as Dictionary)["text"]), str(value)]
		)
	return result


static func _tokenise(text: String, where: String, errors: PackedStringArray) -> Array:
	var tokens: Array = []
	var i := 0
	while i < text.length():
		var chr := text[i]
		if chr == " " or chr == "\t":
			i += 1
			continue
		if chr in ["+", "-", "*", "/", "(", ")"]:
			tokens.append({"kind": "op", "text": chr})
			i += 1
			continue
		if chr.is_valid_int() or chr == ".":
			var start := i
			while i < text.length() and (text[i].is_valid_int() or text[i] == "."):
				i += 1
			var number := text.substr(start, i - start)
			if not number.is_valid_float():
				errors.append("%s: \"%s\" is not a number" % [where, number])
				return []
			tokens.append({"kind": "num", "text": number, "value": number.to_float()})
			continue
		if _is_name_start(chr):
			var start_name := i
			while i < text.length() and (_is_name_start(text[i]) or text[i].is_valid_int()):
				i += 1
			tokens.append({"kind": "name", "text": text.substr(start_name, i - start_name)})
			continue
		errors.append("%s: unexpected character \"%s\" in expression \"%s\"" % [where, chr, text])
		return []
	if tokens.is_empty():
		errors.append("%s: empty expression" % where)
	return tokens


static func _is_name_start(chr: String) -> bool:
	return (chr >= "a" and chr <= "z") or (chr >= "A" and chr <= "Z") or chr == "_"


## A NAME immediately followed by "(" is a call, whether or not the kit knows the
## function. Reading it as a call either way is deliberate: `foo(2)` then names
## the function that does not exist, instead of parsing as the parameter `foo`
## and reporting a trailing bracket.
static func _opens_bracket(tokens: Array, index: int) -> bool:
	if index >= tokens.size():
		return false
	var token := tokens[index] as Dictionary
	return str(token["kind"]) == "op" and str(token["text"]) == "("


static func _parse_expr(
	tokens: Array, cursor: Array, params: Dictionary, where: String, errors: PackedStringArray
) -> float:
	var value := _parse_term(tokens, cursor, params, where, errors)
	while int(cursor[0]) < tokens.size():
		var token := tokens[int(cursor[0])] as Dictionary
		if str(token["kind"]) != "op" or not (str(token["text"]) in ["+", "-"]):
			break
		cursor[0] = int(cursor[0]) + 1
		var rhs := _parse_term(tokens, cursor, params, where, errors)
		value = value + rhs if str(token["text"]) == "+" else value - rhs
	return value


static func _parse_term(
	tokens: Array, cursor: Array, params: Dictionary, where: String, errors: PackedStringArray
) -> float:
	var value := _parse_unary(tokens, cursor, params, where, errors)
	while int(cursor[0]) < tokens.size():
		var token := tokens[int(cursor[0])] as Dictionary
		if str(token["kind"]) != "op" or not (str(token["text"]) in ["*", "/"]):
			break
		cursor[0] = int(cursor[0]) + 1
		var rhs := _parse_unary(tokens, cursor, params, where, errors)
		if str(token["text"]) == "*":
			value *= rhs
		elif is_zero_approx(rhs):
			errors.append("%s: division by zero" % where)
		else:
			value /= rhs
	return value


static func _parse_unary(
	tokens: Array, cursor: Array, params: Dictionary, where: String, errors: PackedStringArray
) -> float:
	if int(cursor[0]) >= tokens.size():
		errors.append("%s: expression ended early" % where)
		return 0.0
	var token := tokens[int(cursor[0])] as Dictionary
	if str(token["kind"]) == "op" and str(token["text"]) == "-":
		cursor[0] = int(cursor[0]) + 1
		return -_parse_unary(tokens, cursor, params, where, errors)
	if str(token["kind"]) == "op" and str(token["text"]) == "+":
		cursor[0] = int(cursor[0]) + 1
		return _parse_unary(tokens, cursor, params, where, errors)
	if str(token["kind"]) == "op" and str(token["text"]) == "(":
		cursor[0] = int(cursor[0]) + 1
		var inner := _parse_expr(tokens, cursor, params, where, errors)
		if int(cursor[0]) >= tokens.size():
			errors.append("%s: unclosed \"(\"" % where)
			return inner
		var closer := tokens[int(cursor[0])] as Dictionary
		if str(closer["kind"]) != "op" or str(closer["text"]) != ")":
			errors.append("%s: expected \")\", got \"%s\"" % [where, str(closer["text"])])
			return inner
		cursor[0] = int(cursor[0]) + 1
		return inner
	if str(token["kind"]) == "name" and _opens_bracket(tokens, int(cursor[0]) + 1):
		var fname := str(token["text"])
		cursor[0] = int(cursor[0]) + 2
		var arg := _parse_expr(tokens, cursor, params, where, errors)
		if int(cursor[0]) >= tokens.size():
			errors.append("%s: unclosed \"(\" after \"%s\"" % [where, fname])
			return 0.0
		var close := tokens[int(cursor[0])] as Dictionary
		if str(close["kind"]) != "op" or str(close["text"]) != ")":
			errors.append("%s: expected \")\" after %s(, got \"%s\"" % [where, fname, str(close["text"])])
			return 0.0
		cursor[0] = int(cursor[0]) + 1
		if not FUNCTIONS.has(fname):
			errors.append(
				"%s: no function \"%s\" — an expression may call %s"
				% [where, fname, ", ".join(PackedStringArray(FUNCTIONS))]
			)
			return 0.0
		if fname == "abs":
			return absf(arg)
		if arg < 0.0:
			## Not a clamp. A square root of a negative means the piece asked for a
			## length that does not exist, and returning 0 would hand the build a
			## plausible number for an impossible shape.
			errors.append("%s: sqrt(%.6f) — the argument is negative" % [where, arg])
			return 0.0
		return sqrt(arg)
	cursor[0] = int(cursor[0]) + 1
	if str(token["kind"]) == "num":
		return float(token["value"])
	if str(token["kind"]) == "name":
		var name := str(token["text"])
		if params.has(name):
			return float(params[name])
		errors.append(
			"%s: unknown parameter \"%s\" (this piece has %s)"
			% [where, name, ", ".join(PackedStringArray(params.keys()))]
		)
		return 0.0
	errors.append("%s: unexpected \"%s\"" % [where, str(token["text"])])
	return 0.0


# ── Placement: a piece on the grid -> plan items ────────────────────────────

## Plan-space metres of a grid NODE. Cells are volumes; pieces stand on the
## lines between them, so this is deliberately NOT `StructurePlan.cell_base_plan`
## (which returns a cell CENTRE and would put every wall half a cell off).
static func node_plan(cell: Vector3i) -> Vector3:
	var m := WorldUnits.DECK_CELL_M
	return Vector3(float(cell.x) * m, float(cell.y) * m, float(cell.z) * m)


static func placement_cell(placement: Dictionary) -> Vector3i:
	var raw: Variant = placement.get("cell", null)
	if not (raw is Array) or (raw as Array).size() != 3:
		return Vector3i.ZERO
	var list := raw as Array
	return Vector3i(roundi(float(list[0])), roundi(float(list[1])), roundi(float(list[2])))


## One placement -> plan `items[]`. Ids are handed out from `next_id`, so a
## resolver run over a whole document never collides with the plan's own items.
## Returns {"items", "errors", "next_id"}.
static func resolve_placement(placement: Dictionary, next_id: int) -> Dictionary:
	var errors := PackedStringArray()
	var items: Array = []
	var piece_id := str(placement.get("piece", "")).strip_edges()
	var raw_label: Variant = placement.get("id", piece_id)
	var label := (
		"%d" % roundi(float(raw_label)) if (raw_label is int or raw_label is float)
		else str(raw_label)
	)
	if not has(piece_id):
		errors.append("placement %s: no piece \"%s\" in the kit" % [label, piece_id])
		return {"items": items, "errors": errors, "next_id": next_id}

	var raw_cell: Variant = placement.get("cell", null)
	if not (raw_cell is Array) or (raw_cell as Array).size() != 3:
		errors.append("placement %s: \"cell\" must be [x, y, z] in whole cells" % label)
		return {"items": items, "errors": errors, "next_id": next_id}
	for value in raw_cell as Array:
		if not (value is float or value is int):
			errors.append("placement %s: cell coordinates must be numbers" % label)
			return {"items": items, "errors": errors, "next_id": next_id}
		if not is_equal_approx(float(value), float(roundi(float(value)))):
			errors.append(
				"placement %s: cell %s is not on the grid — a piece sits on whole cells"
				% [label, str(raw_cell)]
			)
			return {"items": items, "errors": errors, "next_id": next_id}

	var facing := roundi(float(placement.get("facing", 0)))
	if not FACINGS.has(facing):
		errors.append(
			"placement %s: facing %d is not one of %s — nothing is placed at 45 degrees, "
			% [label, facing, str(FACINGS)] + "corner_45 carries its own chord"
		)
		return {"items": items, "errors": errors, "next_id": next_id}

	var given: Dictionary = placement.get("params", {}) as Dictionary if placement.get("params") is Dictionary else {}
	var resolved := resolve(piece_id, given)
	for message in resolved["errors"] as PackedStringArray:
		errors.append("placement %s: %s" % [label, message])
	if errors.size() > 0:
		return {"items": items, "errors": errors, "next_id": next_id}

	var piece := get_piece(piece_id)
	var piece_color := piece.get("color", DEFAULT_COLOR) as Color
	if placement.has("color"):
		var text := str(placement["color"])
		if Color.html_is_valid(text):
			piece_color = Color(text)
		else:
			errors.append("placement %s: colour \"%s\" is not a valid #rrggbb value" % [label, text])
	var at := node_plan(placement_cell(placement))
	var id := next_id
	for spec_variant in resolved["specs"] as Array:
		var spec := spec_variant as Dictionary
		var color: Color = spec.get("color", piece_color) as Color
		var props: Dictionary = {
			"__piece": "%s%s" % [piece_id, "" if str(placement.get("_is", "")).is_empty() else " — " + str(placement["_is"])],
			"primitive": "plate",
			"corners": _corner_array(spec.get("corners", PackedVector3Array())),
			"thickness": float(spec.get("thickness", 0.09)),
			"color": [color.r, color.g, color.b],
			"material": str(spec.get("material", DEFAULT_MATERIAL)),
		}
		if spec.has("openings") and not (spec["openings"] as Array).is_empty():
			props["openings"] = spec["openings"]
		items.append({
			"id": id,
			"item_id": "plate",
			"at": [at.x, at.y, at.z],
			"yaw": float(facing),
			"props": props,
		})
		id += 1
	return {"items": items, "errors": errors, "next_id": id}


static func _corner_array(corners: PackedVector3Array) -> Array:
	var out: Array = []
	for corner in corners:
		out.append([corner.x, corner.y, corner.z])
	return out


## A whole `structure_plan_v1` document carrying `pieces[]` -> the same document
## with those pieces resolved into `items[]` and `pieces` removed. What comes
## back is an ordinary plan; `StructurePlan.from_dict()` needs no change and the
## baker never learns a new word.
##
## Returns {"doc", "errors", "warnings", "placed", "items"}.
static func resolve_document(doc: Dictionary) -> Dictionary:
	var errors := PackedStringArray()
	var warnings := PackedStringArray()
	var out := doc.duplicate(true)
	var raw: Variant = out.get("pieces", null)
	out.erase("pieces")
	if raw == null:
		return {"doc": out, "errors": errors, "warnings": warnings, "placed": 0, "items": 0}
	if not (raw is Array):
		errors.append("plan: \"pieces\" must be an array of placements")
		return {"doc": out, "errors": errors, "warnings": warnings, "placed": 0, "items": 0}

	var items: Array = out.get("items", []) as Array if out.get("items") is Array else []
	var next_id := 1
	for item_variant in items:
		if item_variant is Dictionary:
			next_id = maxi(next_id, int((item_variant as Dictionary).get("id", 0)) + 1)

	## A hand-authored plate in a piece-built plan is exactly the thing this kit
	## exists to remove, so it is REPORTED rather than tolerated. The caller
	## decides whether that is a failure; the count is never hidden.
	var authored := 0
	for item_variant in items:
		if not (item_variant is Dictionary):
			continue
		var props: Variant = (item_variant as Dictionary).get("props", null)
		if props is Dictionary and str((props as Dictionary).get("primitive", "")) == "plate":
			authored += 1
	if authored > 0:
		warnings.append(
			"plan: %d hand-authored plate item(s) alongside %d placements"
			% [authored, (raw as Array).size()]
		)

	var placed := 0
	var made := 0
	for placement_variant in raw as Array:
		if not (placement_variant is Dictionary):
			errors.append("plan: a pieces[] entry is not an object")
			continue
		var result := resolve_placement(placement_variant as Dictionary, next_id)
		for message in result["errors"] as PackedStringArray:
			errors.append(message)
		next_id = int(result["next_id"])
		for item in result["items"] as Array:
			items.append(item)
			made += 1
		placed += 1
	out["items"] = items
	return {"doc": out, "errors": errors, "warnings": warnings, "placed": placed, "items": made}


## Hand-authored plate items in a document — the number this whole wave is trying
## to drive to zero. Counted from the document as written, before resolution.
static func authored_plate_count(doc: Dictionary) -> int:
	var count := 0
	var items: Variant = doc.get("items", null)
	if not (items is Array):
		return 0
	for item_variant in items as Array:
		if not (item_variant is Dictionary):
			continue
		var props: Variant = (item_variant as Dictionary).get("props", null)
		if props is Dictionary and str((props as Dictionary).get("primitive", "")) == "plate":
			count += 1
	return count


# ── Seam checks the tests lean on ───────────────────────────────────────────

## The two TOP corners of a piece's first plate, in piece-local metres, ordered
## along the run. Two pieces butted on the same line at the same rake must agree
## here exactly, and `piece_kit_test.gd` checks that they do.
static func top_edge(piece_id: String, given: Dictionary = {}) -> PackedVector3Array:
	var resolved := resolve(piece_id, given)
	var specs := resolved["specs"] as Array
	if specs.is_empty():
		return PackedVector3Array()
	var corners := (specs[0] as Dictionary).get("corners", PackedVector3Array()) as PackedVector3Array
	if corners.size() != 4:
		return PackedVector3Array()
	return PackedVector3Array([corners[3], corners[2]])


## Piece-local corners of a placed piece's plate, taken to PLAN metres — the same
## multiplication `StructureBaker._item_layers` does. Used by the tests to assert
## that neighbouring PLACEMENTS meet, which is a stronger claim than two pieces
## agreeing in their own frames.
static func placed_corners(placement: Dictionary, step := 0) -> PackedVector3Array:
	var result := resolve_placement(placement, 1)
	var items := result["items"] as Array
	if step < 0 or step >= items.size():
		return PackedVector3Array()
	var item := items[step] as Dictionary
	var props := item["props"] as Dictionary
	var basis := Basis.from_euler(Vector3(0.0, deg_to_rad(float(item["yaw"])), 0.0), EULER_ORDER_YXZ)
	var at_list := item["at"] as Array
	var xform := Transform3D(basis, Vector3(float(at_list[0]), float(at_list[1]), float(at_list[2])))
	var out := PackedVector3Array()
	for corner_variant in props["corners"] as Array:
		var triple := corner_variant as Array
		out.append(xform * Vector3(float(triple[0]), float(triple[1]), float(triple[2])))
	return out


## StructureBaker's own degeneracy check, reached without instantiating it.
## A piece that resolves to something the baker refuses to draw is a broken
## piece, and it is caught at load rather than as a hole in somebody's wheelhouse.
static func _plate_problem(spec: Dictionary) -> String:
	var probe: Dictionary = {
		"corners": _corner_array(spec.get("corners", PackedVector3Array())),
		"thickness": float(spec.get("thickness", 0.0)),
	}
	return StructureBaker.plate_problem(probe)
