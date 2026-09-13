class_name LinePlanner
extends RefCounted
## Геометрия протягивания: L-трасса для лент и прямой ряд для остальных зданий.


## L-трасса от start до end (включительно). x_first — сначала идём по X, потом по Y.
## Каждый шаг — Vector3i(x, y, направление): направление к следующему тайлу,
## у последнего — направление последнего отрезка (или fallback_dir, если тайл один).
static func l_path(start: Vector2i, end: Vector2i, x_first: bool, fallback_dir: int) -> Array[Vector3i]:
	var tiles: Array[Vector2i] = [start]
	var corner := Vector2i(end.x, start.y) if x_first else Vector2i(start.x, end.y)
	_walk(tiles, start, corner)
	_walk(tiles, corner, end)

	var result: Array[Vector3i] = []
	var last_dir := fallback_dir
	for i in tiles.size():
		var dir := last_dir
		if i < tiles.size() - 1:
			dir = GameConst.dir_from_vector(tiles[i + 1] - tiles[i])
			last_dir = dir
		result.append(Vector3i(tiles[i].x, tiles[i].y, dir))
	return result


## Прямой ряд позиций с шагом step вдоль доминирующей оси смещения.
static func straight_line(start: Vector2i, end: Vector2i, step: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var delta := end - start
	var axis := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	var distance := maxi(absi(delta.x), absi(delta.y))
	var count := distance / maxi(step, 1)
	for i in count + 1:
		result.append(start + axis * step * i)
	return result


## Добавляет тайлы от a (не включая) до b (включая) по одной оси.
static func _walk(tiles: Array[Vector2i], a: Vector2i, b: Vector2i) -> void:
	var delta := b - a
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var pos := a
	while pos != b:
		pos += step
		tiles.append(pos)
