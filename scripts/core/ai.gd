class_name TIAI
extends RefCounted
## Giocatore artificiale di Titans.
## Fase A: per ogni Carta Ordini disponibile simula le azioni in modo goloso su una copia leggera del
## tabellone e valuta la posizione (regioni controllate pesate dai round che restano, minacce nemiche,
## battaglie innescate con la loro probabilità di vittoria). Sceglie la carta col piano migliore e poi
## lo esegue passo per passo rispondendo alle richieste del motore.
## In battaglia calcola quanta Forza serve e spende le risorse più economiche per arrivarci.

const D = preload("res://scripts/data/ti_data.gd")
const EDIE := {"F": 0.667, "K": 1.5, "A": 2.167, "T": 2.0}
const UNIT_VAL := {"F": 1.0, "K": 1.5, "A": 1.8, "T": 3.0}

var level := 1
var exp := ""          # varianti sperimentali (prove con tests/sim.gd)
var w_threat := 0.45
var w_loss := 1.0
var w_units := 0.18
var w_opp := 0.5
var rng := RandomNumberGenerator.new()
var plan: Array = []          # passi del piano della Fase A
var step: Dictionary = {}     # passo in esecuzione


func _init(p_level := 1, p_seed := 0) -> void:
	level = p_level
	rng.seed = p_seed if p_seed != 0 else randi()


func set_exp(e: String) -> void:
	exp = e
	for kv in e.split(",", false):
		var p := kv.split("=")
		if p.size() == 2:
			set(p[0], float(p[1]))


func decide(eng, s: int, req: Dictionary):
	match req["type"]:
		"pick":
			return _pick(eng, s, req)
		"region":
			return _region(eng, s, req)
		"cards":
			return _cards(eng, s, req)
		"dice":
			return _dice(eng, s, req)
	return 0


# ================================================================ valutazioni di base

func noise() -> float:
	return [1.2, 0.35, 0.0][clampi(level, 0, 2)] * rng.randf()


func support_value(card: int) -> float:
	var k: String = D.SUPPORT[card]["kind"]
	return {"forza": 1.0, "dado": 1.05, "muovi": 0.8}[k]


func nation_card_value(eng, s: int, ci: int) -> float:
	var c: Dictionary = D.NATION_CARDS[eng.nat(s)][ci]
	var v: float = {
		"die_T": 2.0, "die_A": 2.0, "die_K": 1.4, "die_F": 0.7, "str_1": 1.0, "str_2": 2.0, "max_die": 1.6,
		"draw": 1.0, "draw_discard": 0.4, "vp": 1.6, "dice2_str3": 1.5, "sup2_titan": 0.6, "foe_discard": 0.9,
		"look_discard": 1.0, "take_discard": 1.0, "move_in": 1.0, "foe_move_out": 1.2, "deploy_F": 2.2,
		"move_F": 0.6, "win_str": 0.8,
	}.get(c["eff"], 1.0)
	if c["freq"] == "battaglia":
		v *= 1.3
	v *= 1.0 - 0.12 * (c["req"] as Array).size()
	return v


## Forza attesa di un'armata (conteggi per tipo) con il limite di dadi.
func army_power(cnt: Dictionary) -> float:
	var p := 0.0
	p += mini(cnt.get("F", 0), 3) * EDIE["F"]
	p += mini(cnt.get("K", 0), 2) * EDIE["K"]
	p += mini(cnt.get("A", 0), 1) * EDIE["A"]
	p += mini(cnt.get("T", 0), 1) * EDIE["T"]
	return p


func cnt_size(cnt: Dictionary) -> int:
	var k := 0
	for t in cnt:
		k += int(cnt[t])
	return k


## Probabilità di vittoria dell'attaccante.
func p_attack(eng, att: int, acnt: Dictionary, dfn: int, dcnt: Dictionary, strong: bool) -> float:
	if cnt_size(dcnt) == 0:
		return 1.0
	var ea: float = army_power(acnt) + 0.75 * mini(eng.hand[att].size(), 4) + 0.5 * eng.nowned[att].size()
	var ed: float = army_power(dcnt) + 0.75 * mini(eng.hand[dfn].size() + (1 if strong else 0), 4) + 0.5 * eng.nowned[dfn].size()
	if strong:
		ed += 0.6
	var x: float = (ea - ed - 0.4) / 2.2
	return 1.0 / (1.0 + exp(-x * 1.7))


# ================================================================ simulazione leggera del tabellone

class Sim:
	var own := {}       # r -> posto con unità (-1)
	var cnt := {}       # r -> {F,K,A,T}
	var tok := {}       # r -> posto
	var cap := {}       # r -> posto della capitale viva
	var fort := {}      # r -> bool
	var reserve := []
	var titan := []
	var battles := []   # {r, att, cnt}
	var hand := []
	var vp_gain := 0.0

	func owner(r: int) -> int:
		if own[r] >= 0 and _size(cnt[r]) > 0:
			return own[r]
		if tok[r] >= 0:
			return tok[r]
		if cap[r] >= 0:
			return cap[r]
		return -1

	func _size(c: Dictionary) -> int:
		return c["F"] + c["K"] + c["A"] + c["T"]

	func dup() -> Sim:
		var o := Sim.new()
		o.own = own.duplicate()
		o.cnt = {}
		for r in cnt:
			o.cnt[r] = cnt[r].duplicate()
		o.tok = tok.duplicate()
		o.cap = cap.duplicate()
		o.fort = fort.duplicate()
		o.reserve = []
		for x in reserve:
			o.reserve.append(x.duplicate())
		o.titan = titan.duplicate()
		o.battles = []
		for b in battles:
			o.battles.append({"r": b["r"], "att": b["att"], "cnt": b["cnt"].duplicate()})
		o.hand = hand.duplicate()
		o.vp_gain = vp_gain
		return o


func make_sim(eng) -> Sim:
	var sm := Sim.new()
	for r in eng.regions:
		var g: Dictionary = eng.reg[r]
		sm.own[r] = g["own"]
		sm.cnt[r] = g["n"].duplicate()
		sm.tok[r] = g["tok"]
		var c: int = g["cap"]
		sm.cap[r] = c if (c >= 0 and eng.capital_alive[c] and g["capctrl"] < 0) else (g["capctrl"] if g["capctrl"] >= 0 else -1)
		sm.fort[r] = g["fort"]
	for s in eng.n:
		sm.reserve.append(eng.reserve[s].duplicate())
		sm.hand.append(eng.hand[s].size())
	sm.titan = eng.titan.duplicate()
	for b in eng.battles:
		var c := {"F": 0, "K": 0, "A": 0, "T": 0}
		for u in b["u"]:
			c[u["t"]] += 1
		sm.battles.append({"r": b["r"], "att": b["att"], "cnt": c})
	return sm


func sim_move(eng, sm: Sim, s: int, src: int, dst: int, cnt: Dictionary) -> void:
	for t in cnt:
		sm.cnt[src][t] -= cnt[t]
	if sm._size(sm.cnt[src]) == 0:
		sm.own[src] = -1
		if sm.cap[src] != s:
			sm.tok[src] = s
	var enemy: bool = sm.own[dst] >= 0 and sm.own[dst] != s and sm._size(sm.cnt[dst]) > 0
	for b in sm.battles:
		if b["r"] == dst and b["att"] == s:
			for t in cnt:
				b["cnt"][t] += cnt[t]
			return
	if enemy:
		var full := {"F": 0, "K": 0, "A": 0, "T": 0}
		for t in cnt:
			full[t] += cnt[t]
		sm.battles.append({"r": dst, "att": s, "cnt": full})
		return
	var o := sm.owner(dst)
	if o >= 0 and o != s:
		if sm.tok[dst] == o:
			sm.tok[dst] = -1
		if sm.cap[dst] >= 0 and sm.cap[dst] != s:
			sm.cap[dst] = -1
			sm.vp_gain += 3.0 if not eng.capital_capture else 0.5
	sm.own[dst] = s
	for t in cnt:
		sm.cnt[dst][t] += cnt[t]
	if sm.tok[dst] == s:
		sm.tok[dst] = -1


func sim_deploy(sm: Sim, s: int, t: String, r: int) -> void:
	if t == "T":
		sm.titan[s] = "board"
	else:
		sm.reserve[s][t] -= 1
	sm.own[r] = s
	sm.cnt[r][t] += 1
	if sm.tok[r] == s:
		sm.tok[r] = -1


## Valore della posizione per il posto s.
func evaluate(eng, sm: Sim, s: int) -> float:
	var rem: float = eng.rounds_total - eng.round_no + 1
	var rv := 0.8 + 0.7 * rem
	var mine := 0.0
	var others := 0.0
	var owners := {}
	for r in sm.own:
		if eng.inactive.has(r):
			continue
		owners[r] = sm.owner(r)
	# battaglie in sospeso: si risolvono a mio favore con la loro probabilità
	var bat_val := 0.0
	var contested := {}
	for b in sm.battles:
		if b["att"] != s:
			continue
		var r: int = b["r"]
		var dfn: int = sm.own[r]
		var strong: bool = sm.fort[r] or sm.cap[r] == dfn
		var p := p_attack(eng, s, b["cnt"], dfn, sm.cnt[r], strong)
		var gain := rv * 2.0 + 1.6 + (1.0 if sm.fort[r] else 0.0) + (3.0 if sm.cap[r] == dfn else 0.0)
		gain += 0.6 * army_power(sm.cnt[r])
		var loss := (1.6 + 0.5 * army_power(b["cnt"])) * w_loss
		bat_val += p * gain - (1.0 - p) * loss
		contested[r] = true
	for r in owners:
		var o: int = owners[r]
		if o < 0 or contested.has(r):
			continue
		var val := rv
		if sm.cap[r] == o:
			val += 1.5
		if o == s:
			mine += val
		else:
			others += val
	# minacce: regioni mie adiacenti a eserciti nemici più forti
	var threat := 0.0
	for r in owners:
		if owners[r] != s or contested.has(r):
			continue
		var my := army_power(sm.cnt[r]) if sm.own[r] == s else 0.0
		if sm.fort[r] or sm.cap[r] == s:
			my += 1.0
		var worst := 0.0
		for a in eng.adj(r):
			var e: int = sm.own[a]
			if e >= 0 and e != s and sm._size(sm.cnt[a]) > 0:
				var ep := army_power(sm.cnt[a])
				worst = maxf(worst, ep)
		if worst > 0.0:
			var x := (worst - my - 0.3) / 2.0
			var pl := 1.0 / (1.0 + exp(-x * 1.7))
			var val := rv + (3.0 if sm.cap[r] == s else 0.0) + (1.0 if sm.fort[r] else 0.0)
			threat += pl * val * w_threat
	# unità sul tabellone (in riserva non servono)
	var units := 0.0
	for r in sm.own:
		if sm.own[r] == s:
			for t in D.UNITS:
				units += sm.cnt[r][t] * UNIT_VAL[t] * w_units
	var opp_w := 1.0 if eng.n == 2 else 0.6
	var nopp: int = maxi(1, eng.n - 1)
	return mine - opp_w * others / nopp * (2.0 if eng.n == 2 else 1.0) * w_opp - threat + bat_val + units + sm.vp_gain


# ================================================================ Fase A: pianificazione

func _sources(eng, sm: Sim, s: int, t: String) -> Array:
	var out := []
	for r in sm.own:
		if eng.inactive.has(r) or sm.own[r] != s:
			continue
		if t == "X":
			if sm._size(sm.cnt[r]) > 0:
				out.append(r)
		elif sm.cnt[r][t] > 0:
			out.append(r)
	return out


func _targets(eng, sm: Sim, s: int, src: int) -> Array:
	var out := []
	for a in eng.adj(src):
		var o := sm.owner(a)
		if o >= 0 and o != s:
			# regola dell'ultima regione
			var k := 0
			for r in sm.own:
				if not eng.inactive.has(r) and sm.owner(r) == o:
					k += 1
			if k <= 1:
				continue
		out.append(a)
	return out


func _candidates(eng, sm: Sim, s: int, a: String) -> Array:
	var out := []
	match a:
		"mF", "mK", "mA", "mT", "mX":
			var t := a.substr(1)
			for src in _sources(eng, sm, s, t):
				var types := [t] if t != "X" else D.UNITS.filter(func(u): return sm.cnt[src][u] > 0)
				for u in types:
					for dst in _targets(eng, sm, s, src):
						out.append({"a": a, "src": src, "dst": dst, "cnt": {u: 1}, "unit": u})
		"army":
			for src in _sources(eng, sm, s, "X"):
				var c: Dictionary = sm.cnt[src]
				var all := _take_best(c, 4)
				var opts := [all]
				var tot := sm._size(c)
				if tot >= 2:
					opts.append(_take_best(c, mini(4, tot - 1)))
				if tot >= 3:
					opts.append(_take_best(c, 2))
				for dst in _targets(eng, sm, s, src):
					for cc in opts:
						if cnt_size(cc) > 0:
							out.append({"a": a, "src": src, "dst": dst, "cnt": cc})
		"dF", "dK", "dA", "dX":
			var t := a.substr(1)
			var types := ["F", "K", "A", "T"] if t == "X" else [t]
			for u in types:
				var ok: bool = (sm.titan[s] != "board") if u == "T" else sm.reserve[s][u] > 0
				if not ok:
					continue
				for r in sm.own:
					if not eng.inactive.has(r) and sm.owner(r) == s:
						out.append({"a": a, "dst": r, "unit": u})
		"fort":
			if eng.fortresses_left > 0:
				for r in sm.own:
					if not eng.inactive.has(r) and sm.owner(r) == s and not sm.fort[r]:
						out.append({"a": a, "dst": r})
		"buy", "buy1":
			out.append({"a": a})
	return out


func _take_best(c: Dictionary, k: int) -> Dictionary:
	var out := {"F": 0, "K": 0, "A": 0, "T": 0}
	var left := k
	for t in ["T", "A", "K", "F"]:
		var m: int = mini(left, c[t])
		out[t] = m
		left -= m
	return out


func _apply_cand(eng, sm: Sim, s: int, cd: Dictionary) -> void:
	match cd["a"]:
		"mF", "mK", "mA", "mT", "mX", "army":
			sim_move(eng, sm, s, cd["src"], cd["dst"], cd["cnt"])
		"dF", "dK", "dA", "dX":
			sim_deploy(sm, s, cd["unit"], cd["dst"])
		"fort":
			sm.fort[cd["dst"]] = true


func _buy_value(eng, s: int, extra: int) -> float:
	var best := 0.0
	var disc: int = extra + eng.discount(eng.round_no)
	for ci in eng.ndeck[s].slice(0, 3):
		var cost: int = maxi(0, int(D.NATION_CARDS[eng.nat(s)][ci]["cost"]) - disc)
		if cost > eng.hand[s].size():
			continue
		var v: float = nation_card_value(eng, s, ci) * (eng.rounds_total - eng.round_no + 1) * 0.55 - cost * 0.9
		best = maxf(best, v)
	return best


## Piano per una carta Ordini: [punteggio, passi]. «Difficile» esplora le combinazioni migliori
## (ordine delle azioni compreso), gli altri livelli scelgono un'azione alla volta.
func plan_card(eng, s: int, card: int) -> Array:
	if level >= 2 or exp.contains("beam"):
		var acts: Array = (eng.odeck_src[card]["a"] as Array).duplicate()
		var sm := make_sim(eng)
		var base := evaluate(eng, sm, s)
		var r := _beam(eng, s, sm, base, acts, 4)
		return r
	return _plan_greedy(eng, s, card)


func _beam(eng, s: int, sm: Sim, base: float, acts: Array, k: int) -> Array:
	if acts.is_empty():
		return [0.0, []]
	var cands := []
	for a in acts:
		if a == "buy" or a == "buy1":
			var bv := _buy_value(eng, s, 1 if a == "buy1" else 0)
			if bv > 0.05:
				cands.append([bv, {"a": a}, null, base])
			continue
		for cd in _candidates(eng, sm, s, a):
			var sm2 := sm.dup()
			_apply_cand(eng, sm2, s, cd)
			var e2 := evaluate(eng, sm2, s)
			cands.append([e2 - base, cd, sm2, e2])
	if cands.is_empty():
		return [0.0, []]
	cands.sort_custom(func(x, y): return x[0] > y[0])
	var best := [0.0, []]
	for i in mini(k, cands.size()):
		var c: Array = cands[i]
		if c[0] <= 0.05 and i > 0:
			break
		var rest := acts.duplicate()
		rest.erase(c[1]["a"])
		var sub: Array
		if c[2] == null:
			sub = _beam(eng, s, sm, base, rest, maxi(2, k - 1))
		else:
			sub = _beam(eng, s, c[2], c[3], rest, maxi(2, k - 1))
		var tot: float = maxf(0.0, c[0]) + sub[0]
		if c[0] > 0.05 and tot > best[0]:
			best = [tot, [c[1]] + sub[1]]
	return best


func _plan_greedy(eng, s: int, card: int) -> Array:
	var acts: Array = (eng.odeck_src[card]["a"] as Array).duplicate()
	var sm := make_sim(eng)
	var base := evaluate(eng, sm, s)
	var steps := []
	var total := 0.0
	while not acts.is_empty():
		var best_v := 0.05
		var best_c := {}
		for a in acts:
			if a == "buy" or a == "buy1":
				var bv := _buy_value(eng, s, 1 if a == "buy1" else 0)
				if bv > best_v:
					best_v = bv
					best_c = {"a": a}
				continue
			for cd in _candidates(eng, sm, s, a):
				var sm2 := sm.dup()
				_apply_cand(eng, sm2, s, cd)
				var v := evaluate(eng, sm2, s) - base + noise() * 0.6
				if v > best_v:
					best_v = v
					best_c = cd
		if best_c.is_empty():
			break
		if best_c["a"] != "buy" and best_c["a"] != "buy1":
			_apply_cand(eng, sm, s, best_c)
			base = evaluate(eng, sm, s)
		total += best_v
		steps.append(best_c)
		acts.erase(best_c["a"])
	return [total, steps]


# ================================================================ scelte

func _pick(eng, s: int, req: Dictionary) -> int:
	var opts: Array = req["options"]
	var ctx: String = req.get("ctx", "")
	match ctx:
		"order":
			var best := 0
			var bv := -1e9
			var best_plan := []
			for i in opts.size():
				var r := plan_card(eng, s, opts[i]["order"])
				var v: float = r[0] + noise()
				if v > bv:
					bv = v
					best = i
					best_plan = r[1]
			plan = best_plan
			step = {}
			return best
		"action":
			if plan.is_empty():
				return opts.size() - 1
			var nxt: Dictionary = plan[0]
			for i in opts.size():
				if opts[i]["action"] == nxt["a"] and opts[i].get("ok", false):
					step = plan.pop_front()
					return i
			plan.pop_front()
			return _pick(eng, s, req)
		"buy_start", "buy", "reinf_buy":
			return _pick_buy(eng, s, opts, ctx)
		"bottom":
			var worst := opts.size() - 1
			var wv := 1.2
			for i in opts.size():
				if opts[i]["card"] >= 0:
					var v := nation_card_value(eng, s, opts[i]["card"]) - 0.25 * int(D.NATION_CARDS[eng.nat(s)][opts[i]["card"]]["cost"])
					if v < wv:
						wv = v
						worst = i
			return worst
		"objective":
			var best := 0
			var bv := -1e9
			for i in opts.size():
				var v := objective_ease(eng, s, opts[i]["obj"]) + noise() * 0.3
				if v > bv:
					bv = v
					best = i
			return best
		"move_type":
			if step.has("unit"):
				for i in opts.size():
					if opts[i]["unit"] == step["unit"]:
						return i
			return 0
		"deploy_type":
			if step.has("unit"):
				for i in opts.size():
					if opts[i]["unit"] == step["unit"]:
						return i
			return 0
		"battle_order":
			return 0
		"draw", "reinf_draw":
			for i in opts.size():
				if opts[i]["card"] >= 0 and D.SUPPORT[opts[i]["card"]]["kind"] == "forza":
					return i
			return opts.size() - 1
		"take_faceup":
			return 0
		"reinf1":
			if eng.hand[s].size() <= 3 or eng.obj_hand[s].size() >= 3:
				return 0
			return 1 if eng.round_no < eng.rounds_total - 1 or eng.obj_hand[s].size() <= 1 else 0
		"reinf2":
			var bv := _buy_value(eng, s, 0)
			if opts[0]["k"] == "buy" and bv > 0.6:
				return 0
			for i in opts.size():
				if opts[i]["k"] == "unit":
					return i
			return 0 if bv > 0.0 else opts.size() - 1
		"swap":
			return 0
		"titan_move":
			return 0
		"nc_turn_a":
			return 0
		"nc_after_d":
			return 1
		"before_battle":
			return _before_battle(eng, s, opts)
		"battle":
			return _battle(eng, s, opts)
		"after_win", "after_battle":
			return 0
	# sì/no generici: sì
	if opts.size() == 2 and opts[1].get("label", "") == "Sì":
		return 1
	return 0


func _pick_buy(eng, s: int, opts: Array, ctx: String) -> int:
	var best := opts.size() - 1
	var bv := 0.15 if ctx != "buy_start" else -0.3
	var rem: float = eng.rounds_total - eng.round_no + 1
	for i in opts.size():
		var o: Dictionary = opts[i]
		if o["card"] < 0 or not o.get("ok", false):
			continue
		var v: float = nation_card_value(eng, s, o["card"]) * rem * 0.55 - int(o["cost"]) * 0.9 + noise() * 0.3
		if v > bv:
			bv = v
			best = i
	return best


func objective_ease(eng, s: int, o: int) -> float:
	var od: Dictionary = D.OBJECTIVES[o]
	var e := 0.5
	match od["kind"]:
		"units_on_board":
			e = 0.9 if eng.units_on_board(s) >= 9 else 0.5
		"regions":
			e = clampf(float(eng.controlled(s).size()) / float(od["n"][clampi(eng.n - 2, 0, 2)]), 0.0, 1.0)
		"two_battles", "win_central", "att_smaller_win", "def_smaller_win", "win_diff":
			e = 0.6
		"token_regions":
			e = 0.65
		"only_type_regions":
			e = 0.6 if od["u"] == "F" else 0.55
		"win_no_support":
			e = 0.55
		"nation_cards_battle", "support_cards_battle", "win_foe_2nc":
			e = 0.3
		"win_only_titan", "win_no_titan_vs_titan", "win_vs_titan_central":
			e = 0.35
		"enemy_start", "enemy_start_neigh":
			e = 0.4
		"central_and_neigh", "central_one_unit":
			e = 0.4
		"two_big_armies":
			e = 0.5
	return e * float(od["vp"]) + 0.2 * e


func _region(eng, s: int, req: Dictionary) -> int:
	var allowed: Array = req["allowed"]
	var ctx: String = req.get("ctx", "")
	match ctx:
		"move_from":
			if step.has("src") and step["src"] in allowed:
				return step["src"]
			return -1 if req.get("skip", false) else allowed[0]
		"move_to":
			if step.has("dst") and step["dst"] in allowed:
				return step["dst"]
			return -1 if req.get("skip", false) else _best_simple_target(eng, s, allowed)
		"deploy", "fort":
			if step.has("dst") and step["dst"] in allowed:
				return step["dst"]
			return _best_deploy(eng, s, allowed, req.get("unit", "F"))
		"titan_deploy":
			return _best_deploy(eng, s, allowed, "T")
		"retreat":
			var best: int = allowed[0]
			var bv := -1e9
			for r in allowed:
				var v := float(eng.units_total(r)) + (2.0 if eng.reg[r]["fort"] else 0.0) + (3.0 if eng.is_capital_of(r, s) else 0.0)
				if v > bv:
					bv = v
					best = r
			return best
		"move_in":
			var best: int = allowed[0]
			var bv := -1e9
			for r in allowed:
				var v := 0.0
				for t in D.UNITS:
					if eng.reg[r]["n"][t] > 0:
						v = maxf(v, EDIE[t])
				v -= 0.3 * float(eng.units_total(r) == 1)
				if v > bv:
					bv = v
					best = r
			return best
		"move_out_to":
			return allowed[0]
	return allowed[0] if not req.get("skip", false) else allowed[0]


func _best_simple_target(eng, s: int, allowed: Array) -> int:
	for r in allowed:
		if eng.owner(r) == -1:
			return r
	return allowed[0]


func _best_deploy(eng, s: int, allowed: Array, u: String) -> int:
	var sm := make_sim(eng)
	var best: int = allowed[0]
	var bv := -1e9
	for r in allowed:
		var sm2 := sm.dup()
		if u == "T" or u == "F" or u == "K" or u == "A":
			sm2.own[r] = s
			sm2.cnt[r][u] += 1
			if sm2.tok[r] == s:
				sm2.tok[r] = -1
		else:
			sm2.fort[r] = true
		var v := evaluate(eng, sm2, s)
		# un'unità è più utile sul fronte
		for a in eng.adj(r):
			var o: int = eng.owner(a)
			if o >= 0 and o != s:
				v += 0.25
		if v > bv:
			bv = v
			best = r
	return best


func _cards(eng, s: int, req: Dictionary) -> Array:
	var items: Array = req["items"]
	var nmin: int = req["min"]
	var nmax: int = req["max"]
	var ctx: String = req.get("ctx", "")
	var idx := range(items.size())
	match ctx:
		"army_units":
			var want: Dictionary = step.get("cnt", {})
			var out := []
			var left := want.duplicate()
			for i in items.size():
				var u: String = items[i]
				if left.get(u, 0) > 0:
					out.append(i)
					left[u] -= 1
			if out.is_empty():
				out = [0]
			return out
		"casualties", "move_out":
			# si perdono prima le unità meno preziose
			idx.sort_custom(func(a, b): return UNIT_VAL[items[a]] < UNIT_VAL[items[b]])
			return idx.slice(0, nmin)
		"look_discard", "take_discard":
			idx.sort_custom(func(a, b): return support_value(items[a]) > support_value(items[b]))
			return idx.slice(0, maxi(nmin, 1))
		_:
			# scarti e pagamenti: le carte meno utili ora
			var ks := []
			for i in items.size():
				ks.append(_keep_score(eng, s, items[i]))
			idx.sort_custom(func(a, b): return ks[a] < ks[b] or (ks[a] == ks[b] and a < b))
			return idx.slice(0, nmin)


func _keep_score(eng, s: int, card) -> float:
	if not (card is int):
		return 0.0
	var v := support_value(card)
	if not eng.battle.is_empty() and (s == eng.battle["att"] or s == eng.battle["def"]):
		if not eng.support_req_ok(s, card):
			v -= 0.5
	return v + rng.randf() * 0.05 * float(level == 0)


func _dice(eng, s: int, req: Dictionary) -> Array:
	var items: Array = req["items"]
	var ctx: String = req.get("ctx", "")
	var bt: Dictionary = eng.battle
	var val := func(it) -> float:
		var d: Dictionary = bt["dice"][it[0]][it[1]]
		return float(d["v"]) - EDIE[d["t"]]
	match ctx:
		"reroll":
			var out := []
			for i in items.size():
				if val.call(items[i]) < -0.2:
					out.append(i)
			if out.is_empty():
				var worst := 0
				for i in items.size():
					if val.call(items[i]) < val.call(items[worst]):
						worst = i
				out = [worst]
			return out
		"max_die":
			var best := 0
			var bg := -1e9
			for i in items.size():
				var d: Dictionary = bt["dice"][items[i][0]][items[i][1]]
				var g := float((D.DICE[d["t"]] as Array).max() - int(d["v"]))
				if g > bg:
					bg = g
					best = i
			return [best]
		"drop_dice":
			var idx := range(items.size())
			idx.sort_custom(func(a, b): return bt["dice"][items[a][0]][items[a][1]]["v"] < bt["dice"][items[b][0]][items[b][1]]["v"])
			return idx.slice(0, 2)
		"titan_reroll":
			var best := 0
			var bg := -1e9
			for i in items.size():
				var it: Array = items[i]
				var d: Dictionary = bt["dice"][it[0]][it[1]]
				var g: float = (EDIE[d["t"]] - float(d["v"])) if it[0] == s else (float(d["v"]) - EDIE[d["t"]])
				if g > bg:
					bg = g
					best = i
			return [best]
	return [0]


# ================================================================ battaglia

## Forza che serve per vincere ora: l'attaccante deve superare, al difensore basta pareggiare.
func _need(eng, s: int) -> int:
	var o: int = eng.other(s)
	var target: int = eng.strength(o) + (1 if s == eng.battle["att"] else 0)
	if not eng.battle["done"].has(o):
		# l'avversario risponderà: margine in base alle sue risorse
		var pot: float = 0.8 * mini(eng.hand[o].size(), 4) + 0.6 * eng.usable_nation_cards(o, "battaglia").size()
		target += int(round(pot * (0.55 if level >= 1 else 0.35)))
	return target


func _battle(eng, s: int, opts: Array) -> int:
	var cur: int = eng.strength(s)
	var need := _need(eng, s)
	var end_i := opts.size() - 1
	var gap := need - cur
	# le carte Nazione «una volta per battaglia» non costano nulla: si usano sempre se aiutano
	var best := -1
	var best_score := 0.0
	var reach := 0.0
	for i in opts.size():
		var o: Dictionary = opts[i]
		var g := _gain(eng, s, o)
		reach += maxf(0.0, g["gain"])
		if g["gain"] <= 0.05:
			continue
		var sc: float = g["gain"] / maxf(0.25, g["cost"])
		if o["k"] == "nc" and g["cost"] < 0.3:
			sc += 10.0
		if sc > best_score:
			best_score = sc
			best = i
	if gap <= 0:
		# già davanti: si usano solo le risorse gratuite
		if best >= 0 and opts[best]["k"] == "nc" and _gain(eng, s, opts[best])["cost"] < 0.3 and s == eng.battle["first"]:
			return best
		return end_i
	if best < 0:
		return end_i
	# se anche spendendo tutto non si arriva, si evita di sprecare carte (salvo ridurre le perdite)
	if reach + 0.5 < gap and eng.battle["done"].has(eng.other(s)):
		var diff: int = need - cur
		if diff >= 5 and diff - reach < 5:
			return best
		if diff >= 3 and diff - reach < 3:
			return best
		if opts[best]["k"] == "nc" and _gain(eng, s, opts[best])["cost"] < 0.3:
			return best
		return end_i
	return best


func _gain(eng, s: int, o: Dictionary) -> Dictionary:
	var bt: Dictionary = eng.battle
	match o["k"]:
		"sup":
			var p: Dictionary = o["play"]
			var c: float = p["n"] * 1.0
			match p["kind"]:
				"forza": return {"gain": float([0, 1, 3, 5][p["n"]]), "cost": c}
				"dado": return {"gain": EDIE["F"] if p["n"] == 1 else EDIE["T"], "cost": c}
				"muovi": return {"gain": 1.3, "cost": c + 0.4}
		"reroll":
			var g := 0.0
			for d in bt["dice"][s]:
				g += maxf(0.0, EDIE[d["t"]] - float(d["v"]))
			return {"gain": g * 0.9, "cost": 1.0}
		"nc":
			var ci: int = o["nation_card"]
			var c: Dictionary = D.NATION_CARDS[eng.nat(s)][ci]
			var cost := 0.25 if c["freq"] == "round" else 0.05
			var g := 0.0
			match c["eff"]:
				"die_F": g = EDIE["F"]
				"die_K": g = EDIE["K"]
				"die_A": g = EDIE["A"]
				"die_T": g = EDIE["T"]
				"str_1": g = 1.0
				"str_2": g = 2.0
				"max_die":
					for d in bt["dice"][s]:
						g = maxf(g, float((D.DICE[d["t"]] as Array).max() - int(d["v"])))
				"dice2_str3":
					var vals := []
					for d in bt["dice"][s]:
						vals.append(int(d["v"]))
					vals.sort()
					g = 3.0 - float(vals[0] + vals[1]) if vals.size() >= 2 else 0.0
				"sup2_titan":
					g = EDIE["T"]
					cost = 2.0
				"draw":
					g = 0.6
				"foe_discard", "look_discard":
					g = 0.7 if not bt["done"].has(eng.other(s)) else 0.0
				"move_in":
					g = 1.2
					cost = 1.0
				"foe_move_out":
					g = 1.0
				_:
					g = 0.3
			return {"gain": g, "cost": cost}
		"titan":
			if eng.nat(s) == "pol":
				var g := 0.0
				for d in bt["dice"][s]:
					g = maxf(g, float((D.DICE[d["t"]] as Array).max() - int(d["v"])))
				return {"gain": g, "cost": 1.0}
			var g2 := 0.0
			for d in bt["dice"][s]:
				g2 = maxf(g2, EDIE[d["t"]] - float(d["v"]))
			for d in bt["dice"][eng.other(s)]:
				g2 = maxf(g2, float(d["v"]) - EDIE[d["t"]])
			return {"gain": g2, "cost": 0.05}
		"adv_reroll":
			var g := 0.0
			for d in bt["dice"][s]:
				g += maxf(0.0, EDIE[d["t"]] - float(d["v"]))
			return {"gain": g * 0.9, "cost": 1.2}
		"adv_draw2":
			return {"gain": 1.2, "cost": 1.5}
		"adv_take":
			return {"gain": 0.8, "cost": 1.2}
	return {"gain": 0.0, "cost": 1.0}


func _before_battle(eng, s: int, opts: Array) -> int:
	for i in opts.size():
		var k: String = opts[i]["k"]
		if k == "nc" or k == "cav_in" or k == "titan_in":
			return i
		if k == "foe_rand" and eng.hand[eng.other(s)].size() >= 2:
			return i
	return opts.size() - 1
