extends Node
## Стресс-тест отрисовки: расставляет N зданий по уровню и замеряет время кадра на разных масштабах.
## Запуск: godot --path D:/Mind res://core/game.tscn -- --level=rift --stress=5000

var _count: int = 5000


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stress="):
			_count = arg.substr("--stress=".length()).to_int()
	_run(get_parent() as Game)


func _run(game: Game) -> void:
	await get_tree().process_frame
	# Кадр не ограничиваем вертикальной синхронизацией, чтобы видеть реальную стоимость.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0

	var bm := game.world.buildings
	var grid := game.world.grid
	var defs: Array[BuildingDef] = [
		Registry.get_building(&"conveyor"), Registry.get_building(&"conveyor"), Registry.get_building(&"conveyor"),
		Registry.get_building(&"router"), Registry.get_building(&"drill"), Registry.get_building(&"furnace"),
	]
	var t0 := Time.get_ticks_usec()
	var placed := 0
	var i := 0
	for y in range(2, grid.height - 3, 2):
		for x in range(2, grid.width - 3, 2):
			if placed >= _count:
				break
			var def := defs[i % defs.size()]
			i += 1
			if bm.place(def, Vector2i(x, y), i % 4) != null:
				placed += 1
	var place_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("stress: поставлено %d зданий за %.1f мс" % [placed, place_ms])
	# Заполняем ленты предметами, чтобы нагрузить и симуляцию, и отрисовку предметов.
	var sys := game.world.simulation.conveyors
	for c in sys.count:
		for s in ConveyorSystem.CAP:
			sys.call("_insert", c, s % Registry.items.size(), ConveyorSystem.UNITS - (s + 1) * ConveyorSystem.SPACE + 120, 0.0, 0)
	print("stress: предметов на лентах %d" % sys.get_item_count())

	var center := grid.get_pixel_size() * 0.5
	for zoom in [1.0, 0.5, 0.31, 0.2, 0.1]:
		game.camera.focus_on(center, zoom)
		# Даём дозаполниться чанкам тайлов и перерисоваться чанкам зданий.
		for f in 90:
			await get_tree().process_frame
		var start := Time.get_ticks_usec()
		var last := start
		var worst := 0
		for f in 180:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			worst = maxi(worst, now - last)
			last = now
		print("stress: масштаб %.2f — средний кадр %.2f мс (%.0f FPS), худший %.2f мс, draw calls %d, предметов в кадре %d, тик %.2f мс" % [
			zoom, (last - start) / 180000.0, 180000000.0 / (last - start), worst / 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			game.item_renderer.drawn_count, game.world.simulation.avg_tick_usec / 1000.0])
	get_tree().quit()
