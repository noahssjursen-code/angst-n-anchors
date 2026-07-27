class_name HelmMinimap
extends Control

## Bottom-right north-up chart shown only while helming. It owns only a camera;
## data, layers, nav snapshot, renderer, and raster caches are shared with the
## full marine chart.

const SPAN_M := 5000.0
const REFRESH_S := 0.20
const MARGIN := 14.0
const EXPANDED_SIZE := Vector2(300.0, 238.0)
const COLLAPSED_SIZE := Vector2(44.0, 44.0)

var source: MapOverlay
var camera := ChartCamera.new()
var collapsed := false
var helm_active := false
var modal_hidden := false
var refresh_elapsed := REFRESH_S
var collapse_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	theme = BrandTheme.shared()
	set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_load_preference()
	_build_button()
	_apply_geometry()
	_refresh_visibility()


func setup(chart_source: MapOverlay) -> void:
	source = chart_source


func set_helm_active(active: bool) -> void:
	helm_active = active
	refresh_elapsed = REFRESH_S
	_refresh_visibility()


func set_modal_hidden(hidden: bool) -> void:
	modal_hidden = hidden
	_refresh_visibility()


func _process(delta: float) -> void:
	if not visible or collapsed or source == null:
		return
	refresh_elapsed += delta
	if refresh_elapsed < REFRESH_S:
		return
	refresh_elapsed = 0.0
	if not source.refresh_shared_nav():
		return
	sync_follow_position()
	source.prepare_shared_overlays(_world_bounds())
	queue_redraw()


func sync_follow_position() -> bool:
	if source == null or source.nav == null or not source.nav.has_ship():
		return false
	if source.data != null and source.data.layout != null:
		camera.configure_world(float(source.data.layout.half_extent_m))
	camera.center = Vector2(source.nav.ship_position.x, source.nav.ship_position.z)
	camera.span = minf(SPAN_M, camera.span_max())
	return true


func _input(event: InputEvent) -> void:
	if not visible or not helm_active or not event is InputEventKey:
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.keycode == KEY_K:
		_toggle_collapsed()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()


func _draw() -> void:
	if collapsed:
		return
	var panel := Rect2(Vector2.ZERO, size)
	draw_rect(panel, BrandTokens.alpha(BrandTokens.SCRIM, 0.94))
	draw_rect(panel, BrandTokens.SURFACE_EDGE, false, 1.0)
	draw_string(
		BrandTheme.font_data(),
		Vector2(9.0, 19.0),
		"LOCAL CHART   2.7 nm",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		BrandTokens.BRASS_LIGHT,
	)
	var chart := _chart_rect()
	var bounds := camera.world_bounds(chart.size)
	var context := {
		"chart_rect": chart,
		"world_bounds": bounds,
		"world_span": camera.span,
	}
	source.renderer.render_minimap(self, context, source.layers, source.nav)
	draw_rect(chart, BrandTokens.alpha(BrandTokens.CHART_CONTOUR, 0.90), false, 1.0)
	draw_string(
		BrandTheme.font_data(),
		Vector2(9.0, size.y - 7.0),
		"K  collapse    C  cursor",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
		BrandTokens.INK_INVERSE_DIM,
	)


func _build_button() -> void:
	collapse_button = BrandButton.new("", BrandButton.Variant.CHIP)
	collapse_button.name = "MinimapCollapse"
	collapse_button.mouse_filter = Control.MOUSE_FILTER_STOP
	collapse_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	collapse_button.offset_left = -44.0
	collapse_button.offset_right = 0.0
	collapse_button.offset_top = 0.0
	collapse_button.offset_bottom = 44.0
	collapse_button.pressed.connect(_toggle_collapsed)
	add_child(collapse_button)
	_refresh_button()


func _toggle_collapsed() -> void:
	collapsed = not collapsed
	_apply_geometry()
	_persist_preference()
	queue_redraw()


func _apply_geometry() -> void:
	var target := COLLAPSED_SIZE if collapsed else EXPANDED_SIZE
	offset_left = -MARGIN - target.x
	offset_top = -MARGIN - target.y
	offset_right = -MARGIN
	offset_bottom = -MARGIN
	if collapse_button != null:
		if collapsed:
			collapse_button.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			collapse_button.offset_left = 0.0
			collapse_button.offset_top = 0.0
			collapse_button.offset_right = 0.0
			collapse_button.offset_bottom = 0.0
		else:
			collapse_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
			collapse_button.offset_left = -44.0
			collapse_button.offset_right = 0.0
			collapse_button.offset_top = 0.0
			collapse_button.offset_bottom = 44.0
	_refresh_button()


func _refresh_button() -> void:
	if collapse_button != null:
		collapse_button.text = "▣" if collapsed else "–"
		collapse_button.tooltip_text = "Expand minimap [K]" if collapsed else "Collapse minimap [K]"


func _refresh_visibility() -> void:
	visible = helm_active and not modal_hidden


func _chart_rect() -> Rect2:
	return Rect2(7.0, 31.0, maxf(size.x - 14.0, 1.0), maxf(size.y - 52.0, 1.0))


func _world_bounds() -> Rect2:
	return camera.world_bounds(_chart_rect().size)


func _load_preference() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings != null:
		collapsed = bool(settings.get("minimap_collapsed"))


func _persist_preference() -> void:
	var settings := get_node_or_null("/root/GameSettings")
	if settings == null:
		return
	settings.set("minimap_collapsed", collapsed)
	if settings.has_method("save_settings"):
		settings.call("save_settings")
