class_name PlacementPreview
extends Node2D
## Превью действий игрока: «призраки» размещаемых зданий с подсветкой валидности,
## рамка сноса и подсветка здания под курсором. Перерисовывается только при изменении состояния.

const COLOR_VALID := Color(0.72, 0.73, 0.15)
const COLOR_REPLACE := Color(0.51, 0.65, 0.6)
const COLOR_INVALID := Color(0.98, 0.29, 0.2)
const COLOR_HOVER := Color(0.92, 0.86, 0.7, 0.8)
const COLOR_SELECTED := Color(0.98, 0.74, 0.18)


## Один планируемый к установке объект.
class Ghost:
	var def: BuildingDef
	var origin: Vector2i
	var rotation: int
	var check: BuildingManager.Check

	func _init(p_def: BuildingDef, p_origin: Vector2i, p_rotation: int, p_check: BuildingManager.Check) -> void:
		def = p_def
		origin = p_origin
		rotation = p_rotation
		check = p_check


var _ghosts: Array[Ghost] = []
var _delete_rect: Rect2i = Rect2i()
var _delete_targets: Array[Building] = []
var _hover: Building
var _selected: Building


func set_ghosts(ghosts: Array[Ghost]) -> void:
	_ghosts = ghosts
	queue_redraw()


func set_delete_selection(rect: Rect2i, targets: Array[Building]) -> void:
	_delete_rect = rect
	_delete_targets = targets
	queue_redraw()


func set_hover(building: Building) -> void:
	if building == _hover:
		return
	_hover = building
	queue_redraw()


func set_selection(building: Building) -> void:
	if building == _selected:
		return
	_selected = building
	queue_redraw()


func clear() -> void:
	_ghosts = []
	_delete_rect = Rect2i()
	_delete_targets = []
	queue_redraw()


func _draw() -> void:
	var t := float(GameConst.TILE_SIZE)

	if _hover != null and _hover.id != 0 and _ghosts.is_empty() and _delete_rect.size == Vector2i.ZERO:
		draw_rect(_hover.get_world_rect().grow(1.0), COLOR_HOVER, false, 2.0)

	if _selected != null and _selected.id != 0:
		if _selected is BridgeConveyor:
			_draw_bridge_range(_selected as BridgeConveyor)
		draw_rect(_selected.get_world_rect().grow(3.0), COLOR_SELECTED, false, 3.0)

	for g in _ghosts:
		var rect := Rect2(Vector2(g.origin) * t, g.def.get_pixel_size())
		match g.check:
			BuildingManager.Check.SAME:
				draw_rect(rect.grow(-1.0), Color(1, 1, 1, 0.25), false, 1.0)
			BuildingManager.Check.OK, BuildingManager.Check.REPLACE:
				BuildingLayer.draw_building(self, g.def, g.origin, g.rotation, Color(1, 1, 1, 0.6))
				var col := COLOR_VALID if g.check == BuildingManager.Check.OK else COLOR_REPLACE
				draw_rect(rect.grow(-1.0), Color(col, 0.9), false, 2.0)
			_:
				BuildingLayer.draw_building(self, g.def, g.origin, g.rotation, Color(1.0, 0.45, 0.4, 0.45))
				draw_rect(rect, Color(COLOR_INVALID, 0.18), true)
				draw_rect(rect.grow(-1.0), COLOR_INVALID, false, 2.0)

	if _delete_rect.size != Vector2i.ZERO:
		var r := Rect2(Vector2(_delete_rect.position) * t, Vector2(_delete_rect.size) * t)
		draw_rect(r, Color(COLOR_INVALID, 0.12), true)
		draw_rect(r, Color(COLOR_INVALID, 0.85), false, 2.0)
	for b in _delete_targets:
		if b.id != 0:
			draw_rect(b.get_world_rect().grow(-1.0), COLOR_INVALID, false, 2.0)


## Дальность моста: тайлы по четырём направлениям, мосты-кандидаты обведены.
func _draw_bridge_range(bridge: BridgeConveyor) -> void:
	if bridge.world == null:
		return
	var t := float(GameConst.TILE_SIZE)
	for dir in 4:
		var step := GameConst.dir_vector(dir)
		for distance in range(1, bridge.get_range() + 1):
			var tile := bridge.origin + step * distance
			var rect := Rect2(Vector2(tile) * t, Vector2(t, t))
			if bridge.world.buildings.get_at(tile) is BridgeConveyor:
				draw_rect(rect.grow(-2.0), COLOR_SELECTED, false, 2.0)
			else:
				draw_rect(rect.grow(-6.0), Color(COLOR_SELECTED, 0.18), true)
