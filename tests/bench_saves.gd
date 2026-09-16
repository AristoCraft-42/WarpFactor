extends Node
## Бенчмарк сохранений: забег с большой фабрикой на планете — время сохранения, загрузки и размер файла.
## Запуск: godot --headless --path D:/Mind res://tests/bench_saves.tscn


func _ready() -> void:
	Registry.ensure_loaded()
	var map := LevelMap.new(256, 192, Registry.get_floor(&"stone").index)
	var run := Run.create(null, map, false)
	var bm := run.planet.buildings
	var conveyor := Registry.get_building(&"conveyor")
	var container := Registry.get_building(&"container") as StorageDef
	var copper := Registry.get_item(&"hematite").index
	var placed := 0
	for row in 60:
		var y := 4 + row * 3
		for x in range(4, 84):
			bm.place(conveyor, Vector2i(x, y), GameConst.Dir.RIGHT, true)
			placed += 1
		var storage := bm.place(container, Vector2i(84, y), 0, true) as StorageBuilding
		storage.inventory.add(copper, 700)
		placed += 1
	for c in run.planet.simulation.conveyors.count:
		run.planet.simulation.conveyors.call("_insert", c, copper, 0, 0.0, 0)
	for i in 30:
		run.step()
	var start := Time.get_ticks_usec()
	var error := SaveIO.save_run_as(run, "__bench__", "bench")
	var save_ms := (Time.get_ticks_usec() - start) / 1000.0
	var path := SaveIO.slot_path("__bench__")
	var size := FileAccess.get_file_as_bytes(path).size()
	start = Time.get_ticks_usec()
	var loaded := SaveIO.load_run(path)
	var load_ms := (Time.get_ticks_usec() - start) / 1000.0
	print("Бенчмарк сохранений: зданий %d, сохранение %.1f мс (%s), загрузка %.1f мс, файл %.1f КБ, загружено зданий %d" % [
		placed, save_ms, error_string(error), load_ms, size / 1024.0, loaded.planet.buildings.get_count() if loaded != null else -1])
	SaveIO.delete_save(path)
	run.dispose()
	if loaded != null:
		loaded.dispose()
	get_tree().quit()
