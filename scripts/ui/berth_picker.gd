class_name BerthPicker
extends Control

signal closed
var service:HarbourMasterNpc
var record:Dictionary
var selected:QuayBerthSlot
var camera:Camera3D
var previous:Camera3D
var slots:Array=[]
var available:Array=[]
var confirm:Button
var status:Label
var busy:=false
var refresh_time:=0.0

func open(harbour_service:HarbourMasterNpc,vessel:Dictionary) -> void:
	service=harbour_service;record=vessel.duplicate(true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	previous=get_viewport().get_camera_3d()
	slots=service._harbour().berths()
	available=HarbourDeploy.free_slots_for(service._harbour(),record,service._max_ship_class())
	if slots.is_empty():closed.emit();return
	var center:=Vector3.ZERO
	for slot:QuayBerthSlot in slots:center+=slot.global_position
	center/=slots.size()
	var radius:=45.0
	for slot:QuayBerthSlot in slots:radius=maxf(radius,center.distance_to(slot.global_position)+slot.length_m)
	camera=Camera3D.new();add_child(camera)
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=radius*2.2
	camera.far=3000;camera.global_position=center+Vector3.UP*maxf(radius*2,200)
	camera.look_at(center,Vector3.FORWARD);camera.make_current()
	var sheet:=PanelContainer.new();sheet.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	sheet.position=Vector2(28,28);sheet.custom_minimum_size=Vector2(410,0)
	sheet.add_theme_stylebox_override("panel",VoyageStyle.box(VoyageStyle.PAPER,22));add_child(sheet)
	var col:=VBoxContainer.new();sheet.add_child(col)
	col.add_child(VoyageStyle.label("Choose a berth",28))
	col.add_child(VoyageStyle.label(VesselSpawn.vessel_name_of(record),22))
	status=VoyageStyle.label("Select a green berth to deploy your vessel.",18);col.add_child(status)
	confirm=VoyageStyle.button("Deploy vessel",_deploy,true);confirm.disabled=true;col.add_child(confirm)
	col.add_child(VoyageStyle.button("Back to fleet",func():closed.emit()))
	service.deployment_finished.connect(_finished)
	queue_redraw()

func _process(delta:float)->void:
	if not is_instance_valid(service):closed.emit();return
	refresh_time+=delta
	if refresh_time>=.25 and not busy:
		refresh_time=0
		available=HarbourDeploy.free_slots_for(service._harbour(),record,service._max_ship_class())
		if selected!=null and not available.has(selected):
			selected=null;confirm.disabled=true
			status.text="That berth is no longer available. Select another."
	queue_redraw()

func _polygon(slot:QuayBerthSlot)->PackedVector2Array:
	var req:=HarbourDeploy.ship_requirements(record)
	var pocket:=slot.ship_pocket_local(float(req.beam_world_m),float(req.loa_world_m))
	var p:=pocket.position;var e:=pocket.end
	var points:=PackedVector2Array()
	for corner in [Vector3(p.x,0,p.z),Vector3(e.x,0,p.z),Vector3(e.x,0,e.z),Vector3(p.x,0,e.z)]:
		points.append(camera.unproject_position(slot.to_global(corner)))
	return points

func _draw()->void:
	if not is_instance_valid(camera):return
	for slot:QuayBerthSlot in slots:
		if not is_instance_valid(slot):continue
		var polygon:=_polygon(slot)
		var colour:=Color(.18,.8,.53,.45) if available.has(slot) else Color(.9,.27,.22,.4)
		if slot==selected:colour=Color(.98,.85,.3,.65)
		draw_colored_polygon(polygon,colour)
		polygon.append(polygon[0]);draw_polyline(polygon,Color.WHITE,2,true)

func _gui_input(event:InputEvent)->void:
	if busy or not event is InputEventMouseButton or not event.pressed or event.button_index!=MOUSE_BUTTON_LEFT:return
	for slot:QuayBerthSlot in slots:
		if is_instance_valid(slot) and Geometry2D.is_point_in_polygon(event.position,_polygon(slot)):
			selected=slot if available.has(slot) else null
			confirm.disabled=selected==null
			status.text="Berth occupied or too small." if selected==null else PortServiceDesk.friendly_berth(slot)
			accept_event();return

func _deploy()->void:
	if busy or not is_instance_valid(selected):return
	if not HarbourDeploy.free_slots_for(service._harbour(),record,service._max_ship_class()).has(selected):
		status.text="That berth is no longer available.";confirm.disabled=true;return
	busy=true;confirm.disabled=true;status.text="Deploying vessel…"
	service._deploy_fleet_vessel(record,selected.berth_id)

func _finished(ok:bool,message:String)->void:
	if not busy:return
	busy=false;status.text=message;confirm.disabled=false
	if ok:closed.emit()

func _exit_tree()->void:
	if is_instance_valid(previous):previous.make_current()
