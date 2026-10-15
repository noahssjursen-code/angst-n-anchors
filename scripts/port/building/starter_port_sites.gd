class_name StarterPortSites
extends RefCounted

static var _reserved_crossings:Dictionary={}

static func _clear_of_bridges(bounds:Rect2,chart:ChartDataSnapshot)->bool:
	var key:=chart.layout_checksum
	if not _reserved_crossings.has(key):
		var defs:=CoastalPortPlacer.place_ports(chart.layout,35,PackedStringArray(WorldPortNames.NAMES))
		var zones:=WorldTerrainStreamer.make_flatten_zones(defs,0,chart.world_seed,chart.layout)
		var settlements:=CoastalSettlementPlan.build(chart.layout,defs,zones)
		var plan:=CoastalBridgePlan.build(chart.layout,defs,settlements.buildings)
		var crossings:Array=plan.bridges.duplicate()
		for alternatives in plan.get("alternatives",{}).values():crossings.append_array(alternatives)
		_reserved_crossings[key]=crossings
	for crossing in _reserved_crossings[key]:
		var center:=bounds.get_center()
		# Reserve bridge approaches as well as the span. Deliberately conservative:
		# a starter may use another plot instead of moving generated infrastructure.
		if center.distance_to(Geometry2D.get_closest_point_to_segment(center,crossing.a_xz,crossing.b_xz))<1300:return false
	return true

## Deterministic coastal survey used by local onboarding and the server's
## offline catalogue exporter. Clients never upload a multiplayer port layout.
static func fit(plot:Dictionary,chart:ChartDataSnapshot) -> Dictionary:
	if plot.is_empty() or bool(plot.get("boundary_review_required",true)):return {}
	var bounds:=ChartPlotLayer.plot_rect(plot)
	if not Rect2(Vector2.ONE*-chart.world_size_m*.5,Vector2.ONE*chart.world_size_m).grow(-1000).encloses(bounds):return {}
	var anchor:=Vector2(float(plot.shore_anchor[0]),float(plot.shore_anchor[1]))
	for port in chart.ports:
		var pos:Vector3=port.get("position",Vector3.ZERO)
		if bounds.grow(900).has_point(Vector2(pos.x,pos.z)):return {}
	if not _clear_of_bridges(bounds,chart):return {}
	var layout:=chart.layout
	var options:Array=[]
	for yaw in [0,90,180,270]:
		var inland:=Vector3.BACK.rotated(Vector3.UP,deg_to_rad(yaw))
		var dry:=layout.sample_seabed_elevation(anchor+Vector2(inland.x,inland.z)*12)
		options.append({"yaw":yaw,"dry":dry})
	options.sort_custom(func(a,b):return a.dry>b.dry)
	for option in options:
		if option.dry<.2:continue
		var yaw:=float(option.yaw)
		for shore_z in [72,64,80]:
			var offset:=Vector3(0,0,shore_z).rotated(Vector3.UP,deg_to_rad(yaw))
			var origin:=Vector3(anchor.x-offset.x,WaveSurface.WATER_LEVEL+2,anchor.y-offset.z)
			var fits:=true
			for p in [Vector3(-17,0,39),Vector3(17,0,39),Vector3(-17,0,81),Vector3(17,0,81)]:
				var world:Vector3=origin+p.rotated(Vector3.UP,deg_to_rad(yaw))
				if not bounds.has_point(Vector2(world.x,world.z)):fits=false;break
			if not fits:continue
			for p in [Vector3(-12,0,32),Vector3(12,0,32),Vector3(0,0,16)]:
				var world:Vector3=origin+p.rotated(Vector3.UP,deg_to_rad(yaw))
				if layout.sample_water_depth(Vector2(world.x,world.z))<4:fits=false;break
			if not fits:continue
			var end:=origin+Vector3(8,0,80).rotated(Vector3.UP,deg_to_rad(yaw))
			var height:=layout.sample_seabed_elevation(Vector2(end.x,end.z))
			if height<0 or height>7:continue
			var identity:={"seed":layout.seed,"generation_version":chart.generation_version,"checksum":layout.layout_checksum}
			var plots:Array=[{"id":str(plot.id),"owner_company_id":"company-starter","rect_m":[bounds.position.x-origin.x,bounds.position.y-origin.z,bounds.size.x,bounds.size.y]}]
			var record:=CustomPortStarterExample.build(origin,plots,identity)
			record.vessels=[]
			for row in record.placements:
				var at:=CustomPortCatalog.vector3(row.position_m).rotated(Vector3.UP,deg_to_rad(yaw))
				row.position_m=[at.x,at.y,at.z];row.yaw_degrees=fposmod(float(row.yaw_degrees)+yaw,360)
				if CustomPortCatalog.definition(str(row.asset_id)).kind=="platform":
					var depth:=4.0
					for dx in [-2,0,2]:
						for dz in [-2,0,2]:depth=maxf(depth,origin.y-layout.sample_seabed_elevation(Vector2(origin.x+at.x+dx,origin.z+at.z+dz))+.5)
					row.attributes.support_depth_m=depth
			# Cover the complete berth/approach region with conservatively sampled cells.
			for z in range(-24,40,8):
				for x in range(-24,24,8):
					var at:=Vector3(x+4,0,z+4).rotated(Vector3.UP,deg_to_rad(yaw))
					var depth:=INF
					for dx in range(-4,5,2):
						for dz in range(-4,5,2):depth=minf(depth,layout.sample_water_depth(Vector2(origin.x+at.x+dx,origin.z+at.z+dz)))
					if depth>1:record.water_regions.append({"rect_m":[at.x-4,at.z-4,8,8],"depth_m":depth-1})
			var state:=CustomPortState.from_dict(record,identity,CustomPortCatalog.definitions())
			if not state.validation_errors.is_empty():continue
			var boat:=CustomPortVesselProjection.from_prebuilt("fishing_hook_line","starter-fishing-boat","company-starter","Fishing boat")
			var berth_ok:=false
			for berth in state.derived_berths():
				if CustomPortBerths.fit(berth,boat).ok:berth_ok=true
			if not berth_ok:continue
			record.live_berths=[]
			for berth in state.derived_berths():
				var entry:Dictionary=berth.duplicate(true)
				entry.allowed_hull_ids=[]
				for hull_id in ImportedHullCatalog.ENTRIES:
					var hull:Dictionary=ImportedHullCatalog.ENTRIES[hull_id]
					var dimensions:={"length_m":hull.loa_m,"beam_m":hull.beam_m,"draft_m":hull.draft_m}
					if CustomPortBerths.fit(berth,dimensions).ok:entry.allowed_hull_ids.append(hull_id)
				record.live_berths.append(entry)
			var spawn:=Vector3(5,.15,43).rotated(Vector3.UP,deg_to_rad(yaw))
			record.spawn_local_m=[spawn.x,spawn.y,spawn.z]
			record.starter_version=1
			return record
	return {}

static func owned(template:Dictionary,actor:String,company:String) -> Dictionary:
	var record:=template.duplicate(true)
	record.id="home-"+actor;record.owner_actor_id=actor;record.owner_company_id=company
	for plot in record.plots:plot.owner_company_id=company
	record.revision=1
	return record
