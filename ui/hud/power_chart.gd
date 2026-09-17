class_name PowerChart
extends Control
## График окна электросети: несколько рядов значений (спрос, выработка, заряд) линиями от 0 до max_value,
## последняя точка — справа. Сетка из четырёх делений и подпись верха шкалы.

var series: Array[PackedFloat32Array] = []
var colors := PackedColorArray()
var max_value: float = 1.0
var top_label: String = ""


func _init() -> void:
	custom_minimum_size = Vector2(0, 130)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_data(p_series: Array[PackedFloat32Array], p_colors: PackedColorArray, p_max: float, p_top_label: String) -> void:
	series = p_series
	colors = p_colors
	max_value = maxf(p_max, 0.001)
	top_label = p_top_label
	queue_redraw()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.11, 0.13, 0.13, 0.9), true)
	for i in range(1, 4):
		var y := rect.size.y * i / 4.0
		draw_line(Vector2(0, y), Vector2(rect.size.x, y), Color(1, 1, 1, 0.06), 1.0)
	var font := get_theme_default_font()
	if font != null and not top_label.is_empty():
		draw_string(font, Vector2(4, 13), top_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.45))
	var slots := float(PowerGraph.HISTORY_SIZE - 1)
	for k in series.size():
		var values := series[k]
		if values.size() < 2:
			continue
		var points := PackedVector2Array()
		var start := PowerGraph.HISTORY_SIZE - values.size()
		for i in values.size():
			var x := rect.size.x * (start + i) / slots
			var y := rect.size.y - clampf(values[i] / max_value, 0.0, 1.0) * (rect.size.y - 4.0) - 2.0
			points.append(Vector2(x, y))
		draw_polyline(points, colors[k] if k < colors.size() else Color.WHITE, 2.0, true)
