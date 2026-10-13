extends Node

func _ready() -> void:
	var a := RemoteWorldBackend.new()
	a.configure("http://127.0.0.1:8080")
	a._session = {"session_token":"clock-test"}
	add_child(a)
	await get_tree().create_timer(1.0).timeout
	var b := RemoteWorldBackend.new()
	b.configure("http://127.0.0.1:8080")
	b._session = {"session_token":"clock-test"}
	add_child(b)
	await get_tree().create_timer(1.0).timeout
	assert(a._clock_server_ms > 0 and b._clock_server_ms > 0, "Both clocks must receive Docker server time")
	assert(absf(a.server_unix_seconds()-b.server_unix_seconds()) < .15, "Staggered clients must agree")
	var before := a.server_unix_seconds()
	a.set_process(false)
	await get_tree().create_timer(.5).timeout
	assert(a.server_unix_seconds()-before > .45, "Clock must advance even without simulation frames")
	assert(absf(fposmod(a.server_unix_seconds(),200.0)-fposmod(b.server_unix_seconds(),200.0)) < .15, "FFT phase agrees")
	print("MP OCEAN CLOCK PASS: staggered clients, shared phase, frame-independent time")
	get_tree().quit()
