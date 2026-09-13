shader_type canvas_item;
// Предметы на лентах: один MultiMesh, все иконки в атласе-полосе.
// INSTANCE_CUSTOM.r — номер ячейки атласа (индекс предмета).

uniform float cells = 1.0;

void vertex() {
	UV = vec2((UV.x + INSTANCE_CUSTOM.r) / cells, UV.y);
}
