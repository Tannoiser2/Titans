extends Control
## Vista di gioco: tabellone 3D a tutto schermo, pannelli dei giocatori, Ordini e Carte Supporto,
## barra delle decisioni, mano del giocatore umano, pannello della Battaglia, registro e fine partita.

const D = preload("res://scripts/data/ti_data.gd")

var main
var config: Dictionary
var engine: TIEngine
var online = null
var board: Board3D
var pending: Dictionary = {}
var viewer := -1                 # posto di cui si mostra la mano
var local_humans: Array = []
var _dirty := false

# pannelli
var top_lbl: Label
var phase_lbl: Label
var right_box: VBoxContainer
var left_box: VBoxContainer
var dec_panel: PanelContainer
var dec_box: VBoxContainer
var hand_panel: PanelContainer
var hand_box: HBoxContainer
var battle_panel: PanelContainer
var battle_box: VBoxContainer
var log_panel: PanelContainer
var log_text: RichTextLabel
var tip: PanelContainer
var tip_lbl: Label
var curtain: Control
var zoom: Control
var status_lbl: Label
var sel_cards: Array = []
var sel_dice: Array = []
var hover_r := -1
var log_open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	engine = TIEngine.new()
	add_child(engine)
	online = config.get("online", null)
	if online != null:
		add_child(online)
		online.view = self
		engine.online = online
	engine.setup(config)
	for s in engine.n:
		var p: Dictionary = engine.players[s]
		engine.ais[s] = TIAI.new(int(p["level"]), int(config.get("seed", 0)) * 7 + s + 1 if config.has("seed") else 0)
		if online != null:
			if s == online.seat:
				local_humans.append(s)
		elif not p["ai"]:
			local_humans.append(s)
	viewer = local_humans[0] if not local_humans.is_empty() else -1
	engine.ai_delay = float(config.get("ai_delay", 0.5))
	_build()
	engine.changed.connect(_mark)
	engine.log_added.connect(_on_log)
	engine.decision_requested.connect(_on_decision)
	engine.game_ended.connect(_on_end)
	engine.fx.connect(_on_fx)
	board.setup(engine)
	board.reset_view()
	_refresh()
	if online != null and online.role != "host":
		online.heartbeat_loop()
	engine.run.call_deferred()


func _mark() -> void:
	if not _dirty:
		_dirty = true
		_refresh.call_deferred()


# ================================================================ costruzione

func _build() -> void:
	board = Board3D.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(board)
	board.region_clicked.connect(_on_region_click)
	board.region_hovered.connect(_on_region_hover)
	# barra in alto
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UI.panel_style(Color(0.06, 0.06, 0.08, 0.86), Color(0, 0, 0, 0), 0, 0))
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.custom_minimum_size.y = 58
	add_child(top)
	var th := HBoxContainer.new()
	th.add_theme_constant_override("separation", 16)
	top.add_child(th)
	var tt := UI.title("TITANS", 30)
	th.add_child(tt)
	top_lbl = UI.label("", 22, UI.GOLD_L, UI.font_head_b)
	th.add_child(top_lbl)
	phase_lbl = UI.label("", 20, UI.TEXT)
	phase_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	th.add_child(phase_lbl)
	status_lbl = UI.label("", 18, UI.MUTED)
	th.add_child(status_lbl)
	for spec in [["Vista", _toggle_view], ["Registro", _toggle_log], ["Regole", _show_rules_popup], ["Menu", _confirm_menu]]:
		var b := UI.button(spec[0], 110, 42, 18)
		b.pressed.connect(spec[1])
		th.add_child(b)
	# colonna destra: giocatori
	var rp := ScrollContainer.new()
	rp.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rp.anchor_left = 1.0
	rp.anchor_right = 1.0
	rp.offset_left = -440
	rp.offset_right = -8
	rp.offset_top = 66
	rp.anchor_bottom = 1.0
	rp.offset_bottom = -8
	rp.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(rp)
	right_box = VBoxContainer.new()
	right_box.add_theme_constant_override("separation", 8)
	right_box.custom_minimum_size.x = 420
	rp.add_child(right_box)
	# colonna sinistra: Ordini e Supporto
	var lp := ScrollContainer.new()
	lp.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lp.offset_left = 8
	lp.offset_right = 300
	lp.offset_top = 66
	lp.anchor_bottom = 1.0
	lp.offset_bottom = -8
	add_child(lp)
	left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 6)
	left_box.custom_minimum_size.x = 286
	lp.add_child(left_box)
	# mano del giocatore (in basso)
	hand_panel = PanelContainer.new()
	hand_panel.add_theme_stylebox_override("panel", UI.iron_style(8, 0.9))
	hand_panel.anchor_top = 1.0
	hand_panel.anchor_bottom = 1.0
	hand_panel.offset_left = 310
	hand_panel.offset_right = 1470
	hand_panel.offset_top = -168
	hand_panel.offset_bottom = -6
	add_child(hand_panel)
	var hs := ScrollContainer.new()
	hs.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hand_panel.add_child(hs)
	hand_box = HBoxContainer.new()
	hand_box.add_theme_constant_override("separation", 6)
	hs.add_child(hand_box)
	# decisioni
	dec_panel = PanelContainer.new()
	dec_panel.add_theme_stylebox_override("panel", UI.iron_style(8, 0.95))
	dec_panel.anchor_top = 1.0
	dec_panel.anchor_bottom = 1.0
	dec_panel.offset_left = 330
	dec_panel.offset_right = 1450
	dec_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	dec_panel.offset_top = -190
	dec_panel.offset_bottom = -178
	add_child(dec_panel)
	dec_box = VBoxContainer.new()
	dec_box.add_theme_constant_override("separation", 6)
	dec_panel.add_child(dec_box)
	dec_panel.visible = false
	# battaglia
	battle_panel = PanelContainer.new()
	battle_panel.add_theme_stylebox_override("panel", UI.iron_style(10, 0.94))
	battle_panel.offset_left = 330
	battle_panel.offset_right = 1450
	battle_panel.offset_top = 70
	battle_panel.offset_bottom = 380
	add_child(battle_panel)
	battle_box = VBoxContainer.new()
	battle_box.add_theme_constant_override("separation", 4)
	battle_panel.add_child(battle_box)
	battle_panel.visible = false
	# registro
	log_panel = PanelContainer.new()
	log_panel.add_theme_stylebox_override("panel", UI.iron_style(8, 0.95))
	log_panel.offset_left = 310
	log_panel.offset_right = 1000
	log_panel.offset_top = 66
	log_panel.offset_bottom = 700
	add_child(log_panel)
	log_text = RichTextLabel.new()
	log_text.scroll_following = true
	log_text.bbcode_enabled = true
	log_panel.add_child(log_text)
	log_panel.visible = false
	# suggerimento sulla regione
	tip = PanelContainer.new()
	tip.add_theme_stylebox_override("panel", UI.iron_style(6, 0.92))
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip)
	tip_lbl = UI.label("", 18)
	tip.add_child(tip_lbl)
	tip.visible = false


# ================================================================ aggiornamento

func _refresh() -> void:
	_dirty = false
	if engine == null:
		return
	board.refresh()
	board.set_battle(engine.battle["r"] if not engine.battle.is_empty() else -1)
	var rn := "Preparazione" if engine.round_no == 0 else "Round %d di %d" % [engine.round_no, engine.rounds_total]
	top_lbl.text = rn
	var ph := ""
	if engine.active >= 0 and engine.phase in ["orders", "battles", "battle", "draw", "reset", "play"]:
		ph = "Turno di %s" % engine.pname(engine.active)
		match engine.phase:
			"orders": ph += " — Fase A: Ordini"
			"battles", "battle": ph += " — Fase B: Battaglie"
			"draw": ph += " — Fase C: Carta Supporto"
			"reset": ph += " — Fase D: Ripristino"
	elif engine.phase == "round_end":
		ph = "Fine del Round: Rinforzi"
	elif engine.phase == "setup":
		ph = "Preparazione: Carte Nazione e Obiettivi Segreti"
	phase_lbl.text = ph
	_refresh_players()
	_refresh_left()
	_refresh_hand()
	_refresh_battle()


func _refresh_players() -> void:
	for c in right_box.get_children():
		c.queue_free()
	for s in engine.n:
		right_box.add_child(_player_panel(s))


func _player_panel(s: int) -> Control:
	var nat := engine.nat(s)
	var pc := PanelContainer.new()
	var sb := UI.panel_style(Color(UI.ndark(nat), 0.88), UI.nlight(nat) if s == engine.current else UI.GOLD_D, 3 if s == engine.current else 1, 8)
	pc.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	pc.add_child(hb)
	hb.add_child(UI.icon_rect(UI.banner(nat), Vector2(46, 92)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 1)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	var r1 := HBoxContainer.new()
	var nm := UI.label(engine.pname(s), 22, Color.WHITE, UI.font_head_b)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	r1.add_child(nm)
	if s == engine.first:
		var fp := UI.icon_rect(UI.tex("res://assets/segni/primo.png"), Vector2(28, 28))
		fp.tooltip_text = "Primo Giocatore"
		fp.mouse_filter = Control.MOUSE_FILTER_PASS
		r1.add_child(fp)
	var pv := UI.label("%d PV" % engine.vp[s], 24, UI.GOLD_L, UI.font_head_b)
	r1.add_child(pv)
	vb.add_child(r1)
	var sub := "%s%s" % [D.NATIONS[nat]["name"], "  · IA" if engine.players[s]["ai"] else ""]
	vb.add_child(UI.label(sub, 16, UI.MUTED))
	var reg := engine.controlled(s).size()
	var line := "Regioni %d · Supporto %d · Obiettivi %d (fatti %d)" % [reg, engine.hand[s].size(), engine.obj_hand[s].size(), engine.obj_done[s].size()]
	if engine.advanced:
		line += " · Energia %d" % engine.energy[s]
	vb.add_child(UI.label(line, 16))
	var res: Dictionary = engine.reserve[s]
	var tstate: String = {"board": "in campo", "up": "sulla plancia (in piedi)", "down": "sulla plancia (a terra)"}[engine.titan[s]]
	vb.add_child(UI.label("Riserva: %d Fanterie, %d Cavallerie, %d Artiglierie · Titano %s" % [res["F"], res["K"], res["A"], tstate], 15, UI.MUTED))
	if not engine.capital_alive[s]:
		vb.add_child(UI.label("Capitale distrutta", 15, UI.BLOOD_L))
	if not engine.nowned[s].is_empty():
		var cards := HBoxContainer.new()
		cards.add_theme_constant_override("separation", 3)
		for oc in engine.nowned[s]:
			var tr := UI.icon_rect(UI.nation_card_tex(nat, oc["i"]), Vector2(40, 61))
			tr.mouse_filter = Control.MOUSE_FILTER_STOP
			tr.tooltip_text = D.nation_card_text(nat, oc["i"]) + ("\n(usata in questo Round)" if oc["rot"] else "")
			if oc["rot"]:
				tr.modulate = Color(0.5, 0.5, 0.5)
			var ci: int = oc["i"]
			tr.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_zoom_card(UI.nation_card_tex(nat, ci), D.nation_card_text(nat, ci)))
			cards.add_child(tr)
		vb.add_child(cards)
	pc.tooltip_text = "Abilità della Nazione: %s\nAbilità del Titano: %s" % [D.NATIONS[nat]["nation_ab"], D.NATIONS[nat]["titan_ab"]]
	return pc


func _refresh_left() -> void:
	for c in left_box.get_children():
		c.queue_free()
	left_box.add_child(UI.heading("Ordini", 22))
	var vis := engine.visible_area()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	var choosing: bool = not pending.is_empty() and pending.get("ctx", "") == "order"
	for i in engine.oarea.size():
		var c: int = engine.oarea[i]
		var hidden := not (c in vis)
		var tr: Control
		if hidden:
			tr = _card_back(Vector2(88, 135), "?")
		else:
			tr = _order_card(c, Vector2(88, 135), choosing)
		grid.add_child(tr)
	left_box.add_child(grid)
	if engine.cur_order >= 0:
		left_box.add_child(UI.label("Ordini in corso:", 16, UI.MUTED))
		var cur := _order_card(engine.cur_order, Vector2(88, 135), false)
		left_box.add_child(cur)
		var al := []
		for a in engine.actions_left:
			al.append(D.ACTION_NAME[a])
		if not al.is_empty():
			left_box.add_child(UI.wrap(UI.label("Restano: " + ", ".join(al), 16), 280))
	if not engine.onext.is_empty():
		left_box.add_child(UI.label("Ordini Successivi:", 16, UI.MUTED))
		var g2 := GridContainer.new()
		g2.columns = 4
		g2.add_theme_constant_override("h_separation", 3)
		for i in engine.onext.size():
			var hid: bool = i >= engine.onext.size() - engine.onext_hidden
			g2.add_child(_card_back(Vector2(66, 101), "?") if hid else _order_card(engine.onext[i], Vector2(66, 101), false))
		left_box.add_child(g2)
	left_box.add_child(UI.label("Mazzo Ordini: %d · Scarti: %d" % [engine.odeck.size(), engine.odiscard.size()], 15, UI.MUTED))
	left_box.add_child(HSeparator.new())
	left_box.add_child(UI.heading("Carte Supporto", 22))
	var g3 := GridContainer.new()
	g3.columns = 4
	g3.add_theme_constant_override("h_separation", 3)
	for c in engine.sface:
		g3.add_child(_support_card(c, Vector2(66, 101)))
	left_box.add_child(g3)
	left_box.add_child(UI.label("Mazzo: %d · Scarti: %d · Fortezze: %d" % [engine.sdeck.size(), engine.sdiscard.size(), engine.fortresses_left], 15, UI.MUTED))


func _order_card(c: int, sz: Vector2, clickable: bool) -> Control:
	var tr := UI.icon_rect(UI.order_tex(c, engine.advanced), sz)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.tooltip_text = engine.order_label(c)
	if clickable:
		var fr := PanelContainer.new()
		fr.add_theme_stylebox_override("panel", UI.panel_style(Color(0, 0, 0, 0), UI.GOLD_L, 3, 6))
		fr.add_child(tr)
		tr.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				_choose_order(c))
		fr.tooltip_text = tr.tooltip_text
		return fr
	tr.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			_zoom_card(UI.order_tex(c, engine.advanced), engine.order_label(c)))
	return tr


func _support_card(c: int, sz: Vector2) -> Control:
	var tr := UI.icon_rect(UI.support_tex(c), sz)
	tr.mouse_filter = Control.MOUSE_FILTER_STOP
	tr.tooltip_text = "%s\n%s" % [D.SUPPORT_NAME[D.SUPPORT[c]["kind"]], D.support_text(c)]
	tr.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_zoom_card(UI.support_tex(c), tr.tooltip_text))
	return tr


func _card_back(sz: Vector2, txt: String) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = sz
	p.add_theme_stylebox_override("panel", UI.panel_style(UI.LEATHER, UI.GOLD_D, 2, 6))
	var l := UI.label(txt, 30, UI.GOLD, UI.font_head_b)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p


func _refresh_hand() -> void:
	for c in hand_box.get_children():
		c.queue_free()
	var s := viewer
	hand_panel.visible = s >= 0 and engine.phase != "over"
	if s < 0:
		return
	var nat := engine.nat(s)
	var lbl := VBoxContainer.new()
	lbl.add_child(UI.icon_rect(UI.banner(nat), Vector2(34, 68)))
	lbl.add_child(UI.label("La tua\nmano", 15, UI.MUTED))
	hand_box.add_child(lbl)
	var picking: bool = not pending.is_empty() and pending["type"] == "cards" and not pending.get("units", false) and pending.get("seat", -1) == s and _items_are_hand()
	for i in engine.hand[s].size():
		var c: int = engine.hand[s][i]
		var card := _support_card(c, Vector2(84, 129))
		if picking:
			var idx: int = i
			var fr := PanelContainer.new()
			var on: bool = idx in sel_cards
			fr.add_theme_stylebox_override("panel", UI.panel_style(Color(UI.GOLD, 0.25) if on else Color(0, 0, 0, 0), UI.GOLD_L if on else UI.GOLD_D, 3, 6))
			fr.add_child(card)
			card.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_toggle_card(idx))
			hand_box.add_child(fr)
		else:
			hand_box.add_child(card)
	if engine.hand[s].is_empty():
		hand_box.add_child(UI.label("Nessuna Carta Supporto", 16, UI.MUTED))
	hand_box.add_child(VSeparator.new())
	for o in engine.obj_hand[s]:
		hand_box.add_child(_objective_tile(o, false))
	for o in engine.obj_done[s]:
		hand_box.add_child(_objective_tile(o, true))
	if engine.ndeck[s].size() > 0:
		hand_box.add_child(VSeparator.new())
		var top3 := VBoxContainer.new()
		top3.add_child(UI.label("Mazzo Nazione\n(prime 3)", 14, UI.MUTED))
		var h3 := HBoxContainer.new()
		for ci in engine.ndeck[s].slice(0, 3):
			var tr := UI.icon_rect(UI.nation_card_tex(nat, ci), Vector2(52, 80))
			tr.mouse_filter = Control.MOUSE_FILTER_STOP
			tr.tooltip_text = "Costo %d — %s" % [D.NATION_CARDS[nat][ci]["cost"], D.nation_card_text(nat, ci)]
			h3.add_child(tr)
		top3.add_child(h3)
		hand_box.add_child(top3)


func _items_are_hand() -> bool:
	if pending.is_empty() or pending["type"] != "cards":
		return false
	var items: Array = pending["items"]
	if pending.get("ctx", "") in ["look_discard", "take_discard"]:
		return false
	var h: Array = engine.hand[pending["seat"]]
	return items.size() == h.size()


func _objective_tile(o: int, done: bool) -> Control:
	var od: Dictionary = D.OBJECTIVES[o]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(150, 129)
	var sb := UI.paper_style(6)
	if done:
		sb.bg_color = Color("#b9c7a0")
	p.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	p.add_child(vb)
	var t := UI.label(od["text"], 14, UI.INK)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.custom_minimum_size.x = 130
	t.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(t)
	vb.add_child(UI.label(("✔ " if done else "") + "%d PV" % od["vp"], 17, Color("#5a3b10"), UI.font_head_b))
	p.tooltip_text = od["text"]
	return p


# ================================================================ battaglia

func _refresh_battle() -> void:
	var bt: Dictionary = engine.battle
	battle_panel.visible = not bt.is_empty()
	if bt.is_empty():
		return
	for c in battle_box.get_children():
		c.queue_free()
	var title := UI.heading("Battaglia in %s" % engine.rname(bt["r"]), 26, UI.GOLD_L)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_box.add_child(title)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 20)
	battle_box.add_child(hb)
	hb.add_child(_battle_side(bt["att"], "Attaccante"))
	var mid := VBoxContainer.new()
	mid.custom_minimum_size.x = 120
	var vs := UI.title("VS", 34)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(vs)
	if bt["winner"] >= 0:
		var w := UI.label("Vince\n" + engine.pname(bt["winner"]), 20, UI.GOLD_L, UI.font_head_b)
		w.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(w)
	elif bt["acting"] >= 0:
		var a := UI.label("Combatte\n" + engine.pname(bt["acting"]), 18, UI.TEXT)
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(a)
	hb.add_child(mid)
	hb.add_child(_battle_side(bt["def"], "Difensore"))
	var note := "Pareggio: vince il Difensore. Differenza 0–2: nessuna perdita, 1 PV · 3–4: 1 Unità, 2 PV · 5+: 2 Unità, 4 PV."
	var nl := UI.label(note, 15, UI.MUTED)
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	battle_box.add_child(nl)


func _battle_side(s: int, role: String) -> Control:
	var bt: Dictionary = engine.battle
	var nat := engine.nat(s)
	var pc := PanelContainer.new()
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", UI.panel_style(Color(UI.ndark(nat), 0.85), UI.nlight(nat) if bt["acting"] == s else UI.GOLD_D, 3 if bt["acting"] == s else 1, 8))
	var vb := VBoxContainer.new()
	pc.add_child(vb)
	var r1 := HBoxContainer.new()
	r1.add_child(UI.icon_rect(UI.banner(nat), Vector2(26, 52)))
	var nm := UI.label("%s — %s" % [engine.pname(s), role], 20, Color.WHITE, UI.font_head_b)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r1.add_child(nm)
	var st := UI.label(str(engine.strength(s)), 44, UI.GOLD_L, UI.font_head_b)
	r1.add_child(st)
	vb.add_child(r1)
	var parts := []
	for t in D.UNITS:
		var k := engine.army_count(s, t)
		if k > 0:
			parts.append("%d %s" % [k, (D.UNIT_NAME if k == 1 else D.UNIT_NAME_PL)[t]])
	vb.add_child(UI.label("Armata: " + (", ".join(parts) if not parts.is_empty() else "—"), 17))
	var dice := DiceRow.new()
	dice.view = self
	dice.seat = s
	dice.custom_minimum_size = Vector2(0, 70)
	vb.add_child(dice)
	var extra := []
	if int(bt["bonus"][s]) != 0:
		extra.append("Bonus +%d" % bt["bonus"][s])
	if bt["nab"].has(s):
		extra.append("Abilità della Nazione attiva")
	if bt["titan_ab"].has(s):
		extra.append("Abilità del Titano usata")
	if not (bt["nc_used"][s] as Array).is_empty():
		extra.append("Carte Nazione: %d" % (bt["nc_used"][s] as Array).size())
	if int(bt["sup_used"][s]) > 0:
		extra.append("Carte Supporto: %d" % bt["sup_used"][s])
	extra.append("In mano: %d" % engine.hand[s].size())
	vb.add_child(UI.label(" · ".join(extra), 15, UI.MUTED))
	return pc


class DiceRow extends Control:
	var view
	var seat := -1

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _draw() -> void:
		var eng: TIEngine = view.engine
		if eng.battle.is_empty() or not eng.battle["dice"].has(seat):
			return
		var dice: Array = eng.battle["dice"][seat]
		var sz := 58.0
		for i in dice.size():
			var d: Dictionary = dice[i]
			var r := Rect2(Vector2(4 + i * (sz + 8), 6), Vector2(sz, sz))
			var sel: bool = [seat, i] in view.sel_dice
			UI.draw_die(self, r, d["t"], int(d["v"]), sel)

	func _gui_input(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			var i := int((ev.position.x - 4) / 66.0)
			view._toggle_die(seat, i)

	func _process(_d: float) -> void:
		queue_redraw()


# ================================================================ decisioni

func _on_decision(req: Dictionary) -> void:
	pending = req
	sel_cards = []
	sel_dice = []
	var s: int = req["seat"]
	if s in local_humans and s != viewer and local_humans.size() > 1:
		viewer = s
		_show_curtain(s)
	elif s in local_humans:
		viewer = s
	_show_decision()
	_refresh()


func _show_decision() -> void:
	for c in dec_box.get_children():
		c.queue_free()
	board.set_selectable([])
	if pending.is_empty():
		dec_panel.visible = false
		return
	dec_panel.visible = true
	var req := pending
	var head := HBoxContainer.new()
	head.add_child(UI.icon_rect(UI.banner(engine.nat(req["seat"])), Vector2(20, 40)))
	var tl := UI.label(str(req.get("title", "")), 22, UI.GOLD_L, UI.font_head_b)
	tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	dec_box.add_child(head)
	match req["type"]:
		"pick":
			_show_pick(req)
		"region":
			board.set_selectable(req["allowed"])
			var hint := UI.label("Scegli una regione evidenziata sulla mappa.", 18, UI.MUTED)
			dec_box.add_child(hint)
			if req.get("skip", false):
				var b := UI.button("Rinuncia", 200, 44)
				b.pressed.connect(func(): _provide(-1))
				dec_box.add_child(b)
		"cards":
			_show_cards(req)
		"dice":
			var hint := UI.label("Scegli i dadi nel pannello della Battaglia (da %d a %d)." % [req["min"], mini(req["max"], (req["items"] as Array).size())], 18, UI.MUTED)
			dec_box.add_child(hint)
			var b := UI.primary(UI.button("Conferma", 220, 46))
			b.pressed.connect(_confirm_dice)
			dec_box.add_child(b)


func _show_pick(req: Dictionary) -> void:
	var opts: Array = req["options"]
	var ctx: String = req.get("ctx", "")
	if ctx == "order":
		dec_box.add_child(UI.label("Clicca una carta nella colonna Ordini (a sinistra) oppure qui:", 17, UI.MUTED))
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 6)
	dec_box.add_child(flow)
	for i in opts.size():
		var o: Dictionary = opts[i]
		var idx: int = i
		if o.has("card") and o.has("nation") and int(o["card"]) >= 0:
			# carte Nazione: immagine + testo
			var hb0 := HBoxContainer.new()
			var tr := UI.icon_rect(UI.nation_card_tex(o["nation"], o["card"]), Vector2(96, 147))
			tr.mouse_filter = Control.MOUSE_FILTER_STOP
			tr.tooltip_text = o["label"]
			hb0.add_child(tr)
			var vb := VBoxContainer.new()
			var txt := UI.wrap(UI.label(D.nation_card_text(o["nation"], o["card"]), 15), 190)
			txt.size_flags_vertical = Control.SIZE_EXPAND_FILL
			vb.add_child(txt)
			var b := UI.button(("Prendi (costo %d)" % o["cost"]) if o.has("cost") else "Scegli", 190, 40, 16)
			b.disabled = not o.get("ok", true)
			b.tooltip_text = o["label"]
			b.pressed.connect(func(): _provide(idx))
			vb.add_child(b)
			hb0.add_child(vb)
			flow.add_child(hb0)
			continue
		if o.has("nation_card"):
			var hb := HBoxContainer.new()
			var tr2 := UI.icon_rect(UI.nation_card_tex(engine.nat(req["seat"]), o["nation_card"]), Vector2(36, 55))
			hb.add_child(tr2)
			var b2 := UI.button(o["label"], 0, 55, 16)
			b2.custom_minimum_size.x = 0
			b2.pressed.connect(func(): _provide(idx))
			hb.add_child(b2)
			flow.add_child(hb)
			continue
		var b := UI.button(o["label"], 0, 46, 18)
		if o.has("ok") and not o["ok"]:
			b.disabled = true
		if o.has("order"):
			b.text = engine.order_label(o["order"])
		if o.has("card") and ctx in ["draw", "reinf_draw", "take_faceup"] and int(o["card"]) >= 0:
			b.icon = UI.support_tex(o["card"])
			b.expand_icon = true
			b.custom_minimum_size = Vector2(200, 92)
			b.add_theme_constant_override("icon_max_width", 56)
		b.pressed.connect(func(): _provide(idx))
		flow.add_child(b)


func _show_cards(req: Dictionary) -> void:
	var items: Array = req["items"]
	if req.get("units", false):
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		dec_box.add_child(flow)
		for i in items.size():
			var idx: int = i
			var on: bool = idx in sel_cards
			var b := UI.button(D.UNIT_NAME[items[i]], 140, 46, 18)
			if on:
				b.add_theme_stylebox_override("normal", UI.panel_style(UI.GOLD_D, UI.GOLD_L, 3, 5))
			b.pressed.connect(func(): _toggle_card(idx))
			flow.add_child(b)
	elif not _items_are_hand():
		var flow2 := HFlowContainer.new()
		flow2.add_theme_constant_override("h_separation", 6)
		dec_box.add_child(flow2)
		for i in items.size():
			var idx: int = i
			var on: bool = idx in sel_cards
			var fr := PanelContainer.new()
			fr.add_theme_stylebox_override("panel", UI.panel_style(Color(UI.GOLD, 0.25) if on else Color(0, 0, 0, 0), UI.GOLD_L if on else UI.GOLD_D, 3, 6))
			var card := _support_card(items[i], Vector2(76, 117))
			card.gui_input.connect(func(ev):
				if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					_toggle_card(idx))
			fr.add_child(card)
			flow2.add_child(fr)
	else:
		dec_box.add_child(UI.label("Scegli le carte nella tua mano (in basso).", 17, UI.MUTED))
	var row := HBoxContainer.new()
	var cnt := UI.label("Scelte: %d (da %d a %d)" % [sel_cards.size(), req["min"], req["max"]], 18)
	cnt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(cnt)
	var ok := UI.primary(UI.button("Conferma", 220, 46))
	ok.disabled = sel_cards.size() < int(req["min"]) or sel_cards.size() > int(req["max"])
	ok.pressed.connect(func(): _provide(sel_cards.duplicate()))
	row.add_child(ok)
	dec_box.add_child(row)


func _toggle_card(i: int) -> void:
	if pending.is_empty() or pending["type"] != "cards":
		return
	if i in sel_cards:
		sel_cards.erase(i)
	elif sel_cards.size() < int(pending["max"]):
		sel_cards.append(i)
	elif int(pending["max"]) == 1:
		sel_cards = [i]
	_show_decision()
	_refresh_hand()


func _toggle_die(s: int, i: int) -> void:
	if pending.is_empty() or pending["type"] != "dice":
		return
	var it := [s, i]
	if not (it in pending["items"]):
		return
	if it in sel_dice:
		sel_dice.erase(it)
	elif sel_dice.size() < int(pending["max"]):
		sel_dice.append(it)
	elif int(pending["max"]) == 1:
		sel_dice = [it]


func _confirm_dice() -> void:
	if sel_dice.size() < int(pending["min"]):
		return
	var idx := []
	for it in sel_dice:
		idx.append((pending["items"] as Array).find(it))
	_provide(idx)


func _choose_order(c: int) -> void:
	if pending.is_empty() or pending.get("ctx", "") != "order":
		return
	var opts: Array = pending["options"]
	for i in opts.size():
		if opts[i]["order"] == c:
			_provide(i)
			return


func _on_region_click(r: int) -> void:
	if pending.is_empty() or pending["type"] != "region":
		return
	if r in pending["allowed"]:
		_provide(r)


func _on_region_hover(r: int) -> void:
	hover_r = r
	if r <= 0 or engine == null or not engine.regions.has(r):
		tip.visible = false
		return
	var g: Dictionary = engine.reg[r]
	var lines := [engine.rname(r)]
	if engine.inactive.has(r):
		lines.append("Regione inattiva")
	else:
		var o := engine.owner(r)
		lines.append("Controllo: " + (engine.pname(o) if o >= 0 else "nessuno"))
		if g["own"] >= 0 and engine.units_total(r) > 0:
			var parts := []
			for t in D.UNITS:
				if g["n"][t] > 0:
					parts.append("%d %s" % [g["n"][t], (D.UNIT_NAME if g["n"][t] == 1 else D.UNIT_NAME_PL)[t]])
			lines.append(", ".join(parts))
		if g["cap"] >= 0:
			lines.append("Capitale di %s%s" % [engine.pname(g["cap"]), "" if engine.capital_alive[g["cap"]] else " (distrutta)"])
		if g["fort"]:
			lines.append("Fortezza")
		if r == engine.central:
			lines.append("Regione Centrale")
	tip_lbl.text = "\n".join(lines)
	tip.visible = true
	tip.position = get_local_mouse_position() + Vector2(18, 18)
	tip.reset_size()


func _provide(v) -> void:
	if pending.is_empty():
		return
	pending = {}
	sel_cards = []
	sel_dice = []
	dec_panel.visible = false
	board.set_selectable([])
	engine.provide_decision(v)
	_mark()


# ================================================================ varie

func _on_log(t: String) -> void:
	var col := "#ece3d0"
	if t.begins_with("—"):
		col = "#f0d48a"
	elif t.contains("Battaglia"):
		col = "#f2a07a"
	elif t.contains("PV"):
		col = "#b9e59a"
	log_text.append_text("[color=%s]%s[/color]\n" % [col, t])
	status_lbl.text = t.substr(0, 80)


func _on_fx(kind: String, data: Dictionary) -> void:
	match kind:
		"battle":
			board.focus_region(data["r"])


func _toggle_log() -> void:
	log_open = not log_open
	log_panel.visible = log_open


func _toggle_view() -> void:
	board.reset_view(not board.top_view)


func _show_curtain(s: int) -> void:
	if is_instance_valid(curtain):
		curtain.queue_free()
	curtain = ColorRect.new()
	(curtain as ColorRect).color = Color(0.03, 0.03, 0.04, 1.0)
	curtain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(curtain)
	var cc := CenterContainer.new()
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	curtain.add_child(cc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 18)
	cc.add_child(vb)
	vb.add_child(UI.icon_rect(UI.banner(engine.nat(s)), Vector2(120, 240)))
	var t := UI.title("Tocca a %s" % engine.pname(s), 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var sub := UI.label(D.NATIONS[engine.nat(s)]["name"] + " · passa il dispositivo", 22, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var b := UI.primary(UI.button("Sono pronto", 300, 60, 24))
	b.pressed.connect(func(): curtain.queue_free())
	vb.add_child(b)


func _zoom_card(t: Texture2D, text: String) -> void:
	if is_instance_valid(zoom):
		zoom.queue_free()
	zoom = ColorRect.new()
	(zoom as ColorRect).color = Color(0, 0, 0, 0.7)
	zoom.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	zoom.mouse_filter = Control.MOUSE_FILTER_STOP
	zoom.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			zoom.queue_free())
	add_child(zoom)
	var hb := HBoxContainer.new()
	hb.position = Vector2(560, 220)
	hb.add_theme_constant_override("separation", 24)
	zoom.add_child(hb)
	hb.add_child(UI.icon_rect(t, Vector2(400, 614)))
	var l := UI.wrap(UI.label(text, 24), 420)
	hb.add_child(l)


func _confirm_menu() -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = "Abbandonare la partita e tornare al menu?"
	dlg.ok_button_text = "Sì"
	dlg.cancel_button_text = "No"
	add_child(dlg)
	dlg.confirmed.connect(func():
		engine.abort = true
		if online != null:
			online.alive = false
		main.show_menu())
	dlg.popup_centered()


func _show_rules_popup() -> void:
	var p := preload("res://scripts/ui/rules_view.gd").new()
	p.overlay = true
	add_child(p)


func _on_end(results: Array) -> void:
	pending = {}
	dec_panel.visible = false
	if online != null:
		online.finish()
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.72)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UI.iron_style(10, 0.97))
	pc.position = Vector2(560, 200)
	pc.custom_minimum_size = Vector2(800, 0)
	shade.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var w: int = results[0]["seat"]
	var t := UI.title("Vince %s" % engine.pname(w), 46)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	vb.add_child(UI.label(D.NATIONS[engine.nat(w)]["name"], 22, UI.MUTED))
	for i in results.size():
		var r: Dictionary = results[i]
		var hb := HBoxContainer.new()
		hb.add_child(UI.icon_rect(UI.banner(engine.nat(r["seat"])), Vector2(24, 48)))
		var l := UI.label("%d. %s" % [i + 1, engine.pname(r["seat"])], 26, Color.WHITE, UI.font_head_b)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		hb.add_child(UI.label("%d PV · %d Regioni · %d Unità" % [r["vp"], r["regions"], r["units"]], 22))
		vb.add_child(hb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var again := UI.primary(UI.button("Nuova partita", 300, 56))
	again.pressed.connect(func(): main.show_menu())
	row.add_child(again)
	var stay := UI.button("Guarda la mappa", 300, 56)
	stay.pressed.connect(func(): shade.queue_free())
	row.add_child(stay)
	vb.add_child(row)


# ================================================================ online

func online_waiting(s: int, slow: bool) -> void:
	if s < 0:
		status_lbl.text = ""
	else:
		status_lbl.text = "Aspetto %s…%s" % [engine.pname(s), " (lento)" if slow else ""]


func online_status(t: String) -> void:
	status_lbl.text = t


func online_cancel_decision(t: String) -> void:
	pending = {}
	dec_panel.visible = false
	status_lbl.text = t


func online_caught_up() -> void:
	status_lbl.text = "Partita ripresa."
