class_name BuildingChunkView
extends Node2D
## Все здания одного чанка. _draw() вызывается только после queue_redraw() от BuildingLayer.

var chunk_index: int = 0
var world: GameWorld


func _draw() -> void:
	if world == null or world.buildings == null:
		return
	var manager := world.buildings
	for id in manager.get_chunk_ids(chunk_index):
		var b := manager.get_by_id(id)
		if b != null:
			BuildingLayer.draw_building(self, b.def, b.origin, b.rotation, Color.WHITE, b.get_size(), b.get_art_state())
	# Детали рисуются вторым проходом, чтобы не разрывать батч основных спрайтов.
	for id in manager.get_chunk_ids(chunk_index):
		var b := manager.get_by_id(id)
		if b != null and (b.get_display_item() >= 0 or b.is_inverted() or b is BridgeConveyor or b is GatewayBuilding \
				or (b is Router and (b as Router).has_priorities())):
			BuildingLayer.draw_building_extras(self, b)
