class_name ChartSurface
extends Control

## Separate retained canvases: cursor/nav updates do not redraw geography.
var chart: MapOverlay
var geography := false

func _draw() -> void:
	if chart == null or chart.data == null or chart.data.layout == null:
		return
	var ctx := chart.surface_context()
	if geography:
		chart.renderer.render_geography(self, ctx, chart.layers,
			chart.dragging or chart.interaction_settle > 0.0)
	else:
		chart.renderer.render_contacts(self, ctx, chart.layers, chart.nav,
			chart.selected_port, chart.mode != MapOverlay.Mode.HOME_PORT_PICK)
		if chart.layers.is_visible("plots") and chart.mode == MapOverlay.Mode.NAVIGATION:
			chart.renderer.plots.draw_selection(self, ctx,
				chart.selected_plot, chart.hover_plot)
		chart._draw_compass(ctx.chart_rect, self)
		chart._draw_scale(ctx.chart_rect, ctx.world_bounds, self)
