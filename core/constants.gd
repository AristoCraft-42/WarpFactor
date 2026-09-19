class_name GameConst
extends RefCounted
## Глобальные константы и вспомогательные функции координат.
## Направления: 0 — вправо (+X), 1 — вниз (+Y), 2 — влево, 3 — вверх.
## Поворот на +1 — по часовой стрелке на экране (ось Y смотрит вниз).

const TILE_SIZE: int = 32
const CHUNK_SIZE: int = 32
const CHUNK_PIXELS: int = TILE_SIZE * CHUNK_SIZE

## Частота логического тика симуляции (используется начиная с этапа 2).
const TICK_RATE: int = 30
const TICK_DT: float = 1.0 / TICK_RATE

## Максимальный размер здания в тайлах.
const MAX_BUILDING_SIZE: int = 4

## Границы размера уровня.
const MIN_LEVEL_SIZE: int = 16
const MAX_LEVEL_SIZE: int = 1024

## Масштаб камеры: 1.0 — тайл занимает 32 физических пикселя.
const ZOOM_MIN: float = 0.1
const ZOOM_MAX: float = 4.0
## Ниже этого масштаба тайлмапы скрываются и рисуется обзорная текстура (LOD).
const OVERVIEW_ZOOM: float = 0.3
## Ниже этого масштаба сетка не рисуется.
const GRID_MIN_ZOOM: float = 0.45

## Порог «массового сноса», после которого спрашиваем подтверждение.
const MASS_DELETE_THRESHOLD: int = 40

enum Dir { RIGHT, DOWN, LEFT, UP }


## Единичный вектор направления.
static func dir_vector(dir: int) -> Vector2i:
	match posmod(dir, 4):
		0:
			return Vector2i(1, 0)
		1:
			return Vector2i(0, 1)
		2:
			return Vector2i(-1, 0)
		_:
			return Vector2i(0, -1)


## Угол поворота спрайта для направления (спрайты нарисованы «вправо»).
static func dir_angle(dir: int) -> float:
	return posmod(dir, 4) * PI * 0.5


## Направление по вектору (берётся доминирующая ось).
static func dir_from_vector(v: Vector2i) -> int:
	if absi(v.x) >= absi(v.y):
		return Dir.RIGHT if v.x >= 0 else Dir.LEFT
	return Dir.DOWN if v.y > 0 else Dir.UP


static func world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(floori(pos.x / TILE_SIZE), floori(pos.y / TILE_SIZE))


static func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile * TILE_SIZE)


static func tile_to_chunk(tile: Vector2i) -> Vector2i:
	return Vector2i(floori(float(tile.x) / CHUNK_SIZE), floori(float(tile.y) / CHUNK_SIZE))


## Левый верхний тайл здания размера size, центрированного на позиции курсора.
## Для чётных размеров здание «прилипает» к ближайшему узлу сетки.
static func origin_for_size(world_pos: Vector2, size: int) -> Vector2i:
	var half := size * 0.5
	return Vector2i(
		floori(world_pos.x / TILE_SIZE - half + 0.5),
		floori(world_pos.y / TILE_SIZE - half + 0.5)
	)
