extends SceneTree

## Scratch probe (not a test). Owner decision #3 asks what OPEN_WATER should
## promise a player. That is a LOOK question, so it gets pictures, not a metric:
##
##  1. a plan view of the macro map with the OPEN_WATER cut drawn where the
##     generator actually puts it, the two test samples, and rings at 1800 m
##     (COASTAL_DISTANCE_M) and 5000 m (the bound the test asserts), plus a
##     5 km scale bar;
##  2. an eye-level skyline from each sample, ray-marched through the SAME
##     height field the terrain mesh is built from (WorldLayout.sample_height),
##     at the player camera's own 75 deg vertical FOV, 1280x720, with a 1.8 m
##     scale post at 10 m in frame.
##
## Limits, stated because they bias the picture: no haze/atmosphere, no mesh LOD
## and no wave occlusion, so this shows MORE land than the game would. Earth
## curvature IS applied (t^2/2R). Eye height is a parameter and both a 1.6 m
## standing figure and a 4.0 m wheelhouse eye are rendered.

const GENERATOR := preload("res://scripts/world/world_layout_generator.gd")
const LAND_FIELD := preload("res://scripts/weather/land_field.gd")
const FIXED_SEED := 90210
const OUT_DIR := "res://screenshots/decisions"
const PLAN_PX := 1024
const VIEW_W := 1280
const VIEW_H := 720
const VFOV_DEG := 75.0  ## scripts/player/player_camera.gd base_fov
const EARTH_R := 6371000.0


func _initialize() -> void:
	var layout: WorldLayout = GENERATOR.generate(FIXED_SEED)
	LAND_FIELD.initialize(layout)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	_plan(layout)
	for eye in [1.6, 4.0]:
		_skyline(layout, Vector2(-15000.0, 14500.0), eye)
		_skyline(layout, Vector2(-18000.0, 14500.0), eye)
	quit()


# ── plan view ────────────────────────────────────────────────────────────────
func _plan(layout: WorldLayout) -> void:
	var img := Image.create(PLAN_PX, PLAN_PX, false, Image.FORMAT_RGBA8)
	var half := layout.half_extent_m
	for py in range(PLAN_PX):
		var wz := lerpf(half, -half, float(py) / float(PLAN_PX - 1))
		for px in range(PLAN_PX):
			var wx := lerpf(-half, half, float(px) / float(PLAN_PX - 1))
			var p := Vector2(wx, wz)
			var d := layout.sample_signed_distance(p)
			var color: Color
			if d < 0.0:
				var h := clampf(layout.sample_height(p) / 700.0, 0.0, 1.0)
				color = Color(0.20, 0.36, 0.18).lerp(Color(0.62, 0.63, 0.44), h)
			else:
				match layout.classify_region(p):
					WorldLayout.Region.OPEN_WATER:
						color = Color(0.02, 0.10, 0.22)
					WorldLayout.Region.ARCHIPELAGO:
						color = Color(0.07, 0.28, 0.42)
					WorldLayout.Region.FJORD:
						color = Color(0.05, 0.34, 0.50)
					_:
						color = Color(0.09, 0.31, 0.42)
			img.set_pixel(px, py, color)
	for contour in layout.coastline_contours:
		_line(img, contour[0], contour[1], half, Color(0.98, 0.88, 0.48))
	# the OPEN_WATER cut, as the generator draws it
	_line(img, Vector2(-13500.0, -half), Vector2(-13500.0, half), half, Color(1.0, 0.35, 0.15))
	for sample in [Vector2(-15000.0, 14500.0), Vector2(-18000.0, 14500.0)]:
		_ring(img, sample, LAND_FIELD.COASTAL_DISTANCE_M, half, Color(1.0, 0.85, 0.2))
		_ring(img, sample, 5000.0, half, Color(1.0, 0.25, 0.85))
		_cross(img, sample, half, Color(1.0, 1.0, 1.0))
	# 5 km scale bar, bottom-left
	var bar_px := int(round(5000.0 / (2.0 * half) * float(PLAN_PX)))
	for x in range(40, 40 + bar_px):
		for y in range(PLAN_PX - 50, PLAN_PX - 42):
			img.set_pixel(x, y, Color(1, 1, 1))
	var path := OUT_DIR.path_join("open_water_promise__plan-regions.png")
	print("plan -> %s (ok=%s) 5 km bar = %d px" % [
		path, img.save_png(ProjectSettings.globalize_path(path)) == OK, bar_px,
	])


# ── eye-level skyline ────────────────────────────────────────────────────────
func _skyline(layout: WorldLayout, from: Vector2, eye_y: float) -> void:
	var nearest := _nearest_land(layout, from)
	var bearing: float = atan2(nearest.y - from.y, nearest.x - from.x)
	var img := Image.create(VIEW_W, VIEW_H, false, Image.FORMAT_RGBA8)
	var focal := (float(VIEW_H) * 0.5) / tan(deg_to_rad(VFOV_DEG) * 0.5)
	var top_elev := PackedFloat32Array()
	var top_dist := PackedFloat32Array()
	top_elev.resize(VIEW_W)
	top_dist.resize(VIEW_W)
	var best_elev := -10.0
	var best_dist := 0.0
	for col in range(VIEW_W):
		var yaw: float = bearing + atan2(float(col - VIEW_W / 2), focal)
		var dir := Vector2(cos(yaw), sin(yaw))
		var t := 20.0
		var e_max := -10.0
		var d_at := 0.0
		while t < 20000.0:
			var p := from + dir * t
			if layout.sample_signed_distance(p) < 0.0:
				var h := layout.sample_height(p) - eye_y - (t * t) / (2.0 * EARTH_R)
				var e: float = atan2(h, t)
				if e > e_max:
					e_max = e
					d_at = t
			t += maxf(12.0, t * 0.004)
		top_elev[col] = e_max
		top_dist[col] = d_at
		if e_max > best_elev:
			best_elev = e_max
			best_dist = d_at
	for py in range(VIEW_H):
		var elev: float = atan2(float(VIEW_H / 2 - py), focal)
		for px in range(VIEW_W):
			var color: Color
			if top_elev[px] > -9.0 and elev <= top_elev[px] and elev > -0.0005:
				var fade: float = clampf(top_dist[px] / 12000.0, 0.0, 1.0)
				color = Color(0.16, 0.20, 0.15).lerp(Color(0.55, 0.62, 0.70), fade)
			elif elev > 0.0:
				color = Color(0.45, 0.60, 0.78).lerp(Color(0.72, 0.82, 0.92), 1.0 - clampf(elev * 3.0, 0.0, 1.0))
			else:
				color = Color(0.10, 0.20, 0.28).lerp(Color(0.16, 0.30, 0.38), clampf(-elev * 4.0, 0.0, 1.0))
			img.set_pixel(px, py, color)
	# horizon line
	for px in range(VIEW_W):
		img.set_pixel(px, VIEW_H / 2, Color(1.0, 0.3, 0.3, 1.0))
	# 1.8 m scale post at 10 m, centred
	_scale_post(img, focal, eye_y)
	var name := "open_water_promise__eyelevel-x%d-eye%.1f.png" % [int(from.x), eye_y]
	var path := OUT_DIR.path_join(name)
	print("%s: nearest land (%.0f, %.0f) at %.1f m | tallest land %.4f deg (%.1f px) at %.0f m | saved=%s" % [
		name, nearest.x, nearest.y, from.distance_to(nearest),
		rad_to_deg(best_elev), best_elev * focal, best_dist,
		img.save_png(ProjectSettings.globalize_path(path)) == OK,
	])


func _scale_post(img: Image, focal: float, eye_y: float) -> void:
	var d := 10.0
	var y_bottom := int(round(float(VIEW_H / 2) + focal * (eye_y / d)))
	var y_top := int(round(float(VIEW_H / 2) + focal * ((eye_y - 1.8) / d)))
	var x0 := VIEW_W / 2 - 6
	for y in range(mini(y_top, y_bottom), maxi(y_top, y_bottom) + 1):
		if y < 0 or y >= VIEW_H:
			continue
		for x in range(x0, x0 + 12):
			img.set_pixel(x, y, Color(0.95, 0.25, 0.1))
	print("   scale post: 1.8 m at 10 m spans rows %d..%d (%d px)" % [
		y_top, y_bottom, absi(y_bottom - y_top),
	])


func _nearest_land(layout: WorldLayout, from: Vector2) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	var half := layout.half_extent_m
	var res := layout.raster_resolution
	var cell := layout.cell_size_m
	var raster := layout.get_signed_distance_raster()
	for zi in range(res):
		for xi in range(res):
			if raster[zi * res + xi] >= 0.0:
				continue
			var p := Vector2(-half + float(xi) * cell, -half + float(zi) * cell)
			var d := from.distance_squared_to(p)
			if d < best_d:
				best_d = d
				best = p
	return best


func _world_to_px(p: Vector2, half: float) -> Vector2:
	return Vector2(
		(p.x + half) / (2.0 * half) * float(PLAN_PX - 1),
		(half - p.y) / (2.0 * half) * float(PLAN_PX - 1),
	)


func _line(img: Image, a: Vector2, b: Vector2, half: float, c: Color) -> void:
	var pa := _world_to_px(a, half)
	var pb := _world_to_px(b, half)
	var steps := maxi(1, int(maxf(absf(pb.x - pa.x), absf(pb.y - pa.y))))
	for i in range(steps + 1):
		var p := pa.lerp(pb, float(i) / float(steps))
		_put(img, int(round(p.x)), int(round(p.y)), c)


func _ring(img: Image, center: Vector2, radius_m: float, half: float, c: Color) -> void:
	var steps := 2048
	for i in range(steps):
		var a := TAU * float(i) / float(steps)
		var p := _world_to_px(center + Vector2(cos(a), sin(a)) * radius_m, half)
		_put(img, int(round(p.x)), int(round(p.y)), c)


func _cross(img: Image, center: Vector2, half: float, c: Color) -> void:
	var p := _world_to_px(center, half)
	for k in range(-7, 8):
		_put(img, int(round(p.x)) + k, int(round(p.y)), c)
		_put(img, int(round(p.x)), int(round(p.y)) + k, c)


func _put(img: Image, x: int, y: int, c: Color) -> void:
	if x < 0 or y < 0 or x >= PLAN_PX or y >= PLAN_PX:
		return
	img.set_pixel(x, y, c)
