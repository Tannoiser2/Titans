extends SceneTree
## Screenshot automatici dell'interfaccia (serve un display: xvfb-run).
## xvfb-run godot --path . -s res://tests/shot.gd -- <modo> [secondi]

var main
var n := 0


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/shots")
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func shot(name: String) -> void:
	for i in 4:
		await process_frame
	var img := root.get_viewport().get_texture().get_image()
	n += 1
	img.save_png(OS.get_user_data_dir() + "/shots/%02d_%s.png" % [n, name])
	print("shot ", name)


func wait(f := 10) -> void:
	for i in range(f):
		await process_frame


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var mode: String = args[0] if args.size() > 0 else "game"
	await wait(8)
	await shot("menu")
	if mode == "menu":
		quit()
		return
	if mode == "rules":
		main.show_rules()
		await wait(5)
		await shot("regole")
		quit()
		return
	if mode == "solomenu":
		main.current.nplayers = 1
		main.current.scen_id = "S1"
		main.current._refresh_scen()
		main.current._refresh_seats()
		await wait(5)
		await shot("menu_solo")
		quit()
		return
	var scen: String = {"game4": "4-2B", "game5": "5-2", "hre": "I2-1", "solo": "S1"}.get(mode, "2-1A")
	var seats := []
	for c in TIData.scenario(scen)["nations"]:
		var nt: String = TIData.CODE_TO_NATION[c]
		seats.append({"nat": nt, "ai": seats.size() > 0, "name": "Stefano" if seats.is_empty() else TIData.NATIONS[nt]["short"], "level": 1})
	if mode == "solo":
		seats[1]["automa"] = true
		seats[1]["name"] = "Automa"
	main.start_game({"seats": seats, "scenario": scen, "seed": 42, "ai_delay": 0.0, "advanced": mode == "adv", "solo": mode == "solo", "automa_adv": true})
	await wait(30)
	await shot("inizio")
	# risponde con l'IA alle decisioni umane fino a una battaglia
	var ai := TIAI.new(1, 5)
	var steps := 0
	var shots_taken := {}
	while steps < 4000:
		steps += 1
		await process_frame
		var g = main.current
		var req: Dictionary = g.pending
		if req.is_empty():
			continue
		var e: TIEngine = g.engine
		var key := "%s_%s" % [req["type"], req.get("ctx", "")]
		if not shots_taken.has(key) and key in ["pick_order", "region_move_to", "pick_battle", "cards_pay", "pick_buy_start", "pick_objective", "region_deploy", "pick_action"]:
			shots_taken[key] = true
			await shot(key)
		if e.round_no >= 2 and not shots_taken.has("round2"):
			shots_taken["round2"] = true
			await shot("round2")
			break
		g._provide(ai.decide(e, int(req["seat"]), req))
	quit()
