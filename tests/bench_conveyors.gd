extends Node
## Бенчмарк симуляции лент (headless). Замеряет среднее время тика в разных сценариях.
## Запуск: godot --headless --path D:/Mind res://tests/bench_conveyors.tscn [-- --lines=100 --length=40]

const Worlds := preload("res://tests/support/test_worlds.gd")

var _lines: int = 100
var _length: int = 40


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lines="):
			_lines = arg.substr(8).to_int()
		elif arg.begins_with("--length="):
			_length = arg.substr(9).to_int()
	print("Бенчмарк лент: %d линий × %d = %d лент, тик = 1/%d с" % [_lines, _length, _lines * _length, GameConst.TICK_RATE])
	_scenario("все ленты в движении (источник → линия → приёмник)", true, false)
	_scenario("все ленты забиты (нет приёмника)", false, false)
	_scenario("быстрые ленты (×2) в движении", true, true)
	_scenario_drills()
	get_tree().quit()


## fast — лента вдвое быстрее обычной (как будущие титановые, в ранней игре их нет).
func _scenario(title: String, with_sinks: bool, fast: bool) -> void:
	var world := Worlds.empty_world(_length + 8, _lines * 2 + 4)
	var belt := Registry.get_building(&"conveyor").duplicate() as ConveyorDef
	if fast:
		belt.tiles_per_second *= 2.0
	for i in _lines:
		var y := 2 + i * 2
		world.buildings.place(Worlds.source_def(), Vector2i(1, y), 0, true)
		Worlds.conveyor_line(world, Vector2i(2, y), _length, GameConst.Dir.RIGHT, &"", belt)
		if with_sinks:
			world.buildings.place(Worlds.sink_def(), Vector2i(2 + _length, y), 0, true)
	# Прогрев: линии заполняются до установившегося режима.
	var warmup := int(_length / 2.0 * GameConst.TICK_RATE) + 150
	Worlds.run_ticks(world, warmup)
	var ticks := 300
	var start := Time.get_ticks_usec()
	Worlds.run_ticks(world, ticks)
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / ticks
	var sys := world.simulation.conveyors
	print("  %s: %.3f мс/тик, бодрствует лент %d из %d, предметов %d; x1 = %.1f мс/с, x4 = %.1f мс/кадр при 60 FPS" % [
		title, ms, sys.last_updated, sys.count, sys.get_item_count(),
		ms * GameConst.TICK_RATE, ms * GameConst.TICK_RATE * 4.0 / 60.0])
	world.dispose()


## Смешанная фабрика: буры на гематите (питание — опоры вдоль левого края) отдают в линии, линии уходят в приёмники.
func _scenario_drills() -> void:
	var drills := _lines
	var map := LevelMap.new(_length + 16, drills * 3 + 8, Registry.get_floor(&"stone").index)
	var copper := Registry.get_ore(&"hematite").index + 1
	for i in drills:
		var y := 2 + i * 3
		for dy in 2:
			for dx in 2:
				map.set_ore(1 + dx, y + dy, copper)
	var world := GameWorld.create(null, map, true)
	for i in drills:
		var y := 2 + i * 3
		world.buildings.place(Registry.get_building(&"drill"), Vector2i(1, y), 0, true)
		Worlds.conveyor_line(world, Vector2i(3, y), _length, GameConst.Dir.RIGHT)
		world.buildings.place(Worlds.sink_def(), Vector2i(3 + _length, y), 0, true)
	world.buildings.place(Worlds.generator_def(), Vector2i(0, 3), 0, true)
	for i in drills:
		var pole := world.buildings.place(Registry.get_building(&"small_power_pole"), Vector2i(0, 4 + i * 3), 0, true) as PowerPole
		if pole != null:
			world.power.auto_link(pole)
	Worlds.run_ticks(world, 600)
	var ticks := 600
	var start := Time.get_ticks_usec()
	Worlds.run_ticks(world, ticks)
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / ticks
	print("  буры + редкий поток (%d буров, %d лент): %.3f мс/тик, бодрствует лент %d" % [
		drills, world.simulation.conveyors.count, ms, world.simulation.conveyors.last_updated])
	world.dispose()
