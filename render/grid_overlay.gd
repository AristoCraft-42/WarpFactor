class_name GridOverlay
extends Node2D
## Сетка тайлов поверх пола. Один прямоугольник с шейдером — стоимость не зависит от размера карты.
## В отладочном режиме дополнительно показывает границы чанков.

const SHADER := preload("res://render/shaders/grid.gdshader")

var _size_px: Vector2 = Vector2.ZERO
var _material: ShaderMaterial


func setup(grid: WorldGrid) -> void:
	_size_px = grid.get_pixel_size()
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("tile_size", float(GameConst.TILE_SIZE))
	_material.set_shader_parameter("chunk_tiles", float(GameConst.CHUNK_SIZE))
	material = _material
	queue_redraw()


func set_chunk_lines_visible(enabled: bool) -> void:
	_material.set_shader_parameter("chunk_color", Color(0.98, 0.74, 0.18, 0.55 if enabled else 0.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, _size_px), Color.WHITE)
