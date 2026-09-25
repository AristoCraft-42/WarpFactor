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


## Характер одной планеты: значения типа, сдвинутые в пределах разброса по сиду узла.
## Считается отдельным генератором случайных чисел, чтобы не сбивать остальную генерацию.
class Character:
	var region_frequency: float
	var ridge_frequency: float
	var rock_density: float
	var ridge_breakup: float
	var lakes_per_10k: float
	var lake_min_radius: float
	var lake_max_radius: float
	var deposits_per_10k: float


static func character_of(node: StarMap.StarNode) -> Character:
	var type := node.type
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([node.planet_seed, "character"])
	var spread := type.character_spread
	var c := Character.new()
	c.region_frequency = type.region_frequency * rng.randf_range(1.0 - spread, 1.0 + spread)
	c.ridge_frequency = type.ridge_frequency * rng.randf_range(1.0 - spread, 1.0 + spread)
	c.rock_density = clampf(type.rock_density * rng.randf_range(1.0 - spread, 1.0 + spread), 0.0, 0.6)
	c.ridge_breakup = maxf(type.ridge_breakup + rng.randf_range(-spread, spread), 0.0)
	c.lakes_per_10k = type.lakes_per_10k * rng.randf_range(1.0 - spread * 1.5, 1.0 + spread * 1.5)
	var lake_scale := rng.randf_range(1.0 - spread, 1.0 + spread)
	c.lake_min_radius = type.lake_min_radius * lake_scale
	c.lake_max_radius = type.lake_max_radius * lake_scale
	c.deposits_per_10k = type.deposits_per_10k * rng.randf_range(1.0 - spread * 0.7, 1.0 + spread * 0.7)
	return c


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
	var character := character_of(node)

	_paint_regions(map, type, character, rng)
	_paint_ridges(map, character, rng, center, clear_half)
	_place_lakes(map, node, character, rng, center, clear_radius)

	if not type.safe and type.threat != null:
		var spawn_rng := RandomNumberGenerator.new()
		spawn_rng.seed = hash([node.planet_seed, "spawns"])
		map.spawn_points = SpawnPoints.find(w, h, map.floors, center, type.threat.spawn_point_count, spawn_rng, base_floor)

	_place_ores(map, node, character, rng, center, clear_radius)

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
static func _paint_regions(map: LevelMap, type: PlanetTypeDef, character: Character, rng: RandomNumberGenerator) -> void:
	var base_floor := _floor_index(type.base_floor, &"stone")
	if type.patch_floors.is_empty():
		return
	var regions := FastNoiseLite.new()
	regions.seed = rng.randi()
	regions.frequency = character.region_frequency
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
## а не круглые пятна. Второй шум рвёт их: пробивает бреши (гряда распадается на цепочку
## обломков), мелкий — делает край зубчатым. Насколько сильно — ridge_breakup.
## Порог — квантиль по выборке всей этой смеси, поэтому доля скал всё равно совпадает с заданной.
static func _paint_ridges(map: LevelMap, character: Character, rng: RandomNumberGenerator,
		center: Vector2i, clear_half: int) -> void:
	var rock := _floor_index(&"rock", &"rock")
	var w := map.width
	var h := map.height
	var ridges := FastNoiseLite.new()
	ridges.seed = rng.randi()
	ridges.frequency = character.ridge_frequency
	ridges.fractal_octaves = 2
	var breaks := FastNoiseLite.new()
	breaks.seed = rng.randi()
	breaks.frequency = character.ridge_frequency * 3.5
	var jitter_seed := rng.randi() & 0xffff
	var breakup := character.ridge_breakup
	var threshold := -INF
	if character.rock_density > 0.0:
		var samples := PackedFloat32Array()
		for y in range(0, h, ROCK_SAMPLE_STEP):
			for x in range(0, w, ROCK_SAMPLE_STEP):
				samples.append(_ridge_value(ridges, breaks, jitter_seed, breakup, x, y))
		samples.sort()
		threshold = samples[clampi(roundi(samples.size() * character.rock_density), 0, samples.size() - 1)]
	# Зубцы края могут опустить значение не больше чем на это: всё, что выше порога и с таким
	# запасом, — точно не скала, и остальные шумы для него можно не считать. Таких тайлов
	# подавляющее большинство, поэтому рваные гряды почти не стоят времени.
	var slack := 0.08 * breakup
	for y in h:
		for x in w:
			var at_edge := x < EDGE or y < EDGE or x >= w - EDGE or y >= h - EDGE
			if at_edge:
				map.set_floor(x, y, rock)
				continue
			if threshold == -INF or (absi(x - center.x) <= clear_half and absi(y - center.y) <= clear_half):
				continue
			var ridge := absf(ridges.get_noise_2d(x, y))
			if ridge - slack > threshold:
				continue
			var value := ridge
			if breakup > 0.0:
				value += breakup * (0.5 * maxf(breaks.get_noise_2d(x, y), 0.0) + 0.08 * _tile_jitter(x, y, jitter_seed))
			if value <= threshold:
				map.set_floor(x, y, rock)


## Зубцы края: случайное число от −1 до 1 на тайл (целочисленный хеш — дешевле шума,
## а мелкая зубчатость и есть «шум с частотой в тайл»).
static func _tile_jitter(x: int, y: int, seed_value: int) -> float:
	var h := (x * 374761393 + y * 668265263 + seed_value * 2246822519) & 0x7fffffff
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7fffffff
	return float(h & 1023) / 511.5 - 1.0


## Насколько тайл «не скала»: у гребня около нуля, бреши и зубцы по краю его поднимают.
## Та же формула, что и в основном проходе _paint_ridges, — по ней считается порог.
static func _ridge_value(ridges: FastNoiseLite, breaks: FastNoiseLite, jitter_seed: int,
		breakup: float, x: int, y: int) -> float:
	var value := absf(ridges.get_noise_2d(x, y))
	if breakup > 0.0:
		value += breakup * (0.5 * maxf(breaks.get_noise_2d(x, y), 0.0) + 0.08 * _tile_jitter(x, y, jitter_seed))
	return value


## Озёра: кляксы месторождения воды с полосой берега вокруг. Строить на воде нельзя (кроме насоса
## и бака), так что озеро — это ещё и естественная преграда. Появляются, только если вода выпала
## этому узлу среди руд.
static func _place_lakes(map: LevelMap, node: StarMap.StarNode, character: Character, rng: RandomNumberGenerator,
		center: Vector2i, clear_radius: float) -> void:
	var type := node.type
	var water := -1
	for ore_index in node.ores:
		if Registry.ores[ore_index].fluid != null:
			water = ore_index
	if water < 0 or character.lakes_per_10k <= 0.0:
		return
	var area := float(map.width * map.height)
	var count := maxi(1, roundi(character.lakes_per_10k * area / 10000.0))
	var shore := _floor_index(type.shore_floor, type.base_floor)
	var reach := Vector2(map.width, map.height).length() * 0.45
	for i in count:
		var angle := rng.randf() * TAU
		var min_dist := clear_radius + 16.0
		var dist := rng.randf_range(min_dist, maxf(min_dist + 1.0, reach))
		var at := Vector2(center) + Vector2.from_angle(angle) * dist
		var radius := rng.randf_range(character.lake_min_radius, maxf(character.lake_min_radius, character.lake_max_radius))
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
static func _place_ores(map: LevelMap, node: StarMap.StarNode, character: Character, rng: RandomNumberGenerator,
		center: Vector2i, clear_radius: float) -> void:
	if node.ores.is_empty():
		return
	var area := float(map.width * map.height)
	var per_ore := maxi(1, roundi(character.deposits_per_10k * area / 10000.0))
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
			_blob(map, at, radius, ore_index + 1, rng.randf() * TAU, node.type.ore_richness, rng.randi() & 0xffff)
	SpawnPoints.connect_all(map.width, map.height, map.floors, fields, center, carve_floor)


## Залежь: клякса руды. У каждой клетки своё богатство (OreDef.Richness): к центру жилы и у крупных
## залежей хорошие клетки чаще, тип планеты добавляет свой сдвиг (richness_bonus), а хеш тайла
## перемешивает, чтобы богатые клетки не лежали ровными кольцами.
static func _blob(map: LevelMap, center: Vector2, radius: float, ore_value: int, phase: float,
		richness_bonus: float = 0.0, richness_seed: int = 0) -> void:
	var rock := _floor_index(&"rock", &"rock")
	var r := ceili(radius * 1.4)
	var size_bonus := clampf((radius - 6.0) / 6.0, 0.0, 1.0)
	for y in range(floori(center.y) - r, floori(center.y) + r + 1):
		for x in range(floori(center.x) - r, floori(center.x) + r + 1):
			if not map.in_bounds(x, y) or map.get_floor(x, y) == rock:
				continue
			var offset := Vector2(x, y) - center
			var wobble := 1.0 + 0.3 * sin(3.0 * offset.angle() + phase) + 0.15 * sin(5.0 * offset.angle() + phase * 1.7)
			var edge := radius * wobble
			if offset.length() <= edge:
				var closeness := 1.0 - clampf(offset.length() / maxf(edge, 0.001), 0.0, 1.0)
				var score := 0.65 * closeness + 0.25 * size_bonus + richness_bonus + 0.15 * _tile_jitter(x, y, richness_seed)
				var level := richness_for(score)
				# Залежи одной руды, наложившись, не беднеют: клетке остаётся лучшее из двух богатств.
				if map.get_ore(x, y) == ore_value and OreDef.yield_of(map.get_richness(x, y)) > OreDef.yield_of(level):
					level = map.get_richness(x, y)
				map.set_ore(x, y, ore_value)
				map.set_richness(x, y, level)


## Богатство клетки по её оценке: чем выше, тем лучше. Пороги подобраны так, что у средней
## залежи обычной планеты больше всего средних клеток, по краю — бедные, в середине — богатые,
## а ультра — редкая удача в сердце крупной жилы.
static func richness_for(score: float) -> int:
	if score > 0.75:
		return OreDef.Richness.ULTRA
	if score > 0.5:
		return OreDef.Richness.RICH
	if score > 0.15:
		return OreDef.Richness.MEDIUM
	return OreDef.Richness.POOR


static func _floor_index(id: StringName, fallback: StringName) -> int:
	var f := Registry.get_floor(id)
	if f == null:
		f = Registry.get_floor(fallback)
	return f.index if f != null else 0
