class_name MpTestRunner
extends Node

## Scenario orchestration and reporting for the multiplayer test suite.
## Scenarios are async Callables composed from MpVirtualClient primitives.
## Produces a terse stdout summary plus a structured JSON report whose failure
## entries carry full forensics, so results can be pasted into a chat for
## diagnosis without follow-up questions.

signal scenario_started(scenario_name: String)
signal scenario_finished(scenario_name: String, status: String)

const STATUS_PASS := "PASS"
const STATUS_FAIL := "FAIL"
const STATUS_EXPECTED_FAIL := "EXPECTED_FAIL"
const STATUS_UNEXPECTED_PASS := "UNEXPECTED_PASS"

var report_path := "user://mp_test_report.json"
var context: Dictionary = {}
var forensics_provider := Callable()
var results: Array[Dictionary] = []

var _scenarios: Array[Dictionary] = []
var _current: Dictionary = {}


func add_scenario(scenario_name: String, fn: Callable, expected_fail := false) -> void:
	_scenarios.append({"name": scenario_name, "fn": fn, "expected_fail": expected_fail})


func run_all() -> void:
	for scenario in _scenarios:
		var scenario_name := str(scenario["name"])
		_current = {"name": scenario_name, "steps": [], "failed": false}
		scenario_started.emit(scenario_name)
		print("[mp-test] ── %s" % scenario_name)
		var started_ms := Time.get_ticks_msec()
		await (scenario["fn"] as Callable).call()
		var failed := bool(_current["failed"])
		var expected_fail := bool(scenario["expected_fail"])
		var status := STATUS_PASS
		if failed and expected_fail:
			status = STATUS_EXPECTED_FAIL
		elif failed:
			status = STATUS_FAIL
		elif expected_fail:
			status = STATUS_UNEXPECTED_PASS
		var entry := {
			"name": scenario_name,
			"status": status,
			"duration_s": float(Time.get_ticks_msec() - started_ms) / 1000.0,
			"steps": _current["steps"],
		}
		if (status == STATUS_FAIL or status == STATUS_UNEXPECTED_PASS) and forensics_provider.is_valid():
			entry["forensics"] = forensics_provider.call()
		results.append(entry)
		scenario_finished.emit(scenario_name, status)
	_current = {}


## Records an assertion step. Returns the condition so callers can gate
## follow-up steps on it.
func check(condition: bool, step_label: String, details: Variant = null) -> bool:
	var step := {"label": step_label, "ok": condition}
	if details != null:
		step["details"] = details
	(_current["steps"] as Array).append(step)
	if condition:
		print("[mp-test]    ok  %s" % step_label)
	else:
		_current["failed"] = true
		print("[mp-test]  FAIL  %s — %s" % [step_label, JSON.stringify(details) if details != null else ""])
	return condition


## Records an informational measurement that never fails the scenario.
func note(step_label: String, details: Variant = null) -> void:
	var step := {"label": step_label, "ok": true, "informational": true}
	if details != null:
		step["details"] = details
	(_current["steps"] as Array).append(step)
	print("[mp-test]  note  %s — %s" % [step_label, JSON.stringify(details) if details != null else ""])


func finish() -> int:
	var totals := {STATUS_PASS: 0, STATUS_FAIL: 0, STATUS_EXPECTED_FAIL: 0, STATUS_UNEXPECTED_PASS: 0}
	for entry in results:
		totals[str(entry["status"])] = int(totals.get(str(entry["status"]), 0)) + 1
	var report := {
		"context": context,
		"summary": totals,
		"scenarios": results,
	}
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("")
	print("== MP TEST SUITE REPORT ==")
	print("server: %s" % str(context.get("server", "?")))
	for entry in results:
		print("%-16s %s (%.1fs)" % [str(entry["status"]), str(entry["name"]), float(entry["duration_s"])])
		for step_variant in entry["steps"] as Array:
			var step := step_variant as Dictionary
			if not bool(step.get("ok", true)) or bool(step.get("informational", false)):
				var suffix := ""
				if step.has("details"):
					suffix = " — %s" % JSON.stringify(step["details"])
				print("    %s %s%s" % ["note" if bool(step.get("informational", false)) else "FAIL", str(step["label"]), suffix])
	var failures := int(totals[STATUS_FAIL]) + int(totals[STATUS_UNEXPECTED_PASS])
	print("summary: %d pass, %d fail, %d expected-fail, %d unexpected-pass" % [
		int(totals[STATUS_PASS]), int(totals[STATUS_FAIL]),
		int(totals[STATUS_EXPECTED_FAIL]), int(totals[STATUS_UNEXPECTED_PASS]),
	])
	print("report: %s" % ProjectSettings.globalize_path(report_path))
	if failures > 0:
		print("")
		print("-- failing scenarios (copy-paste for diagnosis) --")
		for entry in results:
			if str(entry["status"]) == STATUS_FAIL or str(entry["status"]) == STATUS_UNEXPECTED_PASS:
				print(JSON.stringify(entry, "  "))
	return 1 if failures > 0 else 0
