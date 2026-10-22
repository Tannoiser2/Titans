class_name TIEngine
extends Node
## Motore delle regole di Titans (regolamento italiano), senza dipendenze dalla UI.
## Ogni scelta passa da `decide()`: l'IA risponde subito; per i giocatori umani viene emesso
## `decision_requested` e si attende `provide_decision()`. Online le scelte viaggiano nel registro di
## mosse (OnlineSession): con lo stesso seme ogni dispositivo gioca la stessa partita.
##
## Tipi di richiesta (req["type"]):
##  - "pick": scelta fra options (ognuna con "label"), risposta = indice;
##  - "region": scelta di una regione in "allowed" (con "skip" si può rinunciare: -1);
##  - "cards": scelta di carte (indici in "items"), da "min" a "max", risposta = array di indici di items;
##  - "dice": scelta di dadi della battaglia (items = [[lato, indice]]), risposta = array di indici di items.

signal changed
signal log_added(text: String)
signal decision_requested(req: Dictionary)
signal decision_provided(result)
signal game_ended(results: Array)
signal fx(kind: String, data: Dictionary)

const D = preload("res://scripts/data/ti_data.gd")
const HAND_LIMIT := 5
const TOKENS := 7

var rng := RandomNumberGenerator.new()
var ai_delay := 0.0
var headless := false
var ais := {}
var online = null
var abort := false

# ---- configurazione
var players: Array = []          # {nat, ai, name, level}
var n := 0
var scen: Dictionary = {}
var side := "A"
var advanced := false
var capital_capture := false
var rounds_total := 3

# ---- mappa
var regions: Dictionary = {}     # rid -> {name, adj, x, y}
var inactive: Dictionary = {}    # rid -> true
var central := -1
var reg: Dictionary = {}         # rid -> {own, n{F,K,A,T}, tok, cap, capctrl, fort}
var start_regions: Array = []    # per posto: regioni di partenza
var fortresses_left := D.FORTRESSES

# ---- giocatori
var reserve: Array = []          # per posto: {F,K,A} unità fuori dal tabellone
var titan: Array = []            # per posto: "board", "up", "down"
var vp: Array = []
var energy: Array = []
var hand: Array = []             # carte Supporto in mano (indici di D.SUPPORT)
var ndeck: Array = []            # mazzo Nazione (indice 0 = cima)
var nowned: Array = []           # carte Nazione acquistate: [{i, rot}]
var obj_hand: Array = []         # obiettivi segreti in mano
var obj_done: Array = []         # obiettivi completati
var obj_turn: Array = []         # turno in cui il giocatore ha completato l'ultimo obiettivo
var hold_flags: Array = []       # obiettivi «da un turno all'altro»: kind -> true
var capital_alive: Array = []

# ---- carte comuni
var sdeck: Array = []
var sdiscard: Array = []
var sface: Array = []            # 4 carte Supporto scoperte
var odeck: Array = []
var odiscard: Array = []
var oarea: Array = []            # carte Ordini disponibili (indici del mazzo in uso)
var onext: Array = []            # Area degli Ordini Successivi
var onext_hidden := 0            # carte coperte in onext (regola 3+1)
var area_hidden := 0             # carte ancora coperte nell'area corrente
var area_picks := 0              # scelte rimaste nell'area corrente
var last_area := false
var odeck_src: Array = []        # mazzo usato (D.ORDERS o D.ADV_ORDERS)
var objdeck: Array = []

# ---- svolgimento
var round_no := 0
var turn_no := 0
var first := 0
var active := -1
var current := -1
var phase := ""
var cur_order := -1
var actions_left: Array = []
var actions_used := 0
var army_moved := -1
var battles: Array = []          # battaglie in sospeso: {r, att, u:[{t, from}]}
var attacked_this_turn: Array = []
var battles_started := 0
var battle: Dictionary = {}      # battaglia in corso (per la UI)
var turn_abilities: Dictionary = {}
var game_over := false
var results: Array = []
var log_lines: Array = []
var stats: Array = []            # per posto: battaglie vinte, perse, ...

# ---- Modalità Solitario
var solo := false
var automa := -1                 # posto dell'Automa
var automa_adv := false          # difficoltà Avanzata (azioni con la stella)
var automa_deck: Array = []
var automa_used: Array = []
var automa_card := -1            # carta Automa in corso
var solo_lost := false           # l'Automa ha preso la Capitale del giocatore

# espansioni Kickstarter
var exp_mon := false             # Monumenti
var exp_emi := false             # Emissari del Re
var exp_fire := false            # Pioggia di Fuoco
var mon: Array = []              # per posto: 3 × {built, gone, r, r2, under}
var mon_built_turn := {}         # posto -> turno dell'ultima costruzione
var mon_declined := {}           # posto -> turno in cui ha rinunciato a costruire nella Fase A
var mon_used := {}               # "posto_chiave" -> turno di utilizzo
var emi: Array = []              # per posto: {} oppure {k, r, b, on}; r = -2 se è in Battaglia come attaccante
var emi_pool: Array = []         # Emissari ancora disponibili
var nobj_hand: Array = []        # Obiettivi Nazione ancora da completare (indici 0..2)
var nobj_done: Array = []
var fire_free: Array = []        # per posto: l'Artiglieria di Fuoco è nella riserva
var exp_echo := false            # Echi del Passato
var fallen_pool := 0             # Unità Cadute nella riserva comune
var fallen_card: Array = []      # per posto: carta Unità Caduta (indice di D.FALLEN_CARDS) o -1
var exp_cos := false             # Campi di Sangue (Cosacchi e mazzo Supporto alternativo)
var cossack_pool := 0            # Cosacchi nella riserva comune
var cos_up: Array = []           # per posto: carte Supporto sotto la Plancia (Potenziamenti dei Cosacchi)
var cos_turn := {}               # posto -> turno in cui ha usato l'Azione speciale dei Cosacchi
var q_stop := {}                 # regioni dove un Cosacco si è fermato in questo turno
var exp_ws := false              # Spirito di Guerra (mazzo Supporto alternativo e Dadi Spirito di Guerra)
var face_n := 4                  # Carte Supporto scoperte (6 se si mescolano due mazzi)
var exp_tp := false              # Potere dei Titani
var tp_owned: Array = []         # per posto: Carte Potere del Titano scoperte (indici 0..4)
var tp_deck: Array = []          # per posto: mazzetto coperto


# ================================================================ preparazione

func setup(config: Dictionary) -> void:
	if config.has("seed"):
		rng.seed = int(config["seed"])
	else:
		rng.randomize()
	ai_delay = float(config.get("ai_delay", 0.0))
	advanced = bool(config.get("advanced", false))
	capital_capture = bool(config.get("capital_capture", false))
	rounds_total = 4 if bool(config.get("extended", false)) else 3
	scen = D.scenario(str(config["scenario"]))
	side = scen["side"]
	players = []
	solo = bool(config.get("solo", false))
	automa = -1
	automa_adv = bool(config.get("automa_adv", false))
	exp_mon = bool(config.get("monuments", false)) and not solo
	exp_emi = bool(config.get("emissaries", false)) and not solo
	exp_fire = bool(config.get("fire", false)) and not solo
	exp_echo = bool(config.get("echoes", false)) and not solo
	exp_cos = bool(config.get("fields", false)) and not solo
	exp_ws = bool(config.get("spirit", false)) and not solo
	exp_tp = bool(config.get("titans", false)) and not solo
	for s in config["seats"]:
		if bool(s.get("automa", false)):
			automa = players.size()
		players.append({"nat": str(s["nat"]), "ai": bool(s["ai"]) or bool(s.get("automa", false)), "name": str(s["name"]), "level": int(s.get("level", 1)), "automa": bool(s.get("automa", false))})
	n = players.size()
	if solo:
		advanced = false
		capital_capture = false
	var md: Dictionary = D.map_data(side)
	regions = {}
	for r in md["regioni"]:
		regions[int(r["id"])] = {"name": r["nome"], "adj": [], "x": float(r["x"]), "y": float(r["y"]), "rad": float(r["raggio"])}
	for e in md["confini"]:
		regions[int(e[0])]["adj"].append(int(e[1]))
		regions[int(e[1])]["adj"].append(int(e[0]))
	inactive = {}
	for r in scen["inactive"]:
		inactive[int(r)] = true
	central = int(scen["central"])
	reg = {}
	for r in regions:
		reg[r] = {"own": -1, "n": {"F": 0, "K": 0, "A": 0, "T": 0, "Q": 0}, "tok": -1, "cap": -1, "capctrl": -1, "fort": false, "fire": -1, "mon": [], "fallen": 0}
	reserve = []
	titan = []
	vp = []
	energy = []
	hand = []
	ndeck = []
	nowned = []
	obj_hand = []
	obj_done = []
	obj_turn = []
	hold_flags = []
	start_regions = []
	capital_alive = []
	stats = []
	mon = []
	emi = []
	emi_pool = []
	nobj_hand = []
	nobj_done = []
	fire_free = []
	fallen_card = []
	fallen_pool = D.FALLEN_TOTAL
	cos_up = []
	tp_owned = []
	tp_deck = []
	cos_turn = {}
	q_stop = {}
	cossack_pool = D.COSSACK_TOTAL
	mon_built_turn = {}
	mon_declined = {}
	mon_used = {}
	for s in n:
		mon.append([])
		for i in 3:
			mon[s].append({"built": false, "gone": false, "r": -1, "r2": -1, "under": []})
		emi.append({})
		nobj_hand.append([])
		nobj_done.append([])
		fire_free.append(exp_fire)
		fallen_card.append(-1)
		cos_up.append([])
		tp_owned.append([])
		var td := range(5)
		_shuffle(td)
		tp_deck.append(td)
		reserve.append({"F": D.UNIT_COUNT["F"], "K": D.UNIT_COUNT["K"], "A": D.UNIT_COUNT["A"], "Q": 0})
		titan.append("up")
		vp.append(0)
		energy.append(1 if advanced else 0)
		hand.append([])
		var nd := range(10)
		_shuffle(nd)
		ndeck.append(nd)
		nowned.append([])
		obj_hand.append([])
		obj_done.append([])
		obj_turn.append(-1)
		hold_flags.append({})
		start_regions.append([])
		capital_alive.append(true)
		stats.append({"won": 0, "lost": 0})
	# unità di partenza
	for s in n:
		var code: String = D.NATIONS[players[s]["nat"]]["code"]
		var setup_map: Dictionary = scen["setup"][code]
		for rk in setup_map:
			var r := int(rk)
			start_regions[s].append(r)
			for ch in str(setup_map[rk]):
				if ch == "C":
					reg[r]["cap"] = s
				else:
					_put(r, s, ch)
					if ch == "T":
						titan[s] = "board"
					else:
						reserve[s][ch] -= 1
	# mazzi
	sdeck = []
	if exp_cos:
		sdeck.append_array(range(D.SUPPORT_BASE, D.SUPPORT_FB))
	if exp_ws:
		sdeck.append_array(range(D.SUPPORT_FB, D.SUPPORT.size()))
	if sdeck.is_empty():
		sdeck = range(D.SUPPORT_BASE)
	face_n = 6 if exp_cos and exp_ws else 4
	_shuffle(sdeck)
	sdiscard = []
	sface = []
	objdeck = range(D.OBJECTIVES.size())
	_shuffle(objdeck)
	odeck_src = D.ADV_ORDERS if advanced else D.ORDERS
	first = 0
	if solo:
		first = automa
		for ci in D.SOLO_REMOVE.get(nat(automa), []):
			ndeck[automa].erase(ci)
		automa_deck = range(D.AUTOMA_CARDS.size())
		_shuffle(automa_deck)
		automa_used = []
	phase = "setup"
	fortresses_left = D.FORTRESSES


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func pname(s: int) -> String:
	return players[s]["name"] if s >= 0 and s < n else "?"


func nat(s: int) -> String:
	return players[s]["nat"]


func rname(r: int) -> String:
	return regions[r]["name"] if regions.has(r) else "?"


func log_msg(t: String) -> void:
	log_lines.append(t)
	if log_lines.size() > 500:
		log_lines.pop_front()
	log_added.emit(t)


func any_local_human() -> bool:
	if online != null:
		return true
	for p in players:
		if not p["ai"]:
			return true
	return false


func _fx(kind: String, data: Dictionary) -> void:
	if not headless:
		fx.emit(kind, data)


# ================================================================ decisioni

func decide(seat: int, req: Dictionary):
	req["seat"] = seat
	current = seat
	changed.emit()
	if abort:
		return ais[seat].decide(self, seat, req)
	if online != null:
		var r0 = await online.decide(self, seat, req)
		return r0
	if players[seat]["ai"]:
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay).timeout
		return ais[seat].decide(self, seat, req)
	decision_requested.emit(req)
	var r = await decision_provided
	return r


func provide_decision(r) -> void:
	decision_provided.emit(r)


func pick(seat: int, ctx: String, title: String, options: Array, extra := {}) -> int:
	if options.is_empty():
		return -1
	var req := {"type": "pick", "ctx": ctx, "title": title, "options": options}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	return clampi(int(c) if (c is int or c is float) else 0, 0, options.size() - 1)


func yesno(seat: int, ctx: String, title: String, extra := {}, no_label := "No", yes_label := "Sì") -> bool:
	return await pick(seat, ctx, title, [{"label": no_label}, {"label": yes_label}], extra) == 1


func pick_region(seat: int, ctx: String, title: String, allowed: Array, allow_skip := false, extra := {}) -> int:
	if allowed.is_empty():
		return -1
	var req := {"type": "region", "ctx": ctx, "title": title, "allowed": allowed, "skip": allow_skip}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	var r := int(c) if (c is int or c is float) else -1
	if r in allowed:
		return r
	if allow_skip:
		return -1
	return allowed[0]


## Scelta di carte: items = elenco di valori (es. indici di carte Supporto); restituisce i valori scelti.
func pick_cards(seat: int, ctx: String, title: String, items: Array, nmin: int, nmax: int, extra := {}) -> Array:
	if items.is_empty() or nmax <= 0:
		return []
	nmin = mini(nmin, items.size())
	var req := {"type": "cards", "ctx": ctx, "title": title, "items": items, "min": nmin, "max": nmax}
	for k in extra:
		req[k] = extra[k]
	var c = await decide(seat, req)
	var out := []
	if c is Array:
		for i in c:
			var ii := int(i)
			if ii >= 0 and ii < items.size() and not (items[ii] in out and out.count(items[ii]) >= items.count(items[ii])):
				out.append(items[ii])
				if out.size() >= nmax:
					break
	var k := 0
	while out.size() < nmin and k < items.size():
		if out.count(items[k]) < items.count(items[k]):
			out.append(items[k])
		k += 1
	return out


## Scelta di dadi della battaglia: items = [[lato, indice]], restituisce gli elementi scelti.
func pick_dice(seat: int, ctx: String, title: String, items: Array, nmin: int, nmax: int) -> Array:
	if items.is_empty():
		return []
	var req := {"type": "dice", "ctx": ctx, "title": title, "items": items, "min": nmin, "max": nmax}
	var c = await decide(seat, req)
	var out := []
	if c is Array:
		for i in c:
			var ii := int(i)
			if ii >= 0 and ii < items.size() and not (items[ii] in out):
				out.append(items[ii])
				if out.size() >= nmax:
					break
	var k := 0
	while out.size() < nmin and k < items.size():
		if not (items[k] in out):
			out.append(items[k])
		k += 1
	return out


# ================================================================ mappa e controllo

func active_regions() -> Array:
	var out := []
	for r in regions:
		if not inactive.has(r):
			out.append(r)
	return out


func adj(r: int) -> Array:
	var out := []
	for a in regions[r]["adj"]:
		if not inactive.has(a):
			out.append(a)
	return out


func units_total(r: int) -> int:
	var c: Dictionary = reg[r]["n"]
	return c["F"] + c["K"] + c["A"] + c["T"] + c["Q"]


## Chi controlla la regione (-1 nessuno).
func owner(r: int) -> int:
	var g: Dictionary = reg[r]
	if g["own"] >= 0 and units_total(r) > 0:
		return g["own"]
	if g["tok"] >= 0:
		return g["tok"]
	if g["capctrl"] >= 0:
		return g["capctrl"]
	if g["cap"] >= 0 and capital_alive[g["cap"]]:
		return g["cap"]
	return -1


func controlled(s: int) -> Array:
	var out := []
	for r in regions:
		if not inactive.has(r) and owner(r) == s:
			out.append(r)
	return out


func units_on_board(s: int) -> int:
	var t := 0
	for r in regions:
		if reg[r]["own"] == s:
			t += units_total(r)
	for b in battles:
		if b["att"] == s:
			t += (b["u"] as Array).size()
	return t


func tokens_used(s: int) -> int:
	var t := 0
	for r in regions:
		if reg[r]["tok"] == s:
			t += 1
	return t


func _put(r: int, s: int, t: String, k := 1) -> void:
	var g: Dictionary = reg[r]
	if g["own"] != s:
		g["own"] = s
	g["n"][t] += k
	if g["tok"] == s:
		g["tok"] = -1
	if t == "T":
		titan[s] = "board"


func _take(r: int, t: String, k := 1) -> void:
	var g: Dictionary = reg[r]
	g["n"][t] = maxi(0, g["n"][t] - k)
	if units_total(r) == 0:
		var s: int = g["own"]
		g["own"] = -1
		# l'ultima unità lascia la regione: segnalino controllo (la Capitale vale come segnalino)
		if s >= 0 and not (g["cap"] == s and capital_alive[s]) and g["capctrl"] != s:
			g["tok"] = s


func is_capital_of(r: int, s: int) -> bool:
	return reg[r]["cap"] == s and capital_alive[s]


func army_of(r: int) -> Dictionary:
	return reg[r]["n"].duplicate()


func unit_types_in(r: int) -> Array:
	var out := []
	for t in D.UNITS:
		if reg[r]["n"][t] > 0:
			out.append(t)
	return out


## Regioni nemiche che non possono essere attaccate (regola dell'ultima regione).
func can_attack(s: int, r: int) -> bool:
	var o := owner(r)
	if o < 0 or o == s:
		return true
	var cnt := controlled(o).size()
	if cnt <= 1:
		return false
	if cnt == 2:
		for b in attacked_this_turn:
			if b[0] == o and b[1] != r:
				return false
	return true


func move_targets(s: int, from: int) -> Array:
	var out := []
	for a in move_adj(from):
		var o := owner(a)
		if o >= 0 and o != s and not can_attack(s, a):
			continue
		out.append(a)
	return out


## Tipi di Unità che possono muovere da r (un Cosacco entrato in una Regione non sua si ferma per il turno).
func movable_types(r: int) -> Array:
	var out := unit_types_in(r)
	if q_stop.has(r):
		out.erase("Q")
	return out


func move_sources(s: int, t: String) -> Array:
	var out := []
	for r in regions:
		if reg[r]["own"] == s and (reg[r]["n"][t] > 0 if t != "X" else not movable_types(r).is_empty()) and not (t == "Q" and q_stop.has(r)):
			if not move_targets(s, r).is_empty():
				out.append(r)
	return out


func deploy_targets(s: int) -> Array:
	return controlled(s)


func has_reserve(s: int, t: String) -> bool:
	if t == "T":
		return titan[s] != "board"
	if t == "Q":
		return exp_cos and cossack_pool > 0
	return reserve[s][t] > 0


func deployable_types(s: int, t: String) -> Array:
	var out := []
	for u in ((["F", "K", "A", "T", "Q"] if exp_cos else ["F", "K", "A", "T"]) if t == "X" else [t]):
		if has_reserve(s, u):
			out.append(u)
	return out


# ================================================================ carte Supporto e Nazione

func draw_support(s: int, k := 1, quiet := false) -> void:
	for i in k:
		if sdeck.is_empty():
			if sdiscard.is_empty():
				return
			sdeck = sdiscard
			sdiscard = []
			_shuffle(sdeck)
			log_msg("Il mazzo Supporto viene rimescolato.")
		hand[s].append(sdeck.pop_front())
	if not quiet and k > 0:
		log_msg("%s pesca %d %s Supporto." % [pname(s), k, "Carta" if k == 1 else "Carte"])


func _refill_face() -> void:
	while sface.size() < face_n:
		if sdeck.is_empty():
			if sdiscard.is_empty():
				return
			sdeck = sdiscard
			sdiscard = []
			_shuffle(sdeck)
		sface.append(sdeck.pop_front())


func discard_support(s: int, card: int) -> void:
	var i: int = hand[s].find(card)
	if i >= 0:
		hand[s].remove_at(i)
		sdiscard.append(card)


func discount(round_idx: int) -> int:
	if rounds_total == 4:
		return {3: 1, 4: 2}.get(round_idx, 0)
	return 1 if round_idx == 3 else 0


## Acquisto di una Carta Nazione: si guardano le prime 3 del mazzo.
func buy_nation_card(s: int, extra_discount: int, ctx := "buy") -> bool:
	var top: Array = ndeck[s].slice(0, 3)
	if top.is_empty():
		return false
	var disc := extra_discount + discount(round_no)
	var opts := []
	for ci in top:
		var cost := maxi(0, int(D.NATION_CARDS[nat(s)][ci]["cost"]) - disc)
		var ok: bool = cost <= hand[s].size()
		opts.append({"label": "%s (costo %d)" % [D.nation_card_text(nat(s), ci), cost], "card": ci, "cost": cost, "ok": ok, "nation": nat(s)})
	opts.append({"label": "Non acquistare", "card": -1})
	var k := await pick(s, ctx, "Acquista una Carta Nazione (sconto %d)" % disc, opts, {"nation": nat(s)})
	var ci: int = opts[k]["card"]
	var bought := false
	if ci >= 0 and opts[k]["ok"]:
		var cost: int = opts[k]["cost"]
		if cost > 0:
			var pay := await pick_cards(s, "pay", "Scegli %d Carte Supporto da scartare" % cost, hand[s].duplicate(), cost, cost)
			for c in pay:
				discard_support(s, c)
		ndeck[s].erase(ci)
		nowned[s].append({"i": ci, "rot": false})
		log_msg("%s acquista una Carta Nazione: %s" % [pname(s), D.nation_card_text(nat(s), ci)])
		bought = true
	# una delle carte rimaste può andare in fondo al mazzo
	var rest := []
	for c in top:
		if not (bought and c == ci):
			rest.append(c)
	if rest.size() >= 1:
		var o2 := []
		for c in rest:
			o2.append({"label": "In fondo: " + D.nation_card_text(nat(s), c), "card": c, "nation": nat(s)})
		o2.append({"label": "Lascia tutte in cima", "card": -1})
		var k2 := await pick(s, "bottom", "Vuoi mettere una Carta Nazione in fondo al mazzo?", o2, {"nation": nat(s)})
		var bc: int = o2[k2]["card"]
		if bc >= 0:
			ndeck[s].erase(bc)
			ndeck[s].append(bc)
	changed.emit()
	return bought


func card_used(s: int, k: int) -> bool:
	return nowned[s][k]["rot"]


# ================================================================ partita

func run() -> void:
	log_msg("Scenario %s, lato %s del tabellone. Regione Centrale: %s." % [scen["id"], side, rname(central)])
	changed.emit()
	await _initial_setup()
	for r in rounds_total:
		if game_over:
			break
		round_no = r + 1
		await _play_round()
		if game_over:
			break
		await _end_round()
	_end_game()


func _initial_setup() -> void:
	if solo:
		await _solo_setup()
		return
	for s in n:
		draw_support(s, 3, true)
	_refill_face()
	changed.emit()
	# prima Carta Nazione
	for s in n:
		var ss := (first + s) % n
		await buy_nation_card(ss, 0, "buy_start")
	if exp_emi:
		emi_pool = D.EMISSARY_KEYS.duplicate()
		_shuffle(emi_pool)
		emi_pool = emi_pool.slice(0, 3 if n == 2 else n)
		for s in n:
			nobj_hand[s] = [0, 1, 2]
		var names := []
		for k in emi_pool:
			names.append(D.EMISSARIES[k])
		log_msg("Emissari del Re: ognuno riceve i 3 Obiettivi Nazione. Emissari disponibili: %s." % "; ".join(names))
	if exp_echo:
		await _echo_setup()
	# obiettivi segreti: 4 a testa, se ne tiene 1 e si passa a destra
	var packs := []
	for s in n:
		var p := []
		for i in 4:
			p.append(objdeck.pop_front())
		packs.append(p)
	for step in 3:
		for s in n:
			var p: Array = packs[s]
			var opts := []
			for o in p:
				opts.append({"label": "%s (%d PV)" % [D.OBJECTIVES[o]["text"], D.OBJECTIVES[o]["vp"]], "obj": o})
			var k := await pick(s, "objective", "Scegli un Obiettivo Segreto da tenere", opts)
			obj_hand[s].append(p[k])
			p.remove_at(k)
		# si passa alla destra (posto precedente)
		var np := []
		for s in n:
			np.append(packs[(s + 1) % n])
		packs = np
	for p in packs:
		for o in p:
			objdeck.append(o)
	log_msg("Ogni giocatore ha scelto 3 Obiettivi Segreti.")
	if exp_tp:
		for i in n:
			await _tp_draw((first + i) % n)
	if exp_cos:
		for i in n:
			var sq := (first + i) % n
			var rs := controlled(sq)
			if not rs.is_empty() and cossack_pool > 0:
				var rq := await pick_region(sq, "q_place", "Campi di Sangue: in quale tua Regione metti il Cosacco?", rs, false, {"unit": "Q"})
				_put(rq, sq, "Q")
				cossack_pool -= 1
				log_msg("%s mette 1 Cosacco in %s." % [pname(sq), rname(rq)])
	phase = "play"
	changed.emit()


func _setup_orders() -> void:
	odeck = []
	for i in odeck_src.size():
		if int(odeck_src[i]["min"]) <= n or solo:
			odeck.append(i)
	_shuffle(odeck)
	odiscard = []
	oarea = []
	onext = []
	onext_hidden = 0
	last_area = false
	var size := area_size()
	for i in size:
		oarea.append(odeck.pop_front())
	area_picks = size - 1
	area_hidden = 0
	_fill_next()


func area_size() -> int:
	return 5 if n == 3 else 4


func _fill_next() -> void:
	onext = []
	onext_hidden = 0
	if odeck.is_empty():
		if advanced:
			# Modalità Avanzata: gli scarti formano un'ultima fila di Ordini Successivi (solo per gli scambi)
			odeck = odiscard
			odiscard = []
			_shuffle(odeck)
			last_area = true
			for i in mini(oarea.size(), odeck.size()):
				onext.append(odeck.pop_front())
		return
	var size := area_size()
	var take := mini(size, odeck.size())
	for i in take:
		onext.append(odeck.pop_front())
	if n == 2 and odeck.is_empty() and take == 4 and not solo:
		onext_hidden = 1       # regola 3+1


func _after_pick() -> void:
	# chiamata dopo che un giocatore ha scelto una carta dall'area
	if solo:
		# Solitario: dopo la scelta del giocatore le 2 carte rimaste si scartano e arrivano gli Ordini Successivi
		for c in oarea:
			odiscard.append(c)
		oarea = []
		if not onext.is_empty():
			oarea = onext
			_fill_next()
		return
	area_picks -= 1
	if area_hidden > 0:
		area_hidden -= 1
		log_msg("Viene rivelata l'ultima Carta Ordini.")
	if area_picks > 0 and oarea.size() > 1:
		return
	for c in oarea:
		odiscard.append(c)
	oarea = []
	if last_area or onext.is_empty():
		onext = []
		return
	oarea = onext
	var hid := onext_hidden
	_fill_next()
	if hid > 0:
		area_hidden = hid
		area_picks = 2
	else:
		area_picks = oarea.size() - 1


## Carte dell'area che si possono scegliere ora (con la regola 3+1 l'ultima è coperta).
func visible_area() -> Array:
	if area_hidden > 0:
		return oarea.slice(0, oarea.size() - area_hidden)
	return oarea.duplicate()


func _play_round() -> void:
	log_msg("— Round %d —" % round_no)
	phase = "play"
	_setup_orders()
	for s in n:
		for c in nowned[s]:
			c["rot"] = false
	active = first
	changed.emit()
	while not oarea.is_empty() and not game_over:
		if solo and active == automa:
			await _automa_turn(active)
		else:
			await _turn(active)
		active = (active + 1) % n


func _turn(s: int) -> void:
	turn_no += 1
	attacked_this_turn = []
	battles = []
	battles_started = 0
	turn_abilities = {}
	q_stop = {}
	log_msg("Turno di %s." % pname(s))
	changed.emit()
	# prima della Fase A: carte Nazione (Svezia) e scambio di Ordini (Avanzata)
	await _pre_phase_a(s)
	# ---- Fase A: Ordini
	phase = "orders"
	var vis := visible_area()
	var opts := []
	for c in vis:
		opts.append({"label": order_label(c), "order": c})
	var k := await pick(s, "order", "Fase A: scegli una Carta Ordini", opts)
	cur_order = vis[k]
	oarea.erase(cur_order)
	odiscard.append(cur_order)
	log_msg("%s sceglie gli Ordini: %s." % [pname(s), order_label(cur_order)])
	actions_left = (odeck_src[cur_order]["a"] as Array).duplicate()
	actions_used = 0
	army_moved = -1
	changed.emit()
	await _do_actions(s)
	if advanced:
		_gain_energy(s)
	_after_pick()
	await _mon_after_a(s)
	# ---- Fase B: battaglie
	phase = "battles"
	battles_started = battles.size()
	await _check_objectives_all()
	while not battles.is_empty():
		var bi := 0
		if battles.size() > 1:
			var bo := []
			for b in battles:
				bo.append({"label": "Battaglia in %s" % rname(b["r"]), "region": b["r"]})
			bi = await pick(s, "battle_order", "Scegli quale Battaglia risolvere", bo)
		var b: Dictionary = battles[bi]
		battles.remove_at(bi)
		await _resolve_battle(b)
		await _check_objectives_all()
	_mon_auto(s)
	# ---- Fase C: 1 Carta Supporto
	phase = "draw"
	await _take_support(s, 1, "draw")
	await _mon_after_c(s)
	# ---- Fase D: ripristino
	phase = "reset"
	while hand[s].size() > HAND_LIMIT:
		var ex: int = hand[s].size() - HAND_LIMIT
		var dc := await pick_cards(s, "hand_limit", "Limite di mano 5: scarta %d Carta%s Supporto" % [ex, "" if ex == 1 else "e"], hand[s].duplicate(), ex, ex)
		for c in dc:
			discard_support(s, c)
		log_msg("%s scarta %d Carte Supporto (limite di mano)." % [pname(s), dc.size()])
	if titan[s] == "down":
		titan[s] = "up"
		log_msg("Il Titano di %s si rialza." % pname(s))
	elif titan[s] == "up":
		var tr := await pick_region(s, "titan_deploy", "Fase D: schiera il Titano in una tua Regione (o rinuncia)", controlled(s), true)
		if tr >= 0:
			_put(tr, s, "T")
			log_msg("%s schiera il Titano in %s." % [pname(s), rname(tr)])
			_fx("deploy", {"seat": s, "t": "T", "r": tr})
	await _post_phase_d(s)
	_mon_auto(s)
	await _mon_after_d(s)
	await _check_objectives_all()
	await _end_turn_holds(s)
	_fix_emissaries()
	_fix_fallen()
	cur_order = -1
	phase = "play"
	changed.emit()


func order_label(c: int) -> String:
	var parts := []
	for a in odeck_src[c]["a"]:
		parts.append(D.ACTION_NAME[a])
	return " · ".join(parts)


func _take_support(s: int, k: int, ctx: String) -> void:
	for i in k:
		_refill_face()
		var opts := []
		for c in sface:
			opts.append({"label": "Scoperta: %s" % D.SUPPORT_NAME[D.SUPPORT[c]["kind"]], "card": c})
		opts.append({"label": "Pesca dal mazzo (coperta)", "card": -1})
		var j := await pick(s, ctx, "Prendi 1 Carta Supporto", opts)
		var c: int = opts[j]["card"]
		if c >= 0:
			sface.erase(c)
			hand[s].append(c)
			_refill_face()
			log_msg("%s prende una Carta Supporto scoperta (%s)." % [pname(s), D.SUPPORT_NAME[D.SUPPORT[c]["kind"]]])
		else:
			draw_support(s, 1)
		changed.emit()


# ---------------------------------------------------------------- Fase A: azioni

func _do_actions(s: int) -> void:
	while not actions_left.is_empty() and not game_over:
		var opts := []
		for a in actions_left:
			var ok := action_possible(s, a)
			opts.append({"label": D.ACTION_NAME[a] + ("" if ok else " (non possibile)"), "action": a, "ok": ok})
		var tr := titan_region(s)
		if tr > 0 and can_adv(s, "titan_inf") and reserve[s]["F"] > 0:
			opts.append({"label": "Abilità Avanzata (7 Energia): +1 Fanteria nella Regione del Titano", "action": "_titan_inf", "ok": true})
		opts.append_array(mon_turn_options(s, false))
		if not cos_actions(s).is_empty():
			opts.append({"label": "Azione speciale dei Cosacchi", "action": "_cos", "ok": true})
		opts.append({"label": "Fine delle azioni", "action": ""})
		var k := await pick(s, "action", "Ordini: scegli un'azione (in qualsiasi ordine)", opts, {"order": cur_order})
		var a: String = opts[k]["action"]
		if a == "":
			break
		if not opts[k]["ok"]:
			continue
		if a.begins_with("_mon"):
			await _mon_turn_action(s, opts[k])
			continue
		if a == "_cos":
			await _cos_special(s)
			continue
		if a == "_titan_inf":
			_pay_adv(s, "titan_inf")
			var rr := titan_region(s)
			reserve[s]["F"] -= 1
			_put(rr, s, "F")
			log_msg("%s schiera 1 Fanteria in %s accanto al Titano." % [pname(s), rname(rr)])
			_fx("deploy", {"seat": s, "t": "F", "r": rr})
			await _maybe_fire(s, rr, "F")
			changed.emit()
			continue
		var done := await _do_action(s, a)
		if done:
			actions_left.erase(a)
			actions_used += 1
		changed.emit()


func titan_region(s: int) -> int:
	for r in regions:
		if reg[r]["own"] == s and reg[r]["n"]["T"] > 0:
			return r
	return -1


func action_possible(s: int, a: String) -> bool:
	match a:
		"mF", "mK", "mA", "mT":
			return not move_sources(s, a.substr(1)).is_empty()
		"mX", "army":
			return not move_sources(s, "X").is_empty()
		"dF", "dK", "dA", "dX":
			return not deployable_types(s, a.substr(1)).is_empty() and not deploy_targets(s).is_empty()
		"fort":
			return fortresses_left > 0 and not fort_targets(s).is_empty()
		"buy", "buy1":
			return not ndeck[s].is_empty()
	return false


func fort_targets(s: int) -> Array:
	var out := []
	for r in controlled(s):
		if not reg[r]["fort"] and reg[r]["mon"].is_empty():
			out.append(r)
	return out


func _do_action(s: int, a: String) -> bool:
	match a:
		"mF", "mK", "mA", "mT":
			var t := a.substr(1)
			if t == "T" and advanced:
				return await _move_titan_adv(s)
			return await _move_one(s, t, a)
		"mX":
			return await _move_one(s, "X", a)
		"army":
			return await _move_army(s, 4)
		"dF", "dK", "dA", "dX":
			return await _deploy(s, a.substr(1))
		"fort":
			var r := await pick_region(s, "fort", "Costruisci una Fortezza in una tua Regione", fort_targets(s), true)
			if r < 0:
				return false
			reg[r]["fort"] = true
			fortresses_left -= 1
			log_msg("%s costruisce una Fortezza in %s." % [pname(s), rname(r)])
			_fx("fort", {"r": r})
			return true
		"buy":
			await buy_nation_card(s, 0)
			return true
		"buy1":
			await buy_nation_card(s, 1)
			return true
	return false


## Muove 1 unità del tipo t ("X" = qualsiasi). Restituisce false se il giocatore rinuncia.
func _move_one(s: int, t: String, ctx: String, no_battle := false) -> bool:
	var srcs := move_sources(s, t)
	var src := await pick_region(s, "move_from", "%s: da quale Regione?" % (D.ACTION_NAME.get(ctx, "Muovi")), srcs, true, {"unit": t})
	if src < 0:
		return false
	var ut := t
	if t == "X":
		var types := movable_types(src)
		if types.size() == 1:
			ut = types[0]
		else:
			var o := []
			for u in types:
				o.append({"label": D.UNIT_NAME[u], "unit": u})
			ut = o[await pick(s, "move_type", "Quale Unità muovi?", o)]["unit"]
	var dests := move_targets(s, src)
	if no_battle:
		dests = dests.filter(func(x): return not _enemy_units(s, x))
	var dst := await pick_region(s, "move_to", "Muovi %s da %s: verso quale Regione?" % [D.UNIT_NAME[ut], rname(src)], dests, true, {"from": src, "unit": ut})
	if dst < 0:
		return false
	await _move_with_spass(s, src, dst, {ut: 1}, no_battle)
	return true


func _enemy_units(s: int, r: int) -> bool:
	return reg[r]["own"] >= 0 and reg[r]["own"] != s and units_total(r) > 0


## Movimento di un'Armata da 1 a nmax unità.
func _move_army(s: int, nmax: int) -> bool:
	var srcs := move_sources(s, "X")
	var src := await pick_region(s, "move_from", "Muovi da 1 a %d Unità: da quale Regione?" % nmax, srcs, true, {"unit": "X"})
	if src < 0:
		return false
	var items := []
	for u in movable_types(src):
		for i in reg[src]["n"][u]:
			items.append(u)
	var sel := await pick_cards(s, "army_units", "Quali Unità muovi da %s? (da 1 a %d)" % [rname(src), nmax], items, 1, nmax, {"units": true, "region": src})
	var dst := await pick_region(s, "move_to", "Verso quale Regione muovi l'Armata?", move_targets(s, src), true, {"from": src, "unit": "X"})
	if dst < 0:
		return false
	var cnt := {}
	for u in sel:
		cnt[u] = cnt.get(u, 0) + 1
	army_moved = sel.size()
	await _move_with_spass(s, src, dst, cnt, false)
	return true


func _move_units(s: int, src: int, dst: int, cnt: Dictionary) -> void:
	var moving := 0
	for u in cnt:
		moving += int(cnt[u])
	var emi_go := false
	if exp_emi and not emi[s].is_empty() and emi[s]["r"] == src:
		if units_total(src) - moving <= 0:
			emi_go = true
		else:
			var to_battle := _enemy_units(s, dst) or not _battle_at(dst, s).is_empty()
			emi_go = await yesno(s, "emi_move", "L'Emissario del Re (%s) segue le Unità che muovi?" % D.EMISSARIES[emi[s]["k"]], {"battle_move": to_battle}, "Resta", "Segue")
	var fallen_go := 0
	if exp_echo and reg[src]["fallen"] > 0:
		var fk: int = reg[src]["fallen"]
		var to_b := _enemy_units(s, dst) or not _battle_at(dst, s).is_empty()
		if units_total(src) - moving <= 0 or await yesno(s, "fallen_move", "Le %d Unità Cadute in %s seguono le Unità che muovi?" % [fk, rname(src)], {"battle_move": to_b}, "Restano", "Seguono"):
			fallen_go = fk
			reg[src]["fallen"] = 0
	var fire_go := false
	if cnt.has("A") and reg[src]["fire"] == s:
		fire_go = true
		reg[src]["fire"] = -1
	var desc := []
	for u in cnt:
		_take(src, u, cnt[u])
		desc.append("%d %s" % [cnt[u], (D.UNIT_NAME if cnt[u] == 1 else D.UNIT_NAME_PL)[u]])
	_fx("move", {"seat": s, "from": src, "to": dst, "units": cnt})
	var o := owner(dst)
	var b := _battle_at(dst, s)
	var joined := not b.is_empty()
	if b.is_empty() and _enemy_units(s, dst):
		# battaglia: le unità restano sul confine
		b = {"r": dst, "att": s, "u": []}
		battles.append(b)
		attacked_this_turn.append([reg[dst]["own"], dst])
		log_msg("%s muove %s da %s verso %s: Battaglia!" % [pname(s), ", ".join(desc), rname(src), rname(dst)])
	if not b.is_empty():
		for u in cnt:
			for i in cnt[u]:
				var e := {"t": u, "from": src}
				if u == "A" and fire_go:
					e["fire"] = true
					fire_go = false
				b["u"].append(e)
		if emi_go:
			emi[s]["r"] = -2
			emi[s]["b"] = dst
		if fallen_go > 0:
			b["fallen"] = int(b.get("fallen", 0)) + fallen_go
		if joined:
			log_msg("%s si unisce alla Battaglia in %s con %s." % [pname(s), rname(dst), ", ".join(desc)])
		_check_monuments()
		_fix_fallen()
		changed.emit()
		return
	# regione libera, propria o nemica senza unità
	if o >= 0 and o != s:
		attacked_this_turn.append([o, dst])
		_enter_enemy_free(s, dst, o)
	for u in cnt:
		_put(dst, s, u, cnt[u])
	if cnt.has("Q") and o != s:
		q_stop[dst] = true
	if fire_go:
		reg[dst]["fire"] = s
	if emi_go:
		emi[s]["r"] = dst
	if fallen_go > 0:
		reg[dst]["fallen"] += fallen_go
		desc.append("%d Unità Cadut%s" % [fallen_go, "a" if fallen_go == 1 else "e"])
	log_msg("%s muove %s da %s a %s." % [pname(s), ", ".join(desc), rname(src), rname(dst)])
	if o != s:
		_gained(s, dst)
	_check_monuments()
	_fix_fallen()
	changed.emit()


func _battle_at(r: int, s: int) -> Dictionary:
	for b in battles:
		if b["r"] == r and b["att"] == s:
			return b
	return {}


## Ingresso in una regione nemica senza unità: si prende il controllo.
func _enter_enemy_free(s: int, r: int, o: int) -> void:
	var g: Dictionary = reg[r]
	if g["tok"] == o:
		g["tok"] = -1
	if g["fort"]:
		log_msg("%s prende possesso della Fortezza in %s." % [pname(s), rname(r)])
	if g["capctrl"] >= 0 and g["capctrl"] != s:
		g["capctrl"] = -1
	if g["cap"] >= 0 and g["cap"] != s and capital_alive[g["cap"]]:
		_capital_taken(s, r, false)


func _capital_taken(s: int, r: int, by_battle: bool) -> void:
	var c: int = reg[r]["cap"]
	if capital_capture:
		reg[r]["capctrl"] = s
		if by_battle:
			_add_vp(s, 1, "Capitale conquistata")
		log_msg("%s conquista la Capitale di %s in %s." % [pname(s), pname(c), rname(r)])
	else:
		capital_alive[c] = false
		_add_vp(s, 3, "Capitale distrutta")
		log_msg("%s distrugge la Capitale di %s in %s!" % [pname(s), pname(c), rname(r)])
	_fx("capital", {"r": r})
	if solo and s == automa and c != automa:
		solo_lost = true
		game_over = true
		log_msg("L'Automa ha conquistato la tua Capitale: la partita è persa.")


func _add_vp(s: int, k: int, why: String) -> void:
	if k == 0:
		return
	vp[s] += k
	log_msg("%s ottiene %d PV (%s)." % [pname(s), k, why])
	_fx("vp", {"seat": s, "n": k})


func _deploy(s: int, t: String) -> bool:
	var types := deployable_types(s, t)
	if types.is_empty():
		return false
	var u: String = types[0]
	if types.size() > 1:
		var o := []
		for x in types:
			o.append({"label": D.UNIT_NAME[x], "unit": x})
		o.append({"label": "Rinuncia", "unit": ""})
		u = o[await pick(s, "deploy_type", "Quale Unità schieri?", o)]["unit"]
		if u == "":
			return false
	var r := await pick_region(s, "deploy", "Schiera 1 %s in una tua Regione" % D.UNIT_NAME[u], deploy_targets(s), true, {"unit": u})
	if r < 0:
		return false
	if u == "Q":
		cossack_pool -= 1
	elif u != "T":
		reserve[s][u] -= 1
	_put(r, s, u)
	log_msg("%s schiera 1 %s in %s." % [pname(s), D.UNIT_NAME[u], rname(r)])
	_fx("deploy", {"seat": s, "t": u, "r": r})
	await _maybe_fire(s, r, u)
	return true


# ---------------------------------------------------------------- Modalità Avanzata

func _gain_energy(s: int) -> void:
	var kind := "army" if odeck_src[cur_order]["a"] == ["army"] else "act"
	var g := 0
	if kind == "army":
		g = {4: 0, 3: 2, 2: 4, 1: 6}.get(army_moved, 6)
	else:
		g = 4 if actions_left.size() > 0 else 1
	var before: int = energy[s]
	energy[s] = mini(D.MAX_ENERGY, energy[s] + g)
	if energy[s] > before:
		log_msg("%s raccoglie %d Energia (%d)." % [pname(s), energy[s] - before, energy[s]])


func adv_ability(s: int, key: String) -> Dictionary:
	for a in D.NATIONS[nat(s)]["adv"]:
		if a["key"] == key:
			return a
	return {}


func can_adv(s: int, key: String) -> bool:
	if not advanced:
		return false
	var a := adv_ability(s, key)
	return not a.is_empty() and energy[s] >= int(a["cost"]) and not turn_abilities.has("%d_%s" % [s, key])


func _pay_adv(s: int, key: String) -> void:
	var a := adv_ability(s, key)
	energy[s] -= int(a["cost"])
	turn_abilities["%d_%s" % [s, key]] = true
	log_msg("%s usa un'Abilità Avanzata del Titano (%d Energia): %s" % [pname(s), a["cost"], a["text"]])


func _move_titan_adv(s: int) -> bool:
	var opts := [{"label": "Muovi il Titano", "k": "normal"}]
	if can_adv(s, "titan_army"):
		opts.append({"label": "Abilità (7 Energia): muovi da 1 a 4 Unità", "k": "titan_army"})
	if can_adv(s, "titan_twice") and titan[s] == "board":
		opts.append({"label": "Abilità (4 Energia): muovi il Titano due volte", "k": "titan_twice"})
	opts.append({"label": "Annulla", "k": "cancel"})
	var k := 0
	if opts.size() > 2:
		k = await pick(s, "titan_move", "Muovi il Titano", opts)
	match opts[k]["k"]:
		"cancel":
			return false
		"titan_army":
			_pay_adv(s, "titan_army")
			return await _move_army(s, 4)
		"titan_twice":
			_pay_adv(s, "titan_twice")
			var ok := await _move_one(s, "T", "mT", true)
			if ok:
				await _move_one(s, "T", "mT")
			return ok
	return await _move_one(s, "T", "mT")


func _pre_phase_a(s: int) -> void:
	# carte Nazione «prima della Fase A» (Svezia: muovi 1 Fanteria in una regione adiacente che controlli)
	for k in nowned[s].size():
		var c := D.nation_card(nat(s), nowned[s][k]["i"])
		if c["when"] != "turno_a":
			continue
		var srcs := []
		for r in regions:
			if reg[r]["own"] == s and reg[r]["n"]["F"] > 0:
				for a in move_adj(r):
					if owner(a) == s:
						srcs.append(r)
						break
		if srcs.is_empty():
			continue
		if await yesno(s, "nc_turn_a", "Usare la Carta Nazione? %s" % D.nation_card_text(nat(s), nowned[s][k]["i"]), {"nation_card": nowned[s][k]["i"]}):
			var src := await pick_region(s, "move_from", "Muovi 1 Fanteria: da quale Regione?", srcs, true, {"unit": "F"})
			if src >= 0:
				var dl := move_adj(src).filter(func(x): return owner(x) == s)
				var dst := await pick_region(s, "move_to", "Verso quale tua Regione?", dl, true, {"from": src, "unit": "F"})
				if dst >= 0:
					_take(src, "F")
					_put(dst, s, "F")
					if exp_emi and not emi[s].is_empty() and emi[s]["r"] == src and units_total(src) == 0:
						emi[s]["r"] = dst
					if units_total(src) == 0 and reg[src]["fallen"] > 0:
						reg[dst]["fallen"] += reg[src]["fallen"]
						reg[src]["fallen"] = 0
					log_msg("%s muove 1 Fanteria da %s a %s (Carta Nazione)." % [pname(s), rname(src), rname(dst)])
					_fx("move", {"seat": s, "from": src, "to": dst, "units": {"F": 1}})
	# scambio di Carte Ordini (Modalità Avanzata)
	if advanced and not onext.is_empty():
		var vis := visible_area()
		var cost := vis.size()
		if energy[s] >= cost:
			var opts := [{"label": "Non scambiare", "a": -1, "b": -1}]
			for a in vis:
				for b in onext:
					opts.append({"label": "Scambia «%s» con «%s» (%d Energia)" % [order_label(a), order_label(b), cost], "a": a, "b": b})
			var k := await pick(s, "swap", "Scambiare una Carta Ordini con una degli Ordini Successivi?", opts)
			if opts[k]["a"] >= 0:
				var a: int = opts[k]["a"]
				var b: int = opts[k]["b"]
				oarea[oarea.find(a)] = b
				onext[onext.find(b)] = a
				energy[s] -= cost
				log_msg("%s spende %d Energia per scambiare una Carta Ordini." % [pname(s), cost])
				changed.emit()


func _post_phase_d(s: int) -> void:
	for k in nowned[s].size():
		var c := D.nation_card(nat(s), nowned[s][k]["i"])
		if c["when"] != "dopo_d" or nowned[s][k]["rot"]:
			continue
		if reserve[s]["F"] <= 0 or controlled(s).is_empty():
			continue
		if await yesno(s, "nc_after_d", "Usare la Carta Nazione? %s" % D.nation_card_text(nat(s), nowned[s][k]["i"]), {"nation_card": nowned[s][k]["i"]}):
			var r := await pick_region(s, "deploy", "Schiera 1 Fanteria in una tua Regione", controlled(s), true, {"unit": "F"})
			if r >= 0:
				reserve[s]["F"] -= 1
				_put(r, s, "F")
				nowned[s][k]["rot"] = true
				log_msg("%s schiera 1 Fanteria in %s (Carta Nazione)." % [pname(s), rname(r)])
				_fx("deploy", {"seat": s, "t": "F", "r": r})
				await _maybe_fire(s, r, "F")


# ================================================================ battaglia

func _resolve_battle(b: Dictionary) -> void:
	var r: int = b["r"]
	var att: int = b["att"]
	var dfn: int = reg[r]["own"]
	if dfn < 0 or units_total(r) == 0:
		# il difensore ha portato via tutte le sue unità: l'attaccante entra senza combattere
		var o := owner(r)
		if o >= 0 and o != att:
			_enter_enemy_free(att, r, o)
		for u in b["u"]:
			_put(r, att, u["t"])
			if u.get("fire", false):
				reg[r]["fire"] = att
		if exp_emi and not emi[att].is_empty() and emi[att]["r"] == -2 and emi[att].get("b", -1) == r:
			emi[att]["r"] = r
		reg[r]["fallen"] += int(b.get("fallen", 0))
		log_msg("%s entra in %s senza combattere." % [pname(att), rname(r)])
		if o != att:
			_gained(att, r)
		_check_monuments()
		changed.emit()
		return
	phase = "battle"
	var bt := {
		"r": r, "att": att, "def": dfn, "u_att": b["u"], "dice": {att: [], dfn: []}, "bonus": {att: 0, dfn: 0},
		"first": dfn, "acting": -1, "done": {}, "nab": {}, "titan_ab": {}, "moved_in": {}, "nc_used": {att: [], dfn: []},
		"sup_used": {att: 0, dfn: 0}, "sup_any": {att: false, dfn: false}, "ignore_req": {}, "size0": {},
		"winner": -1, "diff": 0, "emi": {}, "mon_nc": {}, "cap_region": reg[r]["cap"] >= 0,
		"fal": {att: int(b.get("fallen", 0)), dfn: int(reg[r]["fallen"])}, "fz": {}, "retreat_to": {},
		"played": {att: [], dfn: []}, "tp_used": {},
	}
	bt["fal0"] = bt["fal"].duplicate()
	battle = bt
	log_msg("Battaglia in %s: %s attacca %s." % [rname(r), pname(att), pname(dfn)])
	_fx("battle", {"r": r})
	var strong: bool = reg[r]["fort"] or is_capital_of(r, dfn) or reg[r]["capctrl"] == dfn
	if strong:
		draw_support(dfn, 1, true)
		bt["first"] = att
		log_msg("%s difende una %s: pesca 1 Carta Supporto; l'Attaccante combatte per primo." % [pname(dfn), "Fortezza" if reg[r]["fort"] else "Capitale"])
	# abilità del Titano ottomano: l'avversario combatte per primo
	for s in [att, dfn]:
		if nat(s) == "ott" and has_titan(s):
			bt["first"] = other(s)
			bt["titan_ab"][s] = true
			log_msg("Il Genio di %s: l'avversario svolge per primo la Fase Battaglia." % pname(s))
	bt["size0"] = {att: army_size(att), dfn: army_size(dfn)}
	changed.emit()
	# prima della battaglia
	for s in [att, dfn]:
		await _before_battle(s)
	if exp_cos:
		await _cos_before_battle()
	# Emissari presenti in Battaglia
	if exp_emi:
		for s in [att, dfn]:
			if emi_in_battle(s):
				bt["emi"][s] = {"k": emi[s]["k"], "on": emi[s]["on"]}
	# dadi
	for s in [att, dfn]:
		for t in D.UNITS:
			var k := army_count(s, t)
			if t == "T":
				k = mini(k, 1)
			for i in k:
				_roll_die(s, t, true)
		if fire_in_battle(s) and can_roll(s, "F"):
			_roll_die(s, "F", true)
			log_msg("L'Artiglieria di Fuoco di %s tira anche 1 Dado Fanteria." % pname(s))
		for i in int(bt["fal"][s]):
			_roll_die(s, "C", true)
	bt["rolled"] = true
	_apply_nation_ability(att)
	_apply_nation_ability(dfn)
	for s in [att, dfn]:
		if bt["emi"].has(s) and bt["emi"][s]["on"]:
			await _emissary_effect(s)
	log_msg("Forza iniziale: %s %d, %s %d." % [pname(att), strength(att), pname(dfn), strength(dfn)])
	_fx("dice", {})
	changed.emit()
	var order := [bt["first"], other(bt["first"])]
	for s in order:
		bt["acting"] = s
		changed.emit()
		await _battle_phase(s)
		bt["done"][s] = true
	bt["acting"] = -1
	# esito
	var sa := strength(att)
	var sd := strength(dfn)
	var winner := att if sa > sd else dfn
	bt["winner"] = winner
	var loser := other(winner)
	log_msg("Esito: %s %d — %s %d. Vince %s." % [pname(att), sa, pname(dfn), sd, pname(winner)])
	changed.emit()
	await _after_win_cards(winner)
	_fallen_skulls()
	var diff := absi(strength(att) - strength(dfn))
	if exp_echo and _fallen_neg(loser) == "lose_plus2" and int(bt["fal0"][loser]) > 0:
		diff += 2
		log_msg("Unità Cadute: %s aggiunge 2 Forza nell'Esito della Battaglia." % pname(winner))
	bt["diff"] = diff
	var snap := {}
	for s in [att, dfn]:
		var c := {}
		for t in D.UNITS:
			c[t] = army_count(s, t)
		snap[s] = c
	bt["had_titan"] = {att: snap[att]["T"] > 0, dfn: snap[dfn]["T"] > 0}
	bt["foe_titan"] = {att: snap[dfn]["T"] > 0, dfn: snap[att]["T"] > 0}
	bt["outcome"] = true
	bt["only_titan"] = {att: snap[att]["T"] > 0 and army_size(att) == 1, dfn: snap[dfn]["T"] > 0 and army_size(dfn) == 1}
	await _apply_outcome(bt, winner, loser, diff)
	bt["post"] = snap
	if exp_echo:
		await _fallen_gain(bt, loser)
	if exp_cos:
		await _cos_after_battle(bt, winner)
	if exp_tp and bt["had_titan"].get(att, false):
		await _tp_draw(att)
	stats[winner]["won"] += 1
	stats[loser]["lost"] += 1
	await _after_battle_cards(att)
	await _after_battle_cards(dfn)
	await _battle_objectives(bt)
	battle = {}
	phase = "battles"
	_check_monuments()
	_fix_emissaries()
	_fix_fallen()
	changed.emit()


func other(s: int) -> int:
	if battle.is_empty():
		return -1
	return battle["def"] if s == battle["att"] else battle["att"]


func army_count(s: int, t: String) -> int:
	if battle.is_empty():
		return 0
	if battle.has("post"):
		return int(battle["post"][s][t])
	if s == battle["att"]:
		var k := 0
		for u in battle["u_att"]:
			if u["t"] == t:
				k += 1
		return k
	return reg[battle["r"]]["n"][t]


func army_size(s: int) -> int:
	var k := 0
	for t in D.UNITS:
		k += army_count(s, t)
	return k


func has_titan(s: int) -> bool:
	return army_count(s, "T") > 0


func strength(s: int) -> int:
	if battle.is_empty():
		return 0
	var t: int = battle["bonus"][s]
	var zero: bool = battle.has("fz") and battle["fz"].has(s)
	var blank: bool = exp_cos and cos_has(s, "blank")
	for d in battle["dice"][s]:
		if zero and d["t"] == "C":
			continue
		t += int(d["v"])
		if blank and d["t"] == "Q" and int(d["v"]) == 0:
			t += 1
	return t


func dice_used(s: int, t: String) -> int:
	var k := 0
	for d in battle["dice"][s]:
		if d["t"] == t:
			k += 1
	return k


func can_roll(s: int, t: String) -> bool:
	return dice_used(s, t) < int(D.DICE_LIMIT[t])


func _roll_die(s: int, t: String, quiet := false) -> int:
	if not can_roll(s, t):
		if not quiet:
			log_msg("%s non ha più Dadi %s disponibili." % [pname(s), D.UNIT_NAME[t]])
		return -1
	var face := rng.randi() % 6
	var v: int = D.DICE[t][face]
	var die := {"t": t, "v": v}
	if t == "C":
		die["sk"] = D.FALLEN_SKULL[face]
	battle["dice"][s].append(die)
	if not quiet:
		log_msg("%s lancia un Dado %s: %d." % [pname(s), D.UNIT_NAME[t], v])
	_fx("roll", {"seat": s, "t": t, "v": v})
	return v


func _reroll(s: int, i: int) -> void:
	var d: Dictionary = battle["dice"][s][i]
	var face := rng.randi() % 6
	d["v"] = D.DICE[d["t"]][face]
	if d["t"] == "C":
		d["sk"] = D.FALLEN_SKULL[face]
	if d["t"] == "W":
		d["sym"] = D.WS_SYMBOL[face]
		if d["sym"]:
			d["pend"] = true


func _apply_nation_ability(s: int) -> void:
	if battle["nab"].has(s):
		return
	var nt := nat(s)
	var ok := false
	match nt:
		"pol":
			ok = army_count(s, "K") >= 2
		"rus":
			ok = army_count(s, "F") == 1 and can_roll(s, "F")
		"sve":
			ok = army_count(s, "F") >= 2 and can_roll(s, "K")
		"ott":
			ok = army_count(s, "F") > 0 and army_count(s, "A") > 0
		"sri":
			ok = army_size(s) in [2, 3] and can_roll(s, "F")
	if not ok:
		return
	battle["nab"][s] = true
	match nt:
		"pol", "ott":
			battle["bonus"][s] += 1
			log_msg("Abilità della Nazione di %s: +1 Forza." % pname(s))
		"rus", "sri":
			_roll_die(s, "F")
			log_msg("Abilità della Nazione di %s: +1 Dado Fanteria." % pname(s))
		"sve":
			_roll_die(s, "K")
			log_msg("Abilità della Nazione di %s: +1 Dado Cavalleria." % pname(s))


## Requisiti di una carta Nazione per il posto s nella battaglia in corso.
func req_ok(s: int, req: Array) -> bool:
	var o := other(s)
	for q in req:
		match q:
			"own_F": if army_count(s, "F") == 0: return false
			"own_K": if army_count(s, "K") == 0: return false
			"own_A": if army_count(s, "A") == 0: return false
			"own_T": if army_count(s, "T") == 0: return false
			"foe_F": if army_count(o, "F") == 0: return false
			"foe_K": if army_count(o, "K") == 0: return false
			"foe_A": if army_count(o, "A") == 0: return false
			"foe_T": if army_count(o, "T") == 0: return false
			"own_1F": if army_count(s, "F") != 1: return false
			"own_2K": if army_count(s, "K") < 2: return false
			"only_A": if army_count(s, "A") == 0 or army_size(s) != army_count(s, "A"): return false
			"att": if s != battle["att"]: return false
			"def": if s != battle["def"]: return false
			"fewer": if army_size(s) >= army_size(o): return false
			"foe_2": if army_size(o) < 2: return false
			"more": if army_size(s) <= army_size(o): return false
	return true


func support_req_ok(s: int, card: int) -> bool:
	var rq: Array = D.SUPPORT[card]["req"]
	var who := s if rq[0] == "own" else other(s)
	return army_count(who, rq[1]) > 0


## Carte Nazione usabili ora nel momento `when`.
func usable_nation_cards(s: int, when: String) -> Array:
	var out := []
	for k in nowned[s].size():
		var oc: Dictionary = nowned[s][k]
		var c := D.nation_card(nat(s), oc["i"])
		if c["when"] != when:
			continue
		if oc["rot"]:
			continue
		if not battle.is_empty() and k in battle["nc_used"][s]:
			continue
		if not battle.is_empty() and not req_ok(s, c["req"]):
			continue
		if not _effect_possible(s, c["eff"]):
			continue
		out.append(k)
	return out


func _effect_possible(s: int, eff: String) -> bool:
	if battle.is_empty():
		return true
	match eff:
		"die_F", "die_K", "die_A", "die_T":
			return can_roll(s, eff.substr(4))
		"max_die":
			return not battle["dice"][s].is_empty()
		"dice2_str3":
			return battle["dice"][s].size() >= 2
		"sup2_titan":
			return hand[s].size() >= 2 and can_roll(s, "T")
		"foe_discard", "look_discard":
			return not hand[other(s)].is_empty()
		"take_discard":
			return not sdiscard.is_empty()
		"move_in":
			return not hand[s].is_empty() and not _move_in_sources(s, "X").is_empty()
		"foe_move_out":
			return army_size(other(s)) >= 2
		"reroll2":
			return not hand[s].is_empty() and not battle["dice"][s].is_empty()
	return true


func _use_nation_card(s: int, k: int) -> void:
	var oc: Dictionary = nowned[s][k]
	var c := D.nation_card(nat(s), oc["i"])
	if c["freq"] == "round":
		oc["rot"] = true
		if not battle.is_empty() and _fallen_neg(s) == "nc_round_zero":
			_fallen_zero(s)
	if not battle.is_empty():
		battle["nc_used"][s].append(k)
	log_msg("%s usa una Carta Nazione: %s" % [pname(s), D.nation_card_text(nat(s), oc["i"])])
	_fx("ncard", {"seat": s, "card": oc["i"]})
	await _effect(s, c["eff"])


func _effect(s: int, eff: String) -> void:
	var o := other(s)
	match eff:
		"die_F", "die_K", "die_A", "die_T":
			_roll_die(s, eff.substr(4))
		"str_1":
			battle["bonus"][s] += 1
		"str_2":
			battle["bonus"][s] += 2
		"max_die":
			await _max_die(s)
		"draw":
			draw_support(s, 1)
		"draw_discard":
			draw_support(s, 1)
			var dc := await pick_cards(s, "discard", "Scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
			for c in dc:
				discard_support(s, c)
		"vp":
			_add_vp(s, 1, "Carta Nazione")
		"dice2_str3":
			var items := _dice_items(s, false)
			var sel := await pick_dice(s, "drop_dice", "Scarta 2 Dadi della tua Riserva (+3 Forza)", items, 2, 2)
			var idx := []
			for it in sel:
				idx.append(it[1])
			idx.sort()
			idx.reverse()
			for i in idx:
				battle["dice"][s].remove_at(i)
			battle["bonus"][s] += 3
		"sup2_titan":
			var dc := await pick_cards(s, "discard", "Scarta 2 Carte Supporto per lanciare 1 Dado Titano", hand[s].duplicate(), 2, 2)
			for c in dc:
				discard_support(s, c)
			_roll_die(s, "T")
		"foe_discard":
			if not hand[o].is_empty():
				var dc := await pick_cards(o, "discard", "Devi scartare 1 Carta Supporto", hand[o].duplicate(), 1, 1)
				for c in dc:
					discard_support(o, c)
				log_msg("%s scarta 1 Carta Supporto." % pname(o))
		"look_discard":
			if not hand[o].is_empty():
				var dc := await pick_cards(s, "look_discard", "Carte Supporto di %s: scegline 1 da scartare" % pname(o), hand[o].duplicate(), 1, 1)
				for c in dc:
					discard_support(o, c)
				log_msg("%s fa scartare 1 Carta Supporto a %s." % [pname(s), pname(o)])
		"take_discard":
			if not sdiscard.is_empty():
				var tk := await pick_cards(s, "take_discard", "Prendi 1 carta dalla pila degli scarti Supporto", sdiscard.duplicate(), 1, 1)
				for c in tk:
					sdiscard.erase(c)
					hand[s].append(c)
		"move_in":
			var dc := await pick_cards(s, "discard", "Scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
			for c in dc:
				discard_support(s, c)
			await _move_in(s, "X")
		"foe_move_out":
			await _move_out(o)
		"win_str":
			if battle["winner"] == s:
				battle["bonus"][s] += 1
		"reroll2":
			var dc := await pick_cards(s, "reroll_card", "Scegli la Carta Supporto da scartare", hand[s].duplicate(), 1, 1)
			for c in dc:
				discard_support(s, c)
			battle["sup_any"][s] = true
			if _fallen_neg(s) == "reroll_zero":
				_fallen_zero(s)
			for k in 2:
				changed.emit()
				var sel := await pick_dice(s, "reroll", "Ritiro %d di 2: scegli i Dadi da ritirare" % (k + 1), _dice_items(s), 0, 99)
				for it in sel:
					_reroll(s, it[1])
				log_msg("%s ritira %d Dad%s." % [pname(s), sel.size(), "o" if sel.size() == 1 else "i"])
	changed.emit()


func _dice_items(s: int, change := true) -> Array:
	var items := []
	var lock: bool = change and exp_echo and _fallen_neg(s) == "no_reroll"
	for i in battle["dice"][s].size():
		if lock and battle["dice"][s][i]["t"] == "C":
			continue
		if change and battle["dice"][s][i].get("used", false):
			continue
		items.append([s, i])
	return items


func _max_die(s: int) -> void:
	var sel := await pick_dice(s, "max_die", "Scegli un tuo Dado da portare al valore massimo", _dice_items(s), 1, 1)
	for it in sel:
		var d: Dictionary = battle["dice"][s][it[1]]
		d["v"] = (D.DICE[d["t"]] as Array).max()
		if d["t"] == "C":
			d["sk"] = true
		log_msg("%s porta un Dado %s al massimo (%d)." % [pname(s), D.UNIT_NAME[d["t"]], d["v"]])


## Regioni adiacenti alla battaglia da cui si può far entrare un'unità.
func _move_in_sources(s: int, t: String) -> Array:
	var out := []
	var r: int = battle["r"]
	for a in move_adj(r):
		if reg[a]["own"] == s and (units_total(a) > 0 if t == "X" else reg[a]["n"][t] > 0):
			out.append(a)
	return out


func _move_in(s: int, t: String, override := []) -> void:
	var srcs := _move_in_sources(s, t) if override.is_empty() else override
	var src := await pick_region(s, "move_in", "Muovi 1 Unità nella Battaglia: da quale Regione adiacente?", srcs, true, {"unit": t})
	if src < 0:
		return
	var ut := t
	if t == "X":
		var types := unit_types_in(src)
		if types.size() > 1:
			var o := []
			for u in types:
				o.append({"label": D.UNIT_NAME[u], "unit": u})
			ut = o[await pick(s, "move_type", "Quale Unità entra in Battaglia?", o)]["unit"]
		else:
			ut = types[0]
	var fire_go: bool = ut == "A" and reg[src]["fire"] == s
	if fire_go:
		reg[src]["fire"] = -1
	_take(src, ut)
	if s == battle["att"]:
		var e := {"t": ut, "from": src}
		if fire_go:
			e["fire"] = true
		battle["u_att"].append(e)
	else:
		_put(battle["r"], s, ut)
		if fire_go:
			reg[battle["r"]]["fire"] = s
	if exp_emi and not emi[s].is_empty() and emi[s]["r"] == src and units_total(src) == 0:
		if s == battle["att"]:
			emi[s]["r"] = -2
			emi[s]["b"] = battle["r"]
		else:
			emi[s]["r"] = battle["r"]
	log_msg("%s porta 1 %s da %s nella Battaglia." % [pname(s), D.UNIT_NAME[ut] if not fire_go else D.FIRE_NAME, rname(src)])
	_fx("move", {"seat": s, "from": src, "to": battle["r"], "units": {ut: 1}})
	if battle.get("rolled", false):
		_roll_die(s, ut)
		if fire_go:
			_roll_die(s, "F")
	_apply_nation_ability(s)
	changed.emit()


func _move_out(o: int) -> void:
	var r: int = battle["r"]
	var dests := controlled(o).filter(func(x): return x != r)
	var near := dests.filter(func(x): return x in move_adj(r))
	if not near.is_empty():
		dests = near
	if dests.is_empty():
		return
	var items := []
	for t in D.UNITS:
		for i in army_count(o, t):
			items.append(t)
	var sel := await pick_cards(o, "move_out", "Devi spostare 1 Unità fuori dalla Battaglia", items, 1, 1, {"units": true})
	var ut: String = sel[0]
	var dst := await pick_region(o, "move_out_to", "In quale tua Regione sposti la %s?" % D.UNIT_NAME[ut], dests, false)
	var fire_go := false
	if o == battle["att"]:
		var idx := _att_unit_index(ut)
		fire_go = battle["u_att"][idx].get("fire", false)
		battle["u_att"].remove_at(idx)
	else:
		if ut == "A" and reg[r]["fire"] == o and reg[r]["n"]["A"] == 1:
			fire_go = true
			reg[r]["fire"] = -1
		_take(r, ut)
	_put(dst, o, ut)
	if fire_go:
		reg[dst]["fire"] = o
	log_msg("%s sposta 1 %s fuori dalla Battaglia, in %s." % [pname(o), D.UNIT_NAME[ut], rname(dst)])
	_fx("move", {"seat": o, "from": r, "to": dst, "units": {ut: 1}})


func _before_battle(s: int) -> void:
	while true:
		var opts := []
		for k in usable_nation_cards(s, "prima"):
			opts.append({"label": "Carta Nazione: " + D.nation_card_text(nat(s), nowned[s][k]["i"]), "k": "nc", "card": k, "nation_card": nowned[s][k]["i"]})
		if has_titan(s) and can_adv(s, "cav_in") and not _move_in_sources(s, "K").is_empty():
			opts.append({"label": "Abilità Avanzata (7 Energia): muovi 1 Cavalleria nella Battaglia", "k": "cav_in"})
		if can_adv(s, "titan_in") and not has_titan(s) and not _move_in_sources(s, "T").is_empty():
			opts.append({"label": "Abilità Avanzata (6 Energia): muovi il Titano nella Battaglia", "k": "titan_in"})
		if has_titan(s) and can_adv(s, "foe_rand_discard") and not hand[other(s)].is_empty():
			opts.append({"label": "Abilità Avanzata (5 Energia): l'avversario scarta 1 Carta Supporto a caso", "k": "foe_rand"})
		if opts.is_empty():
			return
		opts.append({"label": "Inizia la Battaglia", "k": "go"})
		var k := await pick(s, "before_battle", "Prima della Battaglia in %s" % rname(battle["r"]), opts, {"battle": true})
		match opts[k]["k"]:
			"go":
				return
			"nc":
				await _use_nation_card(s, opts[k]["card"])
			"cav_in":
				_pay_adv(s, "cav_in")
				await _move_in(s, "K")
			"titan_in":
				_pay_adv(s, "titan_in")
				await _move_in(s, "T")
			"foe_rand":
				_pay_adv(s, "foe_rand_discard")
				var o := other(s)
				var c: int = hand[o][rng.randi() % hand[o].size()]
				discard_support(o, c)
				log_msg("%s scarta 1 Carta Supporto a caso." % pname(o))
		changed.emit()


## Combinazioni di Carte Supporto giocabili ora: [{kind, n, cards, label}].
func support_plays(s: int) -> Array:
	var ignore_left: bool = nat(s) == "sve" and has_titan(s) and not battle["titan_ab"].has(s)
	var out := []
	var decks := []
	for c in hand[s]:
		var dk: String = D.SUPPORT[c].get("deck", "base")
		if not (dk in decks):
			decks.append(dk)
	for combo in _deck_kinds(decks):
		var deck: String = combo[0]
		var kind: String = combo[1]
		var ok_cards := []
		var any_cards := []
		for c in hand[s]:
			if D.SUPPORT[c]["kind"] == kind and D.SUPPORT[c].get("deck", "base") == deck:
				any_cards.append(c)
				if support_req_ok(s, c):
					ok_cards.append(c)
		var maxn: int = {"forza": 3, "dado": 2, "muovi": 1}[kind]
		var ws: bool = deck == "sg"
		if kind == "muovi" and (battle["moved_in"].has(s) or _move_in_sources(s, "X").is_empty()):
			continue
		for k in range(1, maxn + 1):
			var cards := []
			var uses_ign := false
			if ok_cards.size() >= k:
				cards = ok_cards.slice(0, k)
			elif ignore_left and ok_cards.size() == k - 1 and any_cards.size() >= k:
				cards = ok_cards.duplicate()
				for c in any_cards:
					if not (c in cards):
						cards.append(c)
						break
				uses_ign = true
			else:
				continue
			var wsdie: bool = ws and ((kind == "forza" and k >= 2) or (kind == "dado" and k == 2))
			if wsdie and ws_free() <= 0:
				continue
			if kind == "dado" and not wsdie:
				var dt := "F" if k == 1 else "T"
				if not can_roll(s, dt):
					continue
			var lbl := ""
			var ev := -1.0
			match kind:
				"forza": lbl = "Aggiungi Forza: %d carta%s (+%d)" % [k, "" if k == 1 else "e", [0, 1, 3, 5][k]]
				"dado": lbl = "Aggiungi un Dado: %s" % ("1 carta (+1 Dado Fanteria)" if k == 1 else "2 carte (+1 Dado Titano)")
				"muovi": lbl = "Muovi 1 Unità nella Battaglia"
			if wsdie:
				if kind == "forza":
					lbl = "Spirito di Guerra: %d carte Aggiungi Forza (1 Dado Spirito di Guerra, simbolo +%d)" % [k, 3 if k == 2 else 6]
					ev = 1.5 + (1.5 if k == 2 else 3.0)
				else:
					lbl = "Spirito di Guerra: 2 carte Aggiungi un Dado (1 Dado Spirito di Guerra, simbolo = effetto)"
					ev = 2.1
			if uses_ign:
				lbl += " — con l'abilità del Titano"
			var pool: Array = ok_cards.duplicate() if not uses_ign else any_cards.duplicate()
			var play := {"kind": kind, "n": k, "cards": cards, "label": lbl, "ign": uses_ign, "deck": deck, "ws": wsdie, "pool": pool, "okc": ok_cards.duplicate()}
			if ev >= 0.0:
				play["ev"] = ev
			out.append(play)
	return out


func _deck_kinds(decks: Array) -> Array:
	var out := []
	for kind in ["forza", "dado", "muovi"]:
		for dk in decks:
			out.append([dk, kind])
	return out


## Dadi Spirito di Guerra ancora nella riserva comune.
func ws_free() -> int:
	if not exp_ws or battle.is_empty():
		return 0
	var k := 0
	for p in [battle["att"], battle["def"]]:
		for d in battle["dice"][p]:
			if d["t"] == "W":
				k += 1
	return D.WS_DICE - k


func _battle_phase(s: int) -> void:
	var o := other(s)
	while true:
		if exp_ws:
			await _ws_pending(s)
			await _ws_pending(o)
		_apply_nation_ability(s)
		var opts := []
		for p in support_plays(s):
			opts.append({"label": "Gioca: " + p["label"], "k": "sup", "play": p})
		if not hand[s].is_empty() and not battle["dice"][s].is_empty():
			opts.append({"label": "Scarta 1 Carta Supporto per ritirare Dadi", "k": "reroll"})
		for k in usable_nation_cards(s, "battaglia"):
			opts.append({"label": "Carta Nazione: " + D.nation_card_text(nat(s), nowned[s][k]["i"]), "k": "nc", "card": k, "nation_card": nowned[s][k]["i"]})
		if has_titan(s) and not battle["titan_ab"].has(s):
			match nat(s):
				"pol":
					if not hand[s].is_empty() and not battle["dice"][s].is_empty():
						opts.append({"label": "Abilità del Titano: scarta 1 Carta Supporto e porta 1 Dado al massimo", "k": "titan"})
				"rus":
					if not battle["dice"][s].is_empty() or not battle["dice"][o].is_empty():
						opts.append({"label": "Abilità del Titano: ritira 1 Dado qualsiasi", "k": "titan"})
				"sri":
					if not hand[s].is_empty() and not sface.is_empty():
						opts.append({"label": "Abilità del Titano: scarta 1 Carta Supporto e prendine 1 scoperta", "k": "titan"})
		if exp_tp and has_titan(s) and not battle["tp_used"].has(s):
			for ti in tp_owned[s]:
				if not _tp_dice(s, ti).is_empty():
					opts.append({"label": "Potere del Titano: " + D.titan_power_text(nat(s), ti), "k": "tp", "tp": ti})
		if _cos_reroll_die(s) >= 0:
			opts.append({"label": "Potenziamento dei Cosacchi: usa un Dado Cosacco da 1 per ritirare un altro tuo Dado", "k": "cos_reroll"})
		if not _mon_nc_cards(s).is_empty():
			opts.append({"label": "Monumento Municipio: gioca gratis 1 delle prime 3 Carte Nazione del mazzo", "k": "mon_nc"})
		if has_titan(s) and can_adv(s, "die_k") and can_roll(s, "K"):
			opts.append({"label": "Abilità Avanzata (6 Energia): aggiungi 1 Dado Cavalleria", "k": "adv_die_k"})
		if has_titan(s) and can_adv(s, "reroll_any") and not battle["dice"][s].is_empty():
			opts.append({"label": "Abilità Avanzata (4 Energia): ritira qualsiasi tuo Dado", "k": "adv_reroll"})
		if has_titan(s) and can_adv(s, "draw2"):
			opts.append({"label": "Abilità Avanzata (7 Energia): pesca 2 Carte Supporto", "k": "adv_draw2"})
		if has_titan(s) and can_adv(s, "take_faceup") and not sface.is_empty():
			opts.append({"label": "Abilità Avanzata (5 Energia): prendi 1 Carta Supporto scoperta", "k": "adv_take"})
		opts.append({"label": "Termina la Fase Battaglia", "k": "end"})
		var k := await pick(s, "battle", "Fase Battaglia di %s — Forza %d contro %d" % [pname(s), strength(s), strength(o)], opts, {"battle": true})
		var op: Dictionary = opts[k]
		match op["k"]:
			"end":
				return
			"sup":
				var p: Dictionary = op["play"]
				var pool: Array = p.get("pool", [])
				if pool.size() > int(p["n"]):
					# il giocatore sceglie quali carte giocare
					var sel := await pick_cards(s, "sup_cards", "Scegli %d carte «%s» da giocare" % [p["n"], D.SUPPORT_NAME[p["kind"]]], pool, p["n"], p["n"])
					var bad := 0
					for c in sel:
						if not (c in p["okc"]):
							bad += 1
					if sel.size() == int(p["n"]) and bad <= (1 if p["ign"] else 0):
						p["cards"] = sel
						p["ign"] = bad > 0
				for c in p["cards"]:
					discard_support(s, c)
				battle["played"][s].append_array(p["cards"])
				battle["sup_used"][s] += p["cards"].size()
				battle["sup_any"][s] = true
				if p["ign"]:
					battle["titan_ab"][s] = true
				log_msg("%s gioca %s." % [pname(s), p["label"]])
				match p["kind"]:
					"forza":
						if p.get("ws", false):
							await _roll_ws(s, p)
						else:
							battle["bonus"][s] += [0, 1, 3, 5][p["n"]]
					"dado":
						if p.get("ws", false):
							await _roll_ws(s, p)
						else:
							_roll_die(s, "F" if p["n"] == 1 else "T")
					"muovi":
						battle["moved_in"][s] = true
						await _move_in(s, "X")
			"reroll":
				var dc := await pick_cards(s, "reroll_card", "Scegli la Carta Supporto da scartare per ritirare", hand[s].duplicate(), 1, 1)
				for c in dc:
					discard_support(s, c)
				battle["sup_any"][s] = true
				if _fallen_neg(s) == "reroll_zero":
					_fallen_zero(s)
				var sel := await pick_dice(s, "reroll", "Scegli i Dadi da ritirare", _dice_items(s), 1, 99)
				var vals := []
				for it in sel:
					_reroll(s, it[1])
					vals.append(battle["dice"][s][it[1]]["v"])
				log_msg("%s ritira %d Dad%s." % [pname(s), sel.size(), "o" if sel.size() == 1 else "i"])
				_fx("reroll", {"seat": s})
			"nc":
				await _use_nation_card(s, op["card"])
			"titan":
				battle["titan_ab"][s] = true
				if nat(s) == "pol":
					var dc := await pick_cards(s, "discard", "Scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
					for c in dc:
						discard_support(s, c)
					battle["sup_any"][s] = true
					await _max_die(s)
				elif nat(s) == "sri":
					var dc := await pick_cards(s, "discard", "Scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
					for c in dc:
						discard_support(s, c)
					battle["sup_any"][s] = true
					await _take_faceup(s)
					log_msg("Il Guerriero della foresta di %s: cambia una Carta Supporto con una scoperta." % pname(s))
				else:
					var items := _dice_items(s) + _dice_items(o)
					var sel := await pick_dice(s, "titan_reroll", "Scegli 1 Dado da ritirare (tuo o dell'avversario)", items, 1, 1)
					for it in sel:
						_reroll(it[0], it[1])
						log_msg("Il Bogatyr di %s fa ritirare un Dado di %s: %d." % [pname(s), pname(it[0]), battle["dice"][it[0]][it[1]]["v"]])
			"mon_nc":
				await _mon_town_sri(s)
			"tp":
				await _tp_use(s, op["tp"])
			"cos_reroll":
				var qi := _cos_reroll_die(s)
				battle["dice"][s][qi]["used"] = true
				var its := _dice_items(s).filter(func(it): return it[1] != qi)
				var sel := await pick_dice(s, "reroll", "Scegli 1 Dado da ritirare (il Dado Cosacco resta da parte)", its, 1, 1)
				for it in sel:
					_reroll(s, it[1])
					log_msg("%s usa un Dado Cosacco per ritirare un Dado: %d." % [pname(s), battle["dice"][s][it[1]]["v"]])
			"adv_reroll":
				_pay_adv(s, "reroll_any")
				var sel := await pick_dice(s, "reroll", "Scegli i Dadi da ritirare", _dice_items(s), 1, 99)
				for it in sel:
					_reroll(s, it[1])
			"adv_draw2":
				_pay_adv(s, "draw2")
				draw_support(s, 2)
			"adv_die_k":
				_pay_adv(s, "die_k")
				_roll_die(s, "K")
			"adv_take":
				_pay_adv(s, "take_faceup")
				await _take_faceup(s)
		changed.emit()


func _take_faceup(s: int) -> void:
	var opts := []
	for c in sface:
		opts.append({"label": D.SUPPORT_NAME[D.SUPPORT[c]["kind"]], "card": c})
	var j := await pick(s, "take_faceup", "Prendi 1 Carta Supporto scoperta", opts)
	var c: int = opts[j]["card"]
	sface.erase(c)
	hand[s].append(c)
	_refill_face()


func _after_win_cards(s: int) -> void:
	while true:
		var ks := usable_nation_cards(s, "vinta")
		if ks.is_empty():
			return
		var opts := []
		for k in ks:
			opts.append({"label": "Carta Nazione: " + D.nation_card_text(nat(s), nowned[s][k]["i"]), "card": k, "nation_card": nowned[s][k]["i"]})
		opts.append({"label": "Prosegui", "card": -1})
		var j := await pick(s, "after_win", "Hai vinto: usare una Carta Nazione?", opts, {"battle": true})
		if opts[j]["card"] < 0:
			return
		await _use_nation_card(s, opts[j]["card"])


func _after_battle_cards(s: int) -> void:
	while true:
		var ks := usable_nation_cards(s, "dopo")
		if ks.is_empty():
			return
		var opts := []
		for k in ks:
			opts.append({"label": "Carta Nazione: " + D.nation_card_text(nat(s), nowned[s][k]["i"]), "card": k, "nation_card": nowned[s][k]["i"]})
		opts.append({"label": "Prosegui", "card": -1})
		var j := await pick(s, "after_battle", "Dopo la Battaglia: usare una Carta Nazione?", opts, {"battle": true})
		if opts[j]["card"] < 0:
			return
		await _use_nation_card(s, opts[j]["card"])


func _apply_outcome(bt: Dictionary, winner: int, loser: int, diff: int) -> void:
	var r: int = bt["r"]
	var att: int = bt["att"]
	var dfn: int = bt["def"]
	var kill := 0
	if diff >= 5:
		kill = 2
	elif diff >= 3:
		kill = 1
	var lsize := army_size(loser)
	var eff := diff
	if kill == 2 and lsize < 2:
		kill = 1
		eff = 4
	kill = mini(kill, lsize)
	var titan_killed := false
	if kill > 0:
		var items := []
		for t in D.UNITS:
			for i in army_count(loser, t):
				items.append(t)
		var sel := await pick_cards(loser, "casualties", "Hai perso: elimina %d Unità" % kill, items, kill, kill, {"units": true, "battle": true})
		for t in sel:
			var fire_dead := false
			if loser == att:
				var idx := _att_unit_index(t)
				fire_dead = bt["u_att"][idx].get("fire", false)
				bt["u_att"].remove_at(idx)
			else:
				reg[r]["n"][t] -= 1
				if t == "A" and reg[r]["fire"] == loser and reg[r]["n"]["A"] == 0:
					fire_dead = true
					reg[r]["fire"] = -1
			if t == "T":
				titan_killed = true
				titan[loser] = "down" if loser == att else "up"
			elif fire_dead:
				fire_free[loser] = true
			else:
				reserve[loser][t] += 1
			log_msg("%s perde 1 %s." % [pname(loser), D.FIRE_NAME if fire_dead else D.UNIT_NAME[t]])
		_fx("casualties", {"seat": loser, "r": r})
		if exp_mon:
			for p in n:
				var m := mon_standing(p, "stefan")
				if not m.is_empty() and (r == m["r"] or r in adj(m["r"])):
					draw_support(p, 2, true)
					log_msg("Cattedrale di Santo Stefano: %s pesca 2 Carte Supporto." % pname(p))
	bt["wiped"] = kill >= lsize
	# ritirata
	if loser == att:
		var back := -1
		for u in bt["u_att"]:
			var src: int = u["from"]
			if owner(src) == att or owner(src) == -1 or reg[src]["own"] == att:
				_put(src, att, u["t"])
				if u.get("fire", false):
					reg[src]["fire"] = att
				if back < 0:
					back = src
			else:
				# la regione d'origine non è più sua (raro): l'unità torna nella riserva
				if u["t"] == "T":
					titan[att] = "up"
				elif u.get("fire", false):
					fire_free[att] = true
				else:
					reserve[att][u["t"]] += 1
		if exp_emi and not emi[att].is_empty() and emi[att]["r"] == -2 and emi[att].get("b", -1) == r:
			if back >= 0:
				emi[att]["r"] = back
			else:
				_lose_emissary(att)
		var fa := int(bt["fal"].get(att, 0))
		if fa > 0:
			if back >= 0:
				reg[back]["fallen"] += fa
			else:
				fallen_pool += fa
			bt["fal"][att] = 0
		bt["retreat_to"][att] = back
		if not bt["u_att"].is_empty():
			log_msg("%s ritira le sue Unità." % pname(att))
		_fx("retreat", {"seat": att, "r": r})
	else:
		var left := army_of(r)
		var cnt := 0
		for t in D.UNITS:
			cnt += left[t]
		var had_fire: bool = reg[r]["fire"] == dfn
		reg[r]["fire"] = -1
		reg[r]["n"] = {"F": 0, "K": 0, "A": 0, "T": 0, "Q": 0}
		reg[r]["own"] = -1
		var emi_here: bool = exp_emi and not emi[dfn].is_empty() and emi[dfn]["r"] == r
		var fd: int = reg[r]["fallen"]
		reg[r]["fallen"] = 0
		if cnt > 0:
			var mine := move_adj(r).filter(func(x): return owner(x) == dfn)
			var free := move_adj(r).filter(func(x): return owner(x) == -1)
			var dests: Array = mine if not mine.is_empty() else free
			if dests.is_empty():
				for t in D.UNITS:
					if left[t] > 0:
						if t == "T":
							titan[dfn] = "up"
						else:
							reserve[dfn][t] += left[t]
				if had_fire:
					reserve[dfn]["A"] -= 1
					fire_free[dfn] = true
				bt["wiped"] = true
				fallen_pool += fd
				if emi_here:
					_lose_emissary(dfn)
				log_msg("%s non ha dove ritirarsi: le Unità rimaste sono distrutte." % pname(dfn))
			else:
				var dst := await pick_region(dfn, "retreat", "Ritirata: in quale Regione adiacente si ritirano le tue Unità?", dests, false)
				var was_free := owner(dst) == -1
				for t in D.UNITS:
					if left[t] > 0:
						_put(dst, dfn, t, left[t])
				if had_fire:
					reg[dst]["fire"] = dfn
				if emi_here:
					emi[dfn]["r"] = dst
				reg[dst]["fallen"] += fd
				bt["retreat_to"][dfn] = dst
				log_msg("%s si ritira in %s." % [pname(dfn), rname(dst)])
				_fx("move", {"seat": dfn, "from": r, "to": dst, "units": left})
				if was_free:
					_gained(dfn, dst)
		else:
			fallen_pool += fd
			if had_fire:
				fire_free[dfn] = true
			if emi_here:
				_lose_emissary(dfn)
		# l'attaccante entra
		var g: Dictionary = reg[r]
		if g["tok"] >= 0:
			g["tok"] = -1
		for u in bt["u_att"]:
			_put(r, att, u["t"])
			if u.get("fire", false):
				reg[r]["fire"] = att
		if exp_emi and not emi[att].is_empty() and emi[att]["r"] == -2 and emi[att].get("b", -1) == r:
			emi[att]["r"] = r
		reg[r]["fallen"] += int(bt["fal"].get(att, 0))
		_fx("move", {"seat": att, "from": -1, "to": r, "units": {}})
		if g["fort"]:
			g["fort"] = false
			_add_vp(att, 1, "Fortezza distrutta")
			log_msg("La Fortezza in %s è distrutta." % rname(r))
		if g["cap"] == dfn and capital_alive[dfn] and g["capctrl"] < 0:
			_capital_taken(att, r, true)
		elif g["capctrl"] == dfn:
			g["capctrl"] = -1
			if capital_capture and g["cap"] != att:
				g["capctrl"] = att
				_add_vp(att, 1, "Capitale conquistata")
			elif g["cap"] == att:
				log_msg("%s riconquista la propria Capitale." % pname(att))
	# carte al perdente, PV al vincitore
	var cards := 1 if eff <= 2 else (2 if eff <= 4 else 3)
	draw_support(loser, cards)
	var pts := 1 if eff <= 2 else (2 if eff <= 4 else 4)
	_add_vp(winner, pts, "Battaglia vinta")
	if titan_killed:
		_add_vp(winner, 1, "Titano eliminato")
	bt["titan_killed"] = titan_killed
	if winner == att:
		_gained(att, r)
	# Emissari: il segnalino si gira dopo la vittoria e torna attivo nella Battaglia successiva
	for p in bt["emi"]:
		var was_on: bool = bt["emi"][p]["on"]
		if was_on and p == winner and bt["emi"][p]["k"] == "vp":
			_add_vp(p, 1, "Emissario del Re")
		if emi[p].is_empty():
			continue
		if not was_on:
			emi[p]["on"] = true
		elif p == winner:
			emi[p]["on"] = false
	_check_monuments()
	changed.emit()


# ================================================================ obiettivi segreti

func _battle_objectives(bt: Dictionary) -> void:
	var w: int = bt["winner"]
	bt["info"] = {"winner": w, "loser": other(w), "r": bt["r"], "diff": bt["diff"], "w_att": w == bt["att"],
		"w_size0": bt["size0"][w], "l_size0": bt["size0"][other(w)]}
	for s in [bt["att"], bt["def"]]:
		await _try_objectives(s, bt)


func _try_objectives(s: int, bt := {}) -> void:
	if obj_turn[s] == turn_no:
		return
	var best := -1
	var bv := -1.0
	for o in obj_hand[s]:
		if objective_met(s, o, bt):
			if best < 0 or int(D.OBJECTIVES[o]["vp"]) > int(D.OBJECTIVES[best]["vp"]):
				best = o
				bv = float(D.OBJECTIVES[o]["vp"])
	if exp_emi:
		var nv: float = [2.5, 3.0, 5.0][mini(nobj_done[s].size(), 2)]
		for i in nobj_hand[s]:
			if nv > bv and nobj_met(s, i, bt):
				await _complete_nobj(s, i, bt)
				return
	if best >= 0:
		obj_hand[s].erase(best)
		obj_done[s].append(best)
		obj_turn[s] = turn_no
		log_msg("%s completa un Obiettivo Segreto: «%s»" % [pname(s), D.OBJECTIVES[best]["text"]])
		_add_vp(s, int(D.OBJECTIVES[best]["vp"]), "Obiettivo Segreto")
		_fx("objective", {"seat": s, "obj": best})


func _check_objectives_all() -> void:
	for s in n:
		await _try_objectives(s)


func objective_met(s: int, o: int, bt := {}) -> bool:
	var od: Dictionary = D.OBJECTIVES[o]
	var kind: String = od["kind"]
	var pidx := clampi(n - 2, 0, 2)
	match kind:
		"units_on_board":
			return units_on_board(s) >= int(od["n"])
		"regions":
			return controlled(s).size() >= int(od["n"][pidx])
		"central_and_neigh":
			if owner(central) != s:
				return false
			var k := 0
			for a in adj(central):
				if owner(a) == s:
					k += 1
			return k >= int(od["n"][pidx])
		"token_regions":
			var k := 0
			for r in controlled(s):
				if units_total(r) == 0 or reg[r]["own"] != s:
					k += 1
			return k >= int(od["n"])
		"only_type_regions":
			var u: String = od["u"]
			var k := 0
			for r in controlled(s):
				if reg[r]["own"] == s and units_total(r) > 0 and units_total(r) == reg[r]["n"][u]:
					k += 1
			return k >= int(od["n"])
		"enemy_start":
			var k := 0
			for r in _enemy_starts(s):
				if owner(r) == s:
					k += 1
			return k >= int(od["n"])
		"enemy_start_neigh":
			var es := _enemy_starts(s)
			var k := 0
			for r in controlled(s):
				if r in es:
					continue
				for a in adj(r):
					if a in es:
						k += 1
						break
			return k >= int(od["n"])
		"two_battles":
			return s == active and battles_started >= 2
		"two_big_armies", "central_one_unit":
			return hold_flags[s].get(kind + "_done", false)
	# obiettivi di battaglia
	if bt.is_empty() or not bt.has("info"):
		return false
	var info: Dictionary = bt["info"]
	if info["winner"] != s:
		if kind == "nation_cards_battle":
			return (bt["nc_used"][s] as Array).size() >= int(od["n"])
		if kind == "support_cards_battle":
			return int(bt["sup_used"][s]) >= int(od["n"])
		return false
	match kind:
		"nation_cards_battle":
			return (bt["nc_used"][s] as Array).size() >= int(od["n"])
		"support_cards_battle":
			return int(bt["sup_used"][s]) >= int(od["n"])
		"win_no_support":
			return not bt["sup_any"][s]
		"def_smaller_win":
			return not info["w_att"] and info["w_size0"] < info["l_size0"]
		"att_smaller_win":
			return info["w_att"] and info["w_size0"] < info["l_size0"]
		"win_central":
			return info["r"] == central
		"win_vs_titan_central":
			return info["r"] == central and bt.get("foe_titan", {}).get(s, false)
		"win_foe_2nc":
			return (bt["nc_used"][info["loser"]] as Array).size() >= 2
		"win_diff":
			return int(info["diff"]) >= int(od["n"])
		"win_only_titan":
			return bt.get("only_titan", {}).get(s, false)
		"win_no_titan_vs_titan":
			return not bt.get("had_titan", {}).get(s, false) and bt.get("foe_titan", {}).get(s, false)
	return false


func _enemy_starts(s: int) -> Array:
	var out := []
	for t in n:
		if t != s:
			out.append_array(start_regions[t])
	return out


func _end_turn_holds(s: int) -> void:
	# obiettivi da mantenere dalla fine di un tuo turno alla fine del successivo
	var big := 0
	for r in regions:
		if reg[r]["own"] == s and units_total(r) >= 4:
			big += 1
	var c_big := big >= 2
	var c_one: bool = owner(central) == s and reg[central]["own"] == s and units_total(central) == 1
	var hf: Dictionary = hold_flags[s]
	if c_big and hf.get("two_big_armies", false):
		hf["two_big_armies_done"] = true
	if c_one and hf.get("central_one_unit", false):
		hf["central_one_unit_done"] = true
	hf["two_big_armies"] = c_big
	hf["central_one_unit"] = c_one
	await _try_objectives(s)


# ================================================================ fine del round e della partita

func _end_round() -> void:
	phase = "round_end"
	log_msg("— Fine del Round %d —" % round_no)
	if exp_mon:
		for s in n:
			if not mon_standing(s, "sofia").is_empty():
				_add_vp(s, 1, "Cattedrale di Santa Sofia")
	for s in n:
		var k := controlled(s).size()
		if solo and s == automa:
			_add_vp(s, 2 * k, "%d Regioni controllate, 2 PV ciascuna" % k)
		else:
			_add_vp(s, k, "%d Regioni controllate" % k)
	changed.emit()
	if round_no >= rounds_total:
		return
	for c in sface:
		sdiscard.append(c)
	sface = []
	_refill_face()
	for s in n:
		for c in nowned[s]:
			c["rot"] = false
	round_no += 1      # gli sconti del Rinforzo valgono per il round successivo
	var reinf_order := []
	for i in n:
		reinf_order.append((first + i) % n)
	if solo:
		reinf_order = [1 - automa, automa]       # l'Automa sceglie per secondo
	for s in reinf_order:
		if solo and s == automa:
			draw_support(s, 2)
			_automa_buy(s)
			changed.emit()
			continue
		# 1° Rinforzo
		var o1 := [{"label": "Prendi 2 Carte Supporto", "k": "sup"}, {"label": "Pesca 2 Obiettivi Segreti e tienine 1", "k": "obj"}]
		var k1 := await pick(s, "reinf1", "Rinforzi — 1° Rinforzo", o1)
		if o1[k1]["k"] == "sup":
			await _take_support(s, 2, "reinf_draw")
		else:
			var two := []
			for j in 2:
				if not objdeck.is_empty():
					two.append(objdeck.pop_front())
			if not two.is_empty():
				var oo := []
				for o in two:
					oo.append({"label": "%s (%d PV)" % [D.OBJECTIVES[o]["text"], D.OBJECTIVES[o]["vp"]], "obj": o})
				var j := await pick(s, "objective", "Scegli l'Obiettivo Segreto da tenere", oo)
				obj_hand[s].append(two[j])
				two.remove_at(j)
				for o in two:
					objdeck.append(o)
				log_msg("%s pesca nuovi Obiettivi Segreti." % pname(s))
		# 2° Rinforzo
		var o2 := [{"label": "Acquista una Carta Nazione", "k": "buy"}]
		if not hand[s].is_empty() and not controlled(s).is_empty() and not deployable_types(s, "X").is_empty():
			o2.append({"label": "Scarta 1 Carta Supporto e aggiungi 1 Unità", "k": "unit"})
		o2.append({"label": "Nessun rinforzo", "k": "none"})
		var k2 := await pick(s, "reinf2", "Rinforzi — 2° Rinforzo", o2)
		match o2[k2]["k"]:
			"buy":
				await buy_nation_card(s, 0, "reinf_buy")
			"unit":
				var dc := await pick_cards(s, "discard", "Scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
				for c in dc:
					discard_support(s, c)
				await _deploy(s, "X")
		changed.emit()
	round_no -= 1


## Impronta dello stato (per verificare che due dispositivi online abbiano giocato la stessa partita).
func fingerprint() -> String:
	var parts := []
	for s in n:
		parts.append("%d/%d/%d" % [vp[s], controlled(s).size(), units_on_board(s)])
	return "%s|t%d" % [",".join(parts), turn_no]


func _end_game() -> void:
	if capital_capture:
		for r in regions:
			var g: Dictionary = reg[r]
			if g["cap"] >= 0:
				var c := owner(r)
				if c >= 0 and (g["capctrl"] >= 0 or capital_alive[g["cap"]]):
					_add_vp(c, 2, "Capitale controllata")
	game_over = true
	phase = "over"
	results = []
	if solo:
		var me := 1 - automa
		var win: bool = not solo_lost and vp[me] > vp[automa]
		for s in [me, automa]:
			results.append({"seat": s, "vp": vp[s], "regions": controlled(s).size(), "units": units_on_board(s), "first": 0, "solo_win": win})
		if not win:
			results.reverse()
		log_msg("Partita finita: %s" % ("hai sconfitto l'Automa!" if win else "ha vinto l'Automa."))
		changed.emit()
		game_ended.emit(results)
		return
	for s in n:
		results.append({"seat": s, "vp": vp[s], "regions": controlled(s).size(), "units": units_on_board(s), "first": 1 if s == first else 0})
	results.sort_custom(func(a, b):
		if a["vp"] != b["vp"]:
			return a["vp"] > b["vp"]
		if a["regions"] != b["regions"]:
			return a["regions"] > b["regions"]
		if a["units"] != b["units"]:
			return a["units"] > b["units"]
		return a["first"] > b["first"])
	log_msg("Partita finita! Vince %s con %d PV." % [pname(results[0]["seat"]), results[0]["vp"]])
	changed.emit()
	game_ended.emit(results)


# ================================================================ Modalità Solitario: l'Automa

func _solo_setup() -> void:
	var me := 1 - automa
	draw_support(me, 3, true)
	draw_support(automa, 3, true)
	_refill_face()
	changed.emit()
	await buy_nation_card(me, 0, "buy_start")
	_automa_buy(automa)
	# Carte Missione (Obiettivi Segreti): se ne pescano 2 e se ne tiene 1, fino ad averne 3
	for k in 3:
		var two := [objdeck.pop_front(), objdeck.pop_front()]
		var opts := []
		for o in two:
			opts.append({"label": "%s (%d PV)" % [D.OBJECTIVES[o]["text"], D.OBJECTIVES[o]["vp"]], "obj": o})
		var j := await pick(me, "objective", "Scegli un Obiettivo Segreto da tenere (%d di 3)" % (k + 1), opts)
		obj_hand[me].append(two[j])
		objdeck.append(two[1 - j])
	log_msg("Hai scelto 3 Obiettivi Segreti. L'Automa (%s) gioca %s." % [D.NATIONS[nat(automa)]["name"], "a livello Avanzato" if automa_adv else "a livello Base"])
	phase = "play"
	changed.emit()


## L'Automa acquista una Carta Nazione: rivela la prima del suo mazzo e paga con le Carte Supporto dal fondo
## della sua pila; se non può pagare la mette in fondo al mazzo e pesca 1 Carta Supporto.
func _automa_buy(s: int) -> void:
	if ndeck[s].is_empty():
		return
	var ci: int = ndeck[s][0]
	var cost := maxi(0, int(D.NATION_CARDS[nat(s)][ci]["cost"]) - discount(round_no))
	if hand[s].size() >= cost:
		for i in cost:
			sdiscard.append(hand[s].pop_front())
		ndeck[s].pop_front()
		nowned[s].append({"i": ci, "rot": false})
		log_msg("L'Automa acquista una Carta Nazione: %s" % D.nation_card_text(nat(s), ci))
	else:
		ndeck[s].pop_front()
		ndeck[s].append(ci)
		draw_support(s, 1, true)
		log_msg("L'Automa non può pagare la Carta Nazione: la mette in fondo al mazzo e pesca 1 Carta Supporto.")
	changed.emit()


func _automa_turn(s: int) -> void:
	turn_no += 1
	attacked_this_turn = []
	battles = []
	battles_started = 0
	turn_abilities = {}
	if automa_deck.is_empty():
		automa_deck = automa_used
		automa_used = []
		_shuffle(automa_deck)
	automa_card = automa_deck.pop_front()
	automa_used.append(automa_card)
	var card: Dictionary = D.AUTOMA_CARDS[automa_card]
	log_msg("Turno dell'Automa: pesca una carta Automa.")
	phase = "orders"
	changed.emit()
	var acts: Array = (card["a"] as Array).duplicate()
	if automa_adv:
		acts.append_array(card["adv"])
	for act in acts:
		if game_over:
			return
		await _automa_action(s, act)
		changed.emit()
		if ai_delay > 0.0 and not headless and is_inside_tree():
			await get_tree().create_timer(ai_delay * 0.7).timeout
	phase = "battles"
	battles_started = battles.size()
	while not battles.is_empty() and not game_over:
		var b: Dictionary = battles.pop_front()
		await _resolve_battle(b)
		await _check_objectives_all()
	if game_over:
		return
	phase = "draw"
	draw_support(s, 1, true)
	phase = "reset"
	while hand[s].size() > HAND_LIMIT:
		sdiscard.append(hand[s].pop_front())
	if titan[s] != "board":
		var best := -1
		for r in regions:
			if reg[r]["own"] == s and units_total(r) > 0 and (best < 0 or units_total(r) > units_total(best)):
				best = r
		if best < 0 and is_capital_of(_capital_region(s), s):
			best = _capital_region(s)
		if best > 0:
			_put(best, s, "T")
			log_msg("Il Titano dell'Automa torna in campo in %s." % rname(best))
			_fx("deploy", {"seat": s, "t": "T", "r": best})
	# scarta la Carta Ordini indicata (I–IV)
	if not oarea.is_empty():
		var idx := clampi(int(card["d"]) - 1, 0, oarea.size() - 1)
		var oc: int = oarea[idx]
		oarea.remove_at(idx)
		odiscard.append(oc)
		log_msg("L'Automa scarta la Carta Ordini in posizione %s: %s." % [["I", "II", "III", "IV"][clampi(int(card["d"]) - 1, 0, 3)], order_label(oc)])
	await _check_objectives_all()
	phase = "play"
	changed.emit()


func _capital_region(s: int) -> int:
	for r in regions:
		if reg[r]["cap"] == s:
			return r
	return -1


func _automa_armies(s: int) -> Array:
	var out := []
	for r in regions:
		if reg[r]["own"] == s and units_total(r) > 0:
			out.append(r)
	return out


## Regola del Fronte di Battaglia: la regione adiacente al maggior numero di regioni del giocatore, poi a più
## regioni libere, poi a caso.
func _front_pick(cands: Array, s: int) -> int:
	if cands.is_empty():
		return -1
	var me := 1 - s
	var best := []
	var bk := [-1, -1]
	for r in cands:
		var a := 0
		var f := 0
		for x in adj(r):
			if owner(x) == me:
				a += 1
			if units_total(x) == 0:
				f += 1
		var k := [a, f]
		if k[0] > bk[0] or (k[0] == bk[0] and k[1] > bk[1]):
			bk = k
			best = [r]
		elif k == bk:
			best.append(r)
	return best[rng.randi() % best.size()]


func _automa_army(s: int, target: String) -> int:
	var armies := _automa_armies(s)
	var c := []
	match target:
		"big", "small":
			var ext := -1
			for r in armies:
				var k := units_total(r)
				if ext < 0 or (k > ext if target == "big" else k < ext):
					ext = k
			for r in armies:
				if units_total(r) == ext:
					c.append(r)
		"arty":
			c = armies.filter(func(r): return reg[r]["n"]["A"] > 0)
		"titan":
			c = armies.filter(func(r): return reg[r]["n"]["T"] > 0)
	return _front_pick(c, s)


func _automa_action(s: int, act: Array) -> void:
	var kind: String = act[0]
	var target: String = act[1]
	match kind:
		"buy":
			_automa_buy(s)
		"rec_F", "rec_X":
			var r := -1
			match target:
				"small":
					r = _automa_army(s, "small")
				"capA":
					var cr := _capital_region(s)
					if cr > 0 and owner(cr) == s:
						r = cr
				"free":
					r = _front_pick(controlled(s).filter(func(x): return units_total(x) == 0), s)
			if r < 0:
				log_msg("L'Automa non può eseguire: %s." % D.automa_action_text(act))
				return
			var u := ""
			if kind == "rec_F":
				u = "F" if reserve[s]["F"] > 0 else ""
			else:
				for t in ["A", "K", "F"]:
					if reserve[s][t] > 0:
						u = t
						break
			if u == "":
				log_msg("L'Automa non ha Unità da reclutare.")
				return
			reserve[s][u] -= 1
			_put(r, s, u)
			log_msg("L'Automa recluta 1 %s in %s." % [D.UNIT_NAME[u], rname(r)])
			_fx("deploy", {"seat": s, "t": u, "r": r})
		"cap", "exp":
			var src := _automa_army(s, target)
			if src < 0:
				log_msg("L'Automa non può eseguire: %s." % D.automa_action_text(act))
				return
			# limite dei Segnalini Controllo: con tutti e 7 piazzati non lascia regioni scoperte
			if tokens_used(s) >= TOKENS and not is_capital_of(src, s):
				log_msg("L'Automa ha finito i Segnalini Controllo: non muove l'Armata da %s." % rname(src))
				return
			var dst := _automa_dest(s, src, kind == "cap")
			if dst < 0:
				log_msg("L'Automa non può eseguire: %s." % D.automa_action_text(act))
				return
			var cnt := {}
			for t in D.UNITS:
				if reg[src]["n"][t] > 0:
					cnt[t] = reg[src]["n"][t]
			await _move_units(s, src, dst, cnt)


func _dist_from(start: int) -> Dictionary:
	var dist := {start: 0}
	var q := [start]
	while not q.is_empty():
		var r: int = q.pop_front()
		for a in adj(r):
			if not dist.has(a):
				dist[a] = dist[r] + 1
				q.append(a)
	return dist


## Destinazione del movimento dell'Automa (verso la Capitale del giocatore o d'Espansione).
func _automa_dest(s: int, src: int, to_capital: bool) -> int:
	var me := 1 - s
	var cands := move_targets(s, src)
	if to_capital:
		var cr := _capital_region(me)
		if cr < 0:
			return -1
		var dist := _dist_from(cr)
		if not dist.has(src):
			return -1
		cands = cands.filter(func(x): return dist.has(x) and dist[x] < dist[src])
	# limite d'Armata: niente armate oltre il limite dei dadi (3 Fanterie, 2 Cavallerie, 1 Artiglieria)
	var moving: Dictionary = reg[src]["n"]
	var ok := cands.filter(func(x):
		var merge: bool = reg[x]["own"] == s
		for t in ["F", "K", "A"]:
			var k: int = moving[t] + (reg[x]["n"][t] if merge else 0)
			if k > int(D.DICE_LIMIT[t]) and k > moving[t]:
				return false
		return true)
	# priorità: 1 regione libera del giocatore, 2 regione libera non controllata,
	# 3 regione con l'Armata più piccola del giocatore, 4 regione con l'Armata più piccola dell'Automa
	for rank in 4:
		var group := []
		var ext := 999
		for x in ok:
			var u := units_total(x)
			var o := owner(x)
			var hit := false
			match rank:
				0: hit = u == 0 and o == me
				1: hit = u == 0 and o == -1
				2: hit = u > 0 and reg[x]["own"] == me
				3: hit = u > 0 and reg[x]["own"] == s
			if not hit:
				continue
			if rank >= 2:
				if u < ext:
					ext = u
					group = [x]
				elif u == ext:
					group.append(x)
			else:
				group.append(x)
		if not group.is_empty():
			return _front_pick(group, s)
	return -1



# ================================================================ espansioni Kickstarter

## Indice di un'unità dell'attaccante del tipo t (l'Artiglieria di Fuoco per ultima).
func _att_unit_index(t: String) -> int:
	var found := -1
	var ua: Array = battle["u_att"]
	for i in ua.size():
		if ua[i]["t"] == t:
			if not ua[i].get("fire", false):
				return i
			found = i
	return found


func move_adj(r: int) -> Array:
	if not exp_mon:
		return adj(r)
	return adj(r).filter(func(x): return not border_blocked(r, x))


# ---------------------------------------------------------------- Pioggia di Fuoco

func fire_in_battle(s: int) -> bool:
	if not exp_fire or battle.is_empty():
		return false
	if s == battle["att"]:
		for u in battle["u_att"]:
			if u.get("fire", false):
				return true
		return false
	return reg[battle["r"]]["fire"] == s


## Dopo uno schieramento che crea in una Regione la coppia Artiglieria + Fanteria si può sostituirla con
## l'Artiglieria di Fuoco (le due unità tornano nella riserva).
func _maybe_fire(s: int, r: int, u: String) -> void:
	if not exp_fire or not fire_free[s] or not (u in ["A", "F"]):
		return
	var g: Dictionary = reg[r]
	if g["own"] != s or g["fire"] >= 0 or g["n"][u] != 1 or g["n"]["A"] < 1 or g["n"]["F"] < 1:
		return
	if not await yesno(s, "fire", "Pioggia di Fuoco: sostituire 1 Artiglieria e 1 Fanteria in %s con l'Artiglieria di Fuoco?" % rname(r), {"region": r}):
		return
	g["n"]["F"] -= 1
	reserve[s]["F"] += 1
	reserve[s]["A"] += 1          # l'Artiglieria normale torna nella riserva, al suo posto quella di Fuoco
	g["fire"] = s
	fire_free[s] = false
	log_msg("%s schiera l'Artiglieria di Fuoco in %s." % [pname(s), rname(r)])
	_fx("deploy", {"seat": s, "t": "A", "r": r})
	changed.emit()


# ---------------------------------------------------------------- Emissari del Re

func emi_in_battle(s: int) -> bool:
	if not exp_emi or battle.is_empty() or emi[s].is_empty():
		return false
	if s == battle["att"]:
		return emi[s]["r"] == -2 and emi[s].get("b", -1) == battle["r"]
	return emi[s]["r"] == battle["r"]


func _emissary_effect(s: int) -> void:
	var k: String = emi[s]["k"]
	log_msg("L'Emissario del Re aiuta %s: %s." % [pname(s), D.EMISSARIES[k]])
	_fx("emissary", {"seat": s})
	match k:
		"F2":
			_roll_die(s, "F")
			_roll_die(s, "F")
		"K1":
			_roll_die(s, "K")
		"draw":
			draw_support(s, 1, true)
		"max":
			if not battle["dice"][s].is_empty():
				await _max_die(s)
	changed.emit()


func _lose_emissary(s: int) -> void:
	if emi[s].is_empty():
		return
	log_msg("L'Emissario del Re di %s è perduto e torna disponibile." % pname(s))
	emi_pool.append(emi[s]["k"])
	emi[s] = {}


## Un Emissario resta sempre con le Unità del suo giocatore: se la sua regione si svuota (casi rari) è perduto.
func _fix_emissaries() -> void:
	if not exp_emi:
		return
	for s in n:
		var e: Dictionary = emi[s]
		if e.is_empty():
			continue
		var r: int = e["r"]
		if r == -2:
			if _battle_at(int(e.get("b", -1)), s).is_empty() and (battle.is_empty() or battle["att"] != s):
				_lose_emissary(s)
		elif reg[r]["own"] != s or units_total(r) == 0:
			_lose_emissary(s)


func nobj_met(s: int, i: int, bt := {}) -> bool:
	var kind: String = D.NATION_OBJECTIVES[nat(s)][i]["kind"]
	match kind:
		"start_neigh_all":
			var need := []
			for r in start_regions[s]:
				for a in adj(r):
					if not (a in start_regions[s]) and not (a in need):
						need.append(a)
			if need.is_empty():
				return false
			for a in need:
				if owner(a) != s:
					return false
			return true
		"all_F":
			return reserve[s]["F"] == 0
		"all_K":
			return reserve[s]["K"] == 0
		"tokens_plus2":
			var tk := 0
			var un := 0
			for r in controlled(s):
				if reg[r]["own"] == s and units_total(r) > 0:
					un += 1
				else:
					tk += 1
			return tk >= un + 2
		"near_titan3":
			var k := 0
			for r in controlled(s):
				for a in adj(r):
					var o: int = reg[a]["own"]
					if o >= 0 and o != s and reg[a]["n"]["T"] > 0:
						k += 1
						break
			return k >= 3
	if bt.is_empty() or not bt.has("info"):
		return false
	var info: Dictionary = bt["info"]
	match kind:
		"dice8":
			return (bt["dice"][s] as Array).size() >= 8
		"nc5":
			return (bt["nc_used"][s] as Array).size() >= 5
	if info["winner"] != s:
		return false
	var post: Dictionary = bt["post"][s]
	var tot := 0
	for t in D.UNITS:
		tot += int(post[t])
	match kind:
		"win_only_K":
			return tot > 0 and post["K"] == tot
		"win_only_F":
			return tot > 0 and post["F"] == tot
		"win_only_A":
			return tot > 0 and post["A"] == tot
		"win_no_cards":
			return not bt["sup_any"][s] and (bt["nc_used"][s] as Array).is_empty()
		"win_central":
			return info["r"] == central
		"win_empty_hand":
			return hand[s].is_empty()
		"wipe":
			return bt.get("wiped", false)
		"win_capital":
			return bt.get("cap_region", false)
	return false


func _complete_nobj(s: int, i: int, bt: Dictionary) -> void:
	nobj_hand[s].erase(i)
	nobj_done[s].append(i)
	obj_turn[s] = turn_no
	log_msg("%s completa un Obiettivo Nazione: «%s»" % [pname(s), D.NATION_OBJECTIVES[nat(s)][i]["text"]])
	_fx("objective", {"seat": s, "nobj": i})
	var k: int = nobj_done[s].size()
	if k >= 2:
		_add_vp(s, D.NOBJ_VP[k - 1], "Obiettivo Nazione")
		return
	if emi_pool.is_empty():
		log_msg("Non ci sono più Emissari del Re disponibili.")
		return
	var rs := []
	if not bt.is_empty() and bt.get("winner", -1) == s and reg[bt["r"]]["own"] == s and units_total(bt["r"]) > 0:
		rs = [bt["r"]]
	else:
		for r in regions:
			if reg[r]["own"] == s and units_total(r) > 0:
				rs.append(r)
	if rs.is_empty():
		log_msg("%s non ha Armate a cui affidare un Emissario del Re." % pname(s))
		return
	var opts := []
	for kk in emi_pool:
		opts.append({"label": D.EMISSARIES[kk], "emi": kk})
	var j := await pick(s, "emi_token", "Obiettivo Nazione: scegli un Emissario del Re", opts)
	var key: String = opts[j]["emi"]
	var r: int = rs[0]
	if rs.size() > 1:
		r = await pick_region(s, "emi_region", "A quale Armata affidi l'Emissario (%s)?" % D.EMISSARIES[key], rs, false)
	emi_pool.erase(key)
	emi[s] = {"k": key, "r": r, "on": true}
	log_msg("%s affida l'Emissario del Re «%s» all'Armata in %s." % [pname(s), D.EMISSARIES[key], rname(r)])
	_fx("emissary", {"seat": s})
	changed.emit()


# ---------------------------------------------------------------- Monumenti

func mon_standing(s: int, key: String) -> Dictionary:
	if not exp_mon or s < 0:
		return {}
	for i in 3:
		var m: Dictionary = mon[s][i]
		if m["built"] and not m["gone"] and D.monument(nat(s), i)["key"] == key:
			return m
	return {}


func border_blocked(a: int, b: int) -> bool:
	if not exp_mon:
		return false
	for s in n:
		var m := mon_standing(s, "sofia")
		if not m.is_empty() and ((m["r"] == a and m["r2"] == b) or (m["r"] == b and m["r2"] == a)):
			return true
	return false


func mon_ok_region(s: int, i: int, r: int) -> bool:
	if inactive.has(r) or not (reg[r]["mon"] as Array).is_empty():
		return false
	if reg[r]["cap"] >= 0 or reg[r]["fort"]:
		return false
	if D.monument(nat(s), i).get("no_start", false) and r in start_regions[s]:
		return false
	return true


func mon_regions(s: int, i: int) -> Array:
	var out := []
	var border: bool = D.monument(nat(s), i).get("border", false)
	for r in controlled(s):
		if not mon_ok_region(s, i, r):
			continue
		if border:
			var ok := false
			for a in adj(r):
				if mon_ok_region(s, i, a):
					ok = true
			if not ok:
				continue
		out.append(r)
	return out


func mon_cost(s: int, i: int) -> int:
	return maxi(0, int(D.monument(nat(s), i)["cost"]) - discount(round_no))


func mon_buildable(s: int, after_d: bool) -> Array:
	var out := []
	if not exp_mon or mon_built_turn.get(s, -1) == turn_no:
		return out
	for i in 3:
		if mon[s][i]["built"]:
			continue
		if D.monument(nat(s), i).get("after_d", false) and not after_d:
			continue
		if hand[s].size() < mon_cost(s, i) or mon_regions(s, i).is_empty():
			continue
		out.append(i)
	return out


func mon_turn_options(s: int, after_d: bool) -> Array:
	var out := []
	if not exp_mon:
		return out
	for key in ["town_pol", "town_sve"]:
		var m := mon_standing(s, key)
		if m.is_empty() or mon_used.get("%d_%s" % [s, key], -1) == turn_no or hand[s].is_empty():
			continue
		var r: int = m["r"]
		if reserve[s]["F"] > 0:
			out.append({"label": "Municipio: scarta 1 Carta Supporto e schiera 1 Fanteria in %s" % rname(r), "action": "_mon_F", "key": key, "ok": true})
		if key == "town_pol" and reg[r]["own"] == s and reg[r]["n"]["F"] > 0 and reserve[s]["K"] > 0:
			out.append({"label": "Municipio: scarta 1 Carta Supporto e scambia 1 Fanteria con 1 Cavalleria in %s" % rname(r), "action": "_mon_FK", "key": key, "ok": true})
	if not mon_buildable(s, after_d).is_empty() and (after_d or mon_declined.get(s, -1) != turn_no):
		out.append({"label": "Costruisci un Monumento", "action": "_mon_build", "ok": true})
	return out


func _mon_turn_action(s: int, op: Dictionary) -> void:
	match op["action"]:
		"_mon_build":
			var ok := await _mon_build(s, phase == "reset")
			if not ok:
				mon_declined[s] = turn_no
		"_mon_F", "_mon_FK":
			var key: String = op["key"]
			var m := mon_standing(s, key)
			if m.is_empty():
				return
			mon_used["%d_%s" % [s, key]] = turn_no
			var dc := await pick_cards(s, "discard", "Municipio: scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
			for c in dc:
				discard_support(s, c)
			var r: int = m["r"]
			if op["action"] == "_mon_F":
				reserve[s]["F"] -= 1
				_put(r, s, "F")
				log_msg("Municipio: %s schiera 1 Fanteria in %s." % [pname(s), rname(r)])
				_fx("deploy", {"seat": s, "t": "F", "r": r})
				await _maybe_fire(s, r, "F")
			else:
				_take(r, "F")
				reserve[s]["F"] += 1
				reserve[s]["K"] -= 1
				_put(r, s, "K")
				log_msg("Municipio: %s scambia 1 Fanteria con 1 Cavalleria in %s." % [pname(s), rname(r)])
				_fx("deploy", {"seat": s, "t": "K", "r": r})
	changed.emit()


func _mon_build(s: int, after_d: bool) -> bool:
	var cands := mon_buildable(s, after_d)
	if cands.is_empty():
		return false
	var opts := []
	for i in cands:
		var md := D.monument(nat(s), i)
		opts.append({"label": "%s (costo %d): %s" % [md["name"], mon_cost(s, i), md["text"]], "mon": i, "nation": nat(s)})
	opts.append({"label": "Non costruire", "mon": -1})
	var k := await pick(s, "mon_build", "Costruire un Monumento?", opts)
	var i: int = opts[k]["mon"]
	if i < 0:
		return false
	var md := D.monument(nat(s), i)
	var r := await pick_region(s, "mon_region", "%s: in quale tua Regione?" % md["name"], mon_regions(s, i), true, {"mon": i})
	if r < 0:
		return false
	var r2 := -1
	if md.get("border", false):
		var al := adj(r).filter(func(x): return mon_ok_region(s, i, x))
		r2 = await pick_region(s, "mon_region2", "%s: sul confine con quale Regione?" % md["name"], al, true, {"from": r, "mon": i})
		if r2 < 0:
			return false
	var cost := mon_cost(s, i)
	if cost > 0:
		var pay := await pick_cards(s, "pay", "Scegli %d Carte Supporto da scartare" % cost, hand[s].duplicate(), cost, cost)
		for c in pay:
			discard_support(s, c)
	var m: Dictionary = mon[s][i]
	m["built"] = true
	m["r"] = r
	m["r2"] = r2
	reg[r]["mon"] = [s, i]
	if r2 >= 0:
		reg[r2]["mon"] = [s, i]
	mon_built_turn[s] = turn_no
	if r2 >= 0:
		log_msg("%s costruisce il Monumento %s sul confine fra %s e %s." % [pname(s), md["name"], rname(r), rname(r2)])
	else:
		log_msg("%s costruisce il Monumento %s in %s." % [pname(s), md["name"], rname(r)])
	_fx("monument", {"r": r})
	changed.emit()
	return true


## Un Monumento si perde (per sempre) quando il proprietario perde il controllo della sua Regione.
func _check_monuments() -> void:
	if not exp_mon:
		return
	for s in n:
		for i in 3:
			var m: Dictionary = mon[s][i]
			if m["built"] and not m["gone"] and owner(m["r"]) != s:
				m["gone"] = true
				reg[m["r"]]["mon"] = []
				if m["r2"] >= 0:
					reg[m["r2"]]["mon"] = []
				for c in m["under"]:
					sdiscard.append(c)
				m["under"] = []
				log_msg("%s perde il controllo di %s: il Monumento %s è distrutto." % [pname(s), rname(m["r"]), D.monument(nat(s), i)["name"]])


## Si è preso il controllo di una Regione (Cattedrali di Polonia e Svezia).
func _gained(s: int, r: int) -> void:
	if not exp_mon or s < 0:
		return
	var m := mon_standing(s, "cath_pol")
	if not m.is_empty() and r in adj(m["r"]):
		_add_vp(s, 1, "Cattedrale")
	m = mon_standing(s, "cath_sve")
	if not m.is_empty() and r in adj(m["r"]):
		draw_support(s, 2, true)
		log_msg("Cattedrale: %s pesca 2 Carte Supporto." % pname(s))


func _mon_adj_owned(s: int, m: Dictionary) -> int:
	var k := 0
	for a in adj(m["r"]):
		if owner(a) == s:
			k += 1
	return k


## Monumenti che si applicano da soli una volta per turno (Castello Reale, San Basilio, Giannizzeri).
func _mon_auto(s: int) -> void:
	if not exp_mon:
		return
	for key in ["castle_pol", "basil", "jan"]:
		var m := mon_standing(s, key)
		var uk := "%d_%s" % [s, key]
		if m.is_empty() or mon_used.get(uk, -1) == turn_no:
			continue
		var k := _mon_adj_owned(s, m)
		match key:
			"castle_pol":
				if k <= 2:
					mon_used[uk] = turn_no
					draw_support(s, 1, true)
					log_msg("Castello Reale: %s pesca 1 Carta Supporto." % pname(s))
			"basil":
				if k >= 4:
					mon_used[uk] = turn_no
					draw_support(s, 1, true)
					log_msg("Cattedrale di San Basilio: %s pesca 1 Carta Supporto." % pname(s))
			"jan":
				if k >= 5:
					mon_used[uk] = turn_no
					_add_vp(s, 1, "Tenda dei Giannizzeri")
	changed.emit()


## Movimento facoltativo di 1 Unità dalla Regione del Monumento o da una adiacente (Topkapi, Tre Kronor).
func _mon_move(s: int, m: Dictionary, unit: String, title: String, allow_battle: bool) -> void:
	var srcs := []
	for r in [m["r"]] + adj(m["r"]):
		if reg[r]["own"] != s or (reg[r]["n"][unit] <= 0 if unit != "X" else units_total(r) <= 0):
			continue
		var d := move_targets(s, r)
		if not allow_battle:
			d = d.filter(func(x): return not _enemy_units(s, x))
		if not d.is_empty():
			srcs.append(r)
	if srcs.is_empty():
		return
	var src := await pick_region(s, "mon_move_from", "%s: da quale Regione? (puoi rinunciare)" % title, srcs, true, {"unit": unit})
	if src < 0:
		return
	var ut := unit
	if unit == "X":
		var types := unit_types_in(src)
		ut = types[0]
		if types.size() > 1:
			var o := []
			for u in types:
				o.append({"label": D.UNIT_NAME[u], "unit": u})
			ut = o[await pick(s, "move_type", "Quale Unità muovi?", o)]["unit"]
	var dests := move_targets(s, src)
	if not allow_battle:
		dests = dests.filter(func(x): return not _enemy_units(s, x))
	var dst := await pick_region(s, "mon_move_to", "%s: verso quale Regione?" % title, dests, true, {"from": src, "unit": ut})
	if dst < 0:
		return
	await _move_units(s, src, dst, {ut: 1})


func _mon_after_a(s: int) -> void:
	var m := mon_standing(s, "topkapi")
	if not m.is_empty():
		await _mon_move(s, m, "K", "Palazzo di Topkapi: muovi 1 Cavalleria", true)


func _mon_after_c(s: int) -> void:
	if not exp_mon:
		return
	var m := mon_standing(s, "schon")
	if not m.is_empty():
		var k := 0
		for a in adj(m["r"]):
			var o := owner(a)
			if o >= 0 and o != s:
				k += 1
		if k >= 2:
			_add_vp(s, 1, "Castello di Schönbrunn")
	m = mon_standing(s, "mosque")
	if not m.is_empty():
		var opts := [{"label": "Metti la prima Carta Supporto del mazzo sotto la Moschea (ora %d)" % (m["under"] as Array).size(), "k": "put"}]
		if not (m["under"] as Array).is_empty():
			opts.append({"label": "Prendi le %d Carte Supporto sotto la Moschea" % (m["under"] as Array).size(), "k": "take"})
		var j := 0
		if opts.size() > 1:
			j = await pick(s, "mosque", "Moschea Blu", opts, {"under": (m["under"] as Array).size()})
		if opts[j]["k"] == "put":
			var c := _deck_top()
			if c >= 0:
				m["under"].append(c)
				log_msg("Moschea Blu: %s mette una Carta Supporto sotto il Monumento (%d)." % [pname(s), (m["under"] as Array).size()])
		else:
			hand[s].append_array(m["under"])
			log_msg("Moschea Blu: %s prende %d Carte Supporto." % [pname(s), (m["under"] as Array).size()])
			m["under"] = []
		changed.emit()


func _mon_after_d(s: int) -> void:
	if not exp_mon:
		return
	var m := mon_standing(s, "kronor")
	if not m.is_empty():
		await _mon_move(s, m, "X", "Castello di Tre Kronor: muovi 1 Unità", false)
	while true:
		var opts := mon_turn_options(s, true)
		if opts.is_empty():
			return
		opts.append({"label": "Prosegui", "action": ""})
		var k := await pick(s, "mon_menu", "Monumenti: dopo la Fase D", opts)
		if opts[k]["action"] == "":
			return
		var before: int = mon_built_turn.get(s, -1)
		await _mon_turn_action(s, opts[k])
		if opts[k]["action"] == "_mon_build" and mon_built_turn.get(s, -1) == before:
			return


func _deck_top() -> int:
	if sdeck.is_empty():
		if sdiscard.is_empty():
			return -1
		sdeck = sdiscard
		sdiscard = []
		_shuffle(sdeck)
	return sdeck.pop_front()


## Torre di Spasskaja: le Unità che partono dal Monumento possono proseguire di 1 Regione.
func _move_with_spass(s: int, src: int, dst: int, cnt: Dictionary, no_battle: bool) -> void:
	var m := mon_standing(s, "spass")
	if not m.is_empty() and m["r"] == src and not _enemy_units(s, dst) and owner(dst) in [-1, s] and _battle_at(dst, s).is_empty():
		var d2s := move_targets(s, dst).filter(func(x): return x != src)
		if no_battle:
			d2s = d2s.filter(func(x): return not _enemy_units(s, x))
		if not d2s.is_empty() and await yesno(s, "spass", "Torre di Spasskaja: le Unità proseguono di 1 Regione oltre %s?" % rname(dst), {"from": dst}):
			var d2 := await pick_region(s, "spass_to", "Torre di Spasskaja: verso quale Regione proseguono?", d2s, true, {"from": dst})
			if d2 >= 0:
				await _move_units(s, src, dst, cnt)
				await _move_units(s, dst, d2, cnt)
				return
	await _move_units(s, src, dst, cnt)


## Municipio del Sacro Romano Impero: Carte Nazione in cima al mazzo giocabili gratis in questa Battaglia.
func _mon_nc_cards(s: int) -> Array:
	var out := []
	if not exp_mon or battle.is_empty() or battle["mon_nc"].has(s):
		return out
	var m := mon_standing(s, "town_sri")
	if m.is_empty():
		return out
	var r: int = battle["r"]
	if r != m["r"] and not (r in adj(m["r"])):
		return out
	for ci in ndeck[s].slice(0, 3):
		var c := D.nation_card(nat(s), ci)
		if c["when"] in ["battaglia", "prima"] and req_ok(s, c["req"]) and _effect_possible(s, c["eff"]):
			out.append(ci)
	return out


func _mon_town_sri(s: int) -> void:
	var cands := _mon_nc_cards(s)
	if cands.is_empty():
		return
	var opts := []
	for ci in cands:
		opts.append({"label": D.nation_card_text(nat(s), ci), "card": ci, "nation_card": ci})
	var j := await pick(s, "mon_nc_pick", "Municipio: quale Carta Nazione giochi gratis?", opts, {"battle": true})
	var ci: int = opts[j]["card"]
	battle["mon_nc"][s] = true
	battle["nc_used"][s].append(-100 - ci)
	ndeck[s].erase(ci)
	ndeck[s].append(ci)
	log_msg("Municipio: %s gioca gratis la Carta Nazione %s." % [pname(s), D.nation_card_text(nat(s), ci)])
	await _effect(s, D.nation_card(nat(s), ci)["eff"])


# ---------------------------------------------------------------- Echi del Passato

func _fallen_neg(s: int) -> String:
	if not exp_echo or s < 0 or fallen_card[s] < 0:
		return ""
	return D.FALLEN_CARDS[fallen_card[s]]["neg"]


## Preparazione: ognuno sceglie una carta Unità Caduta (dall'ultimo giocatore, in senso antiorario) e poi
## mette 1 Unità Caduta in una propria Regione con Unità.
func _echo_setup() -> void:
	var face := range(D.FALLEN_CARDS.size())
	_shuffle(face)
	face = face.slice(0, mini(n, face.size()))
	var order := []
	for i in n:
		order.append(posmod(first - 1 - i, n))
	for s in order:
		var opts := []
		for ci in face:
			var c: Dictionary = D.FALLEN_CARDS[ci]
			opts.append({"label": "%s / %s" % [c["gain_text"], c["neg_text"]], "fallen": ci})
		var k := await pick(s, "echo_card", "Echi del Passato: scegli una carta Unità Caduta", opts)
		fallen_card[s] = opts[k]["fallen"]
		face.erase(fallen_card[s])
		log_msg("%s prende la carta Unità Caduta: %s" % [pname(s), D.FALLEN_CARDS[fallen_card[s]]["gain_text"]])
	for s in order:
		await _place_fallen(s, _own_army_regions(s), "Echi del Passato: dove metti la tua Unità Caduta?")
	changed.emit()


func _own_army_regions(s: int) -> Array:
	var out := []
	for r in regions:
		if reg[r]["own"] == s and units_total(r) > 0:
			out.append(r)
	return out


func _place_fallen(s: int, rs: Array, title: String) -> void:
	if rs.is_empty() or fallen_pool <= 0:
		return
	var r: int = rs[0]
	if rs.size() > 1:
		r = await pick_region(s, "fallen_place", title, rs, false)
	reg[r]["fallen"] += 1
	fallen_pool -= 1
	log_msg("%s ottiene 1 Unità Caduta in %s." % [pname(s), rname(r)])
	_fx("deploy", {"seat": s, "t": "F", "r": r})


func _fallen_zero(s: int) -> void:
	if battle.is_empty() or int(battle["fal"].get(s, 0)) <= 0 or battle["fz"].has(s):
		return
	battle["fz"][s] = true
	log_msg("Unità Cadute: %s non ottiene Forza dai Dadi Unità Caduta in questa Battaglia." % pname(s))


## Dopo aver stabilito il vincitore: 1 Unità Caduta eliminata per ogni teschio sui propri dadi.
func _fallen_skulls() -> void:
	if not exp_echo:
		return
	for s in [battle["att"], battle["def"]]:
		var have := int(battle["fal"].get(s, 0))
		if have <= 0:
			continue
		var k := 0
		for d in battle["dice"][s]:
			if d["t"] == "C" and (d.get("sk", false) or _fallen_neg(s) == "all_skull"):
				k += 1
		k = mini(k, have)
		if k <= 0:
			continue
		battle["fal"][s] = have - k
		if s == battle["def"]:
			reg[battle["r"]]["fallen"] -= k
		fallen_pool += k
		log_msg("%s perde %d Unità Cadut%s (teschi sui dadi)." % [pname(s), k, "a" if k == 1 else "e"])


## Dopo l'esito: lo sconfitto può ottenere 1 Unità Caduta, secondo la sua carta.
func _fallen_gain(bt: Dictionary, loser: int) -> void:
	if fallen_card[loser] < 0 or fallen_pool <= 0:
		return
	var winner := other(loser)
	var ok := false
	match D.FALLEN_CARDS[fallen_card[loser]]["gain"]:
		"lost":
			ok = true
		"lost_smaller":
			ok = int(bt["size0"][loser]) < int(bt["size0"][winner])
		"lost_def":
			ok = loser == bt["def"]
		"lost_nofallen":
			ok = int(bt["fal0"][loser]) == 0
		"lost_2sup":
			ok = int(bt["sup_used"][loser]) >= 2
	if not ok:
		return
	var dst: int = bt["retreat_to"].get(loser, -1)
	if loser == bt["def"] and dst < 0 and reg[bt["r"]]["own"] == loser:
		dst = bt["r"]
	if dst >= 0 and reg[dst]["own"] == loser and units_total(dst) > 0:
		await _place_fallen(loser, [dst], "")
		return
	var rs := adj(bt["r"]).filter(func(x): return reg[x]["own"] == loser and units_total(x) > 0)
	await _place_fallen(loser, rs, "Unità Caduta: in quale Regione adiacente con le tue Unità?")


## Le Unità Cadute lasciate sole disertano e tornano nella riserva comune.
func _fix_fallen() -> void:
	# Cosacchi eliminati: tornano nella riserva comune
	for p in n:
		if int(reserve[p].get("Q", 0)) > 0:
			cossack_pool += reserve[p]["Q"]
			reserve[p]["Q"] = 0
	if not exp_echo:
		return
	for r in regions:
		var g: Dictionary = reg[r]
		if g["fallen"] > 0 and (g["own"] < 0 or units_total(r) == 0):
			log_msg("%d Unità Cadut%s rimast%s sol%s in %s disertano." % [g["fallen"], "a" if g["fallen"] == 1 else "e", "a" if g["fallen"] == 1 else "e", "a" if g["fallen"] == 1 else "e", rname(r)])
			fallen_pool += g["fallen"]
			g["fallen"] = 0


# ---------------------------------------------------------------- Campi di Sangue: i Cosacchi

func cos_has(s: int, fx: String) -> bool:
	if not exp_cos or s < 0:
		return false
	for c in cos_up[s]:
		if D.SUPPORT[c].get("cos", "") == fx:
			return true
	return false


func cossacks_on_map(s: int) -> int:
	var k := 0
	for r in regions:
		if reg[r]["own"] == s:
			k += int(reg[r]["n"]["Q"])
	return k


func _cos_move_sources(s: int, exclude := -1) -> Array:
	var out := []
	for r in regions:
		if r != exclude and reg[r]["own"] == s and reg[r]["n"]["Q"] > 0 and not q_stop.has(r) and not move_targets(s, r).is_empty():
			out.append(r)
	return out


## Azioni speciali dei Cosacchi disponibili in questo turno (Fase A).
func cos_actions(s: int) -> Array:
	var out := []
	if not exp_cos or cos_turn.get(s, -1) == turn_no:
		return out
	if not _cos_move_sources(s).is_empty():
		out.append({"label": "Muovi 1 Cosacco di 1 Regione" + (" (2 Cosacchi diversi con il Potenziamento)" if cos_has(s, "move2") else ""), "k": "move"})
	for c in hand[s]:
		var fx: String = D.SUPPORT[c].get("cos", "")
		if fx != "" and fx != "dep" and not cos_has(s, fx):
			out.append({"label": "Potenziamento sotto la Plancia: %s" % D.COSSACK_SHORT[fx], "k": "up", "card": c, "fx": fx})
	if cossacks_on_map(s) == 0 and cossack_pool > 0 and not controlled(s).is_empty():
		for c in hand[s]:
			if D.SUPPORT[c].get("cos", "") == "dep":
				out.append({"label": "Schieramento: scarta questa carta e prendi 1 Cosacco", "k": "dep", "card": c})
				break
	return out


func _cos_special(s: int) -> void:
	var opts := cos_actions(s)
	if opts.is_empty():
		return
	opts.append({"label": "Annulla", "k": ""})
	var k := await pick(s, "cos_action", "Azione speciale dei Cosacchi", opts)
	var op: Dictionary = opts[k]
	if op["k"] == "":
		return
	cos_turn[s] = turn_no
	match op["k"]:
		"move":
			var moved := await _cos_move_one(s, -1)
			if moved >= 0 and cos_has(s, "move2"):
				await _cos_move_one(s, moved)
		"up":
			var c: int = op["card"]
			hand[s].erase(c)
			cos_up[s].append(c)
			log_msg("%s mette una Carta Supporto sotto la Plancia: %s" % [pname(s), D.COSSACK_FX[op["fx"]]])
		"dep":
			discard_support(s, op["card"])
			await _cos_deploy(s, controlled(s))
	changed.emit()


func _cos_move_one(s: int, exclude: int) -> int:
	var srcs := _cos_move_sources(s, exclude)
	if srcs.is_empty():
		return -1
	var src := await pick_region(s, "cos_from", "Muovi 1 Cosacco: da quale Regione?", srcs, true, {"unit": "Q"})
	if src < 0:
		return -1
	var dst := await pick_region(s, "cos_to", "Muovi il Cosacco da %s: verso quale Regione?" % rname(src), move_targets(s, src), true, {"from": src, "unit": "Q"})
	if dst < 0:
		return -1
	await _move_units(s, src, dst, {"Q": 1})
	return dst


func _cos_deploy(s: int, rs: Array) -> void:
	if rs.is_empty() or cossack_pool <= 0:
		return
	var r: int = rs[0]
	if rs.size() > 1:
		r = await pick_region(s, "q_place", "Schieramento dei Cosacchi: in quale tua Regione?", rs, false, {"unit": "Q"})
	_put(r, s, "Q")
	cossack_pool -= 1
	log_msg("%s schiera 1 Cosacco in %s." % [pname(s), rname(r)])
	_fx("deploy", {"seat": s, "t": "Q", "r": r})


func _cos_before_battle() -> void:
	var att: int = battle["att"]
	for s in [att, battle["def"]]:
		if army_count(s, "Q") <= 0:
			continue
		if s == att and cos_has(s, "small") and army_size(s) < army_size(other(s)):
			draw_support(s, 1, true)
			log_msg("Potenziamento dei Cosacchi: %s pesca 1 Carta Supporto." % pname(s))
		if cos_has(s, "drawdisc"):
			draw_support(s, 1, true)
			var dc := await pick_cards(s, "discard", "Potenziamento dei Cosacchi: scarta 1 Carta Supporto", hand[s].duplicate(), 1, 1)
			for c in dc:
				discard_support(s, c)
			log_msg("Potenziamento dei Cosacchi: %s pesca e scarta 1 Carta Supporto." % pname(s))


## Indice di un Dado Cosacco che mostra 1 e può ritirare un altro dado (Potenziamento), oppure -1.
func _cos_reroll_die(s: int) -> int:
	if not exp_cos or battle.is_empty() or not cos_has(s, "reroll"):
		return -1
	var dice: Array = battle["dice"][s]
	if dice.size() < 2:
		return -1
	for i in dice.size():
		if dice[i]["t"] == "Q" and int(dice[i]["v"]) == 1 and not dice[i].get("used", false):
			return i
	return -1


func _cos_after_battle(bt: Dictionary, winner: int) -> void:
	for s in [bt["att"], bt["def"]]:
		var had_q: bool = int(bt["post"][s].get("Q", 0)) > 0
		if had_q and s == winner and cos_has(s, "vp"):
			_add_vp(s, 1, "Potenziamento dei Cosacchi")
		if cos_has(s, "draw2"):
			var k := 0
			for d in bt["dice"][s]:
				if d["t"] == "Q" and int(d["v"]) == 2:
					k += 1
			if k > 0:
				draw_support(s, k, true)
				log_msg("Potenziamento dei Cosacchi: %s pesca %d Carte Supporto." % [pname(s), k])
		# Simbolo dei Cosacchi delle Carte Supporto giocate in questa Battaglia
		var played: Array = (bt["played"][s] as Array).filter(func(c): return c in sdiscard and D.SUPPORT[c].has("cos"))
		if played.is_empty():
			continue
		var many: bool = (bt["played"][s] as Array).size() >= 5
		var dep_left := 1 if not had_q else 0
		var up_left := 2 if many else 1
		while not played.is_empty():
			var opts := []
			if dep_left > 0 and cossack_pool > 0 and not controlled(s).is_empty():
				for c in played:
					if D.SUPPORT[c]["cos"] == "dep":
						opts.append({"label": "Schieramento dei Cosacchi: prendi 1 Cosacco", "k": "dep", "card": c})
						break
			if up_left > 0:
				var seen := {}
				for c in played:
					var fx: String = D.SUPPORT[c]["cos"]
					if fx != "dep" and not cos_has(s, fx) and not seen.has(fx):
						seen[fx] = true
						opts.append({"label": "Potenziamento sotto la Plancia: %s" % D.COSSACK_SHORT[fx], "k": "up", "card": c, "fx": fx})
			if opts.is_empty():
				break
			opts.append({"label": "Nessun effetto", "k": ""})
			var j := await pick(s, "cos_end", "Simbolo dei Cosacchi delle carte giocate in Battaglia", opts)
			var op: Dictionary = opts[j]
			if op["k"] == "":
				break
			played.erase(op["card"])
			if op["k"] == "dep":
				dep_left = 0
				await _cos_deploy(s, controlled(s))
			else:
				sdiscard.erase(op["card"])
				cos_up[s].append(op["card"])
				up_left -= 1
				log_msg("%s mette una Carta Supporto sotto la Plancia: %s" % [pname(s), D.COSSACK_FX[op["fx"]]])
			if not many:
				break
	changed.emit()


# ---------------------------------------------------------------- Spirito di Guerra

func _roll_ws(s: int, p: Dictionary) -> void:
	var face := rng.randi() % 6
	var d := {"t": "W", "v": D.DICE["W"][face], "sym": D.WS_SYMBOL[face], "src": p["kind"], "set": p["n"], "cards": (p["cards"] as Array).duplicate()}
	battle["dice"][s].append(d)
	_fx("roll", {"seat": s, "t": "W", "v": d["v"]})
	if d["sym"]:
		log_msg("%s lancia un Dado Spirito di Guerra: simbolo!" % pname(s))
		await _ws_resolve(s, battle["dice"][s].size() - 1)
	else:
		log_msg("%s lancia un Dado Spirito di Guerra: %d." % [pname(s), d["v"]])
	changed.emit()


## Simboli usciti ritirando un Dado Spirito di Guerra: si risolvono appena possibile.
func _ws_pending(s: int) -> void:
	if battle.is_empty() or not battle["dice"].has(s):
		return
	for i in battle["dice"][s].size():
		var d: Dictionary = battle["dice"][s][i]
		if d["t"] == "W" and d.get("pend", false):
			d["pend"] = false
			await _ws_resolve(s, i)


func _ws_resolve(s: int, i: int) -> void:
	var d: Dictionary = battle["dice"][s][i]
	d["pend"] = false
	d["used"] = true          # il dado resta sulla carta: non si ritira più
	if d.get("src", "dado") == "forza":
		d["v"] = 3 if int(d.get("set", 2)) == 2 else 6
		log_msg("Spirito di Guerra: il simbolo vale +%d Forza per %s." % [d["v"], pname(s)])
		return
	d["v"] = 0
	var effs := []
	for c in d.get("cards", []):
		var e: String = D.SUPPORT[c].get("ws", "")
		if e != "" and not (e in effs):
			effs.append(e)
	if effs.is_empty():
		return
	var eff: String = effs[0]
	if effs.size() > 1:
		var opts := []
		for e in effs:
			opts.append({"label": D.WS_FX[e], "ws": e})
		eff = opts[await pick(s, "ws_effect", "Spirito di Guerra: quale effetto usi?", opts, {"battle": true})]["ws"]
	log_msg("Spirito di Guerra: %s — %s" % [pname(s), D.WS_FX[eff]])
	var o := other(s)
	match eff:
		"move":
			var srcs := _move_in_sources(s, "X")
			var r: int = battle["r"]
			for a in move_adj(r):
				if owner(a) == s:
					for a2 in move_adj(a):
						if a2 != r and reg[a2]["own"] == s and units_total(a2) > 0 and not (a2 in srcs):
							srcs.append(a2)
			if not srcs.is_empty():
				await _move_in(s, "X", srcs)
		"inf":
			if reserve[s]["F"] > 0:
				reserve[s]["F"] -= 1
				if s == battle["att"]:
					battle["u_att"].append({"t": "F", "from": battle["u_att"][0]["from"] if not battle["u_att"].is_empty() else battle["r"]})
				else:
					_put(battle["r"], s, "F")
				_roll_die(s, "F")
		"refresh":
			var opts := []
			for k in nowned[s].size():
				if nowned[s][k]["rot"] or k in battle["nc_used"][s]:
					opts.append({"label": D.nation_card_text(nat(s), nowned[s][k]["i"]), "k": k, "nation_card": nowned[s][k]["i"]})
			if not opts.is_empty():
				var j := await pick(s, "ws_refresh", "Spirito di Guerra: quale Carta Nazione ripristini?", opts, {"battle": true})
				var k: int = opts[j]["k"]
				nowned[s][k]["rot"] = false
				battle["nc_used"][s].erase(k)
		"max":
			for dd in battle["dice"][s]:
				if dd["t"] != "W":
					dd["v"] = (D.DICE[dd["t"]] as Array).max()
		"foe_dice":
			battle["bonus"][s] += (battle["dice"][o] as Array).size()
		"own_dice":
			battle["bonus"][s] += (battle["dice"][s] as Array).size()
	changed.emit()


# ---------------------------------------------------------------- Potere dei Titani

## Si pescano le prime 2 Carte Potere del Titano, se ne tiene 1 e l'altra va in fondo.
func _tp_draw(s: int) -> void:
	var top: Array = tp_deck[s].slice(0, 2)
	if top.is_empty():
		return
	var k := 0
	if top.size() > 1:
		var opts := []
		for ti in top:
			opts.append({"label": D.titan_power_text(nat(s), ti), "tp": ti, "nation": nat(s)})
		k = await pick(s, "tp_choose", "Potere del Titano: quale carta tieni?", opts)
	var keep: int = top[k]
	tp_deck[s].erase(keep)
	tp_owned[s].append(keep)
	if top.size() > 1:
		var other_c: int = top[1 - k]
		tp_deck[s].erase(other_c)
		tp_deck[s].append(other_c)
	log_msg("%s ottiene una Carta Potere del Titano: %s" % [pname(s), D.titan_power_text(nat(s), keep)])
	changed.emit()


## Dadi della riserva che attivano la carta (i più bassi possibile), oppure [] se non si può.
func _tp_dice(s: int, ti: int) -> Array:
	var c: Dictionary = D.TITAN_POWERS[nat(s)][ti]
	var need: int = c["n"]
	var by_t := {}
	var dice: Array = battle["dice"][s]
	for i in dice.size():
		var d: Dictionary = dice[i]
		if d.get("used", false):
			continue
		if not by_t.has(d["t"]):
			by_t[d["t"]] = []
		by_t[d["t"]].append(i)
	for t in by_t:
		(by_t[t] as Array).sort_custom(func(a, b): return int(dice[a]["v"]) < int(dice[b]["v"]))
	if c["eq"]:
		var best := []
		for t in by_t:
			if (by_t[t] as Array).size() >= need:
				var cand: Array = (by_t[t] as Array).slice(0, need)
				if best.is_empty() or _dsum(s, cand) < _dsum(s, best):
					best = cand
		return best
	if by_t.size() < need:
		return []
	var firsts := []
	for t in by_t:
		firsts.append(by_t[t][0])
	firsts.sort_custom(func(a, b): return int(dice[a]["v"]) < int(dice[b]["v"]))
	return firsts.slice(0, need)


func _dsum(s: int, idx: Array) -> int:
	var t := 0
	for i in idx:
		t += int(battle["dice"][s][i]["v"])
	return t


func _tp_use(s: int, ti: int) -> void:
	var idx := _tp_dice(s, ti)
	if idx.is_empty():
		return
	battle["tp_used"][s] = true
	for i in idx:
		battle["dice"][s][i]["used"] = true
	var c: Dictionary = D.TITAN_POWERS[nat(s)][ti]
	log_msg("%s attiva il Potere del Titano: %s" % [pname(s), D.titan_power_text(nat(s), ti)])
	_fx("ncard", {"seat": s, "card": -1})
	var fxs: Array = c["fx"]
	if c.get("alt", false):
		var opts := []
		for f in fxs:
			opts.append({"label": D.titan_power_text(nat(s), ti).split(": ")[1].split(" oppure ")[opts.size()], "fx": f})
		fxs = [opts[await pick(s, "tp_or", "Potere del Titano: scegli l'effetto", opts, {"battle": true})]["fx"]]
	var o := other(s)
	for f in fxs:
		match f[0]:
			"draw":
				draw_support(s, f[1])
			"discard":
				var dc := await pick_cards(s, "discard", "Potere del Titano: scarta %d Carta%s Supporto" % [f[1], "" if f[1] == 1 else "e"], hand[s].duplicate(), mini(f[1], hand[s].size()), f[1])
				for cc in dc:
					discard_support(s, cc)
			"keep":
				var drawn := []
				for i in int(f[1]):
					var cc := _deck_top()
					if cc >= 0:
						drawn.append(cc)
				var kept := await pick_cards(s, "tp_keep", "Potere del Titano: quali %d carte tieni?" % f[2], drawn, mini(f[2], drawn.size()), f[2])
				for cc in drawn:
					if cc in kept:
						hand[s].append(cc)
					else:
						sdiscard.append(cc)
			"weak":
				for i in int(f[1]):
					for t in ["F", "K", "A", "T"]:
						if can_roll(s, t):
							_roll_die(s, t)
							break
			"foe_drop":
				for i in int(f[1]):
					var its := _dice_items(o, false)
					if its.is_empty():
						break
					var sel := await pick_dice(o, "drop_own", "Potere del Titano avversario: scarta 1 tuo Dado", its, 1, 1)
					for it in sel:
						var d: Dictionary = battle["dice"][o][it[1]]
						battle["dice"][o].remove_at(it[1])
						log_msg("%s scarta un Dado %s (%d)." % [pname(o), D.UNIT_NAME.get(d["t"], d["t"]), d["v"]])
			"max":
				await _max_die(s)
			"reroll":
				var its := _dice_items(s)
				if not its.is_empty():
					var sel := await pick_dice(s, "reroll", "Potere del Titano: ritira 1 tuo Dado", its, 1, 1)
					for it in sel:
						_reroll(s, it[1])
			"str":
				battle["bonus"][s] += int(f[1])
	changed.emit()
