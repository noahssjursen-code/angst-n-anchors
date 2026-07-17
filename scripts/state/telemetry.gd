extends Node

## Central debug and performance service.
##
## Owns engine/hardware sampling, latest and peak metric values, weakly-held
## system providers, timed actions, events, context flags, and text reports.
## Debug UI consumes this service; gameplay systems publish here instead of
## teaching the UI how to find and inspect their scene nodes.

signal sampled
signal metric_published(key: StringName)
signal event_recorded(entry: Dictionary)
signal flags_changed
signal peaks_reset

const SAMPLE_INTERVAL_S := 0.25
const PROVIDER_INTERVAL_S := 1.0
const HISTORY_LEN := 240 # One minute at 4 Hz.
const MAX_LOAD_EVENTS := 32
const MAX_EVENTS := 128
const SPIKE_THRESHOLD_MS := 25.0
const SPIKE_COOLDOWN_S := 2.0

# Static hardware identity.
var cpu_name := "(unknown)"
var cpu_cores := 0
var gpu_name := "(unknown)"
var gpu_driver := ""
var ram_total_mb := 0
var os_name := ""

# Compatibility fields for existing consumers.
var fps := 0
var frame_time_ms := 0.0
var process_time_ms := 0.0
var physics_time_ms := 0.0
var gpu_frame_ms := 0.0
var render_cpu_ms := 0.0
var draw_calls := 0
var primitives := 0
var video_mem_mb := 0.0
var texture_mem_mb := 0.0
var buffer_mem_mb := 0.0
var node_count := 0
var orphan_count := 0
var object_count := 0
var heap_mb := 0.0
var ram_used_mb := 0
var ram_free_mb := 0
var ram_available_mb := 0

var fps_history := PackedFloat32Array()
var frame_time_history := PackedFloat32Array()
var draw_calls_history := PackedInt32Array()

## key -> {latest, peak, peak_mode, source, category, label, unit, sampled_at}
var metrics: Dictionary = {}
## source id -> {owner: WeakRef, method: StringName, category, metadata}
var providers: Dictionary = {}
## Most recent entries, oldest first.
var events: Array[Dictionary] = []
## Context flags are sticky until explicitly cleared.
var context_flags: Dictionary = {}

## Compatibility loading log.
var load_events: Array = []
var _active_timers: Dictionary = {}
var _next_handle := 1
var _active_actions: Dictionary = {}
var _next_action_handle := 1
var _sample_timer := 0.0
var _provider_timer := PROVIDER_INTERVAL_S
var _last_spike_at_s := -1000.0
var worst_spike_snapshot: Dictionary = {}
var spike_count := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	cpu_name = OS.get_processor_name()
	cpu_cores = OS.get_processor_count()
	os_name = OS.get_name()
	gpu_name = RenderingServer.get_video_adapter_name()
	var driver_info := OS.get_video_adapter_driver_info()
	if driver_info.size() >= 2:
		gpu_driver = "%s %s" % [driver_info[0], driver_info[1]]
	var mem_info := OS.get_memory_info()
	ram_total_mb = int(float(mem_info.get("physical", 0)) / (1024.0 * 1024.0))
	fps_history.resize(HISTORY_LEN)
	frame_time_history.resize(HISTORY_LEN)
	draw_calls_history.resize(HISTORY_LEN)
	var viewport := get_viewport()
	if viewport != null:
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
	_take_sample()


func _process(delta: float) -> void:
	_sample_timer += delta
	if _sample_timer < SAMPLE_INTERVAL_S:
		return
	_sample_timer = fmod(_sample_timer, SAMPLE_INTERVAL_S)
	_take_sample()


## Publish one metric. Numeric metrics retain a peak; peak_mode may be "max"
## (default), "min" (FPS/headroom), or "latest" for non-peakable values.
func publish_metric(key: StringName, value: Variant, options: Dictionary = {}) -> void:
	if key == &"":
		return
	var record := metrics.get(key, {}) as Dictionary
	var first := record.is_empty()
	var peak_mode := str(options.get("peak_mode", record.get("peak_mode", "max")))
	var track_peak := bool(options.get("track_peak", true))
	record["latest"] = value
	record["peak_mode"] = peak_mode
	record["source"] = str(options.get("source", record.get("source", _source_from_key(key))))
	record["category"] = str(options.get("category", record.get("category", "general")))
	record["label"] = str(options.get("label", record.get("label", _label_from_key(key))))
	record["unit"] = str(options.get("unit", record.get("unit", "")))
	record["sampled_at"] = Time.get_ticks_msec() * 0.001
	if track_peak and (first or not record.has("peak")):
		record["peak"] = value
		record["peak_at"] = record["sampled_at"]
	elif track_peak and _should_replace_peak(record.get("peak"), value, peak_mode):
		record["peak"] = value
		record["peak_at"] = record["sampled_at"]
	elif track_peak and peak_mode == "latest":
		record["peak"] = value
		record["peak_at"] = record["sampled_at"]
	metrics[key] = record
	metric_published.emit(key)


func publish_metrics(
		source: StringName,
		values: Dictionary,
		category: StringName = &"general",
		metadata: Dictionary = {},
) -> void:
	for raw_name in values:
		var name := str(raw_name)
		var key := StringName("%s.%s" % [source, name])
		var options := metadata.get(raw_name, metadata.get(name, {})) as Dictionary
		options = options.duplicate()
		options["source"] = str(source)
		options["category"] = str(category)
		publish_metric(key, values[raw_name], options)


## Providers are weakly held, so an unloaded port/world cannot be retained by
## diagnostics. Provider methods should return a Dictionary.
func register_provider(
		source: StringName,
		owner: Object,
		method: StringName = &"get_debug_stats",
		category: StringName = &"general",
		metadata: Dictionary = {},
) -> void:
	if source == &"" or owner == null or not owner.has_method(method):
		push_warning("Telemetry.register_provider: invalid source/owner/method")
		return
	providers[source] = {
		"owner": weakref(owner),
		"method": method,
		"category": category,
		"metadata": metadata.duplicate(true),
	}


func unregister_provider(source: StringName, owner: Object = null) -> void:
	if not providers.has(source):
		return
	if owner != null:
		var current: Object = (providers[source]["owner"] as WeakRef).get_ref()
		if current != owner:
			return
	providers.erase(source)


func clear_source(source: StringName) -> void:
	providers.erase(source)
	var remove_metrics: Array = []
	for key in metrics:
		if str((metrics[key] as Dictionary).get("source", "")) == str(source):
			remove_metrics.append(key)
	for key in remove_metrics:
		metrics.erase(key)
	var remove_flags: Array = []
	for key in context_flags:
		if str((context_flags[key] as Dictionary).get("source", "")) == str(source):
			remove_flags.append(key)
	for key in remove_flags:
		context_flags.erase(key)
	if not remove_flags.is_empty():
		flags_changed.emit()


func metric_value(key: StringName, use_peak := false, fallback: Variant = 0.0) -> Variant:
	var record := metrics.get(key, {}) as Dictionary
	if record.is_empty():
		return fallback
	return record.get("peak" if use_peak else "latest", record.get("latest", fallback))


func metric_records(category := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var keys := metrics.keys()
	keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
	for key in keys:
		var record := (metrics[key] as Dictionary).duplicate()
		if not category.is_empty() and str(record.get("category", "")) != category:
			continue
		record["key"] = key
		result.append(record)
	return result


func set_context_flag(
		key: StringName,
		value: Variant,
		source: StringName = &"game",
		details: Dictionary = {},
) -> void:
	context_flags[key] = {
		"value": value,
		"source": str(source),
		"details": details.duplicate(true),
		"updated_at": Time.get_ticks_msec() * 0.001,
	}
	flags_changed.emit()


func clear_context_flag(key: StringName) -> void:
	if context_flags.erase(key):
		flags_changed.emit()


func record_event(
		source: StringName,
		name: StringName,
		severity := "info",
		context: Dictionary = {},
) -> void:
	var entry: Dictionary = {
		"source": str(source),
		"name": str(name),
		"severity": severity,
		"context": context.duplicate(true),
		"ts": Time.get_ticks_msec() * 0.001,
		"frame": Engine.get_process_frames(),
	}
	events.append(entry)
	if events.size() > MAX_EVENTS:
		events.remove_at(0)
	event_recorded.emit(entry)


func record_action(name: StringName, context: Dictionary = {}) -> void:
	record_event(&"action", name, "info", context)


func begin_action(name: StringName, context: Dictionary = {}) -> int:
	var handle := _next_action_handle
	_next_action_handle += 1
	_active_actions[handle] = {
		"name": name,
		"start_usec": Time.get_ticks_usec(),
		"context": context.duplicate(true),
		"before": _hardware_context(),
	}
	return handle


func end_action(handle: int, context: Dictionary = {}) -> void:
	if not _active_actions.has(handle):
		return
	var action := _active_actions[handle] as Dictionary
	_active_actions.erase(handle)
	var merged := action.get("context", {}) as Dictionary
	merged = merged.duplicate(true)
	merged.merge(context, true)
	merged["duration_ms"] = float(Time.get_ticks_usec() - int(action["start_usec"])) / 1000.0
	merged["before"] = action.get("before", {})
	merged["after"] = _hardware_context()
	record_event(&"action", action.get("name", &"unnamed") as StringName, "info", merged)


func reset_peaks() -> void:
	for key in metrics:
		var record := metrics[key] as Dictionary
		record["peak"] = record.get("latest")
		record["peak_at"] = Time.get_ticks_msec() * 0.001
	worst_spike_snapshot.clear()
	spike_count = 0
	peaks_reset.emit()


func snapshot(use_peaks := false) -> Dictionary:
	var result := {
		"fps": metric_value(&"hardware.fps", use_peaks, fps),
		"frame_time_ms": metric_value(&"hardware.frame_ms", use_peaks, frame_time_ms),
		"process_time_ms": metric_value(&"hardware.process_ms", use_peaks, process_time_ms),
		"physics_time_ms": metric_value(&"hardware.physics_ms", use_peaks, physics_time_ms),
		"gpu_frame_ms": metric_value(&"hardware.gpu_frame_ms", use_peaks, gpu_frame_ms),
		"draw_calls": metric_value(&"hardware.draw_calls", use_peaks, draw_calls),
		"cpu_name": cpu_name,
		"cpu_cores": cpu_cores,
		"gpu_name": gpu_name,
		"gpu_driver": gpu_driver,
		"os_name": os_name,
		"ram_total_mb": ram_total_mb,
	}
	for key in metrics:
		result[str(key)] = metric_value(key, use_peaks)
	return result


func generate_report(use_peaks := false, recent_event_count := 20) -> String:
	var mode := "PEAK/WORST" if use_peaks else "LATEST"
	var lines := PackedStringArray([
		"ANGST 'N ANCHORS DEBUG REPORT",
		"Mode: %s | UTC: %s" % [mode, Time.get_datetime_string_from_system(true, true)],
		"Build: %s | Godot: %s" % [str(ProjectSettings.get_setting("application/config/version", "dev")), Engine.get_version_info().get("string", "unknown")],
		"CPU: %s x%d" % [cpu_name, cpu_cores],
		"GPU: %s | %s" % [gpu_name, gpu_driver],
		"OS: %s | RAM: %d MB" % [os_name, ram_total_mb],
		"",
		"METRICS (%s)" % mode,
	])
	for record in metric_records():
		var value: Variant = record.get("peak" if use_peaks else "latest", record.get("latest"))
		var peak_stamp := ""
		if use_peaks and record.has("peak_at"):
			peak_stamp = " (at +%.3fs)" % float(record["peak_at"])
		lines.append("[%s] %s = %s%s%s" % [
			str(record.get("category", "general")),
			str(record.get("key", "")),
			_format_value(value),
			(" " + str(record.get("unit"))) if not str(record.get("unit", "")).is_empty() else "",
			peak_stamp,
		])
	if use_peaks:
		lines.append("")
		lines.append("WORST COHERENT SPIKE (%d captured)" % spike_count)
		lines.append(JSON.stringify(worst_spike_snapshot) if not worst_spike_snapshot.is_empty() else "(none)")
	lines.append("")
	lines.append("CONTEXT FLAGS")
	if context_flags.is_empty():
		lines.append("(none)")
	else:
		var flag_keys := context_flags.keys()
		flag_keys.sort_custom(func(a: Variant, b: Variant) -> bool: return str(a) < str(b))
		for key in flag_keys:
			var flag := context_flags[key] as Dictionary
			lines.append("%s = %s [%s]" % [key, _format_value(flag.get("value")), flag.get("source", "")])
	lines.append("")
	lines.append("RECENT EVENTS")
	var start := maxi(0, events.size() - maxi(recent_event_count, 0))
	for i in range(start, events.size()):
		var entry := events[i]
		lines.append("%.3f [%s] %s.%s %s" % [
			float(entry.get("ts", 0.0)), entry.get("severity", "info"),
			entry.get("source", ""), entry.get("name", ""),
			JSON.stringify(entry.get("context", {})),
		])
	return "\n".join(lines)


func mark_load_event(name: String) -> int:
	var handle := _next_handle
	_next_handle += 1
	_active_timers[handle] = {"name": name, "start": Time.get_ticks_usec()}
	return handle


func end_load_event(handle: int) -> void:
	if not _active_timers.has(handle):
		return
	var timer := _active_timers[handle] as Dictionary
	var duration_ms := float(Time.get_ticks_usec() - int(timer["start"])) / 1000.0
	_active_timers.erase(handle)
	var entry := {
		"name": str(timer["name"]),
		"duration_ms": duration_ms,
		"ts": Time.get_ticks_msec() * 0.001,
	}
	load_events.append(entry)
	if load_events.size() > MAX_LOAD_EVENTS:
		load_events.remove_at(0)
	publish_metric(StringName("loading.%s.ms" % str(timer["name"])), duration_ms, {
		"source": "loading", "category": "events", "unit": "ms", "peak_mode": "max",
	})
	record_event(&"loading", StringName(str(timer["name"])), "info", {"duration_ms": duration_ms})


func active_load_event_names() -> PackedStringArray:
	var names := PackedStringArray()
	for handle in _active_timers:
		names.append(str((_active_timers[handle] as Dictionary).get("name", "")))
	return names


func time_load_event(name: String, body: Callable) -> Variant:
	var handle := mark_load_event(name)
	var result: Variant = body.call()
	end_load_event(handle)
	return result


func _take_sample() -> void:
	fps = int(Performance.get_monitor(Performance.TIME_FPS))
	process_time_ms = float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	physics_time_ms = float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	# TIME_PROCESS is the measured duration of one rendered frame. FPS is a
	# once-per-second aggregate in Godot, so 1000/FPS is not a spike sample.
	frame_time_ms = process_time_ms
	draw_calls = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	primitives = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	video_mem_mb = _to_mb(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))
	texture_mem_mb = _to_mb(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))
	buffer_mem_mb = _to_mb(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED))
	node_count = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	orphan_count = int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
	object_count = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	heap_mb = _to_mb(Performance.get_monitor(Performance.MEMORY_STATIC))
	var viewport := get_viewport()
	if viewport != null:
		var rid := viewport.get_viewport_rid()
		gpu_frame_ms = RenderingServer.viewport_get_measured_render_time_gpu(rid)
		render_cpu_ms = RenderingServer.viewport_get_measured_render_time_cpu(rid) \
				+ RenderingServer.get_frame_setup_time_cpu()
	var mem_info := OS.get_memory_info()
	ram_free_mb = int(float(mem_info.get("free", 0)) / (1024.0 * 1024.0))
	ram_available_mb = int(float(mem_info.get("available", 0)) / (1024.0 * 1024.0))
	ram_used_mb = ram_total_mb - ram_free_mb if ram_total_mb > 0 else 0
	_publish_engine_metrics()
	_provider_timer += SAMPLE_INTERVAL_S
	if _provider_timer >= PROVIDER_INTERVAL_S:
		_provider_timer = fmod(_provider_timer, PROVIDER_INTERVAL_S)
		_poll_providers()
	_push_history(fps_history, float(fps))
	_push_history(frame_time_history, frame_time_ms)
	_push_int_history(draw_calls_history, draw_calls)
	_maybe_record_spike()
	sampled.emit()


func _publish_engine_metrics() -> void:
	var values := {
		"fps": fps, "frame_ms": frame_time_ms, "process_ms": process_time_ms,
		"physics_ms": physics_time_ms, "gpu_frame_ms": gpu_frame_ms,
		"render_cpu_ms": render_cpu_ms, "draw_calls": draw_calls,
		"primitives": primitives, "video_mem_mb": video_mem_mb,
		"texture_mem_mb": texture_mem_mb, "buffer_mem_mb": buffer_mem_mb,
		"nodes": node_count, "orphans": orphan_count, "objects": object_count,
		"heap_mb": heap_mb, "ram_used_mb": ram_used_mb,
	}
	var meta := {
		# Ignore the engine's uninitialized 0/1 FPS value for retained minima.
		"fps": {
			"unit": "fps",
			"peak_mode": "min",
			"track_peak": fps >= 5 and Engine.get_process_frames() >= 5,
		},
		"frame_ms": {"unit": "ms"}, "process_ms": {"unit": "ms"},
		"physics_ms": {"unit": "ms"}, "gpu_frame_ms": {"unit": "ms"},
		"render_cpu_ms": {"unit": "ms"}, "video_mem_mb": {"unit": "MB"},
		"texture_mem_mb": {"unit": "MB"}, "buffer_mem_mb": {"unit": "MB"},
		"heap_mb": {"unit": "MB"}, "ram_used_mb": {"unit": "MB"},
	}
	publish_metrics(&"hardware", values, &"hardware", meta)


func _poll_providers() -> void:
	var poll_started := Time.get_ticks_usec()
	var stale: Array[StringName] = []
	for source_variant in providers.keys():
		var source := source_variant as StringName
		var provider := providers[source] as Dictionary
		var owner: Object = (provider["owner"] as WeakRef).get_ref()
		if owner == null:
			stale.append(source)
			continue
		var method := provider["method"] as StringName
		if not owner.has_method(method):
			stale.append(source)
			continue
		var result: Variant = owner.call(method)
		if result is Dictionary:
			publish_metrics(
				source, result as Dictionary,
				provider.get("category", &"general") as StringName,
				provider.get("metadata", {}) as Dictionary,
			)
	for source in stale:
		providers.erase(source)
	publish_metric(&"debug.provider_poll_ms", float(Time.get_ticks_usec() - poll_started) / 1000.0, {
		"source": "debug",
		"category": "hardware",
		"unit": "ms",
	})


func _maybe_record_spike() -> void:
	if fps <= 0 or Engine.get_process_frames() < 5:
		return
	# Process, physics and GPU monitors describe different frame domains; adding
	# them creates a duration that never occurred. Use the slowest measured lane.
	var worst_ms := maxf(process_time_ms, maxf(gpu_frame_ms, physics_time_ms))
	var now_s := Time.get_ticks_msec() * 0.001
	if worst_ms < SPIKE_THRESHOLD_MS or now_s - _last_spike_at_s < SPIKE_COOLDOWN_S:
		return
	_last_spike_at_s = now_s
	var context := {
		"frame_ms": frame_time_ms,
		"gpu_ms": gpu_frame_ms,
		"process_ms": process_time_ms,
		"physics_ms": physics_time_ms,
		"draw_calls": draw_calls,
		"nodes": node_count,
		"active_loads": active_load_event_names(),
		"flags": context_flags.duplicate(true),
		"recent_activity": _recent_event_labels(6),
		"captured_at": now_s,
	}
	spike_count += 1
	if worst_spike_snapshot.is_empty() or worst_ms > float(worst_spike_snapshot.get("worst_ms", 0.0)):
		worst_spike_snapshot = context.duplicate(true)
		worst_spike_snapshot["worst_ms"] = worst_ms
	record_event(&"hardware", &"frame_spike", "warning", context)


func _hardware_context() -> Dictionary:
	return {
		"fps": fps,
		"frame_ms": frame_time_ms,
		"gpu_ms": gpu_frame_ms,
		"process_ms": process_time_ms,
		"physics_ms": physics_time_ms,
		"draw_calls": draw_calls,
		"nodes": node_count,
	}


func _recent_event_labels(limit: int) -> PackedStringArray:
	var labels := PackedStringArray()
	var start := maxi(0, events.size() - maxi(limit, 0))
	for i in range(start, events.size()):
		labels.append("%s.%s" % [events[i].get("source", ""), events[i].get("name", "")])
	return labels


static func _should_replace_peak(previous: Variant, value: Variant, mode: String) -> bool:
	if not (previous is int or previous is float) or not (value is int or value is float):
		return mode == "latest"
	var next_value := float(value)
	if not is_finite(next_value):
		return mode == "latest"
	var previous_value := float(previous)
	if not is_finite(previous_value):
		return true
	return next_value < previous_value if mode == "min" else next_value > previous_value


static func _source_from_key(key: StringName) -> String:
	var text := str(key)
	var split := text.rfind(".")
	return text.left(split) if split >= 0 else "general"


static func _label_from_key(key: StringName) -> String:
	var text := str(key)
	var split := text.rfind(".")
	return text.substr(split + 1).replace("_", " ").capitalize()


static func _format_value(value: Variant) -> String:
	if value is float:
		return "%.3f" % float(value)
	if value is Dictionary or value is Array or value is PackedStringArray:
		return JSON.stringify(value)
	return str(value)


static func _to_mb(bytes_value: Variant) -> float:
	return float(bytes_value) / (1024.0 * 1024.0)


static func _push_history(buffer: PackedFloat32Array, value: float) -> void:
	for i in range(buffer.size() - 1):
		buffer[i] = buffer[i + 1]
	if not buffer.is_empty():
		buffer[buffer.size() - 1] = value


static func _push_int_history(buffer: PackedInt32Array, value: int) -> void:
	for i in range(buffer.size() - 1):
		buffer[i] = buffer[i + 1]
	if not buffer.is_empty():
		buffer[buffer.size() - 1] = value
