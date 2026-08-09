class_name StructurePlan
extends RefCounted

## Parametric construction document shared by vessels and land buildings.
##
## Structure is DRAWN, not stacked: five primitives, each one part regardless
## of size, replace fields of voxel bricks:
##   walls  — {id, start:[x,y,z], axis:"x"|"z"|"+x+z"|"+x-z"|"-x+z"|"-x-z",
##             length, height, thickness,
##             color?, openings:[{type, offset, width, height, sill}]}
##   decks  — {id, origin:[x,y,z], size:[w,l], thickness, color?,
##             openings:[{type, offset:[dx,dz], size:[w,l]}]}
##   rooms  — {id, origin:[x,y,z], size:[w,h,l], wall_thickness, color?,
##             open_faces?:["n"|"s"|"e"|"w"], — faces with NO wall (corridor
##                        ends, lean-tos); a corridor is a room with both
##                        ends open.
##             openings:[{face:"n"|"s"|"e"|"w"|"floor"|"ceiling", type,
##                        offset, width, height, sill}]}
##   stairs — {id, start:[x,y,z], dir:"+x"|"-x"|"+z"|"-z", length, width,
##             height, color?}  start = footprint min corner at the LOW end's
##             base level; dir = climb direction; solid stepped run whose top
##             tread lands flush on start.y + height.
##   items  — {id, item_id, cell:[x,y,z], yaw}  (point equipment, later slice)
##
## Coordinates are grid-corner points in whole metres. For vessels x/z match
## DeckGrid cell corners (0..width, 0..length) and y is metres above the deck
## plane. Rooms expand into walls + floor + ceiling plates at bake time —
## see StructureBaker.expand_room().
##
## A wall `axis` names the DIRECTION of the run away from `start`, never a line:
## "x" and "z" run along +X and +Z, and each diagonal spells its signed step, so
## "+x-z" leaves `start` heading toward +X and -Z at 45°. `length` is measured
## ALONG the run in every case, so a diagonal covers length / sqrt(2) metres on
## each axis; `thickness` stays perpendicular to the run (centred on it) and
## `height` stays vertical. All four diagonals exist — two would cover the same
## two lines — so a perimeter can be traced run after run without back-solving a
## start corner for the ones that head toward -X or -Z.
##
## On a vessel the bow is -Z and port is -X. Every hull in the catalogue tapers
## at exactly 45° (bow_taper_m == beam_m * 0.5, and CatalogHullVessel.make_grid()
## hardcodes the same rule), so from the bow shoulder "+x-z" follows the port
## stem and "-x-z" the starboard stem, on every hull.

const FORMAT := "structure_plan_v1"
const DEFAULT_WALL_THICKNESS := 1.0 / 6.0
const DEFAULT_PLATE_THICKNESS := 0.15
const DEFAULT_ROOM_HEIGHT := 3.0

const WALL_AXES := ["x", "z"]
const WALL_DIAGONAL_AXES := ["+x+z", "+x-z", "-x+z", "-x-z"]

const OPENING_DOOR := "door"
const OPENING_WINDOW := "window"
const OPENING_HOLE := "hole"
const OPENING_STAIRWELL := "stairwell"

var context := "vessel" ## "vessel" | "building"
var hull_id := ""
var walls: Array = []
var decks: Array = []
var rooms: Array = []
var stairs: Array = []
var items: Array = []
var palette: Dictionary = {}
var _next_id := 1


static func is_plan(data: Dictionary) -> bool:
	return str(data.get("format", "")) == FORMAT


func allocate_id() -> int:
	var id := _next_id
	_next_id += 1
	return id


## Unit run direction for a wall axis. Unknown names are a mis-authored plan and
## say so — silently baking them along +X is how a bulwark ends up somewhere
## nobody drew it.
static func wall_run(axis: String) -> Vector3:
	match axis:
		"x":
			return Vector3(1, 0, 0)
		"z":
			return Vector3(0, 0, 1)
		"+x+z":
			return Vector3(1, 0, 1).normalized()
		"+x-z":
			return Vector3(1, 0, -1).normalized()
		"-x+z":
			return Vector3(-1, 0, 1).normalized()
		"-x-z":
			return Vector3(-1, 0, -1).normalized()
	push_error(
		"StructurePlan: unknown wall axis \"%s\" — expected one of %s"
		% [axis, WALL_AXES + WALL_DIAGONAL_AXES]
	)
	return Vector3(1, 0, 0)


static func is_diagonal_axis(axis: String) -> bool:
	return WALL_DIAGONAL_AXES.has(axis)


func add_wall(start: Vector3, axis: String, length: float, height := DEFAULT_ROOM_HEIGHT, thickness := DEFAULT_WALL_THICKNESS) -> Dictionary:
	var wall := {
		"id": allocate_id(),
		"start": [start.x, start.y, start.z],
		"axis": axis if (axis == "z" or is_diagonal_axis(axis)) else "x",
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
		"openings": [],
	}
	rooms.append(room)
	return room


func add_stair(start: Vector3, dir: String, length: float, width := 1.0, height := DEFAULT_ROOM_HEIGHT) -> Dictionary:
	var stair := {
		"id": allocate_id(),
		"start": [start.x, start.y, start.z],
		"dir": dir if dir in ["+x", "-x", "+z", "-z"] else "+x",
		"length": maxf(length, 1.0),
		"width": maxf(width, 0.5),
		"height": clampf(height, 0.5, 12.0),
	}
	stairs.append(stair)
	return stair


func add_item(item_id: String, cell: Vector3i, yaw := 0) -> Dictionary:
	var item := {
		"id": allocate_id(),
		"item_id": item_id,
		"cell": [cell.x, cell.y, cell.z],
		"yaw": yaw,
	}
	items.append(item)
	return item


func entity_by_id(id: int) -> Dictionary:
	for collection in [walls, decks, rooms, stairs, items]:
		for entity in collection:
			if int((entity as Dictionary).get("id", -1)) == id:
				return entity
	return {}


func remove_entity(id: int) -> bool:
	for collection in [walls, decks, rooms, stairs, items]:
		for index in (collection as Array).size():
			if int(((collection as Array)[index] as Dictionary).get("id", -1)) == id:
				(collection as Array).remove_at(index)
				return true
	return false


func is_empty() -> bool:
	return walls.is_empty() and decks.is_empty() and rooms.is_empty() and stairs.is_empty() and items.is_empty()


func entity_count() -> int:
	return walls.size() + decks.size() + rooms.size() + stairs.size() + items.size()


func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"context": context,
		"hull_id": hull_id,
		"palette": palette.duplicate(true),
		"walls": walls.duplicate(true),
		"decks": decks.duplicate(true),
		"rooms": rooms.duplicate(true),
		"stairs": stairs.duplicate(true),
		"items": items.duplicate(true),
	}


static func from_dict(data: Dictionary) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.context = str(data.get("context", "vessel"))
	plan.hull_id = str(data.get("hull_id", ""))
	plan.palette = (data.get("palette", {}) as Dictionary).duplicate(true)
	plan.walls = (data.get("walls", []) as Array).duplicate(true)
	plan.decks = (data.get("decks", []) as Array).duplicate(true)
	plan.rooms = (data.get("rooms", []) as Array).duplicate(true)
	plan.stairs = (data.get("stairs", []) as Array).duplicate(true)
	plan.items = (data.get("items", []) as Array).duplicate(true)
	var highest := 0
	for collection in [plan.walls, plan.decks, plan.rooms, plan.stairs, plan.items]:
		for entity in collection:
			highest = maxi(highest, int((entity as Dictionary).get("id", 0)))
	plan._next_id = highest + 1
	return plan


static func vec3_of(value: Variant, fallback := Vector3.ZERO) -> Vector3:
	if value is Array and (value as Array).size() >= 3:
		var list := value as Array
		return Vector3(float(list[0]), float(list[1]), float(list[2]))
	return fallback
