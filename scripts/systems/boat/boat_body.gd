@tool
class_name BoatBody
extends RigidBody3D

## Root node of every boat. Owns physics properties and builds the hull
## geometry + collision from exports — no imported meshes, no scene assets.

@export_group("Physics")
@export var hull_mass:           float = 3500.0:
	set(v):
		hull_mass = v
		mass = v
@export var linear_damp_coeff:   float = 0.7:
	set(v):
		linear_damp_coeff = v
		linear_damp = v
@export var angular_damp_coeff:  float = 0.8:
	set(v):
		angular_damp_coeff = v
		angular_damp = v

@export_group("Hull")
@export var hull_size: Vector3 = Vector3(6.0, 2.0, 14.0): # width, height, length
	set(v):
		hull_size = v
		if is_node_ready():
			_rebuild()

@export_group("Stabilization")
@export var stabilization_torque:  float = 6000.0
@export var stabilization_damp:    float = 1500.0

# Muted, functional colors
const C_HULL      := Color(0.18, 0.20, 0.22) # Slate
const C_DECK      := Color(0.35, 0.35, 0.35) # Steel
const C_CABIN     := Color(0.80, 0.80, 0.78) # Off-white
const C_TRIM      := Color(0.25, 0.25, 0.25) # Dark grey

func _ready() -> void:
	mass         = hull_mass
	linear_damp  = linear_damp_coeff
	angular_damp = angular_damp_coeff
	_rebuild()

func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return

	# Upright stabilization
	var righting: Vector3 = global_transform.basis.y.cross(Vector3.UP)
	apply_torque(righting * stabilization_torque)

	# Angular damping
	var av := angular_velocity
	apply_torque(Vector3(-av.x, 0.0, -av.z) * stabilization_damp)

func _rebuild() -> void:
	for child in get_children():
		if child is MeshInstance3D or child is CollisionShape3D:
			child.queue_free()
	
	_build_collision()
	_build_mesh()

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = hull_size
	col.shape = shape
	col.position = Vector3(0.0, hull_size.y * 0.5, 0.0)
	add_child(col)

func _build_mesh() -> void:
	var w := hull_size.x
	var h := hull_size.y
	var l := hull_size.z

	# 1. Main Hull
	var hull := MeshBuilder.box(hull_size, C_HULL, 0.8, 0.1)
	hull.position = Vector3(0.0, h * 0.5, 0.0)
	add_child(hull)

	# 2. Tapered Bow (Simple wedge)
	var bow_l := l * 0.2
	var bow := MeshBuilder.prism(Vector3(w, h, bow_l), C_HULL, 0.8, 0.1)
	bow.rotation.y = PI
	bow.rotation.x = -PI * 0.5
	bow.position = Vector3(0.0, h * 0.5, -l * 0.5 - bow_l * 0.5)
	add_child(bow)

	# 3. Deck (Slightly recessed look)
	var deck := MeshBuilder.box(Vector3(w - 0.2, 0.1, l - 0.2), C_DECK, 0.7, 0.2)
	deck.position = Vector3(0.0, h + 0.05, 0.0)
	add_child(deck)

	# 4. Aft Cabin (Simple block)
	var cab_w := w * 0.7
	var cab_h := 2.0
	var cab_l := l * 0.25
	var cab_z := l * 0.3
	var cabin := MeshBuilder.box(Vector3(cab_w, cab_h, cab_l), C_CABIN, 0.9)
	cabin.position = Vector3(0.0, h + cab_h * 0.5, cab_z)
	add_child(cabin)

	# 5. Funnel
	var stack := MeshBuilder.cylinder(0.3, 1.5, C_TRIM, 0.5, 0.2)
	stack.position = Vector3(0.0, h + cab_h + 0.75, cab_z + cab_l * 0.2)
	add_child(stack)
