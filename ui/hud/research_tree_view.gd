class_name ResearchTreeView
extends Control
## Дерево исследований: карточки по столбцам глубины (столбец — длина самой длинной цепочки предшественников),
## связи от предшественника к следующему. Карточки создаёт окно исследований и отдаёт сюда вместе с их id.
##
## Связи — плавные кривые, а не ступеньки: у ступенек вертикальные отрезки от разных
## предшественников ложились на одну линию посреди промежутка, и было не понять, что куда ведёт.
## Толщина и яркость говорят о состоянии: следующие шаги (доступно) — ярче и толще,
## изученное — спокойным зелёным, закрытое — тонко и бледно. При наведении на карточку
## подсвечивается её цепочка: всё, что нужно до неё, и что она открывает; остальное гаснет.

const CARD_SIZE := Vector2(272, 124)
const COLUMN_GAP := 84.0
const ROW_GAP := 18.0
## Точек на кривой связи.
const CURVE_POINTS := 18

const LINE_DONE := Color(0.72, 0.73, 0.15)
const LINE_AVAILABLE := Color(0.98, 0.74, 0.18)
const LINE_LOCKED := Color(0.4, 0.37, 0.33)
const LINE_FOCUS := Color(0.99, 0.93, 0.7)

var state: ResearchState
## Карточка под мышью (пусто — ничего не подсвечено).
var hovered: StringName = &""

var _cells: Dictionary[StringName, Vector2i] = {}
## Цепочка карточки под мышью: её предшественники (все уровни) и те, что она открывает сразу.
var _focus: Dictionary[StringName, bool] = {}


## Столбец и ряд каждого исследования. Ряд — не выше ряда первого предшественника, чтобы ветка шла прямо.
static func layout(researches: Array[ResearchDef]) -> Dictionary[StringName, Vector2i]:
	var depth: Dictionary[StringName, int] = {}
	for r in researches:
		depth[r.id] = 0
	for _pass in researches.size():
		for r in researches:
			for p in r.prerequisites:
				if depth.has(p):
					depth[r.id] = maxi(depth[r.id], depth[p] + 1)
	var max_depth := 0
	for r in researches:
		max_depth = maxi(max_depth, depth[r.id])
	var cells: Dictionary[StringName, Vector2i] = {}
	for column in max_depth + 1:
		var entries: Array = []
		for r in researches:
			if depth[r.id] != column:
				continue
			var parent_row := 0
			var first := true
			for p in r.prerequisites:
				if cells.has(p):
					parent_row = cells[p].y if first else mini(parent_row, cells[p].y)
					first = false
			entries.append([parent_row, r.sort_order, r.id])
		entries.sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
		var next_row := 0
		for e in entries:
			var row := maxi(next_row, int(e[0]))
			cells[e[2]] = Vector2i(column, row)
			next_row = row + 1
	return cells


func setup(cards: Dictionary[StringName, Control]) -> void:
	_cells = layout(Registry.researches)
	var extent := Vector2i.ZERO
	for id in cards:
		var cell: Vector2i = _cells.get(id, Vector2i.ZERO)
		var card := cards[id]
		add_child(card)
		card.position = cell_position(cell)
		card.size = CARD_SIZE
		extent = Vector2i(maxi(extent.x, cell.x + 1), maxi(extent.y, cell.y + 1))
	custom_minimum_size = Vector2(extent.x * CARD_SIZE.x + (extent.x - 1) * COLUMN_GAP,
		extent.y * CARD_SIZE.y + (extent.y - 1) * ROW_GAP)


func get_cell(id: StringName) -> Vector2i:
	return _cells.get(id, Vector2i(-1, -1))


static func cell_position(cell: Vector2i) -> Vector2:
	return Vector2(cell.x * (CARD_SIZE.x + COLUMN_GAP), cell.y * (CARD_SIZE.y + ROW_GAP))


## Подсветить цепочку карточки id (пусто — снять подсветку).
func set_hovered(id: StringName) -> void:
	if id == hovered:
		return
	hovered = id
	_focus.clear()
	if id != &"":
		_focus[id] = true
		_collect_ancestors(id)
		for r in Registry.researches:
			if r.prerequisites.has(id):
				_focus[r.id] = true
	queue_redraw()


## Входит ли исследование в подсвеченную цепочку (когда ничего не подсвечено — входят все).
func in_focus(id: StringName) -> bool:
	return hovered == &"" or _focus.has(id)


func _collect_ancestors(id: StringName) -> void:
	var research := Registry.get_research(id)
	if research == null:
		return
	for p in research.prerequisites:
		if not _focus.has(p):
			_focus[p] = true
			_collect_ancestors(p)


func _draw() -> void:
	# Сначала обычные связи, поверх — подсвеченные, чтобы их ничто не перекрывало.
	for pass_focus in [false, true]:
		for r in Registry.researches:
			if not _cells.has(r.id):
				continue
			var to := cell_position(_cells[r.id]) + Vector2(0.0, CARD_SIZE.y * 0.5)
			for p in r.prerequisites:
				if not _cells.has(p):
					continue
				var focused := hovered != &"" and _focus.has(r.id) and _focus.has(p)
				if focused != pass_focus:
					continue
				var from := cell_position(_cells[p]) + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5)
				_draw_link(from, to, r, focused)


## Одна связь: плавная кривая от правого края предшественника к левому краю следующего.
func _draw_link(from: Vector2, to: Vector2, r: ResearchDef, focused: bool) -> void:
	var col := LINE_LOCKED
	var width := 1.5
	if state != null:
		if state.is_done(r.id):
			col = LINE_DONE
			width = 2.0
		elif state.is_available(r):
			col = LINE_AVAILABLE
			width = 3.0
	if focused:
		col = LINE_FOCUS
		width = 3.5
	elif hovered != &"":
		col = Color(col, 0.18)
	elif col == LINE_LOCKED:
		col = Color(col, 0.7)
	var bend := maxf((to.x - from.x) * 0.5, 24.0)
	var points := PackedVector2Array()
	points.resize(CURVE_POINTS + 1)
	for i in CURVE_POINTS + 1:
		var t := float(i) / CURVE_POINTS
		points[i] = from.bezier_interpolate(from + Vector2(bend, 0.0), to - Vector2(bend, 0.0), to, t)
	if col.a > 0.5:
		draw_polyline(points, Color(0, 0, 0, 0.45 * col.a), width + 2.0, true)
	draw_polyline(points, col, width, true)
	var tip := 6.0 + width
	draw_colored_polygon(PackedVector2Array([to, to + Vector2(-tip, -tip * 0.6), to + Vector2(-tip, tip * 0.6)]), col)
