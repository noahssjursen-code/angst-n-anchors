extends SceneTree

## SCRATCH PROBE (leading underscore -> skipped by tools/gate.sh discovery).
## Drawings built to get a WRONG `true` out of `PlanOutfit.enclosure`. Prints
## what each one reports; asserts nothing. The ones that succeed are named as
## limits in `plan_outfit.gd`'s header.


func _initialize() -> void:
	_say("1. a funnel trunk 1.6 x 1.6 x 5 m with a scuttle in it", _trunk(1.6, 5.0, "window"))
	_say("2. the same trunk with no opening at all", _trunk(1.6, 5.0, ""))
	_say("3. a shipping container, doors DRAWN as door openings", _container(true))
	_say("4. the same container with its doors not drawn", _container(false))
	_say("5. a shelter deck: bulwark 1.2 m all round, deck 3 m over it", _shelter(1.2))
	_say("6. the same with the bulwark raised to the deckhead", _shelter(2.9))
	_say("7. a chain locker under a raised foredeck, 2.0 m, no opening", _locker(false))
	_say("8. ...with a hatch drawn as a `hole` in the deck over it", _locker(true))
	_say("9. two decks 2 m apart on posts, open on every side", _posts())
	_say("10. a wall ring with a roof, and the roof is a `stairwell` hole", _open_roof())
	quit(0)


func _say(label: String, plan: StructurePlan) -> void:
	var report := PlanOutfit.enclosure(plan)
	print("%-58s cabin=%-5s  %s" % [label, str(bool(report["cabin"])), str(report["why"])])


## A square trunk `side` across and `height` tall, optionally pierced.
func _trunk(side: float, height: float, opening: String) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	var a := plan.add_wall(Vector3(4.0, 0.0, 12.0), "x", side, height)
	plan.add_wall(Vector3(4.0, 0.0, 12.0 + side), "x", side, height)
	plan.add_wall(Vector3(4.0, 0.0, 12.0), "z", side, height)
	plan.add_wall(Vector3(4.0 + side, 0.0, 12.0), "z", side, height)
	plan.add_deck(Vector3(4.0, height, 12.0), Vector2(side, side))
	if not opening.is_empty():
		(a["openings"] as Array).append({
			"type": opening, "offset": side * 0.5 - 0.2, "width": 0.4, "height": 0.4, "sill": 1.3,
		})
	return plan


## A 12 m ISO box: 2.44 wide, 2.59 tall, 6.06 long, on the deck.
func _container(draw_doors: bool) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	var aft := plan.add_wall(Vector3(3.0, 0.0, 10.0), "x", 2.44, 2.59)
	plan.add_wall(Vector3(3.0, 0.0, 16.06), "x", 2.44, 2.59)
	plan.add_wall(Vector3(3.0, 0.0, 10.0), "z", 6.06, 2.59)
	plan.add_wall(Vector3(5.44, 0.0, 10.0), "z", 6.06, 2.59)
	plan.add_deck(Vector3(3.0, 2.59, 10.0), Vector2(2.44, 6.06))
	plan.add_deck(Vector3(3.0, 0.15, 10.0), Vector2(2.44, 6.06))
	if draw_doors:
		for offset in [0.1, 1.25]:
			(aft["openings"] as Array).append({
				"type": "door", "offset": offset, "width": 1.1, "height": 2.4, "sill": 0.1,
			})
	return plan


## A bulwark `height` tall round a 6 x 8 m patch, with a deck 3 m up over it.
func _shelter(height: float) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	var a := plan.add_wall(Vector3(2.0, 0.0, 10.0), "x", 6.0, height)
	plan.add_wall(Vector3(2.0, 0.0, 18.0), "x", 6.0, height)
	plan.add_wall(Vector3(2.0, 0.0, 10.0), "z", 8.0, height)
	plan.add_wall(Vector3(8.0, 0.0, 10.0), "z", 8.0, height)
	plan.add_deck(Vector3(2.0, 3.0, 10.0), Vector2(6.0, 8.0))
	(a["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	return plan


## A void under a raised foredeck: walls, a deck over, and either nothing or a
## deck hatch declared as a `hole`.
func _locker(hatch: bool) -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	plan.add_wall(Vector3(2.0, 0.0, 2.0), "x", 6.0, 2.0)
	plan.add_wall(Vector3(2.0, 0.0, 6.0), "x", 6.0, 2.0)
	plan.add_wall(Vector3(2.0, 0.0, 2.0), "z", 4.0, 2.0)
	plan.add_wall(Vector3(8.0, 0.0, 2.0), "z", 4.0, 2.0)
	var deck := plan.add_deck(Vector3(2.0, 2.0, 2.0), Vector2(6.0, 4.0))
	if hatch:
		(deck["openings"] as Array).append({
			"type": "hole", "offset": [2.0, 1.0], "size": [1.0, 1.0],
		})
	return plan


## Two deck plates 2 m apart, carried on four spars, open on every side.
func _posts() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	plan.add_deck(Vector3(2.0, 0.2, 10.0), Vector2(6.0, 6.0))
	plan.add_deck(Vector3(2.0, 2.4, 10.0), Vector2(6.0, 6.0))
	for corner in [Vector2(2.2, 10.2), Vector2(7.8, 10.2), Vector2(2.2, 15.8), Vector2(7.8, 15.8)]:
		plan.add_item("spar", Vector3(corner.x, 0.2, corner.y), 0.0, {
			"points": [[0, 0, 0], [0, 2.2, 0]], "radius": 0.08, "solid": true,
		})
	return plan


## A ring of walls whose roof plate is almost entirely a stairwell.
func _open_roof() -> StructurePlan:
	var plan := StructurePlan.new()
	plan.hull_id = "hull_28x10"
	var front := plan.add_wall(Vector3(1.0, 0.0, 6.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, 0.0, 12.0), "x", 6.0, 2.6)
	plan.add_wall(Vector3(1.0, 0.0, 6.0), "z", 6.0, 2.6)
	plan.add_wall(Vector3(7.0, 0.0, 6.0), "z", 6.0, 2.6)
	var deck := plan.add_deck(Vector3(1.0, 2.6, 6.0), Vector2(6.0, 6.0))
	(deck["openings"] as Array).append({
		"type": "stairwell", "offset": [0.5, 0.5], "size": [5.0, 5.0],
	})
	(front["openings"] as Array).append({
		"type": "door", "offset": 2.4, "width": 1.2, "height": 2.1, "sill": 0.0,
	})
	return plan
