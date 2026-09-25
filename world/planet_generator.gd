class_name PlanetGenerator
extends RefCounted
## Генерация карты планеты по узлу звёздной карты: детерминирована от сида узла.
##
## Порядок шагов:
##   1. Области («биомы») — крупный шум выбирает пол области из палитры типа, мелкий размывает края.
##   2. Скальные гряды — длинные хребты (тайлы, где шум близок к нулю) с естественными проходами.
##      Порог берётся как квантиль по выборке, поэтому доля скал всегда равна rock_density типа.
##   3. Озёра — кляксы месторождения воды с берегом из другого пола, подальше от места посадки.
##   4. Точки появления врагов у краёв (с прорубанием коридора, если прохода нет).
##   5. Руды — полями по нескольку залежей: у каждой руды своя сторона карты, а первая залежь
##      каждой всегда рядом с посадкой. К каждому полю прорубается проход, чтобы гряды не заперли
##      руду внутри скал и к ней можно было дотянуть ленту.
##   6. Площадка — металлическая платформа без руды в центре.

## Запас расчищенной земли вокруг площадки, тайлов.
const LANDING_MARGIN := 6
## Ширина скальной кромки по краю карты.
const EDGE := 2
## Шаг выборки при подборе порога скал (каждый n-й тайл).
const ROCK_SAMPLE_STEP := 4


## pad_size — сторона площадки (платформа), clear_size — под какую площадку расчистить землю от скал
## (наибольшую после расширений, чтобы расширение не упёрлось в скалы).
static func generate(node: StarMap.StarNode, pad_size: int, clear_size: int = 0) -> LevelMap:
	var type := node.type
	var w := node.size.x
	var h := node.size.y
	var base_floor := _floor_index(type.base_floor, &"stone")
	var platform := _floor_index(&"metal_plates", type.base_floor)
	var map := LevelMap.new(w, h, base_floor)
	var rng := RandomNumberGenerator.new()
	rng.seed = node.planet_seed

	var center := Vector2i(w / 2, h / 2)
	# Расчищаем квадрат под самую большую площадку, а не круг: площадка квадратная, и при круглой
	# расчистке её углы оставались скалой — плитка туда не ложилась, и площадка выглядела кривой.
	var clear_half := maxi(pad_size, clear_size) / 2 + LANDING_MARGIN
	var clear_radius := float(clear_half)

	_paint_regions(map, type, rng)
	_paint_ridges(map, type, rng, center, clear_half)
	_place_lakes(map, node, rng, center, clear_radius)

	if not type.safe and type.threat != null:
		var spawn_rng := RandomNumberGenerator.new()
		spawn_rng.seed = hash([node.planet_seed, "spawns"])
		map.spawn_points = SpawnPoints.find(w, h, map.floors, center, type.threat.spawn_point_count, spawn_rng, base_floor)

	_place_ores(map, node, rng, center, clear_radius)

	# Площадка — металлическая платформа без руды.
	var half := pad_size / 2
	for y in range(center.y - half, center.y - half + pad_size):
		for x in range(center.x - half, center.x - half + pad_size):
			if map.in_bounds(x, y):
				map.set_floor(x, y, platform)
				map.set_ore(x, y, 0)
	return map


## Области: крупный шум делит карту на зоны, мелкий размывает их границы. Основной пол типа
## занимает примерно base_floor_share карты, полы из patch_floors — свои зоны.
static func _paint_regions(map: LevelMap, type: PlanetTypeDef, rng: RandomNumberGenerator) -> void:
	var base_floor := _floor_index(type.base_floor, &"stone")
	if type.patch_floors.is_empty():
		return
	var regions := FastNoiseLite.new()
	regions.seed = rng.randi()
	regions.frequency = type.region_frequency
	var speckle := FastNoiseLite.new()
	speckle.seed = rng.randi()
	speckle.frequency = 0.07
	var patches := PackedInt32Array()
	for id in type.patch_floors:
		patches.append(_floor_index(id, type.base_floor))
	for y in map.height:
		for x in map.width:
			var v := regions.get_noise_2d(x, y) + 0.2 * speckle.get_noise_2d(x, y)
			var t := clampf((v + 0.6) / 1.2, 0.0, 0.999)
			var floor_index := base_floor
			if t > type.base_floor_share:
				var k := (t - type.base_floor_share) / maxf(1.0 - type.base_floor_share, 0.001)
				floor_index = patches[clampi(int(k * patches.size()), 0, patches.size() - 1)]
			map.set_floor(x, y, floor_index)


## Скальные гряды: скала там, где шум близок к нулю, — получаются длинные хребты с проходами,
## а не круглые пятна. Порог — квантиль по выборке значений, поэтому доля скал совпадает
## с rock_density, как бы ни выглядел сам шум.
static func _paint_ridges(map: LevelMap, type: PlanetTypeDef, rng: RandomNumberGenerator,
		center: Vector2i, clear_half: int) -> void:
	var rock := _floor_index(&"rock", &"rock")
	var w := map.width
	var h := map.height
	var ridges := FastNoiseLite.new()
	ridges.seed = rng.randi()
	ridges.frequency = type.ridge_frequency
	ridges.fractal_octaves = 2
	var threshold := 0.0
	if type.rock_density > 0.0:
		var samples := PackedFloat32Array()
		for y in range(0, h, ROCK_SAMPLE_STEP):
			for x in range(0, w, ROCK_SAMPLE_STEP):
				samples.append(absf(ridges.get_noise_2d(x, y)))
		samples.sort()
		threshold = samples[clampi(roundi(samples.size() * type.rock_density), 0, samples.size() - 1)]
	for y in h:
		for x in w:
			var at_edge := x < EDGE or y < EDGE or x >= w - EDGE or y >= h - EDGE
			var near_landing := absi(x - center.x) <= clear_half and absi(y - center.y) <= clear_half
			if at_edge or (not near_landing and threshold > 0.0 and absf(ridges.get_noise_2d(x, y)) <= threshold):
				map.set_floor(x, y, rock)


## Озёра: кляксы месторождения воды с полосой берега вокруг. Строить на воде нельзя (кроме насоса
## и бака), так что озеро — это ещё и естественная преграда. Появляются, только если вода выпала
## этому узлу среди руд.
static func _place_lakes(map: LevelMap, node: StarMap.StarNode, rng: RandomNumberGenerator,
		center: Vector2i, clear_radius: float) -> void:
	var type := node.type
	var water := -1
	for ore_index in node.ores:
		if Registry.ores[ore_index].fluid != null:
			water = ore_index
	if water < 0 or type.lakes_per_10k <= 0.0:
		return
	var area := float(map.width * map.height)
	var count := maxi(1, roundi(type.lakes_per_10k * area / 10000.0))
	var shore := _floor_index(type.shore_floor, type.base_floor)
	var reach := Vector2(map.width, map.height).length() * 0.45
	for i in count:
		var angle := rng.randf() * TAU
		var min_dist := clear_radius + 16.0
		var dist := rng.randf_range(min_dist, maxf(min_dist + 1.0, reach))
		var at := Vector2(center) + Vector2.from_angle(angle) * dist
		var radius := rng.randf_range(type.lake_min_radius, maxf(type.lake_min_radius, type.lake_max_radius))
		_lake(map, at, radius, water + 1, shore, rng.randf() * TAU)


## Одно озеро: вода внутри кляксы, берег — полоса другого пола снаружи (по скале не разливается).
static func _lake(map: LevelMap, center: Vector2, radius: float, ore_value: int, shore: int, phase: float) -> void:
	var rock := _floor_index(&"rock", &"rock")
	var r := ceili((radius + 2.0) * 1.4)
	for y in range(floori(center.y) - r, floori(center.y) + r + 1):
		for x in range(floori(center.x) - r, floori(center.x) + r + 1):
			if not map.in_bounds(x, y) or map.get_floor(x, y) == rock:
				continue
			var offset := Vector2(x, y) - center
			var wobble := 1.0 + 0.22 * sin(3.0 * offset.angle() + phase) + 0.12 * sin(5.0 * offset.angle() + phase * 1.7)
			var edge := radius * wobble
			var d := offset.length()
			if d <= edge:
				map.set_ore(x, y, ore_value)
			elif d <= edge + 2.0:
				map.set_floor(x, y, shore)


## Руды полями: каждой руде выпадает своя сторона карты, вокруг неё ложатся несколько залежей
## разного размера. Первая залежь каждой руды — рядом с посадкой, иначе начинать забег нечем.
## К каждому полю прорубается проход, чтобы гряды не заперли руду внутри скал.
static func _place_ores(map: LevelMap, node: StarMap.StarNode, rng: RandomNumberGenerator, center: Vector2i, clear_radius: float) -> void:
	if node.ores.is_empty():
		return
	var area := float(map.width * map.height)
	var per_ore := maxi(1, roundi(node.type.deposits_per_10k * area / 10000.0))
	var max_reach := Vector2(map.width, map.height).length() * 0.45
	var cluster := maxi(node.type.ore_cluster_size, 1)
	var carve_floor := _floor_index(node.type.base_floor, &"stone")
	var fields: Array[Vector2i] = []
	for ore_index in node.ores:
		var ore := Registry.ores[ore_index]
		# Вода — это озёра, отдельный шаг генерации.
		if ore.fluid != null:
			continue
		var field_angle := rng.randf() * TAU
		var field_at := Vector2(center)
		for d in per_ore:
			if d == 0:
				# Первая залежь каждой руды — рядом с посадкой, иначе начинать забег нечем.
				var near_dist := rng.randf_range(clear_radius + 4.0, clear_radius + 30.0)
				field_at = Vector2(center) + Vector2.from_angle(rng.randf() * TAU) * near_dist
			elif (d - 1) % cluster == 0:
				# Следующее поле этой руды — в стороне от прошлого, дальше от посадки.
				var dist := rng.randf_range(clear_radius + 30.0, maxf(clear_radius + 31.0, max_reach))
				field_angle += rng.randf_range(0.6, 1.4)
				field_at = Vector2(center) + Vector2.from_angle(field_angle) * dist
				fields.append(Vector2i(field_at.round()))
			var spread := 0.0 if d == 0 else rng.randf_range(4.0, 14.0)
			var at := field_at + Vector2.from_angle(rng.randf() * TAU) * spread
			var radius := rng.randf_range(6.0, 11.0) * (1.0 if ore.hardness <= 2 else 0.85)
			_blob(map, at, radius, ore_index + 1, rng.randf() * TAU)
	SpawnPoints.connect_all(map.width, map.height, map.floors, fields, center, carve_floor)


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
