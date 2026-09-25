extends SceneTree
## Одноразовый предпросмотр генерации: карта каждого типа планеты в PNG.


func _init() -> void:
	Registry.ensure_loaded()
	for type in Registry.planet_types:
		var star := StarMap.new(2024, Registry.run_def, Registry.planet_types)
		var node := star.get_current()
		node.type = type
		node.size = type.min_size
		node.ores.clear()
		for ore_id in type.ore_ids:
			var ore := Registry.get_ore(ore_id)
			if ore != null:
				node.ores.append(ore.index)
		var map := PlanetGenerator.generate(node, Registry.run_def.pad_start_size, 40)
		var image := Image.create_empty(map.width, map.height, false, Image.FORMAT_RGB8)
		for y in map.height:
			for x in map.width:
				var color := Registry.floors[map.get_floor(x, y)].color
				var ore_value := map.get_ore(x, y)
				if ore_value > 0:
					color = Registry.ores[ore_value - 1].get_color()
				image.set_pixel(x, y, color)
		for point in map.spawn_points:
			image.set_pixel(point.x, point.y, Color(1, 0, 1))
		image.save_png("D:/shots/gen_%s.png" % type.id)
		print("gen_%s.png %d×%d" % [type.id, map.width, map.height])
	quit()
