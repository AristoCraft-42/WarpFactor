class_name WorldGrid
extends RefCounted
## Плоские массивы тайлов мира. Никаких объектов на тайл — только упакованные массивы.

var width: int = 0
var height: int = 0
## Индекс FloorDef.
var floors: PackedByteArray
## 0 — нет руды, иначе индекс OreDef + 1.
var ores: PackedByteArray
## Богатство клетки руды (OreDef.Richness; 0 — средняя).
var richness: PackedByteArray
## 0 — пусто, иначе id здания.
var building_ids: PackedInt32Array


func _init(p_width: int, p_height: int) -> void:
	width = p_width
	height = p_height
	floors.resize(width * height)
	ores.resize(width * height)
	richness.resize(width * height)
	richness.fill(0)
	building_ids.resize(width * height)
	building_ids.fill(0)


static func from_level_map(map: LevelMap) -> WorldGrid:
	var grid := WorldGrid.new(map.width, map.height)
	grid.floors = map.floors.duplicate()
	grid.ores = map.ores.duplicate()
	if map.richness.size() == map.width * map.height:
		grid.richness = map.richness.duplicate()
	return grid


func index_of(x: int, y: int) -> int:
	return y * width + x


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func in_bounds_v(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < width and tile.y < height


func rect_in_bounds(rect: Rect2i) -> bool:
	return rect.position.x >= 0 and rect.position.y >= 0 \
		and rect.end.x <= width and rect.end.y <= height


func get_floor(x: int, y: int) -> int:
	return floors[y * width + x]


func get_ore(x: int, y: int) -> int:
	return ores[y * width + x]


func get_richness(x: int, y: int) -> int:
	return richness[y * width + x]


## Во сколько раз клетка даёт больше руды в секунду, чем средняя.
func get_yield(x: int, y: int) -> float:
	return OreDef.yield_of(richness[y * width + x])


func get_building_id(x: int, y: int) -> int:
	return building_ids[y * width + x]


func is_buildable(x: int, y: int) -> bool:
	return Registry.floor_buildable[floors[y * width + x]] == 1


func get_floor_def(x: int, y: int) -> FloorDef:
	return Registry.floors[floors[y * width + x]]


## null, если руды нет.
func get_ore_def(x: int, y: int) -> OreDef:
	var v := ores[y * width + x]
	return Registry.ores[v - 1] if v > 0 else null


func get_pixel_size() -> Vector2:
	return Vector2(width, height) * GameConst.TILE_SIZE


func chunks_x() -> int:
	return ceili(float(width) / GameConst.CHUNK_SIZE)


func chunks_y() -> int:
	return ceili(float(height) / GameConst.CHUNK_SIZE)


func chunk_index(chunk: Vector2i) -> int:
	return chunk.y * chunks_x() + chunk.x


## Прямоугольник тайлов чанка (обрезанный по границе карты).
func chunk_tile_rect(chunk: Vector2i) -> Rect2i:
	var pos := chunk * GameConst.CHUNK_SIZE
	var end := Vector2i(mini(pos.x + GameConst.CHUNK_SIZE, width), mini(pos.y + GameConst.CHUNK_SIZE, height))
	return Rect2i(pos, end - pos)


## Диапазон чанков (включительно), пересекающих прямоугольник в мировых координатах.
func chunk_range_for_world_rect(rect: Rect2) -> Rect2i:
	var cs := float(GameConst.CHUNK_PIXELS)
	var x0 := clampi(floori(rect.position.x / cs), 0, chunks_x() - 1)
	var y0 := clampi(floori(rect.position.y / cs), 0, chunks_y() - 1)
	var x1 := clampi(floori(rect.end.x / cs), 0, chunks_x() - 1)
	var y1 := clampi(floori(rect.end.y / cs), 0, chunks_y() - 1)
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)
