class_name ResearchTreeView
extends Control
## Дерево исследований: карточки по столбцам глубины (столбец — длина самой длинной цепочки предшественников),
## линии от предшественника к следующему. Цвет линии: завершено — зелёный, доступно — жёлтый, закрыто — серый.
## Карточки создаёт окно исследований и отдаёт сюда вместе с их id.

const CARD_SIZE := Vector2(272, 124)
const COLUMN_GAP := 64.0
const ROW_GAP := 14.0

const LINE_DONE := Color(0.72, 0.73, 0.15)
const LINE_AVAILABLE := Color(0.98, 0.74, 0.18)
const LINE_LOCKED := Color(0.4, 0.37, 0.33)

var state: ResearchState

var _cells: Dictionary[StringName, Vector2i] = {}


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


func _draw() -> void:
	for r in Registry.researches:
		if not _cells.has(r.id):
			continue
		var to := cell_position(_cells[r.id]) + Vector2(0.0, CARD_SIZE.y * 0.5)
		for p in r.prerequisites:
			if not _cells.has(p):
				continue
			var from := cell_position(_cells[p]) + Vector2(CARD_SIZE.x, CARD_SIZE.y * 0.5)
			var mid_x := from.x + COLUMN_GAP * 0.5
			var col := LINE_LOCKED
			if state != null:
				if state.is_done(r.id):
					col = LINE_DONE
				elif state.is_available(r):
					col = LINE_AVAILABLE
			var points := PackedVector2Array([from, Vector2(mid_x, from.y), Vector2(mid_x, to.y), to])
			draw_polyline(points, Color(0, 0, 0, 0.5), 5.0)
			draw_polyline(points, col, 3.0)
			draw_colored_polygon(PackedVector2Array([to, to + Vector2(-9, -6), to + Vector2(-9, 6)]), col)
