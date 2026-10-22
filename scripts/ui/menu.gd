extends Control
## Menu principale: numero di giocatori, scenario del regolamento, chi guida ogni nazione (Umano o IA),
## opzioni (Modalità Avanzata, Presa della Capitale, Partita estesa) e gioco online.

const D = preload("res://scripts/data/ti_data.gd")
const MODES := ["Umano", "IA facile", "IA normale", "IA difficile"]

var main
var page: Control
var nplayers := 2
var scen_id := "2-1A"
var modes := {}                 # nazione -> 0..3
var names := {}                 # nazione -> nome
var speed := 1
var advanced := false
var capital_capture := false
var extended := false
var solo_me := ""               # Solitario: la nazione del giocatore (l'altra è l'Automa)
var automa_lvl := 0             # 0 Base, 1 Avanzato
var automa_row: Control
var opt_rows: Array = []
var xp := {"monuments": false, "emissaries": false, "fire": false, "echoes": false, "fields": false, "spirit": false}     # espansioni Kickstarter
var msg: Label
var scen_box: VBoxContainer
var seats_box: VBoxContainer
var seats_scroll: ScrollContainer
var info_lbl: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var st: Dictionary = main.menu_state
	if not st.is_empty():
		nplayers = st["n"]
		scen_id = st["scen"]
		modes = st["modes"].duplicate()
		names = st["names"].duplicate()
		speed = st["speed"]
		advanced = st["adv"]
		capital_capture = st["cap"]
		extended = st["ext"]
		solo_me = st.get("solo_me", "")
		automa_lvl = st.get("alvl", 0)
		var sx: Dictionary = st.get("xp", {})
		for k in sx:
			xp[k] = sx[k]
	for nt in D.NATION_ORDER:
		if not modes.has(nt):
			modes[nt] = 2
		if not names.has(nt):
			names[nt] = D.NATIONS[nt]["short"]
	if modes.values().count(0) == 0:
		modes["pol"] = 0
	var bg := TextureRect.new()
	bg.texture = UI.tex("res://assets/sfondo.jpg")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.modulate = Color(0.62, 0.58, 0.55)
	add_child(bg)
	var shade := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.03, 0.04, 0.25))
	g.set_color(1, Color(0.03, 0.03, 0.04, 0.95))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 0.6)
	shade.texture = grad
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	page = Control.new()
	page.size = Vector2(1920, 1080)
	add_child(page)
	_center.call_deferred()
	get_viewport().size_changed.connect(_center)

	var logo := UI.title("TITANS", 140, UI.GOLD)
	logo.add_theme_constant_override("outline_size", 14)
	logo.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.02, 0.95))
	logo.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	logo.add_theme_constant_override("shadow_offset_x", 5)
	logo.add_theme_constant_override("shadow_offset_y", 7)
	logo.position = Vector2(0, 6)
	logo.size = Vector2(1920, 170)
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(logo)
	var tag := UI.label("Eserciti e Titani si contendono l'Europa · alba del XVII secolo · da 2 a 5 Nazioni", 28, Color("#e8d6ae"), UI.font_italic)
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("outline_size", 6)
	tag.position = Vector2(0, 168)
	tag.size = Vector2(1920, 40)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page.add_child(tag)

	# colonna sinistra: giocatori e scenario
	var left := PanelContainer.new()
	left.add_theme_stylebox_override("panel", UI.iron_style(10, 0.88))
	left.position = Vector2(60, 230)
	left.custom_minimum_size = Vector2(760, 650)
	page.add_child(left)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 10)
	left.add_child(lv)
	lv.add_child(UI.heading("Giocatori e scenario", 30))
	lv.add_child(_segmented("Nazioni", ["2", "3", "4", "5", "Solo"], 4 if nplayers == 1 else nplayers - 2, func(k):
		nplayers = 1 if k == 4 else k + 2
		var l := _scen_list()
		scen_id = l[0]["id"]
		msg.text = ""
		_refresh_scen()
		_refresh_seats(), 100))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(730, 470)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	scen_box = VBoxContainer.new()
	scen_box.add_theme_constant_override("separation", 6)
	scen_box.custom_minimum_size.x = 716
	sc.add_child(scen_box)
	info_lbl = UI.label("", 18, UI.MUTED)
	lv.add_child(UI.wrap(info_lbl, 720))

	# colonna destra: nazioni e opzioni
	var right := PanelContainer.new()
	right.add_theme_stylebox_override("panel", UI.iron_style(10, 0.88))
	right.position = Vector2(850, 230)
	right.custom_minimum_size = Vector2(1000, 650)
	page.add_child(right)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 10)
	right.add_child(rv)
	rv.add_child(UI.heading("Chi guida le Nazioni", 30))
	seats_scroll = ScrollContainer.new()
	seats_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(seats_scroll)
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 6)
	seats_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	seats_scroll.add_child(seats_box)
	rv.add_child(HSeparator.new())
	rv.add_child(UI.heading("Opzioni", 26))
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 14)
	var ol := UI.label("Varianti", 22, Color.WHITE, UI.font_head_b)
	ol.custom_minimum_size.x = 170
	orow.add_child(ol)
	for kv in [["Modalità Avanzata", "Mazzo Ordini Avanzati, Energia e abilità avanzate del Titano", advanced, func(v): advanced = v],
			["Presa della Capitale", "Le Capitali si conquistano invece di essere distrutte: 2 PV a fine partita per ogni Capitale controllata", capital_capture, func(v): capital_capture = v],
			["Partita estesa", "4 Round invece di 3 (sconto 1 nel 3° Round, 2 nel 4°)", extended, func(v): extended = v]]:
		var cb := CheckBox.new()
		cb.text = kv[0]
		cb.tooltip_text = kv[1]
		cb.button_pressed = kv[2]
		var f: Callable = kv[3]
		cb.toggled.connect(func(v): f.call(v))
		orow.add_child(cb)
	opt_rows.append(orow)
	rv.add_child(opt_rows[-1])
	var xrow := HFlowContainer.new()
	xrow.custom_minimum_size.x = 980
	xrow.add_theme_constant_override("h_separation", 8)
	xrow.add_theme_constant_override("v_separation", 4)
	var xl := UI.label("Espansioni", 22, Color.WHITE, UI.font_head_b)
	xl.custom_minimum_size.x = 170
	xrow.add_child(xl)
	for kv in [["monuments", "Monumenti", "Ogni Nazione ha 3 Monumenti da costruire con le Carte Supporto"], ["emissaries", "Emissari", "3 Obiettivi Nazione segreti: il primo dà un Emissario che accompagna un'Armata, poi 3 e 5 PV"], ["fire", "Pioggia di Fuoco", "Un'Artiglieria di Fuoco per Nazione: conta come Artiglieria e tira anche 1 Dado Fanteria"], ["echoes", "Echi del Passato", "Unità Cadute che seguono le Armate e tirano i loro dadi in Battaglia; ognuno ha una carta con un'abilità negativa"], ["fields", "Campi di Sangue", "Cosacchi e il mazzo Supporto di Campi di Sangue, con Potenziamenti e Schieramenti dei Cosacchi"], ["spirit", "Spirito di Guerra", "Il mazzo Supporto di Spirito di Guerra con i suoi Dadi (con Campi di Sangue i due mazzi si mescolano e le carte scoperte sono 6)"]]:
		var cb := CheckBox.new()
		cb.text = kv[1]
		cb.tooltip_text = kv[2]
		cb.button_pressed = xp[kv[0]]
		var key: String = kv[0]
		cb.toggled.connect(func(v): xp[key] = v)
		xrow.add_child(cb)
	opt_rows.append(xrow)
	rv.add_child(xrow)
	automa_row = _segmented("Automa", ["Base", "Avanzato"], automa_lvl, func(k): automa_lvl = k, 170)
	automa_row.tooltip_text = "Livello Avanzato: l'Automa esegue anche le azioni con la stella delle sue carte"
	rv.add_child(automa_row)
	rv.add_child(_segmented("Velocità IA", ["Lenta", "Normale", "Veloce", "Istantanea"], speed, func(k): speed = k, 170))

	msg = UI.label("", 24, UI.BLOOD_L, UI.font_head_b)
	msg.position = Vector2(60, 1000)
	page.add_child(msg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	btns.position = Vector2(60, 905)
	page.add_child(btns)
	var b_start := _big_button("Inizia la guerra", 470, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_rules := _big_button("Regole", 250)
	b_rules.pressed.connect(func():
		_store()
		main.show_rules())
	btns.add_child(b_rules)
	if not OS.has_feature("web"):
		var b_quit := _big_button("Esci", 200)
		b_quit.pressed.connect(func(): get_tree().quit())
		btns.add_child(b_quit)
	var b_online := _big_button("Gioca online", 420)
	b_online.position = Vector2(1440, 905)
	b_online.pressed.connect(_online_panel)
	page.add_child(b_online)
	var credits := UI.label("Adattamento digitale non ufficiale per uso personale · Titans di Łukasz Woźniak · illustrazioni di Piotr Krężelewski · © Go On Board · F11 schermo intero", 17, Color("#8f8778"))
	credits.position = Vector2(60, 1046)
	page.add_child(credits)
	_refresh_scen()
	_refresh_seats()
	if not main.lobby.is_empty():
		_online_panel.call_deferred()


func _center() -> void:
	var vs := get_viewport_rect().size
	page.position = ((vs - page.size) * 0.5).floor()
	page.position.y = maxf(0.0, page.position.y)


func _store() -> void:
	main.menu_state = {"n": nplayers, "scen": scen_id, "modes": modes.duplicate(), "names": names.duplicate(), "speed": speed, "adv": advanced, "cap": capital_capture, "ext": extended, "solo_me": solo_me, "alvl": automa_lvl, "xp": xp.duplicate()}


func _scen_nations() -> Array:
	var sc := D.scenario(scen_id)
	var out := []
	for c in sc["nations"]:
		out.append(D.CODE_TO_NATION[c])
	return out


func _scen_list() -> Array:
	return D.solo_scenarios() if nplayers == 1 else D.scenarios_for(nplayers)


func _refresh_scen() -> void:
	for c in scen_box.get_children():
		c.queue_free()
	for s in _scen_list():
		var sid: String = s["id"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(700, 58)
		b.clip_text = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var nn := []
		for c in s["nations"]:
			nn.append(D.NATIONS[D.CODE_TO_NATION[c]]["short"])
		b.text = "  %s   %s · lato %s · %d regioni inattive%s" % [sid, " · ".join(nn), s["side"], (s["inactive"] as Array).size(), "  · 5ª Nazione" if s.has("expansion") else ""]
		b.add_theme_font_size_override("font_size", 20)
		var on: bool = sid == scen_id
		b.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD_D if on else Color("#1d1f24"), UI.GOLD_L if on else Color("#3a3833"), 2, 5))
		b.add_theme_color_override("font_color", Color.WHITE if on else UI.TEXT)
		b.pressed.connect(func():
			scen_id = sid
			_refresh_scen()
			_refresh_seats())
		scen_box.add_child(b)
	var sc := D.scenario(scen_id)
	if nplayers == 1:
		info_lbl.text = "Modalità Solitario contro l'Automa (Compendio delle Nazioni): 6 scenari sul lato A. Regione Centrale: %s." % D.map_data(sc["side"])["regioni"][int(sc["central"]) - 1]["nome"]
		return
	info_lbl.text = "Scenari del regolamento (pagine 19–24). Lato %s del tabellone: %s. Regione Centrale: %s." % [sc["side"], "mappa più piccola" if sc["side"] == "A" else "mappa più ampia", D.map_data(sc["side"])["regioni"][int(sc["central"]) - 1]["nome"]]


func _refresh_seats() -> void:
	for c in seats_box.get_children():
		c.queue_free()
	if automa_row != null:
		automa_row.visible = nplayers == 1
	for r in opt_rows:
		r.visible = nplayers != 1
	if nplayers == 1 and not solo_me in _scen_nations():
		solo_me = _scen_nations()[0]
	seats_scroll.custom_minimum_size = Vector2(980, mini(_scen_nations().size() * 80, 326))
	for nt in _scen_nations():
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UI.panel_style(Color(UI.ndark(nt), 0.9), UI.ncol(nt), 2, 8))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)
		hb.add_child(UI.icon_rect(UI.banner(nt), Vector2(28, 56)))
		var vb := VBoxContainer.new()
		vb.custom_minimum_size.x = 300
		var nl := UI.label(D.NATIONS[nt]["name"], 19, Color.WHITE, UI.font_head_b)
		vb.add_child(nl)
		var le := LineEdit.new()
		le.text = names[nt]
		le.max_length = 20
		le.custom_minimum_size = Vector2(280, 32)
		le.add_theme_font_size_override("font_size", 17)
		var ntt: String = nt
		le.text_changed.connect(func(t): names[ntt] = t)
		vb.add_child(le)
		hb.add_child(vb)
		var bar := HBoxContainer.new()
		bar.add_theme_constant_override("separation", 4)
		hb.add_child(bar)
		if nplayers == 1:
			for k in 2:
				var b := Button.new()
				b.text = ["Tu", "Automa"][k]
				b.custom_minimum_size = Vector2(200, 44)
				b.add_theme_font_size_override("font_size", 20)
				var on: bool = (solo_me == nt) == (k == 0)
				b.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#1d1f24"), UI.GOLD if on else Color("#3a3833"), 2, 4))
				b.add_theme_color_override("font_color", UI.IRON if on else UI.TEXT)
				b.add_theme_color_override("font_hover_color", UI.IRON if on else UI.GOLD)
				var kk := k
				b.pressed.connect(func():
					var ns := _scen_nations()
					solo_me = ntt if kk == 0 else ns[1 - ns.find(ntt)]
					_refresh_seats())
				bar.add_child(b)
			row.tooltip_text = "Abilità della Nazione: %s\nAbilità del Titano: %s" % [D.NATIONS[nt]["nation_ab"], D.NATIONS[nt]["titan_ab"]]
			seats_box.add_child(row)
			continue
		for k in MODES.size():
			var b := Button.new()
			b.text = MODES[k]
			b.custom_minimum_size = Vector2(132, 44)
			b.add_theme_font_size_override("font_size", 18)
			var on: bool = modes[nt] == k
			b.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#1d1f24"), UI.GOLD if on else Color("#3a3833"), 2, 4))
			b.add_theme_color_override("font_color", UI.IRON if on else UI.TEXT)
			b.add_theme_color_override("font_hover_color", UI.IRON if on else UI.GOLD)
			var kk := k
			b.pressed.connect(func():
				modes[ntt] = kk
				msg.text = ""
				_refresh_seats())
			bar.add_child(b)
		row.tooltip_text = "Abilità della Nazione: %s\nAbilità del Titano: %s" % [D.NATIONS[nt]["nation_ab"], D.NATIONS[nt]["titan_ab"]]
		seats_box.add_child(row)


func _toggle(title: String, desc: String, cur: bool, cb: Callable) -> Control:
	var hb := HBoxContainer.new()
	var cbx := CheckBox.new()
	cbx.text = title
	cbx.button_pressed = cur
	cbx.custom_minimum_size.x = 300
	cbx.toggled.connect(func(v): cb.call(v))
	hb.add_child(cbx)
	hb.add_child(UI.wrap(UI.label(desc, 17, UI.MUTED), 660))
	return hb


func _segmented(label_text: String, items: Array, cur: int, cb: Callable, w := 200) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var l := UI.label(label_text, 24, Color.WHITE, UI.font_head_b)
	l.custom_minimum_size = Vector2(180, 0)
	hb.add_child(l)
	var btns := []
	for k in range(items.size()):
		var b := Button.new()
		b.text = items[k]
		b.custom_minimum_size = Vector2(w, 46)
		b.add_theme_font_size_override("font_size", 20)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			var on: bool = k == sel
			btns[k].add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD if on else Color("#1d1f24"), UI.GOLD if on else Color("#3a3833"), 2, 4))
			btns[k].add_theme_color_override("font_color", UI.IRON if on else UI.TEXT)
			btns[k].add_theme_color_override("font_hover_color", UI.IRON if on else UI.GOLD)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			cb.call(k)
			paint.call(k))
	paint.call(cur)
	return hb


func _big_button(text: String, w: float, primary := false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 80)
	b.add_theme_font_override("font", UI.font_title)
	b.add_theme_font_size_override("font_size", 34)
	if primary:
		UI.primary(b)
	return b


## Configurazione scelta nel menu (anche quella che, online, viaggia agli altri).
func _config() -> Dictionary:
	var seats := []
	for nt in _scen_nations():
		var m: int = modes[nt]
		var nm: String = names[nt].strip_edges()
		if nm == "":
			nm = D.NATIONS[nt]["short"]
		if nplayers == 1:
			var me: bool = nt == solo_me
			seats.append({"nat": nt, "ai": not me, "automa": not me, "name": nm if me else "Automa", "level": 1})
		else:
			seats.append({"nat": nt, "ai": m != 0, "name": nm, "level": maxi(0, m - 1)})
	var speeds := [1.0, 0.5, 0.15, 0.0]
	if nplayers == 1:
		return {"seats": seats, "scenario": scen_id, "ai_delay": speeds[speed], "solo": true, "automa_adv": automa_lvl == 1, "advanced": false, "capital_capture": false, "extended": false}
	return {"seats": seats, "scenario": scen_id, "ai_delay": speeds[speed], "advanced": advanced, "capital_capture": capital_capture, "extended": extended,
		"monuments": xp["monuments"], "emissaries": xp["emissaries"], "fire": xp["fire"], "echoes": xp["echoes"], "fields": xp["fields"], "spirit": xp["spirit"]}


func _on_start() -> void:
	_store()
	main.start_game(_config())


# =================================================================== online

var on_panel: Control
var on_name: LineEdit
var on_code: LineEdit
var on_lbl: Label
var on_start: Button


func _online_panel() -> void:
	if nplayers == 1:
		msg.text = "La Modalità Solitario non si gioca online: scegli da 2 a 5 Nazioni."
		return
	if is_instance_valid(on_panel):
		on_panel.queue_free()
	on_panel = Control.new()
	on_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(on_panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.78)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	on_panel.add_child(shade)
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UI.iron_style(10, 0.97))
	box.position = page.position + Vector2(560, 130)
	box.custom_minimum_size = Vector2(800, 0)
	on_panel.add_child(box)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	box.add_child(vb)
	vb.add_child(UI.title("Gioca online", 50))
	var info := UI.label("Chi crea la stanza sceglie prima nel menu lo scenario e le opzioni: le nazioni su UMANO diventano i posti per gli amici (la prima è la sua). Gli amici entrano con il codice. I posti rimasti liberi li gioca l'IA.", 21, Color("#cccccc"))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 0)
	vb.add_child(info)
	var ses: Dictionary = main.get_net().load_session()
	on_name = _line("Il tuo nome", 20)
	on_name.text = str(ses.get("name", ""))
	vb.add_child(on_name)
	var b_create := UI.button("Crea una stanza", 0, 60, 26)
	b_create.pressed.connect(_online_create)
	vb.add_child(b_create)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	on_code = _line("Codice", 4)
	on_code.custom_minimum_size.x = 220
	on_code.text_changed.connect(func(t):
		on_code.text = t.to_upper()
		on_code.caret_column = t.length())
	row.add_child(on_code)
	var b_join := UI.button("Entra", 200, 60, 26)
	b_join.pressed.connect(_online_join)
	row.add_child(b_join)
	vb.add_child(row)
	on_lbl = UI.label("", 22, Color.WHITE)
	on_lbl.custom_minimum_size = Vector2(760, 120)
	on_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(on_lbl)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	on_start = _big_button("Inizia online", 420, true)
	on_start.pressed.connect(_online_start)
	on_start.visible = main.lobby.get("role", "") == "host"
	row2.add_child(on_start)
	var b_close := _big_button("Indietro", 300)
	b_close.pressed.connect(func(): on_panel.queue_free())
	row2.add_child(b_close)
	vb.add_child(row2)
	if not main.lobby.is_empty():
		on_code.text = main.lobby["code"]
		on_lbl.text = "Stanza %s…" % main.lobby["code"]
	elif str(ses.get("room", "")) != "":
		on_code.text = str(ses["room"])
		on_lbl.text = "Eri nella stanza %s: premi Entra per rientrare." % ses["room"]


func _line(ph: String, maxlen: int) -> LineEdit:
	var le := LineEdit.new()
	le.placeholder_text = ph
	le.max_length = maxlen
	le.custom_minimum_size = Vector2(0, 60)
	le.add_theme_font_size_override("font_size", 28)
	return le


func _say(t: String) -> void:
	if is_instance_valid(on_lbl):
		on_lbl.text = t


func _seats_text(room: Dictionary) -> String:
	var seats := Net._as_dict(room.get("seats", {}))
	var list: Array = _config()["seats"]
	var parts := []
	for idx in room.get("open", []):
		var k := str(int(idx))
		var who := str(seats[k].get("name", "?")) if seats.has(k) and seats[k] is Dictionary else "libero"
		var cname: String = D.NATIONS[list[int(idx)]["nat"]]["short"] if int(idx) < list.size() else "posto %d" % (int(idx) + 1)
		parts.append("%s: %s" % [cname, who])
	return ", ".join(parts)


func _online_create() -> void:
	var nm := on_name.text.strip_edges()
	if nm == "":
		_say("Scrivi il tuo nome.")
		return
	var seats := []
	var list: Array = _config()["seats"]
	for i in list.size():
		if not list[i]["ai"]:
			seats.append(i)
	if seats.size() < 2:
		_say("Metti su Umano almeno due nazioni: la prima è la tua, le altre sono i posti per gli amici.")
		return
	_store()
	_say("Creo la stanza…")
	var net: Net = main.get_net()
	var code := await net.create_room(nm, seats)
	if code == "":
		_say("Non riesco a creare la stanza.\n%s" % net.last_error)
		return
	main.lobby = {"role": "host", "code": code, "seat": seats[0]}
	net.remember_room(code, seats[0])
	net._save({"name": nm})
	if is_instance_valid(on_code):
		on_code.text = code
	if is_instance_valid(on_start):
		on_start.visible = true
	_lobby_poll(code)


func _online_join() -> void:
	var code := on_code.text.strip_edges().to_upper()
	var nm := on_name.text.strip_edges()
	if nm == "" or code.length() != 4:
		_say("Scrivi il tuo nome e il codice di 4 lettere.")
		return
	_say("Entro nella stanza %s…" % code)
	var net: Net = main.get_net()
	var seat := await net.join_room(code, nm)
	if seat == -2:
		_say("Stanza %s non trovata, oppure la partita è già iniziata.%s" % [code, ("\n" + net.last_error) if net.last_error != "" else ""])
		return
	if seat == -1:
		_say("Nella stanza %s non ci sono posti liberi." % code)
		return
	var room: Dictionary = net.last_room
	main.lobby = {"role": "host" if room.get("host", "") == net.uid else "guest", "code": code, "seat": seat}
	net.remember_room(code, seat)
	net._save({"name": nm})
	if room.get("status", "") in ["playing", "over"] and room.has("game"):
		_say("Rientro nella partita della stanza %s…" % code)
		_begin(room["game"], true)
		return
	if is_instance_valid(on_start):
		on_start.visible = main.lobby["role"] == "host"
	_lobby_poll(code)


func _lobby_poll(code: String) -> void:
	var net: Net = main.get_net()
	while is_inside_tree() and main.lobby.get("code", "") == code:
		var room := await net.room(code)
		if not is_inside_tree() or main.lobby.get("code", "") != code:
			return
		if room.is_empty():
			_say("La stanza %s non esiste più." % code)
			main.lobby = {}
			return
		if main.lobby["role"] == "host":
			_say("Stanza [ %s ]: dai il codice ai tuoi amici.\nPosti: %s.\nQuando ci siete tutti premi Inizia online: i posti liberi li gioca l'IA." % [code, _seats_text(room)])
		else:
			if room.get("status", "") == "playing" and room.has("game"):
				_begin(room["game"], false)
				return
			_say("Sei nella stanza [ %s ] (posto %d).\nAspetta che chi l'ha creata avvii la partita." % [code, int(main.lobby["seat"]) + 1])
		await get_tree().create_timer(2.0).timeout


## Chi ha creato la stanza avvia: scenario, opzioni e seme valgono per tutti.
func _online_start() -> void:
	var code: String = main.lobby["code"]
	var net: Net = main.get_net()
	var room := await net.room(code)
	if room.is_empty():
		_say("La stanza %s non esiste più." % code)
		main.lobby = {}
		return
	var seats_db := Net._as_dict(room.get("seats", {}))
	var cfg := _config()
	var my_seat := int(main.lobby["seat"])
	if my_seat >= cfg["seats"].size() or not seats_db.has(str(my_seat)) or cfg["seats"][my_seat]["ai"]:
		_say("Hai cambiato scenario o nazioni dopo aver creato la stanza: creane una nuova.")
		return
	for i in cfg["seats"].size():
		var k := str(i)
		if seats_db.has(k) and seats_db[k] is Dictionary and not cfg["seats"][i]["ai"]:
			cfg["seats"][i]["name"] = str(seats_db[k].get("name", cfg["seats"][i]["name"]))
		else:
			cfg["seats"][i]["ai"] = true
	cfg["seed"] = 1 + randi() % 2000000000
	var g := {"cfg": var_to_str(cfg)}
	if not await net.start_room(code, g):
		_say("Non riesco ad avviare la partita (%s)." % net.last_error)
		return
	_begin(g, false)


func _begin(g: Dictionary, rejoin: bool) -> void:
	var net: Net = main.get_net()
	var lob: Dictionary = main.lobby
	var backlog: Array = []
	if rejoin:
		backlog = await net.get_acts(lob["code"])
		net.set_away(lob["code"], int(lob["seat"]), false)
	var cfg = str_to_var(str(g.get("cfg", "")))
	if not (cfg is Dictionary):
		_say("Configurazione della partita non valida.")
		return
	var ses := OnlineSession.new()
	ses.setup(net, lob["code"], int(lob["seat"]), lob["role"], backlog)
	cfg["online"] = ses
	main.lobby = {}
	main.start_game(cfg)
