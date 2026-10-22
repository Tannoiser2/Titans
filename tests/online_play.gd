extends SceneTree
## Prova del gioco online: due istanze di Titans (chi crea la stanza e un amico) giocano una partita
## intera a 3 nazioni sul finto Firebase (tests/firebase_mock.py); la terza nazione la gioca l'IA.
## TI_ROLE=host|guest, TI_CODEFILE=file per il codice della stanza.
## TI_PHASE=drop: l'ospite esce a metà (per provare il rientro con TI_PHASE=back).
## Alla fine ognuno stampa l'impronta della partita: devono coincidere.

var main
var t0 := 0
var ai := TIAI.new(1, 9)

func _init() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	t0 = Time.get_ticks_msec()
	_run()

func _wait(s: float) -> void:
	await create_timer(s).timeout

func _run() -> void:
	await _wait(0.5)
	var role := OS.get_environment("TI_ROLE")
	var cf := OS.get_environment("TI_CODEFILE")
	var phase := OS.get_environment("TI_PHASE")
	var menu = main.current
	menu.nplayers = 3
	menu.scen_id = "3-1A"
	menu.modes = {"pol": 0, "sve": 0, "ott": 2, "rus": 2}
	menu.speed = 3
	if OS.get_environment("TI_XP") != "":
		menu.xp = {"monuments": true, "emissaries": true, "fire": true, "echoes": true}
	menu._online_panel()
	menu.on_name.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		await menu._online_create()
		var code: String = main.lobby.get("code", "")
		print("TITEST stanza ", code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await main.net.room(code)
			if Net._as_dict(room.get("seats", {})).size() >= 2:
				break
			await _wait(0.5)
		await menu._online_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		menu.on_code.text = code
		await menu._online_join()
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 900000:
			print("TITEST tempo scaduto")
			quit(2)
			return
		var view = main.current
		if view == null or not ("engine" in view) or view.engine == null:
			continue
		var e: TIEngine = view.engine
		var req: Dictionary = view.pending
		if not req.is_empty() and view.online._mine_pending:
			view._provide(ai.decide(e, req["seat"], req))
		if phase == "drop" and e.round_no >= 2:
			print("TITEST esco a metà partita, mossa ", view.online.n)
			quit(0)
			return
		if e.game_over:
			await _wait(0.5)
			print("TITEST impronta ", view.online.n, " | ", e.fingerprint())
			quit(0)
			return
