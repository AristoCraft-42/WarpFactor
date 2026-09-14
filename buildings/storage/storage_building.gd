class_name StorageBuilding
extends Building
## Склад (контейнер, хранилище): инвентарь из ячеек. Принимает любые предметы со всех сторон,
## пока для них есть место; когда места нет — лента перед складом встаёт и ждёт.
## Предметы достают разгрузчики или игрок руками.

var inventory: Inventory


func on_placed() -> void:
	if inventory == null:
		inventory = Inventory.new((def as StorageDef).slots)


func get_inventory() -> Inventory:
	return inventory


func accept_item(_source: Building, item: int) -> bool:
	return inventory != null and inventory.space_for(item) > 0


func handle_item(_source: Building, item: int) -> void:
	inventory.add(item, 1)
	# Разгрузчики, ждущие появления предметов.
	if world != null and world.simulation.has_waiters(id):
		notify_space()


func can_unload() -> bool:
	return true


func get_load_factor(item: int) -> float:
	if inventory == null:
		return 0.0
	return float(inventory.count(item)) / maxi(inventory.count(item) + inventory.space_for(item), 1)


func has_item(item: int) -> bool:
	return inventory != null and inventory.count(item) > 0


func unload_item(item: int) -> bool:
	if inventory == null or inventory.remove(item, 1) == 0:
		return false
	# Освободилось место — ленты, ждущие у склада, могут продолжить.
	notify_space()
	return true


func accepts_player_items() -> bool:
	return true


func take_player_items(item: int, amount: int) -> int:
	if inventory == null:
		return 0
	var taken := inventory.remove(item, amount)
	if taken > 0:
		notify_space()
	return taken


func save_state() -> Dictionary:
	if inventory == null:
		return {}
	return {"slot_items": inventory.slot_items.duplicate(), "slot_counts": inventory.slot_counts.duplicate()}


func load_state(state: Dictionary) -> void:
	if inventory == null:
		return
	inventory.clear()
	var src_items: PackedInt32Array = state.get("slot_items", PackedInt32Array())
	var src_counts: PackedInt32Array = state.get("slot_counts", PackedInt32Array())
	for i in mini(src_items.size(), src_counts.size()):
		if src_items[i] >= 0 and src_items[i] < Registry.items.size():
			inventory.add(src_items[i], src_counts[i])
	notify_space()


func collect_contents(out: PackedInt32Array) -> void:
	if inventory != null:
		inventory.collect_into(out)


func get_info_lines() -> PackedStringArray:
	if inventory == null:
		return PackedStringArray()
	return PackedStringArray([tr("INFO_SLOTS") % [inventory.used_slots(), inventory.size()]])
