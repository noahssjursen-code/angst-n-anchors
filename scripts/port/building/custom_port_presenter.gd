class_name CustomPortPresenter
extends Node3D

## A projection of a JSON port. No ownership, stock or berth decisions live here.
signal operator_selected(placement_id: String)
signal vessel_presented(vessel_id: String, boat: BoatBody)
signal vessel_removing(vessel_id: String, boat: BoatBody)
const BULK_STOCK = preload("res://scripts/port/building/custom_port_bulk_stock_layout.gd")
var placement_nodes: Dictionary = {}
var berth_nodes: Dictionary = {}
var cargo_nodes: Dictionary = {}
var record: Dictionary = {}
var vessel_nodes: Dictionary = {}
var _rows: Dictionary = {}
var _stores: Dictionary = {}
var _berth_rows: Array = []
var _vessel_rows: Dictionary = {}
var _owned_vessels: Dictionary = {}
## Explicit workshop sailing opt-in. Streamed ports and existing static previews
## retain their original lifecycle; this never spawns an undocked record alone.
var retain_departed_vessels := false
## Explicit local document previews keep solid geometry and readable operators,
## but must never become targets of live mooring or cargo discovery.
var passive_services := false

## The workshop reconstructs frozen ships from its data. A streamed world port
## must opt out: production vessel replicas have a separate owner and lifetime.
@export var simulate_vessels := true:
	set(value):
		if simulate_vessels==value: return
		simulate_vessels=value
		if not value:
			_clear_vessels()
		elif is_inside_tree() and not record.is_empty():
			_show_vessels(_berth_rows)

func load_record(snapshot: Dictionary, berths: Array = []) -> void:
	if not record.is_empty() and str(record.get("id",""))!=str(snapshot.get("id","")):
		clear_record()
	var previous:=record
	record=snapshot.duplicate(true)
	var origin: Array=record.get("origin_m",[0,0,0])
	position=CustomPortCatalog.vector3(origin)
	var incoming:= {}
	var rebuilt: Dictionary = {}
	for row in record.get("placements",[]): incoming[str(row.id)]=row
	for id in placement_nodes.keys():
		if not incoming.has(id) or incoming[id]!=_rows.get(id,{}):
			_drop(placement_nodes[id]); placement_nodes.erase(id)
	for row in record.get("placements",[]):
		if not placement_nodes.has(str(row.id)):
			_add_placement(row)
			rebuilt[str(row.id)]=true
	_rows=incoming.duplicate(true)
	if berths!=_berth_rows:
		for node in berth_nodes.values(): _drop(node)
		berth_nodes.clear()
		for berth in berths: _add_berth(berth)
		_berth_rows=berths.duplicate(true)
	var stores_now: Dictionary={}
	for store in record.get("stores",[]):
		stores_now[str(store.id)]=store
		if _stores.get(str(store.id),{})!=store or rebuilt.has(str(store.get("placement_id",""))): _show_store(store)
	for id in _stores:
		if not stores_now.has(id): _clear_store(_stores[id])
	_stores=stores_now.duplicate(true)
	if simulate_vessels and (previous.get("vessels",[])!=record.get("vessels",[]) or berths!=previous.get("_presented_berths",[])):
		_show_vessels(berths)
	record._presented_berths=berths.duplicate(true)
	if passive_services:_suppress_live_service_discovery(self)


func _suppress_live_service_discovery(node: Node) -> void:
	for group in [MooringComponent.DOCK_MOORING_GROUP,CargoSlotPadComponent.PAD_GROUP,
			CargoSlotPadComponent.YARD_PAD_GROUP,ContainerNode.GROUP,"container_yard_drop",
			"quay_berth_slot","provision_crane_auto"]:
		if node.is_in_group(group):node.remove_from_group(group)
	for child in node.get_children():_suppress_live_service_discovery(child)

## Unload only this projection. Never search global ship groups or adopt a
## production replica because it happens to share an id with a simulated ship.
func clear_record() -> void:
	_clear_vessels()
	for node in placement_nodes.values(): _drop(node)
	for node in berth_nodes.values(): _drop(node)
	placement_nodes.clear()
	berth_nodes.clear()
	cargo_nodes.clear()
	_rows.clear()
	_stores.clear()
	_berth_rows.clear()
	record.clear()

func _clear_vessels() -> void:
	for id in _owned_vessels.keys(): _drop_owned_vessel(id)
	vessel_nodes.clear()
	_vessel_rows.clear()

func _drop_owned_vessel(id: String) -> void:
	var boat: BoatBody=_owned_vessels.get(id)
	if is_instance_valid(boat):
		vessel_removing.emit(id,boat)
		if boat is ImportedDraftVessel and is_instance_valid(boat.gangway):
			boat.gangway.apply_berth_projection(null,false)
		_drop(boat)
	_owned_vessels.erase(id)
	vessel_nodes.erase(id)

func _drop(node: Node) -> void:
	if not is_instance_valid(node): return
	if node.get_parent()!=null: node.get_parent().remove_child(node)
	node.queue_free()

func _add_placement(row: Dictionary) -> void:
	var spec:=CustomPortCatalog.definition(str(row.asset_id))
	if spec.is_empty():
		push_error("Missing port asset: "+str(row.asset_id))
		return
	var node: Node3D
	if str(row.asset_id)=="quay_bollard":
		node=Node3D.new()
		var post:=MooringPost.new()
		post.service_discovery_enabled=not passive_services
		post.name="MooringBollard"
		node.add_child(post)
	elif spec.has("cells"):
		node=PlotBuildVisuals.create(spec,false,true,float(row.get("attributes",{}).get("support_depth_m",4.0)))
		if spec.has("visual"):node.set("passive_services",passive_services)
	elif str(spec.kind)=="npc":
		var npc:=preload("res://scripts/port/building/custom_port_operator.gd").new()
		npc.display_name=str(row.get("attributes",{}).get("display_name","Port operator"))
		npc.interaction_requested.connect(func()->void:operator_selected.emit(str(row.id)))
		node=npc
	elif spec.has("model_path") or str(spec.get("factory","")) == "fish_landing_plant":
		node=asset_visual(spec)
	else: return
	node.name=str(row.id).validate_node_name()
	node.position=CustomPortCatalog.vector3(row.position_m)
	node.rotation.y=deg_to_rad(float(row.get("yaw_degrees",0)))
	node.set_meta("port_placement_id",str(row.id))
	add_child(node)
	if spec.has("model_path"):
		var attrs: Dictionary=row.get("attributes",{})
		if str(spec.kind)=="platform": CustomHarbourAssetLibrary.set_foundation_depth(node,float(attrs.get("support_depth_m",4.0)))
		if attrs.has("door_open"): CustomHarbourAssetLibrary.set_door_open(node,bool(attrs.door_open))
		if attrs.has("wall_colour"): CustomHarbourAssetLibrary.set_wall_colour(node,Color(str(attrs.wall_colour)))
	placement_nodes[str(row.id)]=node

static func asset_visual(spec: Dictionary, ghost := false, valid := true) -> Node3D:
	var root:=preload("res://scripts/port/building/custom_harbour_asset_library.gd").instantiate(str(spec.id),not ghost,not ghost)
	if root==null: return Node3D.new()
	if root.has_method("set_preview"):
		root.set_preview(ghost,valid)
	if ghost:
		var material:=StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency=BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color=Color(.28,1,.57,.32) if valid else Color(1,.22,.16,.38)
		for child in root.find_children("*","GeometryInstance3D",true,false):
			child.material_override=material
	for body in root.find_children("*","CollisionObject3D",true,false): body.set_meta("plot_build_visual",root)
	return root

func _add_berth(berth: Dictionary) -> void:
	if passive_services:return
	# The presenter publishes the proven slots through the existing berth type.
	# No HarbourRegistry registration until a gameplay authority owns this port.
	var slot:=QuayBerthSlot.new()
	slot.set_meta("custom_port_berth",berth.duplicate(true))
	slot.berth_id=str(berth.id)
	slot.length_m=float(berth.get("length_m",berth.get("max_length_m",0)))
	slot.name="Berth_"+str(berth.id).validate_node_name()
	var edge_a:=CustomPortCatalog.vector3(berth.edge_start_m)
	var edge_b:=CustomPortCatalog.vector3(berth.edge_end_m)
	slot.position=(edge_a+edge_b)*.5
	slot.water_dir_local=CustomPortCatalog.vector3(berth.outward_normal)
	slot.face_offset_m=0
	slot.berth_gap_m=float(berth.fender_gap_m)
	add_child(slot)
	berth_nodes[str(berth.id)]=slot
	for id in berth.get("bollard_ids",[]):
		var post: Node3D=placement_nodes.get(str(id))
		if post==null: continue
		var found: Node=post.find_child("MooringBollard",true,false)
		if found!=null: slot.add_bollard(found)

func _show_store(store: Dictionary) -> void:
	_clear_store(_stores.get(str(store.id),store))
	var owner_node: Node3D=placement_nodes.get(str(store.get("placement_id","")))
	if owner_node==null: return
	if owner_node.has_method("apply_store"):
		if not owner_node.apply_store(store): push_error("Fish store cannot be fully projected: "+str(store.id))
		for lot in store.get("lots",[]): cargo_nodes[str(lot.id)]=owner_node.bank
		return
	var pad: CargoSlotPadComponent=owner_node.find_child("CargoPad",true,false) as CargoSlotPadComponent
	if pad==null:
		_show_bulk(store,owner_node)
		return
	for lot in store.get("lots",[]):
		var attrs: Dictionary=lot.get("attributes",{})
		if not attrs.has("container_type"): continue
		for index in int(lot.quantity):
			var unit:=ContainerUnit.create("%s-%d" % [lot.id,index],str(lot.commodity_id),float(lot.unit_mass_kg),str(attrs.container_type))
			unit.destination_port_id=str(attrs.get("destination_port_id",""))
			unit.paint_variant=int(attrs.get("paint_variant",index%8))
			if pad.add_container(unit)<0:
				push_error("Port stock exceeds physical container yard capacity: "+str(store.id))
				return
		cargo_nodes[str(lot.id)]=pad

func _clear_store(store: Dictionary) -> void:
	var owner: Node3D=placement_nodes.get(str(store.get("placement_id","")))
	if owner!=null:
		if owner.has_method("apply_store"):
			var empty := store.duplicate(true)
			empty.lots=[]
			owner.apply_store(empty)
		var pad:=owner.find_child("CargoPad",true,false)
		if pad is CargoSlotPadComponent: pad.clear_all()
		var bulk:=owner.find_child("StoredBulk",true,false)
		if bulk!=null: _drop(bulk)
	for lot in store.get("lots",[]): cargo_nodes.erase(str(lot.id))

func _show_bulk(store: Dictionary, owner: Node3D) -> void:
	var pad:=owner.find_child("CargoPad",true,false) as Node3D
	if pad==null or not pad.has_meta("bulk_pad_size_m"): return
	var root:=Node3D.new()
	root.name="StoredBulk"
	pad.add_child(root)
	var piles:=bulk_stock_layout(store,pad.get_meta("bulk_pad_size_m"))
	for commodity in piles:
		var pile: Dictionary=piles[commodity]
		if float(pile.mass_kg)<=0: continue
		var mound:=OreMoundBuilder.build_mound(commodity,pile.size_m,hash(commodity))
		mound.position=pile.position_m
		mound.scale=BULK_STOCK.fill_scale(pile.mass_kg,float(store.capacity_kg))
		mound.set_meta("bulk_commodity_id",commodity)
		root.add_child(mound)
		for lot_id in pile.lot_ids:cargo_nodes[lot_id]=mound

func bulk_stock_layout(store: Dictionary,pad_size: Vector2) -> Dictionary:
	var placement: Dictionary=_rows.get(str(store.get("placement_id","")),{})
	var spec:=CustomPortCatalog.definition(str(placement.get("asset_id","")))
	return BULK_STOCK.project(store,pad_size,spec.get("attached_store",{}).get("accepted_commodities",[]))

func _show_vessels(berths: Array) -> void:
	# Normally these are frozen projections of simulated vessel records. The
	# workshop's explicit sailing session alone retains bodies after departure;
	# production vessel replicas still belong to their existing services.
	if not simulate_vessels: return
	var incoming: Dictionary={}
	for vessel in record.get("vessels",[]):
		if berth_nodes.has(str(vessel.get("berth_id",""))) or (retain_departed_vessels and _owned_vessels.has(str(vessel.id))): incoming[str(vessel.id)]=vessel
	for id in vessel_nodes.keys():
		# The public lookup is presentation-only, not an ownership transfer.
		if vessel_nodes[id]!=_owned_vessels.get(id):
			vessel_nodes.erase(id)
	for id in _owned_vessels.keys():
		if not incoming.has(id) or str(incoming[id].get("prebuilt_id",""))!=str(_vessel_rows.get(id,{}).get("prebuilt_id","")):
			_drop_owned_vessel(id)
		else:
			vessel_nodes[id]=_owned_vessels[id]
	for vessel in record.get("vessels",[]):
		var id:=str(vessel.id)
		var berth_id:=str(vessel.get("berth_id",""))
		if not incoming.has(id): continue
		if vessel_nodes.has(id):
			var existing: BoatBody=vessel_nodes[id]
			if not berth_id.is_empty(): _position_vessel(existing,vessel)
			elif retain_departed_vessels:
				if existing is ImportedDraftVessel and is_instance_valid(existing.gangway): existing.gangway.apply_berth_projection(null,false)
				existing.freeze=false
				existing.set_physics_process(true)
			if vessel.get("lots",[])!=_vessel_rows.get(id,{}).get("lots",[]): _show_vessel_cargo(existing,vessel)
			vessel_presented.emit(id,existing)
			continue
		var prebuilt_id:=str(vessel.get("prebuilt_id",""))
		var preset: Dictionary={}
		for entry in PrebuiltVesselCatalog.catalog_entries(false):
			if str(entry.prebuilt_id)==prebuilt_id: preset=entry; break
		if preset.is_empty(): continue
		var boat:=VesselSpawn.instantiate(str(preset.hull_id),preset.prebuilt_layout,str(preset.get("registration_id","")))
		if boat==null: continue
		boat.freeze=true
		boat.name="Docked_"+str(vessel.id)
		add_child(boat)
		_position_vessel(boat,vessel)
		boat.set_physics_process(false)
		_show_vessel_cargo(boat,vessel)
		vessel_nodes[str(vessel.id)]=boat
		_owned_vessels[str(vessel.id)]=boat
		vessel_presented.emit(id,boat)
	_vessel_rows=incoming.duplicate(true)

func _position_vessel(boat: BoatBody,vessel: Dictionary) -> void:
	var slot: QuayBerthSlot=berth_nodes[str(vessel.berth_id)]
	boat.freeze=true
	boat.set_physics_process(false)
	boat.linear_velocity=Vector3.ZERO
	boat.angular_velocity=Vector3.ZERO
	boat.transform=slot.transform*slot.ship_dock_local(float(vessel.beam_m)*.5,float(vessel.length_m))
	if retain_departed_vessels and bool(boat.get_meta("workshop_reverse_berth",false)):
		boat.rotate_y(PI)
	boat.position.y=WaveSurface.WATER_LEVEL-float(vessel.draft_m)-position.y
	boat.reset_physics_interpolation()
	if boat is ImportedDraftVessel and is_instance_valid(boat.gangway):
		boat.gangway.apply_berth_projection(slot,true)

func _show_vessel_cargo(boat: BoatBody,vessel: Dictionary) -> void:
	var pads: Array[CargoSlotPadComponent]=[]
	var holds: Array[BulkHoldComponent]=[]
	var catch_holds: Array[CatchHoldComponent]=[]
	for node in boat.find_children("*","Node3D",true,false):
		if node is CargoSlotPadComponent:
			pads.append(node)
			node.clear_all()
		elif node is BulkHoldComponent:
			holds.append(node)
			node.apply_state({"hold_id":node.hold_id,"capacity_tonnes_t":node.state.capacity_tonnes_t,"filled_tonnes_t":0})
		elif node is CatchHoldComponent:
			catch_holds.append(node)
			node.apply_state({"hold_id":node.hold_id,"capacity_kg":node.capacity_kg,"lots":[]})
	for lot in vessel.get("lots",[]):
		var attrs: Dictionary=lot.get("attributes",{})
		if not attrs.has("container_type"):
			var mode:=CustomPortState._handling_mode(lot)
			if mode=="bulk":
				var remaining:=BulkCargoLot.create(str(lot.commodity_id),float(lot.quantity)*float(lot.unit_mass_kg)/1000.0,str(attrs.get("consignment_id",lot.id)))
				for hold in holds:
					remaining=hold.accept_lot(remaining)
					if remaining.is_empty(): break
				if not remaining.is_empty(): push_error("Saved bulk cargo does not fit the actual ship: "+str(vessel.id))
			elif mode=="catch":
				var data: Dictionary=attrs.duplicate(true)
				data.merge({"lot_id":str(lot.id),"product_id":str(lot.commodity_id),"mass_kg":float(lot.quantity)*float(lot.unit_mass_kg),
					"vessel_id":str(vessel.id),"owner_id":str(vessel.owner_company_id)},true)
				var remaining:=CatchLot.create(data)
				for hold in catch_holds:
					remaining=hold.accept_lot(remaining)
					if remaining.is_empty(): break
				if not remaining.is_empty(): push_error("Saved catch does not fit the actual ship: "+str(vessel.id))
			continue
		for index in int(lot.quantity):
			var unit:=ContainerUnit.create("%s-%s-%d"%[vessel.id,lot.id,index],str(lot.commodity_id),float(lot.unit_mass_kg),str(attrs.container_type))
			unit.destination_port_id=str(attrs.get("destination_port_id",""))
			unit.paint_variant=int(attrs.get("paint_variant",index%8))
			var placed:=false
			for pad in pads:
				if pad.add_container(unit)>=0: placed=true;break
			if not placed: push_error("Saved cargo does not fit the actual ship: "+str(vessel.id))
