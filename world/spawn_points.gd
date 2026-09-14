class_name SpawnPoints
extends RefCounted
## Точки появления врагов: у краёв карты, в разных секторах вокруг места посадки, и обязательно
## с проходом по земле до центра. Генератор планет прорубает коридор через скалы, если прохода нет;
## для готовых карт точки только ищутся.

## Отступ точки от края карты, тайлов.
const INSET := 5
## Радиус поиска проходимого тайла вокруг идеальной точки.
const SEARCH_RADIUS := 8
## Минимальное расстояние между точками, тайлов.
const MIN_SPACING := 12
## Полуширина прорубаемого коридора.
const CORRIDOR_HALF := 1
## Толщина неприкосновенной скальной кромки карты.
const EDGE := 2


## floors изменяется, только если carve_floor >= 0 (прорубание коридоров).
static func find(width: int, height: int, floors: PackedByteArray, center: Vector2i, count: int,
		rng: RandomNumberGenerator, carve_floor: int = -1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if count <= 0 or width <= INSET * 2 or height <= INSET * 2:
		return result
	var reach := PackedByteArray()
	reach.resize(width * height)
	reach.fill(0)
	_flood(width, height, floors, reach, center)
	var base_angle := rng.randf() * TAU
	for k in count:
		var angle := base_angle + TAU * k / count + rng.randf_range(-0.35, 0.35)
		var ideal := _edge_point(width, height, center, angle)
		var found := _nearest_reachable(width, height, reach, ideal, center)
		if found.x < 0 and carve_floor >= 0:
			_carve(width, height, floors, reach, ideal, center, carve_floor)
			if reach[ideal.y * width + ideal.x] == 1:
				found = ideal
		if found.x < 0:
			continue
		var too_close := false
		for other in result:
			if Vector2(other - found).length() < MIN_SPACING:
				too_close = true
		if not too_close:
			result.append(found)
	return result


static func _passable(floors: PackedByteArray, index: int) -> bool:
	return Registry.floor_buildable[floors[index]] == 1


## Заливка проходимых тайлов от start (4-связно), отмечает reach = 1.
static func _flood(width: int, height: int, floors: PackedByteArray, reach: PackedByteArray, start: Vector2i) -> void:
	if start.x < 0 or start.y < 0 or start.x >= width or start.y >= height:
		return
	var s := start.y * width + start.x
	if reach[s] == 1 or not _passable(floors, s):
		return
	var queue := PackedInt32Array([s])
	reach[s] = 1
	var head := 0
	while head < queue.size():
		var i := queue[head]
		head += 1
		var x := i % width
		var y := i / width
		for n in [i - 1 if x > 0 else -1, i + 1 if x < width - 1 else -1, i - width if y > 0 else -1, i + width if y < height - 1 else -1]:
			if n >= 0 and reach[n] == 0 and _passable(floors, n):
				reach[n] = 1
				queue.append(n)


## Точка на рамке с отступом INSET по лучу из центра под углом angle.
static func _edge_point(width: int, height: int, center: Vector2i, angle: float) -> Vector2i:
	var dir := Vector2.from_angle(angle)
	var lo := Vector2(INSET, INSET)
	var hi := Vector2(width - 1 - INSET, height - 1 - INSET)
	var c := Vector2(center)
	var t := INF
	if absf(dir.x) > 0.0001:
		t = minf(t, ((hi.x if dir.x > 0.0 else lo.x) - c.x) / dir.x)
	if absf(dir.y) > 0.0001:
		t = minf(t, ((hi.y if dir.y > 0.0 else lo.y) - c.y) / dir.y)
	var p := (c + dir * maxf(t, 0.0)).round()
	return Vector2i(clampi(int(p.x), INSET, width - 1 - INSET), clampi(int(p.y), INSET, height - 1 - INSET))


## Ближайший к идеальной точке достижимый тайл, не ближе к центру, чем точка (минус пара тайлов).
static func _nearest_reachable(width: int, height: int, reach: PackedByteArray, ideal: Vector2i, center: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	var min_center := Vector2(ideal - center).length() - 3.0
	for y in range(maxi(ideal.y - SEARCH_RADIUS, INSET), mini(ideal.y + SEARCH_RADIUS, height - 1 - INSET) + 1):
		for x in range(maxi(ideal.x - SEARCH_RADIUS, INSET), mini(ideal.x + SEARCH_RADIUS, width - 1 - INSET) + 1):
			if reach[y * width + x] == 0 or Vector2(x - center.x, y - center.y).length() < min_center:
				continue
			var d := Vector2(x - ideal.x, y - ideal.y).length_squared()
			if d < best_d:
				best_d = d
				best = Vector2i(x, y)
	return best


## Прорубает коридор от точки к центру, пока не встретит тайл с проходом до центра.
static func _carve(width: int, height: int, floors: PackedByteArray, reach: PackedByteArray, from: Vector2i,
		to: Vector2i, carve_floor: int) -> void:
	var a := Vector2(from)
	var b := Vector2(to)
	var length := a.distance_to(b)
	var steps := maxi(1, ceili(length * 2.0))
	for s in steps + 1:
		var p := a.lerp(b, float(s) / steps).round()
		var connected := false
		for oy in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
			for ox in range(-CORRIDOR_HALF, CORRIDOR_HALF + 1):
				var x := int(p.x) + ox
				var y := int(p.y) + oy
				if x < EDGE or y < EDGE or x >= width - EDGE or y >= height - EDGE:
					continue
				var i := y * width + x
				if reach[i] == 1:
					connected = true
				elif not _passable(floors, i):
					floors[i] = carve_floor
		if connected:
			break
	# Прорубленное соединилось с достижимой областью — дозаливаем от начала коридора.
	var start := from.y * width + from.x
	if not _passable(floors, start):
		floors[start] = carve_floor
	_flood(width, height, floors, reach, from)
