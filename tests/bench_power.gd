extends Node
## Бенчмарк электричества (headless): сколько стоит тик симуляции и сбор проводов для отрисовки
## при сотнях опор и потребителей. Игрок жаловался на просадку кадров после 500+ таких зданий.
##
## Запуск: godot --headless --path D:/Mind res://tests/bench_power.tscn [-- --side=120]

const Worlds := preload("res://tests/support/test_worlds.gd")

## Сторона квадрата, который застраивается опорами и потребителями.
var _side: int = 120


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--side="):
			_side = arg.substr(7).to_int()
	print("Бенчмарк электричества: квадрат %d×%d, тик = 1/%d с" % [_side, _side, GameConst.TICK_RATE])
	for side in [60, _side, _side * 2]:
		_scenario(side)
	get_tree().quit()


func _scenario(side: int) -> void:
	var world := Worlds.empty_world(side + 8, side + 8)
	Worlds.power_area(world, Vector2i(2, 2), side, Vector2i(1, 1))
	# Потребители: сборщики сеткой между опорами (им не нужна руда под собой).
	var consumer_def := Registry.get_building(&"assembler")
	var consumers := 0
	# Опоры стоят сеткой через 5 от (4,4) — потребителей ставим между ними.
	for y in range(6, side, 5):
		for x in range(6, side, 5):
			if world.buildings.get_at(Vector2i(x, y)) == null 					and world.buildings.place(consumer_def, Vector2i(x, y), 0, true) != null:
				consumers += 1
	Worlds.run_ticks(world, 30)
	var poles := world.power.poles.size()

	var ticks := 200
	var start := Time.get_ticks_usec()
	Worlds.run_ticks(world, ticks)
	var sim_ms := (Time.get_ticks_usec() - start) / 1000.0 / ticks

	# Отрисовка: сбор проводов. Раньше он шёл каждый кадр, теперь — только при изменении сетей.
	var view := NetworkView.new()
	view._world = world
	var runs := 50
	start = Time.get_ticks_usec()
	var wires := 0
	for i in runs:
		wires = view._collect_wires().size() / 2
	var collect_ms := (Time.get_ticks_usec() - start) / 1000.0 / runs

	start = Time.get_ticks_usec()
	for i in runs:
		view._collect_marks()
	var marks_ms := (Time.get_ticks_usec() - start) / 1000.0 / runs

	print("  опор %d, потребителей %d, проводов %d:" % [poles, consumers, wires])
	print("    симуляция %.3f мс/тик (x1 = %.1f мс/с)" % [sim_ms, sim_ms * GameConst.TICK_RATE])
	print("    сбор проводов %.3f мс — раньше каждый кадр (%.1f мс/с при 60 FPS), теперь при изменении сетей"
		% [collect_ms, collect_ms * 60.0])
	print("    значки питания %.3f мс — раньше каждый кадр (%.1f мс/с при 60 FPS), теперь 4 раза в секунду"
		% [marks_ms, marks_ms * 60.0])
	view.free()
	world.dispose()
