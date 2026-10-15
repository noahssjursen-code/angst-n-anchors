extends Node
const HOME=preload("res://scripts/port/building/custom_port_home_placement.gd")
var failures: Array[String]=[]
var checks:=0

func _ready() -> void:
	if not ShipyardPlaytestMode.active():get_tree().quit(1);return
	var catalog:=CustomPortCatalog.definitions()
	var record: Dictionary={"placements":[]}
	check(not HOME.find(HOME.prepare(record,catalog)).ok,"No floor means no invented deck home")
	record.placements=[CustomPortCatalog.placement("floor","foundation_8m",Vector3(4,0,4))]
	var context:=HOME.prepare(record,catalog)
	check(HOME.find(context).local==Vector3(4,.15,4),"An empty supported floor retains its centre")
	check(not HOME.supported(context,Vector2(.1,.1)),"The whole capsule footprint must fit inside the deck edge")
	record.placements.append(CustomPortCatalog.placement("wall","workshop_wall_4m",Vector3(4,0,4)))
	context=HOME.prepare(record,catalog)
	var found: Dictionary=HOME.find(context)
	check(found.ok and found.local!=Vector3(4,.15,4),"A centre wall selects another point on the same floor")
	check(HOME.clear(context,Vector2(found.local.x,found.local.z)),"Replacement point is genuinely clear")
	check(HOME.find(context)==found,"Unchanged data chooses the same home")
	record.placements.back().yaw_degrees=90
	context=HOME.prepare(record,catalog)
	check(not HOME.clear(context,Vector2(4,4)) and HOME.find(context).ok,"Rotated wall geometry is respected")
	record.placements.pop_back()
	record.placements.append(CustomPortCatalog.placement("roof","workshop_roof_4m",Vector3(4,0,4)))
	context=HOME.prepare(record,catalog)
	check(HOME.find(context).local==Vector3(4,.15,4),"A roof at 3m leaves normal standing headroom")
	check(not HOME.find(HOME.prepare(record,catalog,.35,3.2)).local==Vector3(4,.15,4),"Taller capsules use their actual required headroom")
	for asset in ["foundation_triangle_4m","foundation_chamfer_4m"]:
		for yaw in [0,90,180,270]:
			record.placements=[CustomPortCatalog.placement("shaped",asset,Vector3.ZERO,yaw)]
			context=HOME.prepare(record,catalog)
			found=HOME.find(context)
			check(found.ok and HOME.supported(context,Vector2(found.local.x,found.local.z)),"Shaped quay supports full capsule at rotation "+str(yaw))
	record.placements=[CustomPortCatalog.placement("floor","foundation_8m",Vector3(4,0,4)),CustomPortCatalog.placement("solid","warehouse",Vector3(4,0,4))]
	context=HOME.prepare(record,catalog)
	check(not HOME.find(context).ok,"A completely occupied floor does not return an unsafe fallback")
	record.placements.append(CustomPortCatalog.placement("next-floor","foundation_8m",Vector3(12,0,4)))
	found=HOME.find(HOME.prepare(record,catalog))
	check(found.ok and found.local.x>10,"Search continues to another tile when the first is occupied")
	record.placements=[CustomPortCatalog.placement("plant","fish_landing_plant",Vector3.ZERO)]
	context=HOME.prepare(record,catalog)
	check(HOME.clear(context,Vector2(3.2,0)),"Plant data keeps its 1.75m aisle clear")
	check(not HOME.clear(context,Vector2(-4,2.35)),"Tank/store occupied area is blocked")
	record.placements=[CustomPortCatalog.placement("floor","foundation_8m",Vector3(4,0,4))]
	context=HOME.prepare(record,catalog)
	var before:=record.duplicate(true)
	found=HOME.find(context,func(at: Vector3)->bool:return at.z<3)
	check(found.ok and found.local.z<3,"Optional live-collision refinement can reject a data candidate")
	check(record==before,"Candidate search cannot mutate port data")
	print("CUSTOM PORT HOME PLACEMENT ","PASS" if failures.is_empty() else "FAIL"," checks=",checks," failures=",failures.size())
	for failure in failures:push_error(failure)
	get_tree().quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:failures.append(label)
