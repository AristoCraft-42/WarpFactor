class_name StarMapView
extends Control
## Звёздная карта: шаги слева направо, планеты — кружки цвета типа, связи — линии вперёд.
## Текущая планета обведена, планеты, куда можно лететь, подсвечены; клик выбирает одну из них.
## Подсказка при наведении — тип, размер, руды.

signal node_selected(id: int)

const NODE_RADIUS := 13.0
const MARGIN := 34.0

var selected_id: int = -1

var _run: Run
var _hover_id: int = -1
var _time: float = 0.0


func setup(run: Run) -> void:
	_run = run
	custom_minimum_size = Vector2(520, 280)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(UiTheme.BG_HARD, 0.9))
	if _run == null:
		return
	var map := _run.star_map
	var current := map.get_current()
	var visible_nodes := map.get_visible_nodes()
	var font := get_theme_default_font()
	# Связи.
	for node in visible_nodes:
		if node.depth < current.depth:
			continue
		for target_id in node.links:
			var target := map.get_node(target_id)
			if target == null or target.depth > current.depth + _visible_depth():
				continue
			var from_current := node.id == current.id
			var col := Color(UiTheme.YELLOW, 0.8) if from_current else Color(UiTheme.GRAY, 0.35)
			draw_line(_node_pos(node), _node_pos(target), col, 3.0 if from_current else 1.5)
	# Узлы.
	for node in visible_nodes:
		if node.depth < current.depth:
			continue
		var pos := _node_pos(node)
		var reachable := map.can_travel_to(node.id)
		var base_col := node.type.map_color
		if node.depth > current.depth and not reachable:
			base_col = base_col.darkened(0.35)
		draw_circle(pos, NODE_RADIUS + 3.0, Color(0, 0, 0, 0.5))
		draw_circle(pos, NODE_RADIUS, base_col)
		if node.type.safe:
			draw_arc(pos, NODE_RADIUS - 4.0, 0.0, TAU, 20, Color(1, 1, 1, 0.6), 2.0)
		if node.id == current.id:
			draw_arc(pos, NODE_RADIUS + 5.0, 0.0, TAU, 32, UiTheme.YELLOW, 3.0)
		elif reachable:
			var pulse := 0.5 + 0.5 * sin(_time * 4.0)
			draw_arc(pos, NODE_RADIUS + 4.0 + pulse * 2.0, 0.0, TAU, 32, Color(UiTheme.AQUA, 0.6 + 0.4 * pulse), 2.0)
		if node.id == selected_id:
			draw_arc(pos, NODE_RADIUS + 9.0, 0.0, TAU, 32, UiTheme.FG, 3.0)
		if node.id == _hover_id:
			draw_arc(pos, NODE_RADIUS + 1.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
		draw_string(font, pos + Vector2(-28, NODE_RADIUS + 16), node.code, HORIZONTAL_ALIGNMENT_CENTER, 56, 11, Color(UiTheme.FG, 0.8))


func _gui_input(event: InputEvent) -> void:
	if _run == null:
		return
	if event is InputEventMouseMotion:
		var id := _node_at((event as InputEventMouseMotion).position)
		if id != _hover_id:
			_hover_id = id
			queue_redraw()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var id := _node_at(mb.position)
			if id >= 0 and _run.star_map.can_travel_to(id):
				selected_id = id
				node_selected.emit(id)
				queue_redraw()
			accept_event()


func _get_tooltip(at_position: Vector2) -> String:
	var id := _node_at(at_position)
	if id < 0:
		return ""
	return describe_node(_run.star_map.get_node(id), _run.star_map.can_travel_to(id), _run.star_map.scan_level)


## Текст описания планеты для подсказок и панели выбора.
## scan — что открыла разведка: 0 — ничего, кроме кода планеты; 1 — тип, размер и опасность;
## 2 — ещё и ресурсы. Без разведки игрок летит вслепую, это и есть начало забега.
static func describe_node(node: StarMap.StarNode, reachable: bool, scan: int = 2) -> String:
	var lines := PackedStringArray()
	if scan <= 0:
		lines.append("%s %s" % [TranslationServer.translate("STARMAP_UNKNOWN"), node.code])
		lines.append(TranslationServer.translate("STARMAP_UNKNOWN_HINT"))
		if not reachable:
			lines.append(TranslationServer.translate("STARMAP_UNREACHABLE"))
		return "\n".join(lines)
	lines.append("%s %s" % [TranslationServer.translate(node.type.name_key), node.code])
	lines.append(TranslationServer.translate(node.type.description_key))
	lines.append(TranslationServer.translate("STARMAP_SIZE") % [node.size.x, node.size.y])
	if scan < 2:
		lines.append(TranslationServer.translate("STARMAP_ORES_UNKNOWN"))
	elif node.ores.is_empty():
		lines.append(TranslationServer.translate("STARMAP_NO_ORES"))
	else:
		var names := PackedStringArray()
		for ore_index in node.ores:
			names.append(TranslationServer.translate(Registry.ores[ore_index].get_name_key()))
		lines.append(TranslationServer.translate("STARMAP_ORES") % ", ".join(names))
	lines.append(TranslationServer.translate("STARMAP_SAFE") if node.type.safe else TranslationServer.translate("STARMAP_DANGEROUS"))
	if not reachable:
		lines.append(TranslationServer.translate("STARMAP_UNREACHABLE"))
	return "\n".join(lines)


func _visible_depth() -> int:
	return _run.star_map.get_visible_depth()


func _node_pos(node: StarMap.StarNode) -> Vector2:
	var current_depth := _run.star_map.get_current().depth
	var columns := _visible_depth() + 1
	var col_w := (size.x - MARGIN * 2.0) / maxf(columns - 1, 1)
	var x := MARGIN + (node.depth - current_depth) * col_w
	var y := (size.y - 20.0) * (node.slot + 0.5) / node.slots_in_step + 4.0
	return Vector2(x, y)


func _node_at(pos: Vector2) -> int:
	var current := _run.star_map.get_current()
	for node in _run.star_map.get_visible_nodes():
		if node.depth < current.depth:
			continue
		if _node_pos(node).distance_to(pos) <= NODE_RADIUS + 6.0:
			return node.id
	return -1
