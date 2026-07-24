class_name StructureBaker
extends RefCounted

## Pure StructurePlan -> geometry. One merged surface per (material, color)
## bucket for visuals, and the SAME panel decomposition drives collision boxes,
## so what you see is exactly what you collide with (door and stairwell
## openings are genuinely passable). No gameplay dependencies: reusable by
## DeckFitout, the Structure Studio editor, and headless services.
##
## Geometry conventions (chosen to kill z-fighting by construction):
##  - Room ceiling/floor plates are INSET by half a wall thickness, so plate
##    faces never share a plane with wall tops/bottoms — walls own the ring.
##  - Elevated room floors are lifted 15 mm above their nominal level, so a
##    stacked room's floor never planes against the room-below's ceiling.
##  - Walls with inside/outside colors split into two half-thickness skins.
##  - Every wall opening gets a proud frame (jambs + lintel + sill) in a
##    darkened tone — cuts read as depth from any angle and any lighting.

const DEFAULT_WALL_COLOR := Color(0.82, 0.84, 0.86)
const DEFAULT_DECK_COLOR := Color(0.36, 0.34, 0.31)
const DEFAULT_INTERIOR_COLOR := Color(0.78, 0.70, 0.58) ## warm timber
const MIN_PANEL := 0.02
const RAISED_SOLE := 0.02 ## plates at y<=0 sit just proud of the host deck
const FLOOR_LIFT := 0.015 ## elevated floors float this far above their level
const FRAME_PROUD := 0.09 ## opening frames overhang the wall skin
const FRAME_WIDTH := 0.1
## Anti-coplanarity margin: abutting solids overlap by this much so every
## internal face is buried inside neighbouring geometry instead of sharing a
## plane with it. All room-generated geometry is z-fight-free by construction.
const SKIN_EPS := 0.01

## Material library: name -> surface response. Extend freely; unknown names
## fall back to "painted".
const MATERIALS := {
	"painted": {"roughness": 0.80, "metallic": 0.00},
	"metal": {"roughness": 0.45, "metallic": 0.60},
	"wood": {"roughness": 0.90, "metallic": 0.00},
	"steel": {"roughness": 0.55, "metallic": 0.35},
}


## Expands rooms into walls + plates and merges with the plan's own walls and
## decks. Every element carries `source_id` so editors can map geometry back
## to the plan entity that owns it.
static func expand(plan: StructurePlan) -> Dictionary:
	var walls: Array = []
	var decks: Array = []
	for wall_variant in plan.walls:
		var wall := (wall_variant as Dictionary).duplicate(true)
		wall["source_id"] = int(wall.get("id", -1))
		walls.append(wall)
	for deck_variant in plan.decks:
		var deck := (deck_variant as Dictionary).duplicate(true)
		deck["source_id"] = int(deck.get("id", -1))
		decks.append(deck)
	for room_variant in plan.rooms:
		var expanded := expand_room(room_variant as Dictionary)
		walls.append_array(expanded.get("walls", []))
		decks.append_array(expanded.get("decks", []))
	return {"walls": walls, "decks": decks}


static func expand_room(room: Dictionary) -> Dictionary:
	var origin := StructurePlan.vec3_of(room.get("origin"))
	var size := StructurePlan.vec3_of(room.get("size"), Vector3(4, 3, 4))
	var thickness := float(room.get("wall_thickness", StructurePlan.DEFAULT_WALL_THICKNESS))
	var source_id := int(room.get("id", -1))
	var w := size.x
	var h := size.y
	var l := size.z
	## Inside / outside surface identity. Legacy `color` acts as the outside.
	var color_out: Variant = room.get("color_out", room.get("color", null))
	var color_in: Variant = room.get("color_in", null)
	var material_out := str(room.get("material_out", room.get("material", "painted")))
	var material_in := str(room.get("material_in", "wood"))
	## X-axis walls extend past both ends to fill corners; the extra SKIN_EPS
	## pushes their end faces past the perpendicular wall's skin plane so the
	## corner has no coincident surfaces.
	var ext := thickness * 0.5 + SKIN_EPS
	var wall_specs := {
		"n": {"start": origin + Vector3(-ext, 0, 0), "axis": "x", "length": w + 2.0 * ext, "shift": ext, "outward": -1},
		"s": {"start": origin + Vector3(-ext, 0, l), "axis": "x", "length": w + 2.0 * ext, "shift": ext, "outward": 1},
		"w": {"start": origin, "axis": "z", "length": l, "shift": 0.0, "outward": -1},
		"e": {"start": origin + Vector3(w, 0, 0), "axis": "z", "length": l, "shift": 0.0, "outward": 1},
	}
	var walls: Array = []
	var face_openings: Dictionary = {"n": [], "s": [], "w": [], "e": [], "floor": [], "ceiling": []}
	for opening_variant in room.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var face := str(opening.get("face", "n"))
		if face_openings.has(face):
			(face_openings[face] as Array).append(opening)
	for face in wall_specs.keys():
		var spec := wall_specs[face] as Dictionary
		var wall := {
			"start": [spec["start"].x, spec["start"].y, spec["start"].z],
			"axis": spec["axis"],
			"length": spec["length"],
			"height": h,
			"thickness": thickness,
			"openings": [],
			"source_id": source_id,
			"outward_sign": spec["outward"],
			"material_out": material_out,
			"material_in": material_in,
		}
		if color_out != null:
			wall["color_out"] = color_out
		if color_in != null:
			wall["color_in"] = color_in
		var shift := float(spec.get("shift", 0.0))
		for opening_variant in face_openings[face] as Array:
			var opening := (opening_variant as Dictionary).duplicate(true)
			opening.erase("face")
			opening["offset"] = float(opening.get("offset", 0.0)) + shift
			(wall["openings"] as Array).append(opening)
		walls.append(wall)
	var decks: Array = []
	for level in ["floor", "ceiling"]:
		if level == "ceiling" and not bool(room.get("roof", true)):
			continue
		if level == "floor" and not bool(room.get("floor", true)):
			continue
		## Inset just under half a wall thickness: walls own the perimeter ring
		## and the plate edge tucks INSIDE the interior wall skin, so neither
		## plate faces nor plate edges share a plane with anything.
		var inset := minf(thickness * 0.5 - SKIN_EPS, minf(w, l) * 0.25)
		var plate := {
			"origin": [origin.x + inset, origin.y + (h if level == "ceiling" else 0.0), origin.z + inset],
			"size": [maxf(w - inset * 2.0, 0.5), maxf(l - inset * 2.0, 0.5)],
			"thickness": StructurePlan.DEFAULT_PLATE_THICKNESS,
			"openings": [],
			"source_id": source_id,
			"mount": level,
			"material_out": material_out,
			"material_in": material_in,
		}
		if color_out != null:
			plate["color_out"] = color_out
		if color_in != null:
			plate["color_in"] = color_in
		for opening_variant in face_openings[level] as Array:
			var opening := (opening_variant as Dictionary).duplicate(true)
			opening.erase("face")
			## Compensate hole coordinates for the plate inset.
			var off: Array = opening.get("offset", [0.0, 0.0])
			opening["offset"] = [float(off[0]) - inset, (float(off[1]) if off.size() > 1 else 0.0) - inset]
			(plate["openings"] as Array).append(opening)
		decks.append(plate)
	return {"walls": walls, "decks": decks}


# ── Panel decomposition ──────────────────────────────────────────────────────

## Rectangles {u0,u1,v0,v1} covering the wall span minus its openings.
static func wall_panels(wall: Dictionary) -> Array:
	var length := float(wall.get("length", 1.0))
	var height := float(wall.get("height", 3.0))
	var openings := _parsed_openings(wall)
	var panels: Array = []
	var cursor := 0.0
	for opening in openings:
		var off := float(opening["off"])
		var width := float(opening["w"])
		var sill := float(opening["sill"])
		var top := sill + float(opening["h"])
		if off - cursor > MIN_PANEL:
			panels.append({"u0": cursor, "u1": off, "v0": 0.0, "v1": height})
		if sill > MIN_PANEL:
			panels.append({"u0": off, "u1": off + width, "v0": 0.0, "v1": sill})
		if height - top > MIN_PANEL:
			panels.append({"u0": off, "u1": off + width, "v0": top, "v1": height})
		cursor = maxf(cursor, off + width)
	if length - cursor > MIN_PANEL:
		panels.append({"u0": cursor, "u1": length, "v0": 0.0, "v1": height})
	return panels


static func _parsed_openings(wall: Dictionary) -> Array:
	var length := float(wall.get("length", 1.0))
	var height := float(wall.get("height", 3.0))
	var openings: Array = []
	for opening_variant in wall.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off := clampf(float(opening.get("offset", 0.0)), 0.0, length)
		var width := clampf(float(opening.get("width", 1.0)), 0.0, length - off)
		var type := str(opening.get("type", StructurePlan.OPENING_DOOR))
		var sill := float(opening.get("sill", 1.0 if type == StructurePlan.OPENING_WINDOW else 0.0))
		var opening_height := clampf(float(opening.get("height", 2.2 if type == StructurePlan.OPENING_DOOR else 1.2)), 0.1, height - sill)
		if width > MIN_PANEL:
			openings.append({"off": off, "w": width, "sill": sill, "h": opening_height})
	openings.sort_custom(func(a, b): return float(a["off"]) < float(b["off"]))
	return openings


## Boxes {center: Vector3, size: Vector3} for one wall in plan space.
static func wall_boxes(wall: Dictionary) -> Array:
	var start := StructurePlan.vec3_of(wall.get("start"))
	var axis := str(wall.get("axis", "x"))
	var thickness := float(wall.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS))
	var boxes: Array = []
	for panel_variant in wall_panels(wall):
		var panel := panel_variant as Dictionary
		var u_mid := (float(panel["u0"]) + float(panel["u1"])) * 0.5
		var u_len := float(panel["u1"]) - float(panel["u0"])
		var v_mid := (float(panel["v0"]) + float(panel["v1"])) * 0.5
		var v_len := float(panel["v1"]) - float(panel["v0"])
		if axis == "z":
			boxes.append({
				"center": start + Vector3(0.0, v_mid, u_mid),
				"size": Vector3(thickness, v_len, u_len),
			})
		else:
			boxes.append({
				"center": start + Vector3(u_mid, v_mid, 0.0),
				"size": Vector3(u_len, v_len, thickness),
			})
	return boxes


## Scanline strips {x0,x1,z0,z1} covering the plate minus its holes.
static func deck_strips(deck: Dictionary) -> Array:
	var size_list: Array = deck.get("size", [1.0, 1.0])
	var w := float(size_list[0])
	var l := float(size_list[1]) if size_list.size() > 1 else 1.0
	var holes: Array = []
	for opening_variant in deck.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off: Array = opening.get("offset", [0.0, 0.0])
		var hole_size: Array = opening.get("size", [1.0, 1.0])
		var hx0 := clampf(float(off[0]), 0.0, w)
		var hz0 := clampf(float(off[1]) if off.size() > 1 else 0.0, 0.0, l)
		var hx1 := clampf(hx0 + float(hole_size[0]), 0.0, w)
		var hz1 := clampf(hz0 + (float(hole_size[1]) if hole_size.size() > 1 else 1.0), 0.0, l)
		if hx1 - hx0 > MIN_PANEL and hz1 - hz0 > MIN_PANEL:
			holes.append({"x0": hx0, "x1": hx1, "z0": hz0, "z1": hz1})
	var z_cuts: Array[float] = [0.0, l]
	for hole in holes:
		z_cuts.append(float(hole["z0"]))
		z_cuts.append(float(hole["z1"]))
	z_cuts.sort()
	var strips: Array = []
	for index in z_cuts.size() - 1:
		var z0 := z_cuts[index]
		var z1 := z_cuts[index + 1]
		if z1 - z0 <= MIN_PANEL:
			continue
		var z_mid := (z0 + z1) * 0.5
		var strip_holes: Array = []
		for hole in holes:
			if float(hole["z0"]) <= z_mid and z_mid <= float(hole["z1"]):
				strip_holes.append(hole)
		strip_holes.sort_custom(func(a, b): return float(a["x0"]) < float(b["x0"]))
		var cursor := 0.0
		for hole in strip_holes:
			if float(hole["x0"]) - cursor > MIN_PANEL:
				strips.append({"x0": cursor, "x1": float(hole["x0"]), "z0": z0, "z1": z1})
			cursor = maxf(cursor, float(hole["x1"]))
		if w - cursor > MIN_PANEL:
			strips.append({"x0": cursor, "x1": w, "z0": z0, "z1": z1})
	return strips


## Vertical span [bottom, top] of a plate, honouring its mount convention.
static func _plate_span(deck: Dictionary) -> Vector2:
	var origin := StructurePlan.vec3_of(deck.get("origin"))
	var thickness := float(deck.get("thickness", StructurePlan.DEFAULT_PLATE_THICKNESS))
	match str(deck.get("mount", "")):
		"ceiling":
			return Vector2(origin.y - thickness, origin.y)
		"floor":
			if origin.y > 0.05:
				return Vector2(origin.y + FLOOR_LIFT, origin.y + FLOOR_LIFT + thickness)
			return Vector2(RAISED_SOLE - thickness, RAISED_SOLE)
		_:
			var top_y := origin.y if origin.y > 0.001 else RAISED_SOLE
			return Vector2(top_y - thickness, top_y)


static func deck_boxes(deck: Dictionary) -> Array:
	var origin := StructurePlan.vec3_of(deck.get("origin"))
	var span := _plate_span(deck)
	var boxes: Array = []
	for strip_variant in deck_strips(deck):
		var strip := strip_variant as Dictionary
		var x_mid := (float(strip["x0"]) + float(strip["x1"])) * 0.5
		var x_len := float(strip["x1"]) - float(strip["x0"])
		var z_mid := (float(strip["z0"]) + float(strip["z1"])) * 0.5
		var z_len := float(strip["z1"]) - float(strip["z0"])
		boxes.append({
			"center": Vector3(origin.x + x_mid, (span.x + span.y) * 0.5, origin.z + z_mid),
			"size": Vector3(x_len, span.y - span.x, z_len),
		})
	return boxes


# ── Surface layers (color + material per side) ───────────────────────────────

static func _color_of(value: Variant, fallback: Color) -> Color:
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Color(float(list[0]), float(list[1]), float(list[2]))
	return fallback


## Renderable layers for one wall: either a single skin, or inner + outer
## half-thickness skins when the wall declares two-sided identity. Opening
## frames ride along in a darkened tone.
static func _wall_layers(wall: Dictionary, fallback: Color) -> Array:
	var base := _color_of(wall.get("color", wall.get("color_out", null)), fallback)
	var two_sided := wall.has("color_in") or wall.has("material_in")
	var color_out := _color_of(wall.get("color_out", wall.get("color", null)), fallback)
	var color_in := _color_of(wall.get("color_in", null), DEFAULT_INTERIOR_COLOR)
	var material_out := str(wall.get("material_out", wall.get("material", "painted")))
	var material_in := str(wall.get("material_in", "wood"))
	var outward := float(wall.get("outward_sign", 1.0))
	var axis_z := str(wall.get("axis", "x")) == "z"
	var layers: Array = []
	for box_variant in wall_boxes(wall):
		var box := box_variant as Dictionary
		var center := box["center"] as Vector3
		var size := box["size"] as Vector3
		if not two_sided:
			layers.append({"center": center, "size": size, "color": base, "material": material_out})
			continue
		var t := size.x if axis_z else size.z
		var quarter := t * 0.25
		var normal := Vector3(1, 0, 0) if axis_z else Vector3(0, 0, 1)
		## Skins are slightly over half thickness so they interpenetrate at
		## the centerline — their meeting faces are buried, never coplanar.
		var skin := t * 0.5 + SKIN_EPS * 2.0
		var half_size := Vector3(skin, size.y, size.z) if axis_z else Vector3(size.x, size.y, skin)
		layers.append({
			"center": center + normal * quarter * outward,
			"size": half_size, "color": color_out, "material": material_out,
		})
		layers.append({
			"center": center - normal * quarter * outward,
			"size": half_size, "color": color_in, "material": material_in,
		})
	var frame_color := base.darkened(0.45)
	for frame_variant in _opening_frames(wall):
		var frame := frame_variant as Dictionary
		layers.append({
			"center": frame["center"], "size": frame["size"],
			"color": frame_color, "material": "steel",
		})
	return layers


## Proper casing (dørkarm/vindusramme) around every wall opening, slightly
## proud of the skin. Joinery rules:
##  - Jambs STRADDLE the cut edges — half buried in the wall panel, so no
##    face can plane against the cut.
##  - Lintel (and window sill) runs the FULL width across the jamb ends —
##    closed corners like real casing.
##  - Members interpenetrate by SKIN_EPS so no coplanar contact survives.
static func _opening_frames(wall: Dictionary) -> Array:
	var start := StructurePlan.vec3_of(wall.get("start"))
	var axis_z := str(wall.get("axis", "x")) == "z"
	var thickness := float(wall.get("thickness", StructurePlan.DEFAULT_WALL_THICKNESS))
	var frames: Array = []
	var depth := thickness + FRAME_PROUD
	var half_w := FRAME_WIDTH * 0.5
	for opening in _parsed_openings(wall):
		var off := float(opening["off"])
		var width := float(opening["w"])
		var sill := float(opening["sill"])
		var height := float(opening["h"])
		var has_sill := sill > 0.05
		var head_v := sill + height ## top of the clear opening
		## Jambs run between sill member and lintel, overlapping each by eps.
		var jamb_bottom := (sill + half_w - SKIN_EPS) if has_sill else 0.0
		var jamb_top := head_v - half_w + SKIN_EPS
		var jamb_length := maxf(jamb_top - jamb_bottom, 0.1)
		var jamb_mid := (jamb_top + jamb_bottom) * 0.5
		var full_span := width + FRAME_WIDTH * 2.0 ## lintel/sill across jamb ends
		var members := [
			{"u": off, "v": jamb_mid, "ul": FRAME_WIDTH, "vl": jamb_length},
			{"u": off + width, "v": jamb_mid, "ul": FRAME_WIDTH, "vl": jamb_length},
			{"u": off + width * 0.5, "v": head_v, "ul": full_span, "vl": FRAME_WIDTH},
		]
		if has_sill:
			members.append({"u": off + width * 0.5, "v": sill, "ul": full_span, "vl": FRAME_WIDTH})
		for member in members:
			var u := float(member["u"])
			var v := float(member["v"])
			if axis_z:
				frames.append({
					"center": start + Vector3(0.0, v, u),
					"size": Vector3(depth, float(member["vl"]), float(member["ul"])),
				})
			else:
				frames.append({
					"center": start + Vector3(u, v, 0.0),
					"size": Vector3(float(member["ul"]), float(member["vl"]), depth),
				})
	return frames


## Renderable layers for a plate: two-sided plates split into top/bottom
## halves (ceiling: top = outside/roof, bottom = inside; floor: top = inside
## sole, bottom = outside underside).
static func _plate_layers(deck: Dictionary, wall_fallback: Color, deck_fallback: Color) -> Array:
	var slot_default := wall_fallback if str(deck.get("palette_slot", "")) == "wall" else deck_fallback
	var two_sided := deck.has("color_in") or deck.has("material_in")
	var mount := str(deck.get("mount", ""))
	var base := _color_of(deck.get("color", deck.get("color_out", null)), slot_default)
	var color_out := _color_of(deck.get("color_out", deck.get("color", null)), slot_default)
	var color_in := _color_of(deck.get("color_in", null), DEFAULT_INTERIOR_COLOR)
	var material_out := str(deck.get("material_out", deck.get("material", "painted")))
	var material_in := str(deck.get("material_in", "wood"))
	var layers: Array = []
	for box_variant in deck_boxes(deck):
		var box := box_variant as Dictionary
		var center := box["center"] as Vector3
		var size := box["size"] as Vector3
		if not two_sided or mount.is_empty():
			layers.append({"center": center, "size": size, "color": base, "material": material_out})
			continue
		var half := size.y * 0.5
		var top_color := color_out if mount == "ceiling" else color_in
		var top_material := material_out if mount == "ceiling" else material_in
		var bottom_color := color_in if mount == "ceiling" else color_out
		var bottom_material := material_in if mount == "ceiling" else material_out
		var half_size := Vector3(size.x, half, size.z)
		layers.append({
			"center": center + Vector3(0, half * 0.5, 0),
			"size": half_size, "color": top_color, "material": top_material,
		})
		layers.append({
			"center": center - Vector3(0, half * 0.5, 0),
			"size": half_size, "color": bottom_color, "material": bottom_material,
		})
	return layers


# ── Bake outputs ─────────────────────────────────────────────────────────────

## All collision boxes for the plan, offset into host-local space.
static func collect_colliders(plan: StructurePlan, offset := Vector3.ZERO) -> Array:
	var expanded := expand(plan)
	var out: Array = []
	for wall_variant in expanded["walls"] as Array:
		for box_variant in wall_boxes(wall_variant as Dictionary):
			var box := box_variant as Dictionary
			out.append({"center": (box["center"] as Vector3) + offset, "size": box["size"]})
	for deck_variant in expanded["decks"] as Array:
		for box_variant in deck_boxes(deck_variant as Dictionary):
			var box := box_variant as Dictionary
			out.append({"center": (box["center"] as Vector3) + offset, "size": box["size"]})
	return out


## Merged visual bake: one MeshInstance3D per (material, color) bucket.
## `ghost` renders the whole bake as translucent shadowless x-ray.
static func bake(plan: StructurePlan, offset := Vector3.ZERO, ghost := false) -> Node3D:
	var root := Node3D.new()
	root.name = "StructureBake"
	var buckets: Dictionary = {}
	var expanded := expand(plan)
	var wall_default := _palette_color(plan, "wall", DEFAULT_WALL_COLOR)
	var deck_default := _palette_color(plan, "deck", DEFAULT_DECK_COLOR)
	for wall_variant in expanded["walls"] as Array:
		for layer_variant in _wall_layers(wall_variant as Dictionary, wall_default):
			_bucket_layer(buckets, layer_variant as Dictionary, offset)
	for deck_variant in expanded["decks"] as Array:
		for layer_variant in _plate_layers(deck_variant as Dictionary, wall_default, deck_default):
			_bucket_layer(buckets, layer_variant as Dictionary, offset)
	for key in buckets.keys():
		var bucket := buckets[key] as Dictionary
		var st := bucket["st"] as SurfaceTool
		var material := StandardMaterial3D.new()
		material.albedo_color = bucket["color"] as Color
		var response: Dictionary = MATERIALS.get(str(bucket["material"]), MATERIALS["painted"])
		material.roughness = float(response["roughness"])
		material.metallic = float(response["metallic"])
		if ghost:
			material.albedo_color = Color(material.albedo_color, 0.13)
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		st.set_material(material)
		var mesh := st.commit()
		if mesh != null and mesh.get_surface_count() > 0:
			var instance := MeshInstance3D.new()
			instance.name = "Structure_%s" % str(key)
			instance.mesh = mesh
			if ghost:
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(instance)
	return root


static func _palette_color(plan: StructurePlan, slot: String, fallback: Color) -> Color:
	var raw: Variant = plan.palette.get(slot, null)
	return _color_of(raw, fallback)


static func _bucket_layer(buckets: Dictionary, layer: Dictionary, offset: Vector3) -> void:
	var color := layer["color"] as Color
	var material := str(layer["material"])
	var key := "%s_%02x%02x%02x" % [material, int(color.r * 255.0), int(color.g * 255.0), int(color.b * 255.0)]
	if not buckets.has(key):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		buckets[key] = {"color": color, "material": material, "st": st}
	_append_box(
		(buckets[key] as Dictionary)["st"] as SurfaceTool,
		(layer["center"] as Vector3) + offset,
		layer["size"] as Vector3,
	)


## Axis-aligned box, 12 triangles, clockwise-front winding (Godot convention:
## right-hand cross of vertex order = MINUS the outward normal — verified in
## tests/winding_probe.gd).
static func _append_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var corners := [
		center + Vector3(-h.x, -h.y, -h.z), center + Vector3(h.x, -h.y, -h.z),
		center + Vector3(h.x, -h.y, h.z), center + Vector3(-h.x, -h.y, h.z),
		center + Vector3(-h.x, h.y, -h.z), center + Vector3(h.x, h.y, -h.z),
		center + Vector3(h.x, h.y, h.z), center + Vector3(-h.x, h.y, h.z),
	]
	var faces := [
		[[0, 1, 5, 4], Vector3(0, 0, -1)],
		[[2, 3, 7, 6], Vector3(0, 0, 1)],
		[[1, 2, 6, 5], Vector3(1, 0, 0)],
		[[3, 0, 4, 7], Vector3(-1, 0, 0)],
		[[4, 5, 6, 7], Vector3(0, 1, 0)],
		[[3, 2, 1, 0], Vector3(0, -1, 0)],
	]
	for face in faces:
		var idx: Array = face[0]
		var normal: Vector3 = face[1]
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri:
				st.set_normal(normal)
				st.add_vertex(corners[idx[k]])
