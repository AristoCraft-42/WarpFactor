extends Node
## Бенчмарк турелей: 400 пулемётов на площадке и 600 врагов вокруг.
## Меряет тик забега в двух состояниях — когда врагов нет (турели спят) и когда идёт бой,
## и заодно считает, сколько раз за 300 кадров отрисовке турелей пришлось бы перерисовываться:
## слой рисует стволы, только когда картинка меняется.
## Запуск: godot --headless --path D:/Mind res://tests/bench_turrets.tscn

const TURRETS := 400
const ENEMIES := 600
const TICKS := 300


func _ready() -> void:
	Registry.ensure_loaded()
	var map := LevelMap.new(160, 120, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	var planet := run.planet
	planet.gateway.health = 1.0e12
	if planet.threat != null:
		planet.threat.delay_next_wave(100000000)
	var bm := planet.buildings
	var gun := Registry.get_building(&"machine_gun")
	var ammo := Registry.get_item(&"cartridge_iron").index
	var turrets: Array[Turret] = []
	var center := Vector2i(80, 60)
	for k in TURRETS:
		var ring := 12 + k / 40
		var angle := TAU * (k % 40) / 40.0 + ring * 0.11
		var tile := center + Vector2i(Vector2.from_angle(angle) * ring)
		var t := bm.place(gun, tile, 0, true) as Turret
		if t == null:
			continue
		while t.accept_item(null, ammo):
			t.handle_item(null, ammo)
		turrets.append(t)
	for i in 60:
		run.step()

	var idle := _measure(run, turrets, ammo)
	var idle_redraws := _redraws(planet)

	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var spawned := 0
	var guard := 0
	while spawned < ENEMIES and guard < ENEMIES * 200:
		guard += 1
		var tile := Vector2i(rng.randi_range(4, 155), rng.randi_range(4, 115))
		if Vector2(tile - center).length() < 22.0 or Vector2(tile - center).length() > 46.0:
			continue
		planet.spawn_enemy(Registry.enemies[spawned % Registry.enemies.size()], Vector2(tile * GameConst.TILE_SIZE))
		spawned += 1
	for i in 30:
		run.step()
	var fight := _measure(run, turrets, ammo)
	var fight_redraws := _redraws(planet)

	print("Бенчмарк турелей: %d турелей, %d врагов, тик = 1/%d с" % [turrets.size(), spawned, GameConst.TICK_RATE])
	print("  без врагов: %.3f мс/тик (турели спят), перерисовок участков за %d тиков: %d"
		% [idle, TICKS, idle_redraws])
	print("  в бою: %.3f мс/тик, перерисовок участков за %d тиков: %d" % [fight, TICKS, fight_redraws])
	print("    из них враги %.3f мс, снаряды %.3f мс, здания %.3f мс (%.0f бодрствует, %.0f снарядов в воздухе)"
		% [last_enemy_ms, last_shot_ms, last_build_ms, last_awake, last_projectiles])
	print("  живых врагов осталось: %d" % planet.enemies.count)
	run.dispose()
	get_tree().quit()


## Средние за прогон доли тика: враги, снаряды и бодрствующие здания (турели).
var last_enemy_ms: float = 0.0
var last_shot_ms: float = 0.0
var last_build_ms: float = 0.0
var last_projectiles: float = 0.0
var last_awake: float = 0.0


func _measure(run: Run, turrets: Array[Turret], ammo: int) -> float:
	var total := 0
	var enemy_usec := 0
	var shot_usec := 0
	var build_usec := 0
	var projectiles := 0
	var awake := 0
	for i in TICKS:
		if i % 30 == 0:
			for t in turrets:
				if t.world != null:
					while t.accept_item(null, ammo):
						t.handle_item(null, ammo)
		var start := Time.get_ticks_usec()
		run.step()
		total += Time.get_ticks_usec() - start
		enemy_usec += run.planet.enemies.last_update_usec
		shot_usec += run.planet.projectiles.last_update_usec
		build_usec += run.planet.simulation.last_buildings_usec
		projectiles += run.planet.projectiles.count
		awake += run.planet.simulation.last_awake_buildings
	last_enemy_ms = enemy_usec / 1000.0 / TICKS
	last_shot_ms = shot_usec / 1000.0 / TICKS
	last_build_ms = build_usec / 1000.0 / TICKS
	last_projectiles = float(projectiles) / TICKS
	last_awake = float(awake) / TICKS
	return total / 1000.0 / TICKS


## Сколько участков слою турелей пришлось бы перерисовать за TICKS тиков (все участки считаются
## видимыми): по той же подписи участка, по которой слой и решает (углы стволов, выстрелы, статусы).
func _redraws(world: GameWorld) -> int:
	var view := TurretView.new()
	add_child(view)
	view.setup(world, _camera())
	view.call("_sync_cells")
	var cells: Dictionary = view.get("_cells")
	var last: Dictionary = {}
	var redraws := 0
	for i in TICKS:
		world.simulation.step()
		for key in cells:
			var signature: float = view.call("_signature_of", cells[key], world.simulation.tick)
			if not is_equal_approx(signature, float(last.get(key, INF))):
				last[key] = signature
				redraws += 1
	view.queue_free()
	return redraws


func _camera() -> CameraController:
	var camera := CameraController.new()
	add_child(camera)
	camera.setup(Rect2())
	return camera
