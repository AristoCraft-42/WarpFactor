class_name PlacementPreview
extends Node2D
## Превью действий игрока: «призраки» размещаемых зданий с подсветкой валидности,
## рамка выделения, выбранное для настройки здание и подсветка под курсором.
## Перерисовывается только при изменении состояния.

const COLOR_VALID := Color(0.72, 0.73, 0.15)
const COLOR_REPLACE := Color(0.51, 0.65, 0.6)
const COLOR_INVALID := Color(0.98, 0.29, 0.2)
const COLOR_HOVER := Color(0.92, 0.86, 0.7, 0.8)
const COLOR_SELECTED := Color(0.98, 0.74, 0.18)
const COLOR_AREA := Color(0.51, 0.65, 0.6)


## Один планируемый к установке объект.
class Ghost:
	var def: BuildingDef
	var origin: Vector2i
	var rotation: int
	var check: BuildingManager.Check
	## Настройка вставляемого здания (для скопированного плана).
	var config: Variant = null

	func _init(p_def: BuildingDef, p_origin: Vector2i, p_rotation: int, p_check: BuildingManager.Check) -> void:
		def = p_def
		origin = p_origin
		rotation = p_rotation
		check = p_check


var _ghosts: Array[Ghost] = []
var _area_rect: Rect2i = Rect2i()
var _area_targets: Array[Building] = []
var _hover: Building
var _selected: Building
## Сетевая игра: поставленное, но ещё не построенное — команда идёт до хоста и обратно
## сотни миллисекунд, и без отметки клик выглядит так, будто не сработал.
## Каждый элемент: {"ghost": Ghost, "world": GameWorld, "until": мс}.
var _pending: Array = []
## Сколько ждать постройку, прежде чем убрать отметку (не хватило предметов, место заняли).
const PENDING_MSEC := 3000


func add_pending(ghosts: Array[Ghost], world: GameWorld) -> void:
	var until := Time.get_ticks_msec() + PENDING_MSEC
	for g in ghosts:
		_pending.append({"ghost": g, "world": world, "until": until})
	queue_redraw()


## Здания, которые уже отмечены к сносу (команда в пути).
var _pending_removals: Array[Building] = []


func set_pending_removals(buildings: Array[Building]) -> void:
	if buildings == _pending_removals:
		return
	_pending_removals = buildings
	queue_redraw()


func _process(_delta: float) -> void:
	if _pending.is_empty():
		return
	var now := Time.get_ticks_msec()
	var before := _pending.size()
	_pending = _pending.filter(func(entry: Dictionary) -> bool:
		var g: Ghost = entry["ghost"]
		var world: GameWorld = entry["world"]
		if now > int(entry["until"]) or world == null or world.buildings == null:
			return false
		var built := world.buildings.get_at(g.origin)
		return built == null or built.def != g.def)
	if _pending.size() != before or not _pending.is_empty():
		queue_redraw()


func set_ghosts(ghosts: Array[Ghost]) -> void:
	_ghosts = ghosts
	queue_redraw()


func set_area(rect: Rect2i, targets: Array[Building]) -> void:
	if rect == _area_rect and targets == _area_targets:
		return
	_area_rect = rect
	_area_targets = targets
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
	_area_rect = Rect2i()
	_area_targets = []
	queue_redraw()


func _draw() -> void:
	var t := float(GameConst.TILE_SIZE)

	if _hover != null and _hover.id != 0 and _ghosts.is_empty() and _area_rect.size == Vector2i.ZERO:
		draw_rect(_hover.get_world_rect().grow(1.0), COLOR_HOVER, false, 2.0)
		if _hover is Turret:
			TurretView.draw_range(self, (_hover as Turret).get_turret_def(), _hover.get_world_center())

	if _selected != null and _selected.id != 0:
		if _selected is BridgeConveyor:
			_draw_bridge_range(_selected as BridgeConveyor)
		if _selected is Turret:
			TurretView.draw_range(self, (_selected as Turret).get_turret_def(), _selected.get_world_center())
		draw_rect(_selected.get_world_rect().grow(3.0), COLOR_SELECTED, false, 3.0)

	# Опора в руке: зона питания и дальность проводов.
	if not _ghosts.is_empty() and _ghosts[_ghosts.size() - 1].def is PowerPoleDef:
		var pole := _ghosts[_ghosts.size() - 1]
		var pd := pole.def as PowerPoleDef
		var center := Vector2(pole.origin) * t + pd.get_pixel_size() * 0.5
		var half := Vector2.ONE * pd.supply_size * t * 0.5
		draw_rect(Rect2(center - half, half * 2.0), Color(0.98, 0.74, 0.18, 0.12), true)
		draw_rect(Rect2(center - half, half * 2.0), Color(0.98, 0.74, 0.18, 0.8), false, 2.0)
		draw_arc(center, pd.wire_range * t, 0.0, TAU, 64, Color(0.85, 0.65, 0.3, 0.6), 2.0)
	# Подземная труба в руке: дальность подземного участка по направлению поворота.
	if not _ghosts.is_empty() and _ghosts[_ghosts.size() - 1].def is FluidBuildingDef 			and (_ghosts[_ghosts.size() - 1].def as FluidBuildingDef).role == FluidBuildingDef.Role.UNDERGROUND:
		var under := _ghosts[_ghosts.size() - 1]
		var ud := under.def as FluidBuildingDef
		var from := Vector2(under.origin) * t + Vector2.ONE * t * 0.5
		var dir := Vector2(GameConst.dir_vector(under.rotation))
		draw_dashed_line(from, from + dir * ud.underground_range * t, Color(0.51, 0.65, 0.6, 0.7), 2.0, 8.0)
		draw_rect(Rect2(Vector2(under.origin + GameConst.dir_vector(under.rotation) * ud.underground_range) * t, Vector2.ONE * t),
			Color(0.51, 0.65, 0.6, 0.6), false, 2.0)
	# Радиус турели в руке (у ряда — только у последней, чтобы не пестрило).
	if not _ghosts.is_empty() and _ghosts[_ghosts.size() - 1].def is TurretDef:
		var last := _ghosts[_ghosts.size() - 1]
		TurretView.draw_range(self, last.def as TurretDef, Vector2(last.origin) * t + last.def.get_pixel_size() * 0.5)
	for g in _ghosts:
		var rect := Rect2(Vector2(g.origin) * t, g.def.get_pixel_size())
		match g.check:
			BuildingManager.Check.SAME:
				draw_rect(rect.grow(-1.0), Color(1, 1, 1, 0.25), false, 1.0)
			BuildingManager.Check.OK, BuildingManager.Check.REPLACE:
				BuildingLayer.draw_building(self, g.def, g.origin, g.rotation, Color(1, 1, 1, 0.6))
				if g.def is LogisticDef and g.config is Vector2i:
					var link: Vector2i = g.config
					draw_line(rect.get_center(), rect.get_center() + Vector2(link) * t, Color(0.98, 0.74, 0.18, 0.7), 3.0)
				if g.def is DrillDef:
					BuildingLayer.draw_side_arrow(self, rect.get_center(), g.def.size, g.rotation, false, 0.8)
				var col := COLOR_VALID if g.check == BuildingManager.Check.OK else COLOR_REPLACE
				draw_rect(rect.grow(-1.0), Color(col, 0.9), false, 2.0)
			_:
				BuildingLayer.draw_building(self, g.def, g.origin, g.rotation, Color(1.0, 0.45, 0.4, 0.45))
				draw_rect(rect, Color(COLOR_INVALID, 0.18), true)
				draw_rect(rect.grow(-1.0), COLOR_INVALID, false, 2.0)

	# Отданный снос виден сразу: здание перечёркнуто, пока команда идёт до хоста.
	for entry in _pending_removals:
		var b: Building = entry
		if b != null and b.id != 0:
			var r := b.get_world_rect()
			draw_rect(r.grow(-1.0), Color(COLOR_INVALID, 0.5), false, 2.0)
			draw_line(r.position, r.end, Color(COLOR_INVALID, 0.6), 2.0)
			draw_line(Vector2(r.position.x, r.end.y), Vector2(r.end.x, r.position.y), Color(COLOR_INVALID, 0.6), 2.0)

	for entry in _pending:
		var g: Ghost = entry["ghost"]
		BuildingLayer.draw_building(self, g.def, g.origin, g.rotation, Color(1, 1, 1, 0.35))
		draw_rect(Rect2(Vector2(g.origin) * t, g.def.get_pixel_size()).grow(-1.0), Color(COLOR_VALID, 0.5), false, 1.0)

	if _area_rect.size != Vector2i.ZERO:
		var r := Rect2(Vector2(_area_rect.position) * t, Vector2(_area_rect.size) * t)
		draw_rect(r, Color(COLOR_AREA, 0.14), true)
		draw_rect(r, Color(COLOR_AREA, 0.9), false, 2.0)
	for b in _area_targets:
		if b.id != 0:
			draw_rect(b.get_world_rect().grow(-1.0), COLOR_AREA, false, 2.0)


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
