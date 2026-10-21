class_name Board3D
extends SubViewportContainer
## Tabellone in 3D: la mappa del lato scelto su un tavolo, le miniature delle nazioni (i modelli 3D
## di Stefano, ricolorati per nazione), Capitali, Fortezze, stendardi di controllo, regioni inattive e
## Regione Centrale. Telecamera orbitale (trascina col tasto sinistro per ruotare, destro per spostare,
## rotella per lo zoom). Clic su una regione per sceglierla.

signal region_clicked(r: int)
signal region_hovered(r: int)

const D = preload("res://scripts/data/ti_data.gd")
const W := 20.0                     # lato della mappa in unità 3D
const MAXR := 48

var eng: TIEngine
var vp: SubViewport
var cam: Camera3D
var pivot: Node3D
var yaw := 0.0
var pitch := -58.0
var dist := 21.0
var target := Vector3.ZERO
var map_mat: ShaderMaterial
var lab_img: Image
var pieces: Node3D
var region_nodes := {}             # r -> Node3D
var selectable: Array = []
var hover := -1
var drag_btn := -1
var drag_from := Vector2.ZERO
var drag_moved := false
var models := {}                    # nome -> Mesh
var mats := {}                      # chiave -> Material
var tints: PackedColorArray
var flags: PackedVector4Array
var battle_r := -1
var pulse := 0.0
var top_view := false


func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	vp = SubViewport.new()
	vp.msaa_3d = Viewport.MSAA_2X
	vp.own_world_3d = true
	vp.handle_input_locally = false
	vp.positional_shadow_atlas_size = 1024
	add_child(vp)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#0d0e11")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#8a8070")
	e.ambient_light_energy = 0.75
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.glow_enabled = false
	env.environment = e
	vp.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, 35, 0)
	sun.light_energy = 1.15
	sun.light_color = Color("#fff1d8")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 45.0
	vp.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-30, -140, 0)
	fill.light_energy = 0.35
	fill.light_color = Color("#9fb4d8")
	vp.add_child(fill)
	pivot = Node3D.new()
	vp.add_child(pivot)
	cam = Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.1
	cam.far = 200.0
	pivot.add_child(cam)
	_update_cam()
	_load_models()


func setup(p_eng: TIEngine) -> void:
	eng = p_eng
	var side: String = eng.side
	# tavolo
	var table := MeshInstance3D.new()
	var tm := PlaneMesh.new()
	tm.size = Vector2(W * 2.6, W * 2.0)
	table.mesh = tm
	table.position.y = -0.02
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color("#2b2119")
	tmat.roughness = 0.85
	table.material_override = tmat
	vp.add_child(table)
	# cornice
	var frame := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(W + 0.8, 0.12, W + 0.8)
	frame.mesh = fm
	frame.position.y = -0.07
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color("#16120e")
	fmat.roughness = 0.6
	frame.material_override = fmat
	vp.add_child(frame)
	# mappa
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(W, W)
	plane.mesh = pm
	map_mat = ShaderMaterial.new()
	map_mat.shader = _shader()
	map_mat.set_shader_parameter("albedo", load("res://assets/map/mappa_%s.jpg" % side))
	var lt: Texture2D = load("res://assets/map/regioni_%s.png" % side)
	map_mat.set_shader_parameter("labels", lt)
	map_mat.set_shader_parameter("mask", load("res://assets/map/maschera_%s.png" % side))
	lab_img = lt.get_image()
	if lab_img.is_compressed():
		lab_img.decompress()
	plane.material_override = map_mat
	vp.add_child(plane)
	pieces = Node3D.new()
	vp.add_child(pieces)
	tints = PackedColorArray()
	tints.resize(MAXR)
	flags = PackedVector4Array()
	flags.resize(MAXR)
	refresh()


func _shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D albedo : source_color, filter_linear_mipmap;
uniform sampler2D labels : filter_nearest;
uniform sampler2D mask : filter_linear;
uniform vec4 tint[48];
uniform vec4 flags[48];
uniform float time = 0.0;
uniform float sel_on = 0.0;
void fragment() {
	vec3 c = texture(albedo, UV).rgb;
	float m = texture(mask, UV).r;
	int id = int(texture(labels, UV).r * 255.0 + 0.5);
	vec4 f = flags[id];
	vec4 t = tint[id];
	if (id > 0) {
		c = mix(c, t.rgb, t.a);
		if (f.x > 0.5) {
			float g = dot(c, vec3(0.3, 0.59, 0.11));
			c = mix(c, vec3(g) * 0.42, 0.85);
		}
		if (f.y > 0.5) {
			float p = 0.5 + 0.5 * sin(time * 4.0);
			c = mix(c, vec3(1.0, 0.86, 0.45), 0.22 + 0.18 * p) * 1.12;
		} else if (sel_on > 0.5) {
			c *= 0.5;
		}
		if (f.z > 0.5) {
			c = c * 1.22 + vec3(0.04);
		}
		if (f.w > 0.5) {
			float p2 = 0.5 + 0.5 * sin(time * 6.0);
			c = mix(c, vec3(0.9, 0.15, 0.1), 0.22 + 0.15 * p2);
		}
	}
	ALBEDO = mix(vec3(0.05, 0.045, 0.04), c, m);
}
"""
	return sh


# ---------------------------------------------------------------- modelli

func _load_models() -> void:
	var files := {"F": "fanteria", "K": "cavalleria", "A": "artiglieria", "C": "capitale",
		"T_pol": "titano_pol", "T_rus": "titano_rus", "T_sve": "titano_sve", "T_ott": "titano_ott"}
	for k in files:
		var ps: PackedScene = load("res://assets/modelli/%s.glb" % files[k])
		if ps == null:
			continue
		var inst := ps.instantiate()
		var mi := _find_mesh(inst)
		if mi != null:
			models[k] = {"mesh": mi.mesh, "xf": _mesh_xform(mi)}
		inst.free()


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _mesh_xform(mi: MeshInstance3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var p: Node = mi
	while p != null and p is Node3D:
		t = (p as Node3D).transform * t
		p = p.get_parent()
	return t


## Materiale della nazione (le miniature sono bianche: le si colora).
func _mat(key: String, col: Color, rough := 0.55, metal := 0.15) -> Material:
	if not mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		m.rim_enabled = true
		m.rim = 0.25
		mats[key] = m
	return mats[key]


func _model(kind: String, nat: String, height: float) -> Node3D:
	var key := kind if kind != "T" else "T_" + nat
	var holder := Node3D.new()
	if not models.has(key):
		var cyl := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.16
		cm.height = height
		cyl.mesh = cm
		cyl.position.y = height * 0.5
		cyl.material_override = _mat(nat, UI.ncol(nat))
		holder.add_child(cyl)
		return holder
	var md: Dictionary = models[key]
	var mesh: Mesh = md["mesh"]
	var aabb: AABB = md["xf"] * mesh.get_aabb()
	var sc := height / maxf(0.001, aabb.size.y)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var xf: Transform3D = md["xf"]
	xf = Transform3D(Basis.IDENTITY.scaled(Vector3(sc, sc, sc)), Vector3.ZERO) * xf
	var a2: AABB = xf * mesh.get_aabb()
	xf.origin -= Vector3(a2.get_center().x, a2.position.y, a2.get_center().z)
	mi.transform = xf
	var col := UI.ncol(nat) if nat != "" else Color("#8c8a84")
	mi.material_override = _mat(nat + kind, col.lightened(0.08), 0.5, 0.2 if kind != "C" else 0.05)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	holder.add_child(mi)
	return holder


func _fortress() -> Node3D:
	var n := Node3D.new()
	var stone := _mat("stone", Color("#8f8b82"), 0.9, 0.0)
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.radial_segments = 5
	bm.top_radius = 0.34
	bm.bottom_radius = 0.38
	bm.height = 0.16
	base.mesh = bm
	base.position.y = 0.08
	base.material_override = stone
	n.add_child(base)
	for i in 5:
		var a := TAU * i / 5.0
		var t := MeshInstance3D.new()
		var tmh := CylinderMesh.new()
		tmh.top_radius = 0.08
		tmh.bottom_radius = 0.09
		tmh.height = 0.34
		tmh.radial_segments = 8
		t.mesh = tmh
		t.position = Vector3(cos(a) * 0.32, 0.17, sin(a) * 0.32)
		t.material_override = stone
		n.add_child(t)
	return n


func _flat_sprite(path: String, size: float) -> Sprite3D:
	var s := Sprite3D.new()
	s.texture = load(path)
	s.pixel_size = size / maxf(1.0, float(s.texture.get_width()))
	s.rotation_degrees.x = -90
	s.position.y = 0.02
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	return s


func _count_label(k: int, col: Color) -> Label3D:
	var l := Label3D.new()
	l.text = "×%d" % k
	l.font = UI.font_head_b
	l.font_size = 64
	l.pixel_size = 0.0045
	l.outline_size = 14
	l.modulate = Color.WHITE
	l.outline_modulate = col.darkened(0.6)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = Vector3(0.22, 0.8, 0)
	return l


# ---------------------------------------------------------------- stato

func rpos(r: int) -> Vector3:
	var g: Dictionary = eng.regions[r]
	return Vector3((float(g["x"]) - 0.5) * W, 0.0, (float(g["y"]) - 0.5) * W)


func refresh() -> void:
	if eng == null:
		return
	for c in pieces.get_children():
		c.queue_free()
	for r in eng.regions:
		_build_region(r)
	# battaglie in sospeso: unità sul confine
	for b in eng.battles:
		_build_border(b["att"], b["r"], b["u"])
	if not eng.battle.is_empty() and not eng.battle.has("outcome"):
		_build_border(eng.battle["att"], eng.battle["r"], eng.battle["u_att"])
	_update_flags()


func _build_region(r: int) -> void:
	var g: Dictionary = eng.reg[r]
	var base := rpos(r)
	var root := Node3D.new()
	root.position = base
	pieces.add_child(root)
	if eng.inactive.has(r):
		var x := _flat_sprite("res://assets/segni/inattiva.png", 0.85)
		root.add_child(x)
		return
	var slots := _slots(r)
	var si := 0
	if r == eng.central:
		var st := _flat_sprite("res://assets/segni/centrale.png", 0.62)
		st.position = Vector3(0.0, 0.02, 0.0) + slots[slots.size() - 1]
		root.add_child(st)
	if g["cap"] >= 0 and (eng.capital_alive[g["cap"]] or g["capctrl"] >= 0):
		var cn: String = eng.nat(g["cap"])
		var cap := _model("C", cn, 0.85)
		cap.position = slots[si]
		cap.rotation_degrees.y = 20
		root.add_child(cap)
		si += 1
		if g["capctrl"] >= 0:
			var bn := _banner(eng.nat(g["capctrl"]))
			bn.position = slots[si - 1] + Vector3(0.3, 0, 0.1)
			root.add_child(bn)
	if g["fort"]:
		var f := _fortress()
		f.position = slots[si]
		root.add_child(f)
		si += 1
	var own: int = g["own"]
	if own >= 0 and eng.units_total(r) > 0:
		var nat: String = eng.nat(own)
		for t in ["T", "A", "K", "F"]:
			var k: int = g["n"][t]
			if k <= 0:
				continue
			var h: float = {"T": 1.55, "A": 0.62, "K": 0.85, "F": 0.78}[t]
			var m := _model(t, nat, h)
			m.position = slots[si % slots.size()]
			m.rotation_degrees.y = 200 + si * 23
			root.add_child(m)
			if k > 1:
				var lb := _count_label(k, UI.ncol(nat))
				lb.position.y = h + 0.12
				m.add_child(lb)
			si += 1
	elif g["tok"] >= 0:
		var bn := _banner(eng.nat(g["tok"]))
		bn.position = slots[si % slots.size()]
		root.add_child(bn)
	region_nodes[r] = root


func _banner(nat: String) -> Node3D:
	var n := Node3D.new()
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.015
	pm.bottom_radius = 0.02
	pm.height = 0.75
	pole.mesh = pm
	pole.position.y = 0.375
	pole.material_override = _mat("pole", Color("#3a2a1a"), 0.8, 0.0)
	n.add_child(pole)
	var s := Sprite3D.new()
	s.texture = UI.banner(nat)
	s.pixel_size = 0.3 / float(s.texture.get_width())
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.position = Vector3(0.15, 0.55, 0)
	s.shaded = false
	n.add_child(s)
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.14
	dm.bottom_radius = 0.15
	dm.height = 0.04
	disc.mesh = dm
	disc.position.y = 0.02
	disc.material_override = _mat(nat, UI.ncol(nat))
	n.add_child(disc)
	return n


## Posti per le miniature attorno al centro della regione.
func _slots(r: int) -> Array:
	var rad: float = float(eng.regions[r]["rad"]) * W
	var step := clampf(rad * 0.7, 0.42, 0.62)
	var out := [Vector3.ZERO]
	for i in 6:
		var a := TAU * i / 6.0 + 0.4
		out.append(Vector3(cos(a), 0, sin(a)) * step)
	for i in 6:
		var a := TAU * i / 6.0 + 0.92
		out.append(Vector3(cos(a), 0, sin(a)) * step * 1.75)
	return out


func _build_border(att: int, r: int, units: Array) -> void:
	if units.is_empty():
		return
	var nat: String = eng.nat(att)
	var groups := {}
	for u in units:
		var key := "%d" % int(u["from"])
		if not groups.has(key):
			groups[key] = {}
		groups[key][u["t"]] = groups[key].get(u["t"], 0) + 1
	for key in groups:
		var src := int(key)
		var a := rpos(src)
		var b := rpos(r)
		var p := a.lerp(b, 0.62)
		var dir := (b - a).normalized()
		var side := Vector3(-dir.z, 0, dir.x)
		var i := 0
		for t in ["T", "A", "K", "F"]:
			var k: int = groups[key].get(t, 0)
			if k <= 0:
				continue
			var h: float = {"T": 1.55, "A": 0.62, "K": 0.85, "F": 0.78}[t]
			var m := _model(t, nat, h)
			m.position = p + side * (float(i) - 0.5) * 0.42
			m.look_at_from_position(m.position, m.position + dir * 3.0, Vector3.UP)
			pieces.add_child(m)
			if k > 1:
				var lb := _count_label(k, UI.ncol(nat))
				lb.position.y = h + 0.12
				m.add_child(lb)
			i += 1
	var sw := Label3D.new()
	sw.text = "⚔"
	sw.font_size = 120
	sw.pixel_size = 0.006
	sw.outline_size = 18
	sw.modulate = Color("#ffd27a")
	sw.outline_modulate = Color(0, 0, 0)
	sw.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sw.no_depth_test = true
	sw.position = rpos(r) + Vector3(0, 1.5, 0)
	pieces.add_child(sw)


func _update_flags() -> void:
	for i in MAXR:
		tints[i] = Color(0, 0, 0, 0)
		flags[i] = Vector4.ZERO
	for r in eng.regions:
		if r >= MAXR:
			continue
		var o: int = eng.owner(r)
		if o >= 0 and not eng.inactive.has(r):
			var c := UI.ncol(eng.nat(o))
			tints[r] = Color(c.r, c.g, c.b, 0.2)
		flags[r] = Vector4(1.0 if eng.inactive.has(r) else 0.0, 1.0 if r in selectable else 0.0, 1.0 if r == hover else 0.0, 1.0 if r == battle_r else 0.0)
	map_mat.set_shader_parameter("sel_on", 1.0 if not selectable.is_empty() else 0.0)
	map_mat.set_shader_parameter("tint", tints)
	map_mat.set_shader_parameter("flags", flags)


func set_selectable(rs: Array) -> void:
	selectable = rs.duplicate()
	if eng != null:
		_update_flags()


func set_battle(r: int) -> void:
	battle_r = r
	if eng != null:
		_update_flags()


# ---------------------------------------------------------------- telecamera e input

func _process(delta: float) -> void:
	pulse += delta
	if map_mat != null:
		map_mat.set_shader_parameter("time", pulse)


func _update_cam() -> void:
	pivot.position = target
	pivot.rotation_degrees = Vector3(pitch, yaw, 0)
	cam.position = Vector3(0, 0, dist)
	cam.rotation = Vector3.ZERO


func reset_view(top := false) -> void:
	top_view = top
	yaw = 0.0
	pitch = -89.0 if top else -60.0
	dist = 24.5 if top else 24.0
	target = Vector3(0.9, 0, 2.3) if not top else Vector3(0.9, 0, 1.6)
	_update_cam()


func focus_region(r: int) -> void:
	if eng == null or r < 0:
		return
	var tw := create_tween()
	var dest := rpos(r)
	tw.tween_method(func(v: Vector3):
		target = v
		_update_cam(), target, dest.lerp(Vector3(0.9, 0, 2.3), 0.45), 0.5).set_trans(Tween.TRANS_SINE)


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			dist = clampf(dist * (0.9 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.11), 6.0, 34.0)
			_update_cam()
			accept_event()
			return
		if mb.pressed and (mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE):
			drag_btn = mb.button_index
			drag_from = mb.position
			drag_moved = false
		elif not mb.pressed and mb.button_index == drag_btn:
			if not drag_moved and drag_btn == MOUSE_BUTTON_LEFT:
				var r := _pick(mb.position)
				if r > 0:
					region_clicked.emit(r)
			drag_btn = -1
		accept_event()
	elif ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		if drag_btn >= 0:
			if mm.position.distance_to(drag_from) > 6.0:
				drag_moved = true
			if drag_moved:
				if drag_btn == MOUSE_BUTTON_LEFT:
					yaw -= mm.relative.x * 0.25
					pitch = clampf(pitch - mm.relative.y * 0.2, -89.0, -18.0)
				else:
					var right := cam.global_transform.basis.x
					var fwd := Vector3(-sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
					var k := dist * 0.0018
					target += (-right * mm.relative.x + fwd * mm.relative.y) * k
					target.x = clampf(target.x, -W * 0.6, W * 0.6)
					target.z = clampf(target.z, -W * 0.6, W * 0.6)
				_update_cam()
		var r := _pick(mm.position)
		if r != hover:
			hover = r
			region_hovered.emit(r)
			if eng != null:
				_update_flags()
	elif ev is InputEventMagnifyGesture:
		dist = clampf(dist / (ev as InputEventMagnifyGesture).factor, 6.0, 34.0)
		_update_cam()
	elif ev is InputEventPanGesture:
		var pg := ev as InputEventPanGesture
		yaw -= pg.delta.x * 2.0
		pitch = clampf(pitch - pg.delta.y * 2.0, -89.0, -18.0)
		_update_cam()


## Regione sotto il cursore (0 = nessuna).
func _pick(p: Vector2) -> int:
	if eng == null or lab_img == null:
		return 0
	var sp := p * (Vector2(vp.size) / size)
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return 0
	var t := -o.y / d.y
	if t < 0:
		return 0
	var hit := o + d * t
	var u := hit.x / W + 0.5
	var v := hit.z / W + 0.5
	if u < 0 or u >= 1 or v < 0 or v >= 1:
		return 0
	var px := int(u * lab_img.get_width())
	var py := int(v * lab_img.get_height())
	var c := lab_img.get_pixel(px, py)
	return int(round(c.r * 255.0))


## Posizione sullo schermo (coordinate del contenitore) di una regione, per etichette 2D.
func screen_pos(r: int) -> Vector2:
	var p := cam.unproject_position(rpos(r))
	return p * (size / Vector2(vp.size))
