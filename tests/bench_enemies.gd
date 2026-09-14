extends Node
## Бенчмарк боя: планета 256×192 со скалами, ~5000 зданий (ленты, склады, 80 турелей), 1000 врагов идут к шлюзу.
## Замеряет тик планеты (симуляция зданий + враги + поле потоков), отдельно врагов, полный пересчёт поля
## потоков и пересчёт порциями.
## Запуск: godot --headless --path D:/Mind res://tests/bench_enemies.tscn

const ENEMIES := 1000
const TICKS := 300


func _ready() -> void:
	Registry.ensure_loaded()
	var map := LevelMap.new(256, 192, Registry.get_floor(&"stone").index)
	var rock := Registry.get_floor(&"rock").index
	var noise := FastNoiseLite.new()
	noise.seed = 12
	noise.frequency = 0.06
	for y in 192:
		for x in 256:
			var near_center := Vector2(x - 128, y - 96).length() < 20.0
			if not near_center and noise.get_noise_2d(x, y) > 0.45:
				map.set_floor(x, y, rock)
	var run := Run.create(null, map, false)
	var planet := run.planet
	planet.threat.delay_next_wave(100000000)
	planet.gateway.health = 1.0e12
	var bm := planet.buildings
	var conveyor := Registry.get_building(&"conveyor")
	var container := Registry.get_building(&"container")
	var copper := Registry.get_item(&"copper").index
	var placed := 0
	# Ленты рядами с разрывами и склады-кварталы — твёрдые препятствия для поля потоков.
	var pad := Rect2i(Vector2i(128, 96) - Vector2i(12, 12), Vector2i(24, 24))
	for row in 23:
		var y := 8 + row * 7
		for x in range(10, 246):
			if x % 24 < 20 and not pad.has_point(Vector2i(x, y)) and bm.place(conveyor, Vector2i(x, y), GameConst.Dir.RIGHT, true) != null:
				placed += 1
		for x in range(12, 244, 12):
			if pad.intersects(Rect2i(x, y + 1, 2, 2)):
				continue
			var storage := bm.place(container, Vector2i(x, y + 1), 0, true) as StorageBuilding
			if storage != null:
				storage.inventory.add(copper, 50)
				placed += 1
	# Кольцо турелей вокруг площадки: 60 пулемётов и 20 артиллерий с большим запасом патронов.
	var gun := Registry.get_building(&"machine_gun")
	var art := Registry.get_building(&"artillery")
	var turrets: Array[Turret] = []
	for k in 80:
		var angle := TAU * k / 80.0
		var def: BuildingDef = art if k % 4 == 0 else gun
		var tile := Vector2i(128, 96) + Vector2i(Vector2.from_angle(angle) * (16.0 if def == gun else 20.0))
		var t := bm.place(def, tile, 0, true) as Turret
		if t != null:
			turrets.append(t)
			placed += 1
	for c in planet.simulation.conveyors.count:
		planet.simulation.conveyors.call("_insert", c, copper, 0, 0.0, 0)
	var t0 := Time.get_ticks_usec()
	planet.flow.mark_dirty()
	planet.flow.compute_now()
	var full_ms := (Time.get_ticks_usec() - t0) / 1000.0

	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var spawned := 0
	var guard := 0
	while spawned < ENEMIES and guard < ENEMIES * 400:
		guard += 1
		var tile := Vector2i(rng.randi_range(2, 253), rng.randi_range(2, 189))
		var edge := mini(mini(tile.x, tile.y), mini(255 - tile.x, 191 - tile.y))
		# Половина — у краёв, половина — у кольца турелей (чтобы турели стреляли).
		var from_center := Vector2(tile - Vector2i(128, 96)).length()
		var near_ring := from_center > 22.0 and from_center < 30.0
		if (edge > 30 if spawned % 2 == 0 else not near_ring) or planet.flow.get_dist(tile) >= FlowField.INF or planet.flow.blocked[tile.y * 256 + tile.x] != FlowField.OPEN:
			continue
		var def := Registry.enemies[spawned % Registry.enemies.size()]
		planet.spawn_enemy(def, Vector2(tile * GameConst.TILE_SIZE) + Vector2(16, 16))
		spawned += 1
	for i in 30:
		run.step()
	var graphite := Registry.get_item(&"graphite").index

	var total := 0
	var enemy_total := 0
	var worst := 0
	for i in TICKS:
		var start := Time.get_ticks_usec()
		run.step()
		var spent := Time.get_ticks_usec() - start
		# Патроны не кончаются: бенчмарк меряет стрельбу, а не логистику.
		if i % 30 == 0:
			for t in turrets:
				if t.world != null:
					while t.accept_item(null, graphite):
						t.handle_item(null, graphite)
		total += spent
		worst = maxi(worst, spent)
		enemy_total += planet.enemies.last_update_usec
	# Пересчёт порциями после сноса склада.
	var any_storage := bm.find_first(&"container")
	bm.remove(any_storage, true)
	var slice_ticks := 0
	var slice_total := 0
	while (planet.flow.is_dirty() or planet.flow.is_computing() or slice_ticks == 0) and slice_ticks < 200:
		var start := Time.get_ticks_usec()
		planet.flow.update()
		slice_total += Time.get_ticks_usec() - start
		slice_ticks += 1
	print("Бенчмарк врагов: зданий %d, врагов %d (живы %d), лент %d" % [placed, spawned, planet.enemies.count, planet.simulation.conveyors.count])
	print("  тик забега: средний %.2f мс, худший %.2f мс; из них враги %.2f мс" % [
		total / 1000.0 / TICKS, worst / 1000.0, enemy_total / 1000.0 / TICKS])
	print("  поле потоков 256×192: полный пересчёт %.1f мс; порциями — %d тиков по %.2f мс" % [
		full_ms, slice_ticks, slice_total / 1000.0 / maxi(slice_ticks, 1)])
	print("  турелей %d, выстрелов %d, попаданий %d, уничтожено врагов %d, разрушено построек %d" % [turrets.size(),
		planet.projectiles.fired, planet.projectiles.hits, planet.enemies.killed, planet.destroyed_count])
	run.dispose()
	get_tree().quit()
