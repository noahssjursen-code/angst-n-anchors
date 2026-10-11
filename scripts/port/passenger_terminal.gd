class_name PassengerTerminal
extends Node3D
## Authored modular passenger pier. Kept isolated until passenger berths and
## the service contract are integrated; existing generated ports are untouched.
const DIRECTORY := "res://resources/models/parts/passenger_terminal/"
var guard_joints: Dictionary={}
var berth: QuayBerthSlot
var shore_connection := false
var shore_rise := 0.0

func _ready() -> void:
	if get_child_count()>0:return
	for x in [-9.0,-3.0,3.0,9.0]:
		for z in [-22.0,-28.0,-34.0,-40.0]:place("passenger_pier_6m",Vector3(x,0,z))
	# L-shaped support quay: bow boarding plus accessible breast/spring lines.
	for z in [-16.0,-10.0,-4.0,2.0,8.0,14.0]:
		place("passenger_pier_6m",Vector3(-9,0,z))
	for x in [-12.0,-6.0]:
		for z in [-17.5,-14.5,-11.5,-8.5,-5.5,-2.5,.5,3.5,6.5,9.5,12.5,15.5]:
			guard(Vector3(x,0,z),90)
	for x in [-10.5,-7.5]: guard(Vector3(x,0,17))
	for z in [-14.0,16.0]:place("passenger_berth_fender",Vector3(-6,0,z),90)
	for x in [-7.5,-4.5,-1.5,1.5,4.5,7.5]:
		place("terminal_entry_3m" if absf(x)<2 else "terminal_glazed_bay_3m",Vector3(x,0,-30.5))
		place("terminal_entry_3m" if shore_connection and absf(x)<2 else "terminal_solid_bay_3m",Vector3(x,0,-39.5),180)
		place("terminal_roof_3x10m",Vector3(x,3.3,-35))
		place("terminal_canopy_3m",Vector3(x,0,-28.5))
	place("terminal_canopy_post",Vector3(9,0,-26.9))
	for x in [-9.0,9.0]:
		place("terminal_gable_10m",Vector3(x,3.3,-35))
		for z in [-38.0,-35.0,-32.0]:place("terminal_glazed_bay_3m",Vector3(x,0,z),90)
	for x in [-6.0,6.0]:
		for z in [-34.0,-37.0]:place("terminal_waiting_bench",Vector3(x,0,z))
	for x in [-3.5,3.5]:place("terminal_information_pylon",Vector3(x,0,-24.0))
	for x in [-4.5,4.5,7.5,10.5]:guard(Vector3(x,0,-19.0))
	for x in [-12.0,12.0]:
		for z in [-20.5,-23.5,-26.5,-29.5,-32.5,-35.5,-38.5,-41.5]:guard(Vector3(x,0,z),90)
	for x in [-4.3,4.3]:place("passenger_berth_fender",Vector3(x,0,-19.0))
	var landing:=Marker3D.new();landing.name="PassengerLanding";landing.position=Vector3(0,0,-20);add_child(landing)
	landing.set_meta("landing_size",Vector2(5.5,2.0))
	if shore_connection:
		var run := sqrt(36.0-shore_rise*shore_rise)
		var approach := place("terminal_shore_ramp_6m",Vector3(0,shore_rise*.5,-43-run*.5))
		approach.rotation.x=asin(shore_rise/6.0)

## Explicit opt-in: isolated terminals don't silently register as world ports.
func register_berth(harbour: HarbourController, station_id: String = "passenger") -> QuayBerthSlot:
	if is_instance_valid(berth): return berth
	berth = QuayBerthSlot.new()
	berth.setup(harbour.port_id()+"/"+station_id,station_id,"passenger",[],45,24,1,Vector3.BACK,0)
	berth.bow_in = true
	berth.berth_gap_m = .75
	berth.position = Vector3(0,0,-19)
	berth.boarding_landing = get_node("PassengerLanding")
	add_child(berth)
	for z in [-14.0,16.0]:
		var bollard := MooringPost.new()
		bollard.position = Vector3(-6.8,0,z)
		bollard.set_meta("harbour_port_id",harbour.port_id())
		add_child(bollard)
		berth.add_bollard(bollard)
	harbour.register_berth(berth)
	return berth

func guard(at: Vector3, yaw: float=0) -> void:
	place("passenger_pier_guard_3m",at,yaw)
	for x in [-1.5,0.0,1.5]:
		var joint:=(at+Basis(Vector3.UP,deg_to_rad(yaw))*Vector3(x,0,0)).snapped(Vector3(.001,.001,.001))
		if guard_joints.has(joint):continue
		guard_joints[joint]=true
		place("passenger_pier_guard_post",joint)

func place(asset: String, at: Vector3, yaw: float=0) -> Node3D:
	var visual:Node3D=(load(DIRECTORY+asset+".glb") as PackedScene).instantiate()
	visual.position=at;visual.rotation_degrees.y=yaw;add_child(visual)
	SurfaceMaterialLibrary.apply(visual,"passenger_terminal")
	var body:=StaticBody3D.new();body.collision_layer=1;body.collision_mask=0
	visual.add_child(body)
	for mesh:MeshInstance3D in visual.find_children("*","MeshInstance3D",true,false):
		var collider:=CollisionShape3D.new();collider.shape=mesh.mesh.create_trimesh_shape()
		var transform:=mesh.transform
		var parent:=mesh.get_parent()
		while parent!=visual:
			if parent is Node3D:transform=parent.transform*transform
			parent=parent.get_parent()
		collider.transform=transform;body.add_child(collider)
	return visual
