class_name FishingInstrument
extends Control

const INK := Color("e8ece7")
const MUTED := Color("a9bcb9")
const MINT := Color("9fe0c2")
const AMBER := Color("ffd38b")
var data: Dictionary = {}
var _status: Label
var _panel: StyleBoxFlat
var _track: StyleBoxFlat
var _smooth: Dictionary = {}
var _sonar: SonarDisplay

func _ready() -> void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_panel=VoyageStyle.box(Color(.035,.067,.077,.89),9)
	_panel.border_width_top=1
	_panel.border_color=Color(.55,.72,.69,.3)
	_track=VoyageStyle.box(Color("071b22"),4)
	_status=Label.new();_status.position=Vector2(16,215);_status.size=Vector2(328,95)
	_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size",16)
	_status.add_theme_color_override("font_color",INK)
	add_child(_status)
	_sonar=SonarDisplay.new();add_child(_sonar);_sonar.hide()

func present(value: Dictionary) -> void:
	if value.get("phase","")!=data.get("phase",""):_smooth.clear()
	data=value
	var sonar:=bool(data.get("sonar_view",false))
	var scale := SonarDisplay.scale_for(int(data.get("view", SonarDisplay.VIEW_FULL))) if sonar else 1.0
	_sonar.scale = Vector2(scale, scale)
	var box := SonarDisplay.layout_size(int(data.get("view", SonarDisplay.VIEW_FULL))) if sonar else Vector2(480, 152)
	_status.position=Vector2(8, box.y - 22) if sonar else Vector2(18,88)
	_status.size=Vector2(box.x - 16, 20) if sonar else Vector2(444,25)
	var message:=str(data.get("message",""))
	_sonar.visible=sonar
	if sonar:_sonar.present(data)
	_status.visible=sonar or (data.get("phase","")=="stowed" and not message.begins_with("Hold left") and not message.begins_with("Hold right") and not message.begins_with("Line recovered"))
	_status.text="N  size" if sonar else message
	_status.add_theme_font_size_override("font_size",15 if sonar else 14)
	_status.add_theme_constant_override("outline_size", 4 if sonar else 0)
	set_process(not sonar)
	queue_redraw()

func _process(delta: float) -> void:
	if not is_visible_in_tree():return
	# Interpolate only presentation. Gameplay still uses the exact physics values.
	for key in ["control","fish_position","progress","tension","charge"]:
		var target:=float(data.get(key,0))
		_smooth[key]=lerpf(float(_smooth.get(key,target)),target,1-exp(-delta*35))
	queue_redraw()

func _text(at: Vector2, text: String, font_size: int = 15, color: Color = INK) -> void:
	draw_string(ThemeDB.fallback_font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,color)

func _meter(rect: Rect2, amount: float, color: Color) -> void:
	draw_style_box(_track,rect)
	draw_rect(Rect2(rect.position,Vector2(rect.size.x*clampf(amount,0,1),rect.size.y)),color)

func _mouse(at: Vector2, right: bool, label: String, active: bool) -> void:
	var color:=MINT if active else MUTED
	draw_rect(Rect2(at,Vector2(16,22)),color,false,1.2)
	draw_line(at+Vector2(8,0),at+Vector2(8,10),color,1)
	draw_rect(Rect2(at+Vector2(8 if right else 1,1),Vector2(7,9)),MINT if active else Color("4c6868"))
	_text(at+Vector2(25,16),label,16,color)

func _draw_rod() -> void:
	var phase:=str(data.get("phase","stowed"))
	var action:=str(data.get("line_action","hold"))
	var harpe:=str(data.get("equipment",""))=="harpe"
	var occupied:=int(data.get("hook_count",0))
	draw_style_box(_panel,Rect2(0,0,480,152))
	if phase=="fighting":
		_text(Vector2(18,26),"FISH ON",17,MINT)
		_text(Vector2(120,26),"Keep the fish inside the white bar",16,MUTED)
		var bar:=Rect2(18,40,444,27)
		draw_style_box(_track,bar)
		var control:=float(_smooth.get("control",data.get("control",.5)))
		var width:=float(data.get("band_width",.28))
		var fish:=float(_smooth.get("fish_position",data.get("fish_position",.5)))
		var band:=Rect2(bar.position+Vector2((control-width*.5)*bar.size.x,0),Vector2(width*bar.size.x,27))
		draw_rect(band,Color(1,1,1,.20));draw_rect(band,Color.WHITE,false,2)
		var x:=bar.position.x+fish*bar.size.x
		draw_line(Vector2(x,36),Vector2(x,71),INK,2,true)
		draw_colored_polygon(PackedVector2Array([Vector2(x-5,33),Vector2(x+5,33),Vector2(x,39)]),INK)
		_text(Vector2(18,92),"HAUL",12,MUTED)
		_meter(Rect2(72,84,194,5),float(_smooth.get("progress",0)),MINT)
		_text(Vector2(292,92),"TENSION",12,MUTED)
		var stress:=float(_smooth.get("tension",.25))
		_meter(Rect2(359,84,103,5),stress,AMBER if stress>.7 else MUTED)
	elif phase=="landed":
		var caught:Dictionary=data.get("catch",{})
		var entry:=FishCatalog.species(str(caught.get("species_id","")))
		_text(Vector2(18,26),"CAUGHT",12,MINT)
		_text(Vector2(18,58),"%d fish landed"%occupied if harpe else str(entry.get("name","Fish")),25)
		_text(Vector2(18,87),("%.2f kg total"%float(data.get("total_catch_kg",0))) if harpe else "%.2f kg  /  %.1f cm"%[float(caught.get("mass_kg",0)),float(caught.get("length_cm",0))],17)
		_text(Vector2(300,58),PlayerData.format_money(int(data.get("total_catch_value",roundi(float(caught.get("mass_kg",0))*float(entry.get("marks_per_kg",0)))))),22,MINT)
		_text(Vector2(300,84),"Individual fish in crate" if harpe else str(entry.get("rarity","")),14,MUTED)
		_text(Vector2(18,128),"Crate full · Fish released" if "fish released" in str(data.get("message","")) else "Hold RMB to drop again  ·  F at mount to put gear away",14,MUTED)
		return
	elif phase=="bite":
		_text(Vector2(18,29),"BITE!",21,AMBER)
		_text(Vector2(18,64),"Left click to set the hook",25)
		_text(Vector2(18,90),"The fish has taken your bait",14,MUTED)
	elif phase in ["stowed","charging","casting"]:
		_text(Vector2(18,27),"LOWER YOUR TACKLE",14,MINT)
		_text(Vector2(18,59),"Stand at the rail",24)
		_text(Vector2(18,92),"Six light hooks · fish up to 5 kg" if harpe else "Heavy pilk · larger fish from 1.5 kg",14,MUTED)
		_text(Vector2(18,127),"Hold RMB · Lower     Hold LMB · Retrieve",15,MUTED)
		return
	else:
		var depth:=float(data.get("line_m",0))
		var bottom:=float(data.get("bottom_m",0))
		_text(Vector2(18,26),"HARPE · %d / 6 HOOKS"%occupied if harpe else "TACKLE DEPTH",13,MUTED)
		_text(Vector2(18,61),"%.1f m"%depth,30)
		_text(Vector2(250,27),"LETTING LINE OUT" if action=="pay" else ("REELING IN" if action=="reel" else "HOLDING LINE"),14,MINT)
		_text(Vector2(250,57),"Seabed  %.1f m"%bottom,17,MUTED)
		_meter(Rect2(18,79,444,5),depth/maxf(1,bottom),MINT)
		if depth>=bottom-1.1 and bottom>0:_text(Vector2(18,102),"Just above the seabed",12,AMBER)
	_mouse(Vector2(18,116),false,"LMB · Pull right" if phase=="fighting" else ("LMB · Haul %d fish"%occupied if harpe and occupied>0 else "Hold LMB · Reel in"),action=="reel")
	_mouse(Vector2(250,116),true,"RMB · Give left" if phase=="fighting" else "Hold RMB · Let out",action=="pay")

func _draw() -> void:
	if not data.get("sonar_view",false):_draw_rod()
