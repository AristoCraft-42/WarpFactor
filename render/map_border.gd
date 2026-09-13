class_name MapBorder
extends Node2D
## Рамка по границе карты: за её пределами строить нельзя.

var _size_px: Vector2 = Vector2.ZERO


func setup(grid: WorldGrid) -> void:
	_size_px = grid.get_pixel_size()
	queue_redraw()


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, _size_px)
	draw_rect(r.grow(6.0), Color(0.05, 0.05, 0.05, 1.0), false, 12.0)
	draw_rect(r.grow(1.0), Color(0.98, 0.74, 0.18, 0.45), false, 2.0)
