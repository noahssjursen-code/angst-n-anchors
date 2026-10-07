extends SceneTree
const FAR = preload("res://scripts/world/distant_forest.gd")
class Coast extends RefCounted:
	var half_extent_m := 200.0
	var world_size_m := 400.0
	func sample_signed_distance(p: Vector2) -> float: return -p.x
	func sample_height(_p: Vector2) -> float: return 30.0
func _initialize() -> void:
	var a := FAR.new();var b := FAR.new()
	var zone := {"center":Vector2(110,0),"half_size":Vector2(35,35),"falloff":0.0}
	for node in [a,b]:
		node.layout=Coast.new();node.cell_m=100.0
		node.coverage=Image.create(4,4,false,Image.FORMAT_R8);node.coverage.fill(Color.WHITE)
		node.zones=[zone]
		for y in 4:
			for x in 4: node.build_cell(Vector2i(x,y))
	var count := 0
	for key in a.batches:
		for species in 4:
			assert(a.batches[key][species] == b.batches[key][species],"World canopy is not deterministic")
			for xf in a.batches[key][species]:
				count+=1
				assert(xf.origin.x>22.0,"Canopy crosses bare shoreline")
				assert(not ForestField.inside_flatten_zones(Vector2(xf.origin.x,xf.origin.z),[zone]),"Canopy enters cleared port")
	assert(count>200,"Distant forest unexpectedly sparse")
	a.free();b.free()
	print("Persistent canopy placement PASS: deterministic, shoreline and port exclusions; instances=",count)
	quit()
