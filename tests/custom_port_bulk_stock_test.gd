extends Node

const STOCK = preload("res://scripts/port/building/custom_port_bulk_stock_layout.gd")
var failures: Array[String] = []
var checks := 0

func _ready() -> void:
	var store: Dictionary={"accepted_commodities":["iron_ore","coal"],"capacity_kg":450000,"lots":[
		{"id":"ore-a","commodity_id":"iron_ore","quantity":200000,"unit_mass_kg":1,"attributes":{}},
		{"id":"ore-b","commodity_id":"iron_ore","quantity":20000,"unit_mass_kg":1,"attributes":{}},
		{"id":"coal-a","commodity_id":"coal","quantity":80000,"unit_mass_kg":1,"attributes":{}}]}
	var before:=JSON.stringify(store)
	var known: Array=["iron_ore","grain","coal"]
	for size in [Vector2(8,40),Vector2(40,8),Vector2(24,24)]:
		var projected: Dictionary=STOCK.project(store,size,known)
		_check(projected.size()==3,"Catalog reserves each commodity bay")
		_check(projected.iron_ore.mass_kg==220000 and projected.iron_ore.lot_ids==["ore-a","ore-b"],"Both consignments contribute to ore visual without losing IDs")
		_check(projected.coal.mass_kg==80000 and projected.grain.mass_kg==0,"Each commodity has its own real balance")
		for id in projected:
			var pile: Dictionary=projected[id]
			_check(Rect2(-size*.5,size).encloses(pile.bay_m),"Bay is contained by actual receiving pad")
			for other in projected:
				if id==other:continue
				# Render-space Vector2 edges can differ by a few float32 ULPs.
				_check(not pile.bay_m.grow(-.0001).intersects(projected[other].bay_m),"Commodity bays remain separate to sub-millimetre render precision")
		var changed:=store.duplicate(true)
		changed.lots.reverse()
		changed.accepted_commodities.reverse()
		_check(STOCK.project(changed,size,known)==projected,"Document array order does not move piles")
		changed.lots=[]
		var empty: Dictionary=STOCK.project(changed,size,known)
		for id in projected:_check(empty[id].position_m==projected[id].position_m,"Empty stock preserves bay positions for later arrivals")
	_check(JSON.stringify(store)==before,"Projection never mutates authoritative stock")
	_check(STOCK.fill_scale(0,450000)==Vector3.ZERO and STOCK.fill_scale(450000,450000)==Vector3.ONE,"Fill has finite empty and full endpoints")
	if failures.is_empty():print("CUSTOM PORT BULK STOCK PASS (%d checks)"%checks)
	else:
		for failure in failures:push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func _check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failures.append(message)
