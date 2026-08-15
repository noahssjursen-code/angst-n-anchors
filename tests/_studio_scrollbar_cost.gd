extends Node3D

## SCRATCH PROBE (leading underscore — the gate skips it).
##
## WHAT WOULD A SCROLLBAR THAT EXISTS COST THE REST OF THE BRANDED UI?
##
## `brand_theme.gd:_style_misc` gives every `HScrollBar`/`VScrollBar` a `scroll`
## stylebox built by `_box(..., 0, 0)` — zero border, zero content margin — so the
## bar's combined minimum size is (0, 0) and every ScrollContainer in the branded
## UI has an invisible, un-draggable, zero-width scrollbar.
##
## A scrollbar is not free: a ScrollContainer subtracts the bar's width from the
## content it hands its child. This measures the subtraction, on the surfaces it
## can actually boot, at two candidate widths — and then reports the surfaces it
## did NOT measure by name (REALITY §4d).

const BRAND_THEME := preload("res://scripts/ui/design_system/brand_theme.gd")

## Every site in the branded UI that builds a ScrollContainer, so the ones this
## probe does not boot are still counted.
const SCROLL_SITES := [
	"scripts/ui/character_creator_panel.gd", "scripts/ui/captain_roster_panel.gd",
	"scripts/ui/main_menu.gd", "scripts/ui/settings_panel.gd",
	"scripts/ui/ui_system_showcase.gd", "scripts/ui/company_panel.gd",
	"scripts/npc/dialogue_panel.gd (x2)", "scripts/weather/weather_debug_presets.gd",
	"scripts/apps/building_brick_editor.gd (x2)",
	"scripts/apps/shipyard_brick_editor.gd (x2)",
	"scripts/character/character_customization_showcase.gd",
	"scripts/apps/structure_studio.gd (x2)",
]

var _studio: Node


func _ready() -> void:
	_studio = load("res://scenes/apps/structure_studio.tscn").instantiate()
	add_child(_studio)
	for _i in 4:
		await get_tree().process_frame
	_studio.call("_set_tool", 6) ## fitting: the tallest state of the left palette
	_studio.call("_refresh_panel")
	for _i in 3:
		await get_tree().process_frame

	print("=== SCROLLBAR WIDTH IN THE BRANDED THEME")
	var theme: Theme = BRAND_THEME.shared()
	var box: StyleBox = theme.get_stylebox(&"scroll", &"VScrollBar")
	print("  VScrollBar 'scroll' stylebox min size = %s  (that is the bar's width)"
		% box.get_minimum_size())
	print("  %d ScrollContainer construction sites in the branded UI:" % SCROLL_SITES.size())
	for site in SCROLL_SITES:
		print("    %s" % site)

	for width in [0, 6, 10]:
		await _measure(width)

	print("\nCOST PROBE DONE")
	get_tree().quit(0)


func _measure(width: int) -> void:
	var ui: Control = _studio.get("_ui_root")
	## THE LEVER THAT ACTUALLY MOVES IT is the THEME stylebox, not
	## `custom_minimum_size` on the bar: `ScrollContainer` subtracts
	## `v_scroll->get_minimum_size()`, which a ScrollBar derives from its `scroll`
	## stylebox — so a custom minimum on the bar changes nothing at all (measured:
	## 0, 6 and 10 px all gave content 291 px). Suspect the instrument first.
	var theme: Theme = BRAND_THEME.shared()
	for type_name in [&"VScrollBar", &"HScrollBar"]:
		var box := theme.get_stylebox(&"scroll", type_name) as StyleBoxFlat
		box.content_margin_left = float(width) * 0.5
		box.content_margin_right = float(width) * 0.5
		var grabber := theme.get_stylebox(&"grabber", type_name) as StyleBoxFlat
		grabber.content_margin_left = float(width) * 0.5
		grabber.content_margin_right = float(width) * 0.5
	for scroll_variant in _scrolls(ui, []):
		(scroll_variant as ScrollContainer).queue_sort()
	for _i in 3:
		await get_tree().process_frame
	print("\n--- bar width %d px" % width)
	for scroll_variant in _scrolls(ui, []):
		var scroll := scroll_variant as ScrollContainer
		var content := scroll.get_child(0) as Control
		var hidden := maxf(content.size.y - scroll.size.y, 0.0)
		print("  %-18s bar %.0f px | viewport %.0f x %.0f | content %.0f x %.0f | %.0f px below the fold" % [
			_panel_of(scroll), scroll.get_v_scroll_bar().get_minimum_size().x,
			scroll.size.x, scroll.size.y,
			content.size.x, content.size.y, hidden
		])


func _panel_of(node: Node) -> String:
	var walk := node
	while walk != null:
		if str(walk.name) in ["ToolPalette", "PropertiesDrawer"]:
			return str(walk.name)
		walk = walk.get_parent()
	return "?"


func _scrolls(root: Node, out: Array = []) -> Array:
	## NOT a default-argument array reused across calls — every caller passes a
	## fresh one; the default exists only for the recursive tail.
	for child in root.get_children():
		if child is ScrollContainer:
			out.append(child)
		_scrolls(child, out)
	return out
