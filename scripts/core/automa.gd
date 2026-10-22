class_name TIAutoma
extends RefCounted
## L'Automa della Modalità Solitario (Compendio delle Nazioni, pagine 10–15). Le sue azioni nella Fase A le
## esegue il motore seguendo le carte Automa; qui ci sono le scelte che il motore gli chiede durante le
## Battaglie e nelle altre fasi, secondo le priorità del regolamento.
## Le Carte Supporto dell'Automa sono una pila coperta: l'indice 0 della mano è il fondo della pila.

const D = preload("res://scripts/data/ti_data.gd")
const PRIO := {"T": 0, "A": 1, "K": 2, "F": 3}       # dal dado più forte al più debole

var rng := RandomNumberGenerator.new()


func _init(p_seed := 0) -> void:
	rng.seed = p_seed if p_seed != 0 else randi()


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


func _pick(eng, s: int, req: Dictionary) -> int:
	var opts: Array = req["options"]
	match req.get("ctx", ""):
		"battle":
			return _battle(eng, s, opts)
		"before_battle", "after_win", "after_battle":
			# usa le Carte Nazione disponibili
			for i in opts.size():
				if opts[i].get("k", "") == "nc" or int(opts[i].get("card", -1)) >= 0:
					return i
			return opts.size() - 1
		"move_type":
			# l'Unità più forte che aggiunge un dado
			var best := 0
			for i in opts.size():
				var u: String = opts[i]["unit"]
				if eng.can_roll(s, u) and (not eng.can_roll(s, opts[best]["unit"]) or PRIO[u] < PRIO[opts[best]["unit"]]):
					best = i
			return best
		"draw", "reinf_draw":
			return opts.size() - 1        # dalla cima del mazzo
		"battle_order":
			return 0
	return 0


## Fase Battaglia dell'Automa: abilità della Nazione (automatica), Carte Nazione, Carte Supporto
## (Muovi 1 Unità > Aggiungi Forza > Aggiungi un Dado), ritiro dei dadi col risultato più basso.
func _battle(eng, s: int, opts: Array) -> int:
	var bt: Dictionary = eng.battle
	var o: int = eng.other(s)
	var end_i := opts.size() - 1
	# limite di differenza: se gioca per secondo e ha già il massimo vantaggio si ferma
	if bt["done"].has(o):
		var lim := 3 if eng.army_size(o) == 1 else 5
		if eng.strength(s) - eng.strength(o) >= lim:
			return end_i
	for i in opts.size():
		if opts[i]["k"] == "nc":
			return i
	for i in opts.size():
		if opts[i]["k"] == "titan" and _titan_useful(eng, s):
			return i
	for kind in ["muovi", "forza", "dado"]:
		var best := -1
		for i in opts.size():
			if opts[i]["k"] == "sup" and opts[i]["play"]["kind"] == kind:
				if best < 0 or opts[i]["play"]["n"] > opts[best]["play"]["n"]:
					best = i
		if best >= 0:
			return best
	for i in opts.size():
		if opts[i]["k"] == "reroll" and not _lowest(eng, s).is_empty():
			return i
	return end_i


## Indici dei dadi dell'Automa che mostrano il risultato più basso possibile.
func _lowest(eng, s: int) -> Array:
	var out := []
	var dice: Array = eng.battle["dice"][s]
	for i in dice.size():
		var d: Dictionary = dice[i]
		if int(d["v"]) == (D.DICE[d["t"]] as Array).min():
			out.append(i)
	return out


func _titan_useful(eng, s: int) -> bool:
	match eng.nat(s):
		"pol", "rus":
			return not _lowest(eng, s).is_empty()
	return false


## Il dado più forte che mostra il risultato più basso (Titano > Artiglieria > Cavalleria > Fanteria).
func _strongest_low(eng, s: int) -> int:
	var best := -1
	var dice: Array = eng.battle["dice"][s]
	for i in _lowest(eng, s):
		if best < 0 or PRIO[dice[i]["t"]] < PRIO[dice[best]["t"]]:
			best = i
	return best


func _dice(eng, s: int, req: Dictionary) -> Array:
	var items: Array = req["items"]
	match req.get("ctx", ""):
		"reroll":
			var low := _lowest(eng, s)
			var out := []
			for k in items.size():
				if items[k][0] == s and items[k][1] in low:
					out.append(k)
			if out.is_empty() and int(req["min"]) > 0:
				out = [0]
			return out
		"max_die", "titan_reroll":
			var i := _strongest_low(eng, s)
			for k in items.size():
				if items[k][0] == s and items[k][1] == i:
					return [k]
			for k in items.size():
				if items[k][0] == s:
					return [k]
			return [0]
		"drop_dice":
			var idx := range(items.size())
			var bt: Dictionary = eng.battle
			idx.sort_custom(func(a, b): return bt["dice"][items[a][0]][items[a][1]]["v"] < bt["dice"][items[b][0]][items[b][1]]["v"])
			return idx.slice(0, 2)
	return [0]


func _cards(eng, s: int, req: Dictionary) -> Array:
	var items: Array = req["items"]
	var nmin: int = req["min"]
	var idx := range(items.size())
	match req.get("ctx", ""):
		"casualties", "move_out":
			idx.sort_custom(func(a, b): return PRIO[items[a]] > PRIO[items[b]])
			return idx.slice(0, nmin)
		"look_discard", "take_discard":
			return [rng.randi() % items.size()]
	# pagamenti e scarti: dal fondo della pila
	return idx.slice(0, maxi(nmin, 1) if int(req["max"]) > 0 else 0)


func _region(eng, s: int, req: Dictionary) -> int:
	var allowed: Array = req["allowed"]
	match req.get("ctx", ""):
		"retreat":
			return _retreat(eng, s, allowed)
		"move_in":
			var best: int = allowed[0]
			var bp := 9
			for r in allowed:
				for t in D.UNITS:
					if eng.reg[r]["n"][t] > 0 and eng.can_roll(s, t) and PRIO[t] < bp:
						bp = PRIO[t]
						best = r
			return best
	return allowed[0] if not req.get("skip", false) else allowed[0]


## Ritirata del difensore: la Capitale, poi la regione libera controllata più vicina alla Capitale, poi la
## regione controllata più vicina alla Capitale con l'Armata più piccola.
func _retreat(eng, s: int, allowed: Array) -> int:
	var cr: int = eng._capital_region(s)
	if cr in allowed and eng.is_capital_of(cr, s):
		return cr
	var dist: Dictionary = eng._dist_from(cr) if cr > 0 else {}
	var best: int = allowed[0]
	var bk := [99, 99, 99]
	for r in allowed:
		var k := [0 if eng.units_total(r) == 0 else 1, int(dist.get(r, 50)), eng.units_total(r)]
		if k < bk:
			bk = k
			best = r
	return best
