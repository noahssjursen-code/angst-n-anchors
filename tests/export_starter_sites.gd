extends Node
func _ready()->void:_run.call_deferred()
func _run()->void:
	var world_seed:=72482
	var output:="C:/Users/noahs/Documents/angst-n-anchors-mp/internal/authority/starter_sites.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):world_seed=int(arg.trim_prefix("--seed="))
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	var chart:=ChartDataSnapshot.for_preview(world_seed)
	var index:=CoastalPlotIndex.for_layout(chart.layout)
	var records:Dictionary={}
	var n:=0
	for id in index.plot_ids():
		var record:=StarterPortSites.fit(index.get_plot(id),chart)
		if not record.is_empty():records[id]=record
		n+=1
		if n%100==0:print("STARTER SURVEY ",n,"/",index.count()," accepted=",records.size());await get_tree().process_frame
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("Cannot write starter sites");get_tree().quit(1);return
	file.store_string(JSON.stringify({"world":CustomPortWorldImport.world_identity(chart.world_context()),"sites":records},"",true,true));file.close()
	print("STARTER CATALOG ",records.size()," ",output)
	get_tree().quit(0 if not records.is_empty() else 1)
