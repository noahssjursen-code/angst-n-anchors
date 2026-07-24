class_name StructurePlan
extends RefCounted

## Parametric construction document shared by vessels and land buildings.
##
## Structure is DRAWN, not stacked: four primitives, each one part regardless
## of size, replace fields of voxel bricks:
##   walls  — {id, start:[x,y,z], axis:"x"|"z", length, height, thickness,
##             color?/color_out?/color_in?, material?/material_out?/material_in?,
##             openings:[{type, offset, width, height, sill}]}
##   decks  — {id, origin:[x,y,z], size:[w,l], thickness, color?, material?,
##             openings:[{type, offset:[dx,dz], size:[w,l]}]}
##   rooms  — {id, origin:[x,y,z], size:[w,h,l], wall_thickness,
##             color_out/in, material_out/in, roof?, floor?,
##             openings:[{face:"n"|"s"|"e"|"w"|"floor"|"ceiling", type,
##                        offset, width, height, sill}]}
##   items  — {id, item_id, cell:[x,y,z], yaw}  (point equipment — catalog
##             ready via StructureItemCatalog; definitions land later)
##
## Coordinates are grid-corner points in whole metres. For vessels x/z match
## DeckGrid cell corners (0..width, 0..length) and y is metres above the deck
## plane. Rooms expand into walls + floor + ceiling plates at bake time —
## see StructureBaker.expand_room().
##
## Surface ids resolve through StructureMaterialLibrary (global construction
## materials). Unknown ids fall back to "painted" at bake time.

const FORMAT := "structure_plan_v1"
const DEFAULT_WALL_THICKNESS := 1.0 / 6.0
const DEFAULT_PLATE_THICKNESS := 0.15
const DEFAULT_ROOM_HEIGHT := 3.0

const OPENING_DOOR := "door"
const OPENING_WINDOW := "window"
const OPENING_HOLE := "hole"
const OPENING_STAIRWELL := "stairwell"

const CONTEXTS := ["vessel", "building"]

var context := "vessel" ## "vessel" | "building"
var hull_id := ""
var walls: Array = []
var decks: Array = []
var rooms: Array = []
var items: Array = []
var palette: Dictionary = {}
var _next_id := 1


static func is_plan(data: Dictionary) -> bool:
	return str(data.get("format", "")) == FORMAT


func allocate_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


func add_wall(start: Vector3, axis: String, length: float, height := DEFAULT_ROOM_HEIGHT, thickness := DEFAULT_WALL_THICKNESS) -> Dictionary:
	var wall := {
		"id": allocate_id(),
		"start": [start.x, start.y, start.z],
		"axis": "z" if axis == "z" else "x",
		"length": maxf(length, 1.0),
		"height": maxf(height, 0.5),
		"thickness": clampf(thickness, 0.05, 1.0),
		"openings": [],
	}
	walls.append(wall)
	return wall


func add_deck(origin: Vector3, size: Vector2, thickness := DEFAULT_PLATE_THICKNESS) -> Dictionary:
	var deck := {
		"id": allocate_id(),
		"origin": [origin.x, origin.y, origin.z],
		"size": [maxf(size.x, 1.0), maxf(size.y, 1.0)],
		"thickness": clampf(thickness, 0.05, 1.0),
		"openings": [],
	}
	decks.append(deck)
	return deck


func add_room(origin: Vector3, size: Vector3) -> Dictionary:
	var room := {
		"id": allocate_id(),
		"origin": [origin.x, origin.y, origin.z],
		"size": [maxf(size.x, 2.0), maxf(size.y, 2.0), maxf(size.z, 2.0)],
		"wall_thickness": DEFAULT_WALL_THICKNESS,
		"roof": true,
		"floor": true,
		"openings": [],
	}
	rooms.append(room)
	return room


func add_item(item_id: String, cell: Vector3i, yaw := 0) -> Dictionary:
	var item := {
		"id": allocate_id(),
		"item_id": item_id.strip_edges(),
		"cell": [cell.x, cell.y, cell.z],
		"yaw": int(yaw),
	}
	items.append(item)
	return item


func entity_by_id(id: int) -> Dictionary:
	for collection in [walls, decks, rooms, items]:
		for entity in collection:
			if int((entity as Dictionary).get("id", -1)) == id:
				return entity
	return {}


func entity_kind(id: int) -> String:
	var entity := entity_by_id(id)
	if entity.is_empty():
		return ""
	return kind_of_entity(entity)


static func kind_of_entity(entity: Dictionary) -> String:
	if entity.has("item_id"):
		return "item"
	if entity.has("axis"):
		return "wall"
	if entity.has("size") and (entity.get("size") as Array).size() == 3:
		return "room"
	if entity.has("size"):
		return "deck"
	return "unknown"


func remove_entity(id: int) -> bool:
	for collection in [walls, decks, rooms, items]:
		for index in (collection as Array).size():
			if int(((collection as Array)[index] as Dictionary).get("id", -1)) == id:
				(collection as Array).remove_at(index)
				return true
	return false


## Deep-copies an entity to a new id, offset by delta metres / cells.
func duplicate_entity(id: int, delta := Vector3(1, 0, 1)) -> Dictionary:
	var source := entity_by_id(id)
	if source.is_empty():
		return {}
	var copy := source.duplicate(true)
	copy["id"] = allocate_id()
	var kind := kind_of_entity(source)
	match kind:
		"wall":
			var start := vec3_of(copy.get("start"))
			copy["start"] = [start.x + delta.x, start.y + delta.y, start.z + delta.z]
			walls.append(copy)
		"deck":
			var origin := vec3_of(copy.get("origin"))
			copy["origin"] = [origin.x + delta.x, origin.y + delta.y, origin.z + delta.z]
			decks.append(copy)
		"room":
			var origin := vec3_of(copy.get("origin"))
			copy["origin"] = [origin.x + delta.x, origin.y + delta.y, origin.z + delta.z]
			rooms.append(copy)
		"item":
			var cell := copy.get("cell", [0, 0, 0]) as Array
			copy["cell"] = [
				int(cell[0]) + int(delta.x),
				int(cell[1]) + int(delta.y),
				int(cell[2]) + int(delta.z),
			]
			items.append(copy)
		_:
			return {}
	return copy


func is_empty() -> bool:
	return walls.is_empty() and decks.is_empty() and rooms.is_empty() and items.is_empty()


func entity_count() -> int:
	return walls.size() + decks.size() + rooms.size() + items.size()


func structure_count() -> int:
	return walls.size() + decks.size() + rooms.size()


func clear() -> void:
	walls.clear()
	decks.clear()
	rooms.clear()
	items.clear()
	palette.clear()
	_next_id = 1


## Soft validation for Studio / publish later. Never mutates the plan.
## Returns {ok: bool, errors: PackedStringArray, warnings: PackedStringArray}.
func validate(grid_width := 0, grid_length := 0) -> Dictionary:
	var errors: PackedStringArray = []
	var warnings: PackedStringArray = []
	if context not in CONTEXTS:
		errors.append("context must be vessel or building")
	if context == "vessel" and hull_id.strip_edges().is_empty():
		warnings.append("vessel plan has no hull_id")
	for wall_variant in walls:
		var wall := wall_variant as Dictionary
		if float(wall.get("length", 0.0)) < 1.0:
			errors.append("wall #%d length < 1" % int(wall.get("id", -1)))
		_validate_extents(wall, "wall", grid_width, grid_length, warnings)
		_validate_materials(wall, warnings)
		_validate_wall_openings(wall, warnings)
	for deck_variant in decks:
		var deck := deck_variant as Dictionary
		_validate_extents(deck, "deck", grid_width, grid_length, warnings)
		_validate_materials(deck, warnings)
		_validate_plate_openings(deck, warnings)
	for room_variant in rooms:
		var room := room_variant as Dictionary
		var size := vec3_of(room.get("size"), Vector3(2, 3, 2))
		if size.x < 2.0 or size.z < 2.0:
			warnings.append("room #%d footprint under 2×2" % int(room.get("id", -1)))
		_validate_extents(room, "room", grid_width, grid_length, warnings)
		_validate_materials(room, warnings)
		_validate_room_openings(room, warnings)
	for item_variant in items:
		var item := item_variant as Dictionary
		var item_id := str(item.get("item_id", "")).strip_edges()
		if item_id.is_empty():
			errors.append("item #%d missing item_id" % int(item.get("id", -1)))
		elif not StructureItemCatalog.has_id(item_id):
			## Catalog is empty this pass — warn, do not hard-fail.
			warnings.append("item #%d references unknown item_id '%s'" % [
				int(item.get("id", -1)), item_id,
			])
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
	}


func _validate_extents(entity: Dictionary, kind: String, grid_width: int, grid_length: int, warnings: PackedStringArray) -> void:
	if grid_width <= 0 or grid_length <= 0:
		return
	var origin := vec3_of(entity.get("start", entity.get("origin")))
	var end := origin
	match kind:
		"wall":
			var length := float(entity.get("length", 1.0))
			if str(entity.get("axis", "x")) == "z":
				end = origin + Vector3(0.0, 0.0, length)
			else:
				end = origin + Vector3(length, 0.0, 0.0)
		"deck":
			var plate := vec2_of(entity.get("size"), Vector2(1, 1))
			end = origin + Vector3(plate.x, 0.0, plate.y)
		"room":
			var size := vec3_of(entity.get("size"), Vector3(2, 3, 2))
			end = origin + Vector3(size.x, 0.0, size.z)
	var id := int(entity.get("id", -1))
	if origin.x < -0.01 or origin.z < -0.01:
		warnings.append("entity #%d origin outside grid" % id)
	if end.x > float(grid_width) + 0.01 or end.z > float(grid_length) + 0.01:
		warnings.append("entity #%d extends outside grid" % id)


func _validate_materials(entity: Dictionary, warnings: PackedStringArray) -> void:
	var id := int(entity.get("id", -1))
	for key in ["material", "material_out", "material_in"]:
		if not entity.has(key):
			continue
		var mat_id := str(entity.get(key, "")).strip_edges()
		if mat_id.is_empty():
			continue
		if not StructureMaterialLibrary.has_id(mat_id):
			warnings.append("entity #%d unknown %s '%s'" % [id, key, mat_id])


func _validate_wall_openings(wall: Dictionary, warnings: PackedStringArray) -> void:
	var id := int(wall.get("id", -1))
	var length := float(wall.get("length", 1.0))
	var height := float(wall.get("height", 3.0))
	var spans: Array = []
	for opening_variant in wall.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off := float(opening.get("offset", 0.0))
		var width := float(opening.get("width", 1.0))
		var sill := float(opening.get("sill", 0.0))
		var oh := float(opening.get("height", 2.0))
		if off < -0.01 or off + width > length + 0.01:
			warnings.append("wall #%d opening past length" % id)
		if sill < -0.01 or sill + oh > height + 0.01:
			warnings.append("wall #%d opening past height" % id)
		for span_variant in spans:
			var span: Vector2 = span_variant
			if off < span.y - 0.01 and off + width > span.x + 0.01:
				warnings.append("wall #%d overlapping openings" % id)
				break
		spans.append(Vector2(off, off + width))


func _validate_plate_openings(deck: Dictionary, warnings: PackedStringArray) -> void:
	var id := int(deck.get("id", -1))
	var plate := vec2_of(deck.get("size"), Vector2(1, 1))
	for opening_variant in deck.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var off := vec2_of(opening.get("offset"), Vector2.ZERO)
		var hole := vec2_of(opening.get("size"), Vector2(1, 1))
		if off.x < -0.01 or off.y < -0.01 or off.x + hole.x > plate.x + 0.01 or off.y + hole.y > plate.y + 0.01:
			warnings.append("deck #%d hole outside plate" % id)


func _validate_room_openings(room: Dictionary, warnings: PackedStringArray) -> void:
	var id := int(room.get("id", -1))
	var size := vec3_of(room.get("size"), Vector3(2, 3, 2))
	for opening_variant in room.get("openings", []) as Array:
		var opening := opening_variant as Dictionary
		var face := str(opening.get("face", ""))
		if face in ["floor", "ceiling"]:
			var off := vec2_of(opening.get("offset"), Vector2.ZERO)
			var hole := vec2_of(opening.get("size"), Vector2(1, 1))
			if off.x + hole.x > size.x + 0.01 or off.y + hole.y > size.z + 0.01:
				warnings.append("room #%d plate opening outside footprint" % id)
			continue
		var run := size.x if face in ["n", "s"] else size.z
		var off_u := float(opening.get("offset", 0.0))
		var width := float(opening.get("width", 1.0))
		var sill := float(opening.get("sill", 0.0))
		var oh := float(opening.get("height", 2.0))
		if off_u + width > run + 0.01:
			warnings.append("room #%d opening past %s face" % [id, face])
		if sill + oh > size.y + 0.01:
			warnings.append("room #%d opening past room height" % id)


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"context": context,
		"hull_id": hull_id,
		"palette": palette.duplicate(true),
		"walls": walls.duplicate(true),
		"decks": decks.duplicate(true),
		"rooms": rooms.duplicate(true),
		"items": items.duplicate(true),
	}


static func from_dict(data: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.context = str(data.get("context", "vessel"))
	if plan.context not in CONTEXTS:
		plan.context = "vessel"
	plan.hull_id = str(data.get("hull_id", ""))
	plan.palette = (data.get("palette", {}) as Dictionary).duplicate(true)
	plan.walls = (data.get("walls", []) as Array).duplicate(true)
	plan.decks = (data.get("decks", []) as Array).duplicate(true)
	plan.rooms = (data.get("rooms", []) as Array).duplicate(true)
	plan.items = (data.get("items", []) as Array).duplicate(true)
	var highest := 0
	for collection in [plan.walls, plan.decks, plan.rooms, plan.items]:
		for entity in collection:
			highest = maxi(highest, int((entity as Dictionary).get("id", 0)))
			## Guarantee openings arrays exist so Studio can append safely.
			var dict := entity as Dictionary
			if not dict.has("openings") and not dict.has("item_id"):
				dict["openings"] = []
	plan._next_id = highest + 1
	return plan


static func vec3_of(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Vector3(float(list[0]), float(list[1]), float(list[2]))
	return fallback


static func vec2_of(value: Variant, fallback := Vector2.ZERO) -> Vector2:
	if value is Array and (value as Array).size() >= 2:
		var list := value as Array
		return Vector2(float(list[0]), float(list[1]))
	return fallback
