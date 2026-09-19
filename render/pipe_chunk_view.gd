class_name PipeChunkView
extends Node2D
## Трубы одного чанка: стыки со сторонами-соседями и квадрат заполнения сети.
## _draw() вызывается только по queue_redraw() от PipeLayer.

const JOINT_DARK := Color(0.11, 0.13, 0.13)

var world: GameWorld
var pipes: Array[Building] = []


func _draw() -> void:
	if world == null or world.fluids == null:
		return
	var fluids := world.fluids
	var t := float(GameConst.TILE_SIZE)
	for pipe in pipes:
		if pipe.world == null:
			continue
		var center := pipe.get_world_rect().get_center()
		var body := pipe.def.color
		for side in 4:
			if not fluids.pipe_connects(pipe, side):
				continue
			var dir := Vector2(GameConst.dir_vector(side))
			var a := center + dir * 5.0
			var b := center + dir * (t * 0.5)
			draw_line(a, b, JOINT_DARK, 14.0)
			draw_line(a, b, body, 10.0)
			draw_line(a + Vector2(dir.y, -dir.x) * 3.0, b + Vector2(dir.y, -dir.x) * 3.0, body.lightened(0.25), 2.0)
		var net := fluids.get_pipe_network(pipe)
		if net != null and net.fluid >= 0 and net.capacity > 0.0:
			var fill := clampf(net.amount / net.capacity, 0.0, 1.0)
			var col := Registry.fluids[net.fluid].color
			draw_rect(Rect2(center - Vector2(4, 4), Vector2(8, 8)), Color(col, 0.35 + 0.65 * fill), true)
