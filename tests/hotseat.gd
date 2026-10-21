extends SceneTree
## Screenshot del passaggio di mano fra due giocatori umani sullo stesso dispositivo.
var main
func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()
func _run() -> void:
	for i in 8: await process_frame
	main.start_game({"seats": [{"nat": "sve", "ai": false, "name": "Anna", "level": 1}, {"nat": "rus", "ai": false, "name": "Bruno", "level": 1}], "scenario": "2-2B", "seed": 3, "ai_delay": 0.0})
	var ai := TIAI.new(1, 2)
	var shots := 0
	for k in 3000:
		await process_frame
		var g = main.current
		if is_instance_valid(g.curtain) and shots < 1:
			for i in 4: await process_frame
			root.get_viewport().get_texture().get_image().save_png("/tmp/hot_curtain.png")
			shots += 1
			g.curtain.queue_free()
		if g.pending.is_empty():
			continue
		if g.pending.get("ctx", "") == "buy_start" and shots == 1:
			for i in 4: await process_frame
			root.get_viewport().get_texture().get_image().save_png("/tmp/hot_buy.png")
			shots += 1
		if shots >= 2 and g.engine.phase == "orders":
			for i in 4: await process_frame
			root.get_viewport().get_texture().get_image().save_png("/tmp/hot_orders.png")
			break
		g._provide(ai.decide(g.engine, int(g.pending["seat"]), g.pending))
	quit()
