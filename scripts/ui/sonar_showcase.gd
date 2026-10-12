extends Control
## F6: production sounder UI fed by the real habitat ping path on known grounds.
class Ground extends FishingHabitat:
	var mode:=0
	func bottom(at:Vector2)->float:
		var depth:=116.0-24*exp(-pow((at.x-210)/29,2))+sin(at.x/22)*2+sin(at.x/7)*.7
		return WaveSurface.WATER_LEVEL-(depth if mode!=2 else 24+sin(at.x/35)*4)
	func schools_near(_at:Vector2,_hours:float,_radius:float=200)->Array:
		if mode==1:return []
		var groups:Array=[{"id":"cod:review","species":"cod","position":Vector2.ZERO,"depth_m":76.0 if mode==0 else 14.0,"radius_m":15.0,"count":8,"total":8}]
		if mode==0:
			groups.append({"id":"saithe:review","species":"saithe","position":Vector2(210,0),"depth_m":47.0,"radius_m":17.0,"count":12,"total":12})
			groups.append({"id":"pollack:review","species":"pollack","position":Vector2(290,0),"depth_m":81.0,"radius_m":13.0,"count":4,"total":4})
			groups.append({"id":"cod:review2","species":"cod","position":Vector2(105,0),"depth_m":95.0,"radius_m":12.0,"count":5,"total":5})
		return groups
var ground:=Ground.new()
var display:SonarDisplay
var history:Array=[]
var elapsed:=0.0
var serial:=0
var enabled:=true
var at:=Vector2.ZERO

func _ready()->void:
	assert(ShipyardPlaytestMode.active())
	GameMenu.set_gameplay_hud_visible(false);GameMenu.hide_loading()
	var background:=ColorRect.new();background.color=Color("06101a");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(background)
	display=SonarDisplay.new();add_child(display)
	display.scale=Vector2.ONE*minf((get_viewport_rect().size.x-100)/SonarDisplay.WIDTH,(get_viewport_rect().size.y-100)/SonarDisplay.HEIGHT);display.position=(get_viewport_rect().size-Vector2(SonarDisplay.WIDTH,SonarDisplay.HEIGHT)*display.scale)*.5
	_fill()
	if OS.get_cmdline_user_args().has("--capture"):_review.call_deferred()

func _fill()->void:
	history.clear()
	for i in 91:
		at=Vector2((90-i)*(4.0 if ground.mode!=2 else 1.18),0)
		var ping:=ground.ping(at,0)
		serial+=1;ping["sequence"]=serial;history.append(ping)
	display.present({"history":history.duplicate(),"sounder":enabled,"ping_age_s":0})

func _process(dt:float)->void:
	if not enabled:return
	elapsed+=dt
	if elapsed>=.5:
		elapsed=fmod(elapsed,.5);at.x-=.25
		var ping:=ground.ping(at,0);serial+=1;ping["sequence"]=serial
		history.append(ping);if history.size()>91:history.pop_front()
		display.present({"history":history.duplicate(),"sounder":true,"ping_age_s":elapsed})

func _unhandled_key_input(event:InputEvent)->void:
	if event.is_pressed() and event is InputEventKey:
		if event.keycode in [KEY_LEFT,KEY_RIGHT]:ground.mode=wrapi(ground.mode+(1 if event.keycode==KEY_RIGHT else -1),0,3);_fill()
		if event.keycode==KEY_SPACE:
			enabled=not enabled;display.present({"history":history.duplicate(),"sounder":enabled,"ping_age_s":elapsed})

func _review()->void:
	set_process(false)
	for mode in 3:
		ground.mode=mode
		var start:=Time.get_ticks_usec();_fill()
		print("SONAR raster + 91 habitat pings ms: ",(Time.get_ticks_usec()-start)/1000.0)
		var bins:=display._signals(history[-1])
		if mode==1:
			for strength in bins:assert(strength==0,"Empty water must not draw invented targets")
		else:
			assert(not history[-1].echoes.is_empty())
			var depth:float=history[-1].echoes[0].depth_m
			assert(not ground.at_hook(Vector2(65,0),depth,0).is_empty(),"Displayed school depth must be fishable 65 m away")
			var strongest:=0.0
			for strength in bins: strongest=maxf(strongest,strength)
			assert(strongest>.1)
			for target:Dictionary in history[-1].targets:
				assert(not ground.at_hook(Vector2(65,0),target.range_m,0).is_empty(),"Current displayed echo range must be fishable from the deck")
		for i in 8:await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var dir:="C:/Users/noahs/Pictures/machinescreenshots";DirAccess.make_dir_recursive_absolute(dir)
		var path:=dir.path_join("sonar-%s-%d-%d.png"%[["deep","empty","shallow"][mode],Time.get_unix_time_from_system(),Time.get_ticks_usec()])
		get_viewport().get_texture().get_image().save_png(path);print("CAPTURE ",path)
	var began:=Time.get_ticks_usec()
	var latest:Dictionary=history[-1].duplicate(true);serial+=1;latest.sequence=serial
	history.append(latest);history.pop_front()
	display.present({"history":history.duplicate(),"sounder":true})
	print("SONAR incremental ping raster ms: ",(Time.get_ticks_usec()-began)/1000.0)
	var incremental:=display._raster.get_data()
	display._rendered_stamp=-100
	display._rebuild()
	assert(incremental==display._raster.get_data(),"Incremental scroll must exactly match a full history render")
	display._age=0;display._process(.1)
	assert(display._age>0 and display._age<.5,"Presentation must scroll between pings")
	display.present({"history":history.duplicate(),"sounder":false,"ping_age_s":.1})
	display._process(.1)
	assert(is_equal_approx(display._age,.1),"Stopped transmission must freeze history")
	display.present({"history":[],"sounder":true,"stream_id":1})
	assert(display._history.is_empty(),"Changing ships must clear the previous ship's sonar history")
	assert(display._raster.get_pixel(100,100).is_equal_approx(SonarDisplay.WATER),"New ship starts with unmeasured blue water")
	print("SONAR DISPLAY PASS: deep/shallow matching bait depths; empty water has no false targets")
	get_tree().quit()
