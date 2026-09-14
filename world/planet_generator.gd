class_name PlanetGenerator
extends RefCounted
## Генерация карты планеты по узлу звёздной карты: детерминирована от сида узла.
## Пол — шум с пятнами, скалы — второй шум (края карты всегда скальные), руды — залежи-кляксы
## из списка руд узла. Центр карты — место посадки: вокруг площадки земля расчищена,
## под самой площадкой — металлическая платформа без руды.

## Запас расчищенной земли вокруг площадки, тайлов.
const LANDING_MARGIN := 6
## Ширина скальной кромки по краю карты.
const EDGE := 2


static func generate(node: StarMap.StarNode, pad_size: int) -> LevelMap:
	var type := node.type
	var w := node.size.x
	var h := node.size.y
	var base_floor := _floor_index(type.base_floor, &"stone")
	var rock := _floor_index(&"rock", &"rock")
	var platform := _floor_index(&"metal_plates", type.base_floor)
	var map := LevelMap.new(w, h, base_floor)
	var rng := RandomNumberGenerator.new()
	rng.seed = node.planet_seed

	var patches := FastNoiseLite.new()
	patches.seed = rng.randi()
	patches.frequency = 0.045
	var rocks := FastNoiseLite.new()
	rocks.seed = rng.randi()
	rocks.frequency = 0.06
	rocks.fractal_octaves = 3

	var center := Vector2i(w / 2, h / 2)
	var clear_radius := pad_size * 0.5 + LANDING_MARGIN
	# Порог скал подбирается так, чтобы доля скал была примерно rock_density.
	var rock_threshold := lerpf(0.55, -0.1, clampf(type.rock_density / 0.6, 0.0, 1.0))
	for y in h:
		for x in w:
			var floor_index := base_floor
			if not type.patch_floors.is_empty():
				var v := patches.get_noise_2d(x, y)
				if v > 0.28:
					var pick := int((v - 0.28) * 10.0) % type.patch_floors.size()
					floor_index = _floor_index(type.patch_floors[pick], type.base_floor)
			var at_edge := x < EDGE or y < EDGE or x >= w - EDGE or y >= h - EDGE
			var near_landing := Vector2(x - center.x, y - center.y).length() < clear_radius
			if at_edge or (not near_landing and rocks.get_noise_2d(x, y) > rock_threshold):
				floor_index = rock
			map.set_floor(x, y, floor_index)

	_place_ores(map, node, rng, center, clear_radius)

	# Площадка — металлическая платформа без руды.
	var half := pad_size / 2
	for y in range(center.y - half, center.y - half + pad_size):
		for x in range(center.x - half, center.x - half + pad_size):
			if map.in_bounds(x, y):
				map.set_floor(x, y, platform)
				map.set_ore(x, y, 0)
	return map


static func _place_ores(map: LevelMap, node: StarMap.StarNode, rng: RandomNumberGenerator, center: Vector2i, clear_radius: float) -> void:
	if node.ores.is_empty():
		return
	var area := float(map.width * map.height)
	var per_ore := maxi(1, roundi(node.type.deposits_per_10k * area / 10000.0))
	var max_reach := Vector2(map.width, map.height).length() * 0.45
	for ore_index in node.ores:
		var ore := Registry.ores[ore_index]
		for d in per_ore:
			# Первая залежь каждой руды — недалеко от посадки, остальные — по всей карте.
			var near := d == 0
			var min_dist := clear_radius + 4.0
			var max_dist := clear_radius + 22.0 if near else max_reach
			var angle := rng.randf() * TAU
			var dist := rng.randf_range(min_dist, maxf(min_dist + 1.0, max_dist))
			var blob_center := Vector2(center) + Vector2.from_angle(angle) * dist
			var radius := rng.randf_range(2.8, 4.8) * (1.0 if ore.hardness <= 2 else 0.85)
			_blob(map, blob_center, radius, ore_index + 1, rng.randf() * TAU)


static func _blob(map: LevelMap, center: Vector2, radius: float, ore_value: int, phase: float) -> void:
	var rock := _floor_index(&"rock", &"rock")
	var r := ceili(radius * 1.4)
	for y in range(floori(center.y) - r, floori(center.y) + r + 1):
		for x in range(floori(center.x) - r, floori(center.x) + r + 1):
			if not map.in_bounds(x, y) or map.get_floor(x, y) == rock:
				continue
			var offset := Vector2(x, y) - center
			var wobble := 1.0 + 0.3 * sin(3.0 * offset.angle() + phase) + 0.15 * sin(5.0 * offset.angle() + phase * 1.7)
			if offset.length() <= radius * wobble:
				map.set_ore(x, y, ore_value)


static func _floor_index(id: StringName, fallback: StringName) -> int:
	var f := Registry.get_floor(id)
	if f == null:
		f = Registry.get_floor(fallback)
	return f.index if f != null else 0
