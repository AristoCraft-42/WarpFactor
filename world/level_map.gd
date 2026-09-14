class_name LevelMap
extends RefCounted
## Содержимое карты уровня: слои пола и руды плюс предустановленные здания.
## Индексы — текущие индексы Registry (при чтении файла они переназначаются по строковым id).

## Предустановленное здание.
class Placement:
	var def: BuildingDef
	var origin: Vector2i
	var rotation: int = 0

	func _init(p_def: BuildingDef = null, p_origin: Vector2i = Vector2i.ZERO, p_rotation: int = 0) -> void:
		def = p_def
		origin = p_origin
		rotation = p_rotation


var width: int = 0
var height: int = 0
## Индекс FloorDef на тайл.
var floors: PackedByteArray = PackedByteArray()
## 0 — нет руды, иначе индекс OreDef + 1.
var ores: PackedByteArray = PackedByteArray()
var placements: Array[Placement] = []
## Точки появления врагов (генератор планет; у готовых карт ищутся при запуске).
var spawn_points: Array[Vector2i] = []


func _init(p_width: int = 0, p_height: int = 0, fill_floor: int = 0) -> void:
	width = p_width
	height = p_height
	floors.resize(width * height)
	floors.fill(fill_floor)
	ores.resize(width * height)
	ores.fill(0)


func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height


func get_floor(x: int, y: int) -> int:
	return floors[y * width + x]


func set_floor(x: int, y: int, floor_index: int) -> void:
	if in_bounds(x, y):
		floors[y * width + x] = floor_index


func get_ore(x: int, y: int) -> int:
	return ores[y * width + x]


## ore_value: 0 — убрать руду, иначе индекс OreDef + 1.
func set_ore(x: int, y: int, ore_value: int) -> void:
	if in_bounds(x, y):
		ores[y * width + x] = ore_value


func add_placement(def: BuildingDef, origin: Vector2i, rotation: int = 0) -> void:
	placements.append(Placement.new(def, origin, rotation))
