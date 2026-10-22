extends SceneTree
## Partite simulate fra IA, senza grafica: controlla che le regole reggano (unità sempre 13 per nazione,
## nessuna regione con due proprietari) e misura i tempi.
## Uso: godot --headless --path . -s tests/sim.gd -- [partite] [giocatori] [livello] [avanzata 0/1]

var errors := 0


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 3
	var np := int(args[1]) if args.size() > 1 else 2
	var lvl := int(args[2]) if args.size() > 2 else 1
	var adv := int(args[3]) == 1 if args.size() > 3 else false
	_run(games, np, lvl, adv)


func _run(games: int, np: int, lvl: int, adv: bool) -> void:
	await process_frame
	var wins := {}
	var t0 := Time.get_ticks_msec()
	var solo := OS.get_environment("TI_SOLO") != ""
	var sc := TIData.solo_scenarios() if solo else TIData.scenarios_for(np)
	var solo_wins := 0
	for g in games:
		var eng := TIEngine.new()
		eng.headless = true
		root.add_child(eng)
		var scn: Dictionary = sc[g % sc.size()]
		var seats := []
		for i in np:
			var code: String = scn["nations"][(i + g / sc.size()) % np] if solo else scn["nations"][i]
			seats.append({"nat": TIData.CODE_TO_NATION[code], "ai": true, "name": TIData.NATIONS[TIData.CODE_TO_NATION[code]]["short"], "level": lvl})
		if solo:
			seats[1]["automa"] = true
			seats[1]["name"] = "Automa"
		var seed := int(OS.get_environment("TI_SEED") if OS.get_environment("TI_SEED") != "" else "100") + g
		eng.setup({"seats": seats, "seed": seed, "scenario": scn["id"], "advanced": adv, "capital_capture": OS.get_environment("TI_CAP") == "1", "extended": OS.get_environment("TI_EXT") == "1", "solo": solo, "automa_adv": OS.get_environment("TI_SOLO") == "2"})
		var tseat := 0 if solo else g % np
		var lvl0 := int(OS.get_environment("TI_LVL0")) if OS.get_environment("TI_LVL0") != "" else lvl
		for i in np:
			eng.ais[i] = TIAI.new(lvl0 if i == tseat else lvl, 77 + g * 10 + i)
			if solo and i == 1:
				eng.ais[i] = TIAutoma.new(99 + g)
				continue
			if i == tseat:
				eng.ais[i].set_exp(OS.get_environment("TI_EXP"))
			else:
				eng.ais[i].set_exp(OS.get_environment("TI_EXP_O"))
		eng.changed.connect(_check.bind(eng))
		if OS.get_environment("TI_LIVE") == "1":
			eng.log_added.connect(func(t): print("  ", t))
		var tg := Time.get_ticks_msec()
		await eng.run()
		if OS.get_environment("TI_LOG") == "1":
			for l in eng.log_lines:
				print("  ", l)
		var line := []
		for r in eng.results:
			line.append("%s %d PV (%d reg.)" % [eng.pname(r["seat"]), r["vp"], r["regions"]])
		var w: String = "test" if eng.results[0]["seat"] == tseat else "altri"
		if solo:
			w = "giocatore" if eng.results[0].get("solo_win", false) else "automa"
			if eng.solo_lost:
				w = "automa (capitale)"
		wins[w] = wins.get(w, 0) + 1
		var bt := 0
		for s in np:
			bt += eng.stats[s]["won"]
		print("partita %d %s (%d ms, %d battaglie, %d turni): %s" % [g, scn["id"], Time.get_ticks_msec() - tg, bt, eng.turn_no, ", ".join(line)])
		eng.queue_free()
	print("vittorie: ", wins, "  errori: ", errors, "  tempo totale %d ms" % (Time.get_ticks_msec() - t0))
	quit(1 if errors > 0 else 0)


func _check(eng: TIEngine) -> void:
	if errors > 20:
		return
	for s in eng.n:
		var k := {"F": 0, "K": 0, "A": 0, "T": 0}
		for r in eng.regions:
			if eng.reg[r]["own"] == s:
				for t in TIData.UNITS:
					k[t] += eng.reg[r]["n"][t]
			elif eng.reg[r]["own"] != s:
				pass
		for b in eng.battles:
			if b["att"] == s:
				for u in b["u"]:
					k[u["t"]] += 1
		if not eng.battle.is_empty() and eng.battle.has("outcome"):
			return
		if not eng.battle.is_empty() and eng.battle["att"] == s and not eng.battle.has("post"):
			for u in eng.battle["u_att"]:
				k[u["t"]] += 1
		for t in ["F", "K", "A"]:
			var tot: int = k[t] + eng.reserve[s][t]
			if tot != TIData.UNIT_COUNT[t] and not (not eng.battle.is_empty() and eng.battle.has("post")):
				errors += 1
				print("ERRORE: %s ha %d %s (turno %d, fase %s)" % [eng.pname(s), tot, t, eng.turn_no, eng.phase])
		var tb: bool = k["T"] > 0
		if tb != (eng.titan[s] == "board") and eng.battle.is_empty():
			errors += 1
			print("ERRORE: Titano di %s: %s ma sul tabellone %d" % [eng.pname(s), eng.titan[s], k["T"]])
	for r in eng.regions:
		var g: Dictionary = eng.reg[r]
		var tot := 0
		for t in TIData.UNITS:
			if g["n"][t] < 0:
				errors += 1
				print("ERRORE: unità negative in ", eng.rname(r))
			tot += g["n"][t]
		if tot > 0 and g["own"] < 0:
			errors += 1
			print("ERRORE: unità senza proprietario in ", eng.rname(r))
		if tot > 0 and g["tok"] >= 0 and g["tok"] != g["own"] and eng.battle.is_empty():
			errors += 1
			print("ERRORE: segnalino di %s e unità di %s in %s" % [eng.pname(g["tok"]), eng.pname(g["own"]), eng.rname(r)])
