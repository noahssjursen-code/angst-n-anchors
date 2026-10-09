class_name PassengerTerminal
extends Node3D
## Authored modular passenger pier. Kept isolated until passenger berths and
## the service contract are integrated; existing generated ports are untouched.
const DIRECTORY := "res://resources/models/parts/passenger_terminal/"
var guard_joints: Dictionary={}

func _ready() -> void:
	if get_child_count()>0:return
	for x in [-9.0,-3.0,3.0,9.0]:
		for z in [-22.0,-28.0,-34.0,-40.0]:place("passenger_pier_6m",Vector3(x,0,z))
	for x in [-7.5,-4.5,-1.5,1.5,4.5,7.5]:
		place("terminal_entry_3m" if absf(x)<2 else "terminal_glazed_bay_3m",Vector3(x,0,-30.5))
		place("terminal_solid_bay_3m",Vector3(x,0,-39.5))
		place("terminal_roof_3x10m",Vector3(x,3.3,-35))
		place("terminal_canopy_3m",Vector3(x,0,-28.5))
	place("terminal_canopy_post",Vector3(9,0,-26.9))
	for x in [-9.0,9.0]:
		place("terminal_gable_10m",Vector3(x,3.3,-35))
		for z in [-38.0,-35.0,-32.0]:place("terminal_glazed_bay_3m",Vector3(x,0,z),90)
	for x in [-6.0,6.0]:
		for z in [-34.0,-37.0]:place("terminal_waiting_bench",Vector3(x,0,z))
	for x in [-3.5,3.5]:place("terminal_information_pylon",Vector3(x,0,-24.0))
	for x in [-10.5,-7.5,-4.5,4.5,7.5,10.5]:guard(Vector3(x,0,-19.0))
	for x in [-12.0,12.0]:
		for z in [-20.5,-23.5,-26.5,-29.5,-32.5,-35.5,-38.5,-41.5]:guard(Vector3(x,0,z),90)
	for x in [-4.3,4.3]:place("passenger_berth_fender",Vector3(x,0,-19.0))
	var landing:=Marker3D.new();landing.name="PassengerLanding";landing.position=Vector3(0,0,-19.1);add_child(landing)

func guard(at: Vector3, yaw: float=0) -> void:
	place("passenger_pier_guard_3m",at,yaw)
	for x in [-1.5,0.0,1.5]:
		var joint:=(at+Basis(Vector3.UP,deg_to_rad(yaw))*Vector3(x,0,0)).snapped(Vector3(.001,.001,.001))
		if guard_joints.has(joint):continue
		guard_joints[joint]=true
		place("passenger_pier_guard_post",joint)

func place(asset: String, at: Vector3, yaw: float=0) -> void:
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
