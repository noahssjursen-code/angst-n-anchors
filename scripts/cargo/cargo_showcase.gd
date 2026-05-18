@tool
class_name CargoShowcase
extends Node3D

## Lines up every commodity at every pallet size (1 unit → max_pallet_units),
## one row per commodity, so the look of each can be tweaked without launching
## the game. Tick the `rebuild` checkbox in the inspector to refresh after any
## change to PalletNode visuals or ContractRegistry.COMMODITIES.

## Preloaded directly so the constants resolve in @tool mode (autoload
## singleton isn't running in the editor).
const REGISTRY := preload("res://scripts/cargo/contract_registry.gd")

const CELL_SIZE := 1.5
const PALLET_GAP := 0.8
const ROW_GAP    := 4.5
const LABEL_H    := 2.6


## Tick → regenerates the layout. Untoggles itself.
@export var rebuild: bool = false:
	set(v):
		if v and is_inside_tree():
			_rebuild()


@export_group("Display")
## Adds a generated dark concrete pad under the lineup so pallets aren't
## floating over checker grid.
@export var show_ground_pad: bool = true:
	set(v):
		show_ground_pad = v
		if is_inside_tree():
			_rebuild()
## Adds a Label3D above each pallet describing it.
@export var show_labels: bool = true:
	set(v):
		show_labels = v
		if is_inside_tree():
			_rebuild()


func _ready() -> void:
	_rebuild()


func _rebuild() -> void:
	for child in get_children():
		child.queue_free()

	var commodities: Array = REGISTRY.COMMODITIES
	if commodities.is_empty():
		push_warning("CargoShowcase: COMMODITIES table is empty.")
		return

	# Pre-pass: compute the grid size so we can lay down a backing pad.
	var max_row_x := 0.0
	var total_z := 0.0
	for entry in commodities:
		var rules := entry as Dictionary
		var max_units := int(rules.get("max_pallet_units", 4))
		var row_w := 0.0
		var deepest := 0.0
		for n in range(1, max_units + 1):
			var fp := PalletFactory.best_footprint(n, max_units)
			row_w += CELL_SIZE * float(fp.x) + PALLET_GAP
			deepest = maxf(deepest, CELL_SIZE * float(fp.y))
		max_row_x = maxf(max_row_x, row_w)
		total_z += deepest + ROW_GAP

	if show_ground_pad:
		var pad := MeshInstance3D.new()
		pad.name = "GroundPad"
		var bm := BoxMesh.new()
		bm.size = Vector3(max_row_x + 4.0, 0.12, total_z + 2.0)
		pad.mesh = bm
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.34, 0.32, 0.30)
		pad.material_override = mat
		pad.position = Vector3(max_row_x * 0.5, 0.06, total_z * 0.5)
		add_child(pad)
		pad.owner = _scene_owner()

	# Lay out one row per commodity.
	var z := 1.0
	for entry in commodities:
		var rules := entry as Dictionary
		var commodity_id := str(rules.get("id", ""))
		var display_name := str(rules.get("display", commodity_id))
		var max_units := int(rules.get("max_pallet_units", 4))
		var mass_per_unit := float(rules.get("mass_kg", 0.0))
		var value_per_unit := int(rules.get("value", 0))

		var deepest := 0.0
		var x := 1.0
		for n in range(1, max_units + 1):
			var fp := PalletFactory.best_footprint(n, max_units)
			var pallet := Pallet.new()
			pallet.id                  = "showcase_%s_%d" % [commodity_id, n]
			pallet.commodity           = commodity_id
			pallet.display_name        = display_name
			pallet.units               = n
			pallet.max_units           = max_units
			pallet.footprint           = fp
			pallet.mass_kg             = mass_per_unit * float(n)
			pallet.value_gold          = value_per_unit * n

			var w := CELL_SIZE * float(fp.x)
			var d := CELL_SIZE * float(fp.y)

			var node := PalletNode.new()
			node.name = "%s_%d" % [commodity_id, n]
			add_child(node)
			node.position = Vector3(x + w * 0.5, 0.12, z + d * 0.5)
			node.setup(pallet, w, d)
			node.owner = _scene_owner()

			if show_labels:
				var lbl := Label3D.new()
				lbl.name        = "Label_%s_%d" % [commodity_id, n]
				lbl.text        = "%s ×%d\n%d×%d cells" % [display_name, n, fp.x, fp.y]
				lbl.font_size   = 36
				lbl.pixel_size  = 0.0045
				lbl.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
				lbl.no_depth_test = true
				lbl.position    = Vector3(x + w * 0.5, LABEL_H, z + d * 0.5)
				lbl.modulate    = Color(0.95, 0.92, 0.78)
				add_child(lbl)
				lbl.owner = _scene_owner()

			x += w + PALLET_GAP
			deepest = maxf(deepest, d)

		# Row header on the left, slightly above the pallets.
		if show_labels:
			var row_lbl := Label3D.new()
			row_lbl.name        = "Row_" + commodity_id
			row_lbl.text        = display_name.to_upper()
			row_lbl.font_size   = 48
			row_lbl.pixel_size  = 0.006
			row_lbl.billboard   = BaseMaterial3D.BILLBOARD_ENABLED
			row_lbl.no_depth_test = true
			row_lbl.position    = Vector3(-1.5, LABEL_H + 0.6, z + deepest * 0.5)
			row_lbl.modulate    = REGISTRY.commodity_color(commodity_id)
			add_child(row_lbl)
			row_lbl.owner = _scene_owner()

		z += deepest + ROW_GAP

	rebuild = false


func _scene_owner() -> Node:
	# In editor: parent owner is the edited scene root so children show up
	# under the right tree. At runtime: just self (so they get freed cleanly).
	if Engine.is_editor_hint() and get_tree() != null and get_tree().edited_scene_root != null:
		return get_tree().edited_scene_root
	return null
