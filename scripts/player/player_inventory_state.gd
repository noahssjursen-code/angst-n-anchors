class_name PlayerInventoryState
extends RefCounted
## Personal equipment only. Bulk goods stay in existing company/vessel storage.
const HOTBAR_COUNT := 6
const BAG_COUNT := 24
const SLOT_COUNT := HOTBAR_COUNT+BAG_COUNT
const VERSION := 1

static func empty() -> Dictionary:
	var slots: Array=[]
	for i in SLOT_COUNT: slots.append({})
	return {"version":VERSION,"slots":slots,"selected_slot":-1,"clothing":{}}

static func normalize(raw: Variant) -> Dictionary:
	var out:=empty()
	if not raw is Dictionary: return out
	var seen: Dictionary={}
	var slots: Array=raw.get("slots",[]) if raw.get("slots",[]) is Array else []
	for i in mini(SLOT_COUNT,slots.size()):
		if not slots[i] is Dictionary: continue
		var item: Dictionary=slots[i]
		var uid:=str(item.get("uid",""))
		var id:=str(item.get("item_id",""))
		if uid.is_empty() or id.is_empty() or seen.has(uid): continue
		seen[uid]=true
		out.slots[i]={"uid":uid,"item_id":id,"quantity":maxi(1,int(item.get("quantity",1))),"attributes":item.get("attributes",{}).duplicate(true) if item.get("attributes",{}) is Dictionary else {}}
	out.selected_slot=clampi(int(raw.get("selected_slot",-1)),-1,HOTBAR_COUNT-1)
	out.clothing=raw.get("clothing",{}).duplicate(true) if raw.get("clothing",{}) is Dictionary else {}
	return out

static func selected(raw: Dictionary) -> Dictionary:
	var state:=normalize(raw)
	var index:=int(state.selected_slot)
	return state.slots[index].duplicate(true) if index>=0 else {}

static func stock() -> Array[Dictionary]:
	var out: Array[Dictionary]=[]
	for id in ["fishing_rod","harpe"]:
		var item:=VesselEquipment.item(id)
		item["description"]="Heavy pilks for larger fish at depth." if id=="fishing_rod" else "Six hooks for smaller schooling fish."
		out.append(item)
	return out

static func change(raw: Dictionary, action: String, body: Dictionary, uid: String="") -> Dictionary:
	var state:=normalize(raw)
	match action:
		"inventory.ensure": pass
		"inventory.purchase":
			var id:=str(body.get("item_id",""))
			if id not in ["fishing_rod","harpe"]: return {"ok":false,"message":"This item is not available."}
			var free:=-1
			for i in SLOT_COUNT:
				if state.slots[i].is_empty(): free=i;break
			if free<0:return {"ok":false,"message":"Your inventory is full."}
			state.slots[free]={"uid":uid,"item_id":id,"quantity":1,"attributes":{}}
		"inventory.move":
			var a:=int(body.get("from",-1));var b:=int(body.get("to",-1))
			if a<0 or b<0 or a>=SLOT_COUNT or b>=SLOT_COUNT:return {"ok":false,"message":"Choose valid inventory slots."}
			var item: Dictionary=state.slots[a];state.slots[a]=state.slots[b];state.slots[b]=item
			# Moving selected equipment into the bag stows it.
			if state.selected_slot in [a,b]: state.selected_slot=-1
		"inventory.select":
			var slot:=int(body.get("slot",-1))
			if slot< -1 or slot>=HOTBAR_COUNT:return {"ok":false,"message":"Choose hotbar slot 1-6."}
			state.selected_slot=slot
		_ : return {"ok":false,"message":"Unknown inventory action."}
	return {"ok":true,"inventory":state}
