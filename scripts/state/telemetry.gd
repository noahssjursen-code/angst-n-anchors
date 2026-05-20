extends Node

## Centralised performance + system telemetry.
##
## Samples engine `Performance` monitors and OS memory info once per
## SAMPLE_INTERVAL_S and emits `sampled` for UI consumers. UIs should
## NOT call `Performance.get_monitor()` themselves or read this node
## per-frame; subscribe to `sampled` and read the cached fields.
##
## Also exposes a load-event timing log: any system that spawns
## heavyweight resources (world generation, port loading, ship
## building, mesh baking) brackets the work with
## `mark_load_event(name)` / `end_load_event(handle)`, and the most
## recent N events become visible in the debug HUD with their
## durations.
##
## Cost: per frame this node does a single delta accumulator + branch.
## Real sampling work runs once per second.

signal sampled

const SAMPLE_INTERVAL_S : float = 1.0
const HISTORY_LEN       : int   = 60   # one minute of history at 1 Hz
const MAX_LOAD_EVENTS   : int   = 32

# ── Static info (set once at _ready) ─────────────────────────────────────────
var cpu_name:     String = "(unknown)"
var cpu_cores:    int    = 0
var gpu_name:     String = "(unknown)"
var gpu_driver:   String = ""
var ram_total_mb: int    = 0
var os_name:      String = ""

# ── Latest sample ────────────────────────────────────────────────────────────
var fps:                int    = 0
var frame_time_ms:      float  = 0.0
var process_time_ms:    float  = 0.0
var physics_time_ms:    float  = 0.0
var draw_calls:         int    = 0
var primitives:         int    = 0
var video_mem_mb:       float  = 0.0
var texture_mem_mb:     float  = 0.0
var buffer_mem_mb:      float  = 0.0
var node_count:         int    = 0
var orphan_count:       int    = 0
var object_count:       int    = 0
var heap_mb:            float  = 0.0
var ram_used_mb:        int    = 0
var ram_free_mb:        int    = 0
var ram_available_mb:   int    = 0

# ── Ring buffers for graphs ──────────────────────────────────────────────────
var fps_history:        PackedFloat32Array = PackedFloat32Array()
var frame_time_history: PackedFloat32Array = PackedFloat32Array()
var draw_calls_history: PackedInt32Array   = PackedInt32Array()

# ── Loading log ──────────────────────────────────────────────────────────────
## Most recent MAX_LOAD_EVENTS entries; oldest first.
## Each entry: { "name": String, "duration_ms": float, "ts": float }
var load_events: Array = []
## Active timers, keyed by handle int.
var _active_timers: Dictionary = {}
var _next_handle: int = 1

# ── Internal ─────────────────────────────────────────────────────────────────
var _sample_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	cpu_name  = OS.get_processor_name()
	cpu_cores = OS.get_processor_count()
	os_name   = OS.get_name()

	var rs := RenderingServer
	gpu_name  = rs.get_video_adapter_name()
	gpu_driver = ""
	var driver_info := OS.get_video_adapter_driver_info()
	if driver_info.size() >= 2:
		gpu_driver = "%s %s" % [driver_info[0], driver_info[1]]

	var mem_info := OS.get_memory_info()
	ram_total_mb = int(float(mem_info.get("physical", 0)) / (1024.0 * 1024.0))

	# Pre-fill ring buffers with zeros so consumers can render
	# without checking length.
	fps_history.resize(HISTORY_LEN)
	frame_time_history.resize(HISTORY_LEN)
	draw_calls_history.resize(HISTORY_LEN)

	# Take an immediate first sample so consumers don't see all-zero
	# values for the first second.
	_take_sample()


func _process(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer < SAMPLE_INTERVAL_S:
		return
	_sample_timer = 0.0
	_take_sample()


## Returns a stable read-only Dictionary snapshot for UI consumers
## that want one-shot access instead of touching the public vars.
func snapshot() -> Dictionary:
	return {
		"fps":               fps,
		"frame_time_ms":     frame_time_ms,
		"process_time_ms":   process_time_ms,
		"physics_time_ms":   physics_time_ms,
		"draw_calls":        draw_calls,
		"primitives":        primitives,
		"video_mem_mb":      video_mem_mb,
		"texture_mem_mb":    texture_mem_mb,
		"buffer_mem_mb":     buffer_mem_mb,
		"node_count":        node_count,
		"orphan_count":      orphan_count,
		"object_count":      object_count,
		"heap_mb":           heap_mb,
		"ram_used_mb":       ram_used_mb,
		"ram_free_mb":       ram_free_mb,
		"ram_available_mb":  ram_available_mb,
		"ram_total_mb":      ram_total_mb,
		"cpu_name":          cpu_name,
		"cpu_cores":         cpu_cores,
		"gpu_name":          gpu_name,
		"gpu_driver":        gpu_driver,
		"os_name":           os_name,
	}


## Start timing a named load event. Returns a handle; pass it back to
## `end_load_event` when the work is complete.
##
## Convention for `name`: dot-namespaced, lowercase. Examples:
##   "world.init"
##   "port.load:port-home"
##   "ship.build:coastal_trader"
##   "island.mesh:port-home"
##   "land_field.bake"
##   "fft.init"
func mark_load_event(name: String) -> int:
	var handle := _next_handle
	_next_handle += 1
	_active_timers[handle] = {
		"name":  name,
		"start": Time.get_ticks_usec(),
	}
	return handle


## End a previously started load event. No-op if the handle is stale.
func end_load_event(handle: int) -> void:
	if not _active_timers.has(handle):
		return
	var rec: Dictionary = _active_timers[handle]
	var duration_us := Time.get_ticks_usec() - int(rec["start"])
	_active_timers.erase(handle)
	load_events.append({
		"name":        str(rec["name"]),
		"duration_ms": float(duration_us) / 1000.0,
		"ts":          Time.get_ticks_msec() * 0.001,
	})
	if load_events.size() > MAX_LOAD_EVENTS:
		load_events.remove_at(0)


## Convenience for sites that have a one-shot block to time. Caller
## passes a Callable; we time it, log the duration, return the result.
func time_load_event(name: String, body: Callable) -> Variant:
	var handle := mark_load_event(name)
	var result: Variant = body.call()
	end_load_event(handle)
	return result


# ── Internals ────────────────────────────────────────────────────────────────

func _take_sample() -> void:
	fps             = int(Performance.get_monitor(Performance.TIME_FPS))
	process_time_ms = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	physics_time_ms = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	frame_time_ms   = 1000.0 / maxf(float(fps), 1.0)
	draw_calls      = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives      = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	video_mem_mb    = _to_mb(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	texture_mem_mb  = _to_mb(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	buffer_mem_mb   = _to_mb(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
	node_count      = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	orphan_count    = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	object_count    = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	heap_mb         = _to_mb(Performance.get_monitor(Performance.MEMORY_STATIC))

	var mem_info := OS.get_memory_info()
	var phys     := float(mem_info.get("physical", 0))
	var free     := float(mem_info.get("free", 0))
	var avail    := float(mem_info.get("available", 0))
	ram_free_mb      = int(free  / (1024.0 * 1024.0))
	ram_available_mb = int(avail / (1024.0 * 1024.0))
	ram_used_mb      = ram_total_mb - ram_free_mb if ram_total_mb > 0 else 0

	_push_history(fps_history,        float(fps))
	_push_history(frame_time_history, frame_time_ms)
	_push_int_history(draw_calls_history, draw_calls)

	sampled.emit()


static func _to_mb(bytes_value: Variant) -> float:
	return float(bytes_value) / (1024.0 * 1024.0)


static func _push_history(buf: PackedFloat32Array, v: float) -> void:
	# Shift left by one (drop oldest), append new value at end.
	# PackedFloat32Array is contiguous so this is one memmove + one set.
	var n := buf.size()
	for i in range(n - 1):
		buf[i] = buf[i + 1]
	if n > 0:
		buf[n - 1] = v


static func _push_int_history(buf: PackedInt32Array, v: int) -> void:
	var n := buf.size()
	for i in range(n - 1):
		buf[i] = buf[i + 1]
	if n > 0:
		buf[n - 1] = v
