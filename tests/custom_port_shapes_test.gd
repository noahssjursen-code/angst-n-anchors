extends Node

var checks:=0
var failures:=0
const Rules=preload("res://scripts/port/state/custom_port_placement_rules.gd")

func _ready() -> void:
	var triangle: Dictionary={"kind":"platform","footprint_m":[4,4],"footprint_polygon_m":[[-2,-2],[2,2],[-2,2]],"placement_layer":"platform"}
	var square: Dictionary={"kind":"platform","footprint_m":[4,4],"placement_layer":"platform"}
	var prop: Dictionary={"kind":"decoration","footprint_m":[1,1],"requires_support":true,"placement_layer":"surface"}
	var catalog: Dictionary={"triangle":triangle,"square":square,"prop":prop}
	var a:=_piece("a","triangle",Vector3.ZERO)
	var b:=_piece("b","triangle",Vector3.ZERO,180)
	_check(Rules.validate({"placements":[a,b]},catalog).is_empty(),"Complementary triangular foundations share one4mcell withoutoverlap")
	_check(not Rules.validate({"placements":[a,a.duplicate(true)]},catalog).is_empty(),"Samehalf cannot be occupiedtwice")
	var supported:=_piece("supported","prop",Vector3(-1,0,1))
	var over_water:=_piece("water","prop",Vector3(1,0,-1))
	_check(Rules.validate({"placements":[a,supported]},catalog).is_empty(),"Prop in filledtriangle supported")
	_check(not Rules.validate({"placements":[a,over_water]},catalog).is_empty(),"Missingdiagonalcorner providesnosupport")
	_check(Rules.validate({"placements":[a,b,_piece("across","prop",Vector3.ZERO)]},catalog).is_empty(),"Prop maycrossfilleddiagonaljoin")
	_check(not Rules.validate({"placements":[a,_piece("square","square",Vector3.ZERO)]},catalog).is_empty(),"Square overlaps actualtriangle")
	var plots: Array=[{"rect_m":[-2,-2,2,4]},{"rect_m":[0,1,2,1]}]
	_check(not Rules.placement_within_plots(a,catalog,plots),"Triangularextension cannotcrossunownedwedge")
	_check(Rules.placement_within_plots(a,catalog,[{"rect_m":[-2,-2,4,4]}]),"Ownedwholecell acceptsdiagonal")
	for yaw in [0,90,180,270]:
		var row:=_piece("r","triangle",Vector3(12,0,8),yaw)
		var polygon: PackedVector2Array=Rules.polygons(row,triangle)[0]
		_check(is_equal_approx(Rules.polygon_area(polygon),8),"Rotatedtriangle retains8m2")
		_check(Rules.polygon_bounds(polygon).size.is_equal_approx(Vector2(4,4)),"Quarterturn retainssnapfootprint")
	print("CUSTOM_PORT_SHAPES_", "PASS" if failures==0 else "FAIL", " checks=",checks," failures=",failures)
	get_tree().quit(0 if failures==0 else 1)

func _piece(id:String,asset:String,at:Vector3,yaw:=0.0) -> Dictionary:
	return {"id":id,"asset_id":asset,"position_m":[at.x,at.y,at.z],"yaw_degrees":yaw,"attributes":{}}

func _check(value:bool,message:String) -> void:
	if not value: push_error(message); failures+=1
	checks+=1
