@tool
class_name SurfaceMaterialLibrary
extends RefCounted

## Shared physical finishes for ships and ports. Optical materials and authored
## crane/cargo colour atlases stay intact. Profiles and source provenance are data.
const SHADER := preload("res://resources/shaders/marine_surface.gdshader")
const DIRECTORY := "res://resources/textures/marine/"
static var _profiles: Dictionary = {}
static var _materials: Dictionary = {}
static var _batch_meshes: Dictionary = {}
static var enabled := true

static func profiles() -> Dictionary:
	if _profiles.is_empty():
		_profiles = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "profiles.json"))
	return _profiles

static func profile_for(name: String, context: String = "") -> String:
	var data := assignments()
	var overrides: Dictionary = data.get("asset_overrides", {}).get(context, {})
	if overrides.has(name): return overrides[name]
	if name.begins_with("Paint_Surface"):
		return "deck_grip" if context == "floor" else ("roof_enamel" if context == "roof" else "console_laminate")
	if data.exact.has(name): return data.exact[name]
	for prefix in data.prefix:
		if name.begins_with(prefix): return data.prefix[prefix]
	return ""

static func keeps_atlas(name: String) -> bool:
	for prefix in assignments().preserve_authored_colour_prefix:
		if name.begins_with(prefix): return true
	return false

static var _assignments: Dictionary = {}
static func assignments() -> Dictionary:
	if _assignments.is_empty():
		_assignments = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "assignments.json"))
	return _assignments

static func material(profile: String, colour: Color, source_name: String = "", authored_colour: Texture2D = null) -> ShaderMaterial:
	var key := profile + ":" + colour.to_html(true) + ":" + source_name + (":" + str(authored_colour.get_instance_id()) if authored_colour else "")
	if _materials.has(key): return _materials[key]
	var spec: Dictionary = profiles()[profile]
	var result := ShaderMaterial.new()
	result.shader = SHADER
	result.resource_name = source_name
	result.set_meta("marine_profile", profile)
	result.set_shader_parameter("base_color", colour)
	if authored_colour:
		result.set_shader_parameter("authored_colour", authored_colour)
		result.set_shader_parameter("use_authored_colour", true)
	var asset: String = spec.asset
	for channel in {"colour_map":"Color", "roughness_map":"Roughness", "normal_map":"NormalGL", "metal_map":"Metalness"}:
		var suffix: String = {"colour_map":"Color", "roughness_map":"Roughness", "normal_map":"NormalGL", "metal_map":"Metalness"}[channel]
		var path := DIRECTORY + asset + "/" + asset + "_1K-PNG_" + suffix + ".png"
		assert(channel == "metal_map" or ResourceLoader.exists(path), "Missing marine source map: " + path)
		if ResourceLoader.exists(path): result.set_shader_parameter(channel, load(path))
	if float(spec.get("corrosion", 0)) > 0:
		result.set_shader_parameter("corrosion_map", load(DIRECTORY + "MetalPlates013/MetalPlates013_1K-PNG_Color.png"))
	for parameter in ["source_mean", "colour_contrast", "source_colour", "roughness_low", "roughness_high", "relief", "metal_amount", "use_metal_map", "corrosion", "corrosion_metres", "corrosion_base_band"]:
		if spec.has(parameter): result.set_shader_parameter(parameter, spec[parameter])
	result.set_shader_parameter("repeat_metres", Vector2(spec.metres[0], spec.metres[1]))
	# Editor colour scrubbing must not retain every historical colour forever.
	if _materials.size() >= 512: _materials.clear()
	_materials[key] = result
	return result

static func colour_of(value: Material) -> Color:
	if value is ShaderMaterial and value.shader == SHADER: return value.get_shader_parameter("base_color")
	if value is StandardMaterial3D: return value.albedo_color
	return Color.WHITE

static func character_material(original: Material, part_name: String = "") -> Material:
	# Character UVs deform with the authored skeleton and morphs. Never project
	# a rigid world/rest-space finish onto skinning, or replace a clothing print.
	var copy := original.duplicate() as StandardMaterial3D
	if copy == null: return original.duplicate()
	var spec: Dictionary = assignments().character_uv.get(original.resource_name,{})
	if not enabled or spec.is_empty(): return copy
	var asset: String = spec.asset
	var prefix := DIRECTORY+asset+"/"+asset+"_1K-PNG_"
	copy.normal_enabled=true
	copy.normal_texture=load(prefix+"NormalGL.png")
	copy.normal_scale=float(spec.normal_scale)
	copy.roughness_texture=load(prefix+"Roughness.png")
	copy.roughness_texture_channel=BaseMaterial3D.TEXTURE_CHANNEL_RED
	copy.roughness=float(spec.roughness)
	if part_name=="Headwear_Hardhat" and original.resource_name=="Outerwear":
		copy.normal_scale=.025
		copy.roughness=.52
	copy.metallic=0.0
	copy.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	# Existing albedo prints retain their original UV repeat and placement.
	if copy.albedo_texture==null: copy.uv1_scale=Vector3(float(spec.repeat),float(spec.repeat),1)
	copy.set_meta("source_asset",asset)
	return copy

static func apply(root: Node3D, context: String = "") -> void:
	if not enabled: return
	map_frame(root)
	for node in meshes(root):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null: continue
		for surface in mesh.mesh.get_surface_count():
			var original := mesh.mesh.surface_get_material(surface) as StandardMaterial3D
			if original == null: continue
			var profile := profile_for(original.resource_name.get_slice(".", 0), context)
			if profile.is_empty(): continue
			var colour := colour_of(mesh.get_active_material(surface))
			var atlas := original.albedo_texture if keeps_atlas(original.resource_name) else null
			mesh.set_surface_override_material(surface, material(profile, colour, original.resource_name, atlas))

static func finished_mesh(source: MeshInstance3D) -> ArrayMesh:
	# Ports share the same finished prototype, not another mesh per quay/run.
	var key:=str(source.mesh.get_instance_id())
	for surface in source.mesh.get_surface_count():
		var active:=source.get_active_material(surface)
		key += ":"+str(active.get_instance_id() if active else 0)
	if _batch_meshes.has(key): return _batch_meshes[key]
	var result := source.mesh.duplicate() as ArrayMesh
	for surface in result.get_surface_count():
		result.surface_set_material(surface, source.get_active_material(surface))
	if _batch_meshes.size()>=128:_batch_meshes.clear()
	_batch_meshes[key]=result
	return result

static func map_frame(root: Node3D, rest_frame := Transform3D.IDENTITY) -> void:
	# Placement frame, never global position: adjacent panels agree at their end
	# sockets, but moving the entire vessel cannot make the finish swim.
	for node in meshes(root):
		var mesh := node as MeshInstance3D
		var frame := mesh.transform
		var parent := mesh.get_parent() if mesh != root else null
		if mesh == root: frame = Transform3D.IDENTITY
		while parent != root and parent != null:
			if parent is Node3D: frame = parent.transform * frame
			parent = parent.get_parent()
		set_mapping(mesh, rest_frame * frame)

static func meshes(root: Node3D) -> Array[Node]:
	var result := root.find_children("*", "MeshInstance3D", true, false)
	if root is MeshInstance3D: result.push_front(root)
	return result

static func set_mapping(mesh: MeshInstance3D, frame: Transform3D) -> void:
	mesh.set_instance_shader_parameter("finish_x", Vector4(frame.basis.x.x, frame.basis.y.x, frame.basis.z.x, frame.origin.x))
	mesh.set_instance_shader_parameter("finish_y", Vector4(frame.basis.x.y, frame.basis.y.y, frame.basis.z.y, frame.origin.y))
	mesh.set_instance_shader_parameter("finish_z", Vector4(frame.basis.x.z, frame.basis.y.z, frame.basis.z.z, frame.origin.z))
