extends RefCounted

## Shared pass/fail bookkeeping for the test suite.
##
## Godot's `assert()` is the wrong tool for a test: it does not abort, it does
## not set an exit code, and in an exported build it is compiled out entirely.
## A test built on it can print PASS while its assertions fail — which is
## exactly what `company_service_test` was doing. Every test records through
## this instead, and the process exit code is derived from the record.
##
## Both gate lanes use it.
##
## SceneTree lane (`godot ... --script res://tests/x.gd`):
##
##     const TestReport := preload("res://tests/support/test_report.gd")
##
##     func _initialize() -> void:
##         var t := TestReport.new("x_test")
##         t.check("the thing holds", thing == expected)
##         t.equal("count", got, 3)
##         t.finish(self)
##
## Scene lane (`godot ... res://tests/x.tscn`, autoloads available):
##
##     func _run() -> void:
##         var t := TestReport.new("x_test")
##         ...
##         t.finish(get_tree())

var _name: String
var _failures: PackedStringArray = PackedStringArray()
var _checks: int = 0
var _verbose: bool


func _init(test_name: String, verbose: bool = true) -> void:
	_name = test_name
	_verbose = verbose


## Record one boolean expectation. Returns `ok`, so a caller can early-out:
##     if not t.check("plan parsed", plan != null): return
func check(label: String, ok: bool) -> bool:
	_checks += 1
	if ok:
		if _verbose:
			print("  PASS  %s" % label)
	else:
		_failures.append(label)
		print("  FAIL  %s" % label)
	return ok


## Equality with the operands printed on failure — the reason a bare boolean
## check is frustrating to debug is that it never tells you what it saw.
func equal(label: String, actual: Variant, expected: Variant) -> bool:
	var ok: bool = actual == expected
	if not ok:
		return check("%s (expected %s, got %s)" % [label, expected, actual], false)
	return check(label, true)


func not_equal(label: String, actual: Variant, unexpected: Variant) -> bool:
	if actual == unexpected:
		return check("%s (should not have been %s)" % [label, unexpected], false)
	return check(label, true)


## Float comparison with an explicit tolerance. Geometry tests need this and
## `==` on floats is a bug waiting for a different CPU.
func near(label: String, actual: float, expected: float, tolerance: float = 0.0001) -> bool:
	var delta: float = absf(actual - expected)
	if delta > tolerance:
		return check(
			"%s (expected %s ±%s, got %s — off by %s)" % [label, expected, tolerance, actual, delta],
			false,
		)
	return check(label, true)


## Record a failure that is not expressible as a single boolean — an exception
## path, an unreachable branch, a missing fixture.
func fail(label: String) -> void:
	check(label, false)


func ok() -> bool:
	return _failures.is_empty()


func failure_count() -> int:
	return _failures.size()


func check_count() -> int:
	return _checks


func summary() -> String:
	if _checks == 0:
		return "%s: NO CHECKS RAN" % _name
	if ok():
		return "%s: PASS (%d checks)" % [_name, _checks]
	return "%s: %d/%d FAILED" % [_name, _failures.size(), _checks]


## Print the verdict and quit with 0 (green) or 1 (red).
##
## A test that ran zero checks exits 1: silently checking nothing is a failure
## mode that otherwise reads as success for the rest of the suite's life.
func finish(tree: SceneTree) -> void:
	print("---")
	for failure in _failures:
		push_error("%s: %s" % [_name, failure])
	print(summary())
	if tree == null:
		OS.crash("TestReport.finish() needs the SceneTree to set an exit code")
		return
	tree.quit(0 if (ok() and _checks > 0) else 1)
