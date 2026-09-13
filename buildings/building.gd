class_name Building
extends RefCounted
## Базовое здание. Это лёгкий объект данных, а не нода сцены.
## Отрисовка выполняется слоями render/, логика тиков появится на этапе 2.

## Уникальный id в BuildingManager (0 — «нет здания»).
var id: int = 0
var def: BuildingDef
## Левый верхний тайл.
var origin: Vector2i = Vector2i.ZERO
## Направление 0..3 (см. GameConst.Dir).
var rotation: int = 0
## Мир, которому принадлежит здание. Обнуляется при удалении/выгрузке мира.
var world: GameWorld


func get_size() -> int:
	return def.size


func get_rect() -> Rect2i:
	return Rect2i(origin, Vector2i(def.size, def.size))


func get_world_rect() -> Rect2:
	return Rect2(Vector2(origin * GameConst.TILE_SIZE), def.get_pixel_size())


func get_world_center() -> Vector2:
	return get_world_rect().get_center()


func occupies(tile: Vector2i) -> bool:
	return get_rect().has_point(tile)


func get_display_name() -> String:
	return tr(def.name_key)


## Вызывается после того, как здание занесено в сетку.
func on_placed() -> void:
	pass


## Вызывается перед удалением здания из сетки.
func on_removed() -> void:
	pass


## Настройка здания (фильтр сортировщика, связь моста и т. п.). Используется пипеткой.
func get_config() -> Variant:
	return null


func set_config(_value: Variant) -> void:
	pass
