extends Node
## Стресс отрисовки турелей: N турелей на экране, замер кадра в покое, в полёте камеры и в бою.
## Запуск: godot --path D:/Mind res://core/game.tscn -- --level=rift --stress-turrets=400
## Кадр меряется без вертикальной синхронизации, чтобы видеть настоящую стоимость.

var _count: int = 400


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stress-turrets="):
			_count = arg.substr("--stress-turrets=".length()).to_int()
	_run(get_parent() as Game)


func _run(game: Game) -> void:
	await get_tree().process_frame
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var world := game.world
	var run := game.run
	# Угрозу откладываем: враги нужны только в своей части замера.
	if world.threat != null:
		world.threat.delay_next_wave(100000000)
	var gun := Registry.get_building(&"machine_gun") as TurretDef
	var ammo := Registry.get_item(&"cartridge_iron").index
	var center := world.drone.get_tile()
	# Квадрат турелей через тайл вокруг дрона — все помещаются на экран при обычном масштабе.
	var side := ceili(sqrt(float(_count)))
	var placed := 0
	for gy in side:
		for gx in side:
			if placed >= _count:
				break
			var tile := center + Vector2i((gx - side / 2) * 2, (gy - side / 2) * 2 + 8)
			var turret := world.buildings.place(gun, tile, 0, true) as Turret
			if turret == null:
				continue
			for k in 4:
				turret.handle_item(null, ammo)
			placed += 1
	print("stress-turrets: поставлено %d турелей" % placed)
	game.camera.focus_on(Vector2(center + Vector2i(0, 8)) * GameConst.TILE_SIZE, 0.6)
	for f in 60:
		await get_tree().process_frame
	await _measure(game, "покой, камера стоит")

	# Полёт: камера едет каждый кадр, как когда дрон летит над базой.
	var origin := game.camera.position
	var flight := func(f: int) -> void:
		game.camera.position = origin + Vector2(sin(f * 0.05), cos(f * 0.04)) * 200.0
	await _measure(game, "покой, камера летит", flight)
	game.camera.position = origin

	# Бой: враги кольцом вокруг квадрата турелей.
	var ring := Vector2(center + Vector2i(0, 8)) * GameConst.TILE_SIZE
	var crawler := Registry.get_enemy(&"crawler")
	for k in 300:
		var angle := TAU * k / 300.0
		world.spawn_enemy(crawler, ring + Vector2.from_angle(angle) * (side + 10) * GameConst.TILE_SIZE)
	for f in 30:
		await get_tree().process_frame
	await _measure(game, "бой")
	get_tree().quit()


func _measure(game: Game, label: String, each_frame: Callable = Callable()) -> void:
	var frames := 180
	var start := Time.get_ticks_usec()
	var last := start
	var worst := 0
	var turret_draw := 0
	for f in frames:
		if each_frame.is_valid():
			each_frame.call(f)
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		worst = maxi(worst, now - last)
		last = now
		turret_draw += game.planet_view.turret_view.last_draw_usec
		game.planet_view.turret_view.last_draw_usec = 0
	print("stress-turrets: %s — средний кадр %.2f мс (%.0f FPS), худший %.2f мс, отрисовка турелей %.2f мс/кадр, перерисовок %d, draw calls %d" % [
		label, (last - start) / 1000.0 / frames, frames * 1000000.0 / (last - start), worst / 1000.0,
		turret_draw / 1000.0 / frames, game.planet_view.turret_view.redraws,
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
	game.planet_view.turret_view.redraws = 0
