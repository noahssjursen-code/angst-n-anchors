extends RefCounted

## Lay out the harbour's storage flank within the actual crane's working reach.
## Local -Z faces the water; the long cargo flank runs along the quay (X).
const YARD := preload("res://scripts/port/port_cargo_yard.gd")
const FOUNDATION_M := 4.0
const REACH_MARGIN_M := 1.0
const WALK_CLEARANCE_M := 2.0

static func configure(spec: Dictionary) -> void:
	var container := str(spec.visual)=="container_crane"
	var crane: Node3D = ProvisionCrane.new() if container else BulkCrane.new()
	var model: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(crane.model_path))
	var base_part: Dictionary = model.parts[0]
	var mesh: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://resources/data/meshes/"+str(base_part.mesh)))
	var vertices: Array = mesh.vertices
	var base_half := 0.0
	for i in range(0,vertices.size(),3):
		base_half = maxf(base_half,maxf(absf(float(vertices[i])),absf(float(vertices[i+2])))*crane.model_scale)
	var inner: float
	var outer: float
	if container:
		inner = absf(float(model.meta.rail_z_max_m))*crane.model_scale
		outer = absf(float(model.meta.rail_z_min_m))*crane.model_scale
	else:
		var boom: float = float(model.meta.boom_length_m)*crane.model_scale
		# Conservative bounds: keep the entire pad outside the raised boom's
		# dead zone, including the imported rig's offset from the slew pivot.
		var hinge_offset: float = Vector2(1.75,2.5).length()*crane.model_scale
		inner = boom*cos(deg_to_rad(crane.boom_max_deg))+hinge_offset
		outer = boom*cos(deg_to_rad(crane.boom_min_deg))
	crane.free()
	var radius := outer-REACH_MARGIN_M
	var near := ceilf(maxf(base_half+WALK_CLEARANCE_M,inner+REACH_MARGIN_M)/FOUNDATION_M)*FOUNDATION_M
	var depth: float
	var length: float
	if container:
		depth = YARD.packed_size(Vector2(YARD.MAX_WIDTH_M,YARD.MAX_LENGTH_M)).x
		length = minf(YARD.MAX_LENGTH_M,2.0*sqrt(maxf(0,radius*radius-pow(near+depth,2))))
		var packed := YARD.packed_size(Vector2(depth,length))
		depth = packed.x
		length = packed.y
	else:
		# Largest rectangular receiving area in the crane's landward sweep.
		var far := (near+sqrt(near*near+8.0*radius*radius))*.25
		depth = floorf((far-near)/FOUNDATION_M)*FOUNDATION_M
		length = floorf(2.0*sqrt(maxf(0,radius*radius-pow(near+depth,2)))/FOUNDATION_M)*FOUNDATION_M
	var front := ceilf(base_half/FOUNDATION_M)*FOUNDATION_M
	var width := ceilf(maxf(length,base_half*2)/FOUNDATION_M)*FOUNDATION_M
	var total_depth := ceilf((front+near+depth)/FOUNDATION_M)*FOUNDATION_M
	spec.cells = [roundi(width/2),roundi(total_depth/2)]
	spec.snap_cells = [2,2]
	spec.crane_offset_m = [0,front-total_depth*.5]
	spec.pad_offset_m = [0,front+near+depth*.5-total_depth*.5]
	spec.pad_size_m = [depth,length]
	spec.pad_yaw_degrees = 90.0
	spec.reach_m = outer
	spec.reach_min_m = inner
	spec.base_size_m = base_half*2.0
	if container:
		var fp := Vector2(ContainerUnit.DEFAULT_FOOTPRINT)
		spec.slot_count = roundi(depth/fp.x)*roundi(length/fp.y)
