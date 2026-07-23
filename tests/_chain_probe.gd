extends SceneTree
func _initialize(): call_deferred("_run")
func _run():
    var def := PortDefinition.new()
    def.port_id = "chain"
    def.size = 6
    def.site_seed = 111111
    def.port_generation_version = PortDefinition.CURRENT_PORT_GENERATION_VERSION
    var g := PortExpander.expand(def, 424242).layout_graph
    for edge in g.edges:
        if str(edge.parent_slot_id) != "extend": continue
        var p := g.modules[str(edge.parent_instance_id)] as PortPlacedModule
        var c := g.modules[str(edge.child_instance_id)] as PortPlacedModule
        var pd := g.module_definition(p.module_id)
        var cd := g.module_definition(c.module_id)
        var out := pd.output_slot("extend")
        var inp := cd.input_for("quay_extension")
        var pp := p.position_m + Basis(Vector3.UP, deg_to_rad(p.yaw_degrees)) * (out.position_m as Vector3)
        var cp := c.position_m + Basis(Vector3.UP, deg_to_rad(c.yaw_degrees)) * (inp.position_m as Vector3)
        print("%s -> %s dist=%.4f" % [edge.parent_instance_id, edge.child_instance_id, pp.distance_to(cp)])
    quit(0)
