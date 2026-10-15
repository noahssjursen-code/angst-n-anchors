extends Node

## Read-only site survey of the actual island used by the build showcase.
## No terrain flattening, generated ports, captain state or pretend water depths.
const OUTPUT := "C:/Users/noahs/Documents/Codex/2026-10-11/referenced-chatgpt-conversation-this-is-an/outputs/custom-port-site.json"
var layout: WorldLayout
var plots: CoastalPlotIndex
var grid_cache := {}
var height_cache := {}

func _ready() -> void:
	assert(ShipyardPlaytestMode.active())
	call_deferred("_survey")

func _height(at: Vector2) -> float:
	var key := Vector2i((at*10.0).round())
	if not height_cache.has(key):
		# Check the continuous source AND the actual finest terrain triangles.
		height_cache[key] = maxf(WorldTerrainStreamer.sample_render_terrain_height(layout,at),WorldForestStreamer.sample_root_height(layout,at,[],grid_cache))
	return float(height_cache[key])

func _survey() -> void:
	layout=WorldLayoutGenerator.generate(73119,WorldLayoutGenerator.DEFAULT_CONFIG_PATH,15000)
	plots=CoastalPlotIndex.for_layout(layout,200)
	var island:=PlotBuildIsland.choose(layout,plots)
	assert(not island.is_empty())
	var bounds: Rect2 = island.bounds
	var candidates: Array[Dictionary] = []
	var seen := {}
	var checked := 0
	for segment in layout.macro_coastline_contours():
		var midpoint: Vector2 = segment[0].lerp(segment[1],.5)
		if not bounds.grow(2).has_point(midpoint):continue
		for turn in 4:
			var angle:=float(turn)*PI*.5
			var inland:=Vector2(sin(angle),cos(angle))
			var across:=Vector2(cos(angle),-sin(angle))
			# The back edge should join low shoreline; never bury a foundation in
			# a hillside merely to make a chosen orientation look possible.
			for rear_inland in [-16,-8,0,8,16]:
				var origin: Vector2 = (midpoint-inland*(64.0-float(rear_inland))).snapped(Vector2(4,4))
				var key := str(origin)+":"+str(turn)
				if seen.has(key):continue
				seen[key]=true
				checked+=1
				var back: Vector2 = origin+inland*64.0
				var back_distance:=layout.sample_signed_distance(back)
				if back_distance > 28 or back_distance < -30:continue
				if layout.sample_signed_distance(origin)<10:continue
				var back_height:=_height(back)
				if back_height > .35 or back_height < -8:continue
				var min_depth:=INF
				var bad:=false
				for x in range(-72,73,12):
					for z in [-4,-12,-24,-48,-80,-120]:
						var p: Vector2 = origin+across*float(x)+inland*float(z)
						var depth:=WaveSurface.WATER_LEVEL-_height(p)
						min_depth=minf(min_depth,depth)
						if depth<4.0:bad=true;break
					if bad:break
				if bad:continue
				var maximum_height:=-INF
				var minimum_height:=INF
				var plot_ids: Array[String] = []
				for x in range(-72,73,8):
					for z in range(0,65,8):
						var p: Vector2 = origin+across*float(x)+inland*float(z)
						var h:=_height(p)
						maximum_height=maxf(maximum_height,h)
						minimum_height=minf(minimum_height,h)
						if h>.35:bad=true;break
						var plot:=plots.plot_at(p)
						if plot.is_empty():bad=true;break
						if not str(plot.id) in plot_ids:plot_ids.append(str(plot.id))
					if bad:break
				if bad:continue
				plot_ids.sort()
				var records: Array[Dictionary] = []
				for id in plot_ids:records.append(plots.get_plot(id))
				var access: Vector2 = back
				var best_access_gap:=INF
				var access_height:=0.0
				for x in range(-64,65,8):
					for z in range(64,97,4):
						var p: Vector2 = origin+across*float(x)+inland*float(z)
						var h:=_height(p)
						if h>-.1 and h<1.3:
							var gap:=float(z-64)+absf(h-.5)*4.0
							if gap<best_access_gap:best_access_gap=gap;access=p;access_height=h
				var score:=absf(back_height-.2)*4+maxf(back_distance,0)*.1+float(plot_ids.size())*4+best_access_gap*.2+maxf(-minimum_height-30,0)*.1
				candidates.append({"origin_xz":[origin.x,origin.y],"rotation_y_degrees":turn*90,"local_rectangle_m":{"min":[-72,0],"max":[72,64]},"deck_world_y":.5,"deck_above_mean_sea_m":2,"min_sampled_approach_depth_m":min_depth,"maximum_ground_y_under_deck":maximum_height,"minimum_ground_y_under_deck":minimum_height,"back_centre_signed_shore_distance_m":back_distance,"back_centre_ground_y":back_height,"access_xz":[access.x,access.y],"access_ground_y":access_height,"access_gap_score":best_access_gap,"plot_ids":plot_ids,"plot_records":records,"score":score})
	candidates.sort_custom(func(a,b):return float(a.score)<float(b.score))
	var top: Array[Dictionary] = []
	for candidate in candidates:
		var unique:=true
		for other in top:
			if Vector2(candidate.origin_xz[0],candidate.origin_xz[1]).distance_to(Vector2(other.origin_xz[0],other.origin_xz[1]))<80:unique=false;break
		if unique:top.append(candidate)
		if top.size()>=5:break
	var output:={"world_identity":plots.world_identity,"island_bounds":{"position":[bounds.position.x,bounds.position.y],"size":[bounds.size.x,bounds.size.y]},"candidates_checked":checked,"valid_candidates":candidates.size(),"sample_spacing_m":8,"approach_depth_sample_x_step_m":12,"note":"Uses max of continuous terrain and actual25m terrain triangles, no flatten zones. Coast plot IDs include only footprint, not an arbitrary distant sea parcel. Draft3m plus1m underkeel clearance checked from4m to120m seaward. Dense/native inspection still needed for selected site.","selected":top[0] if not top.is_empty() else {},"alternatives":top}
	var file:=FileAccess.open(OUTPUT,FileAccess.WRITE)
	file.store_string(JSON.stringify(output,"\t"));file.close()
	print("CUSTOM PORT SITE SURVEY checked=",checked," valid=",candidates.size()," output=",OUTPUT)
	if not top.is_empty():print("SITE ",JSON.stringify(top[0]))
	get_tree().quit(0 if not top.is_empty() else 1)
