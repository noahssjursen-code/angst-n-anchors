class_name VesselEquipment
extends RefCounted

## Purchased stores belong to the durable vessel record, not its spawned scene.
static var _catalog: Array=[]

static func catalog() -> Array:
	if _catalog.is_empty():
		_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/equipment/shop.json")) as Array
	return _catalog.duplicate(true)

static func item(id: String) -> Dictionary:
	for entry: Dictionary in catalog():
		if entry.id==id:return entry.duplicate(true)
	return {}

static func normalize(raw: Variant) -> Array:
	var result: Array=[]
	var seen: Dictionary={}
	if not raw is Array:return result
	for entry in raw:
		if not entry is Dictionary:continue
		var uid:=str(entry.get("uid",""))
		var id:=str(entry.get("item_id",""))
		if uid.is_empty() or id.is_empty() or seen.has(uid):continue
		seen[uid]=true
		result.append({"uid":uid,"item_id":id,"quantity":clampi(int(entry.get("quantity",1)),1,999),"purchased_at_unix":int(entry.get("purchased_at_unix",0))})
	return result

static func count(record: Dictionary, id: String) -> int:
	var total:=0
	for entry in normalize(record.get("purchased_items",[])):
		if entry.item_id==id:total+=int(entry.quantity)
	return total


static func has_mount(record:Dictionary)->bool:
	for part in record.get("brick_layout",{}).get("parts",[]):
		if str(part.get("asset_id",""))=="hook_line_station":return true
	return false
