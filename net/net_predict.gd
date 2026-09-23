class_name NetPredict
extends RefCounted
## Предсказание своих действий в сетевой игре: чтобы клик отзывался сразу, а не через задержку.
##
## В общей симуляции команда применится только тогда, когда её назначит хост, — это сотни
## миллисекунд. Предсказание показывает результат сразу: перекладывание в инвентарь и из сундука,
## трату построек при установке, возврат при сносе, добычу и очередь крафта.
##
## Правило, на котором всё держится: **симуляция не трогается**. Предсказание живёт в копиях
## инвентарей и в пометках; интерфейс читает их вместо настоящих, а мир идёт своим ходом. Иначе
## мир у игроков разойдётся — ровно та беда, которую мы уже ловили.
##
## Когда команда применяется по-настоящему (Run.command_applied), её предсказание снимается,
## и интерфейс снова показывает то, что в мире. Если хост решил иначе (напарник успел забрать
## предмет первым), значение на экране поправится — это и есть цена мгновенного отклика.

## Дольше этого предсказание не живёт: команда потерялась или её отвергли.
const KEEP_TICKS := 120

## Растёт при каждой смене предсказания — интерфейсу это знак обновиться.
var revision: int = 0

var _run: Run
## Свои отданные, но ещё не применённые команды.
var _ops: Array[Command] = []
## Тик отдачи по номеру команды.
var _sent_tick: Dictionary[int, int] = {}
## Предсказанные копии: инвентарь своего дрона и инвентари зданий (по id).
var _drone_inv: Inventory
var _store_inv: Dictionary[int, Inventory] = {}
## Здания, которые вот-вот снесут, и тайл, который вот-вот начнут добывать.
var _removing: Dictionary[int, bool] = {}
var _mine_tile: Vector2i = Drone.NO_TILE
## Рецепты, которые вот-вот встанут в очередь крафта: [рецепт, сколько].
var _crafts: Array = []
## Кадр и состояние настоящего инвентаря, на которых копии пересчитаны в последний раз.
var _built_frame: int = -1
var _built_revision: int = -1


func setup(run: Run) -> void:
	_drop_all()
	if _run != null:
		if _run.command_sent.is_connected(_on_sent):
			_run.command_sent.disconnect(_on_sent)
		if _run.command_applied.is_connected(_on_applied):
			_run.command_applied.disconnect(_on_applied)
	_run = run
	if _run != null:
		_run.command_sent.connect(_on_sent)
		_run.command_applied.connect(_on_applied)


func is_active() -> bool:
	return _run != null and not _ops.is_empty()


## Инвентарь дрона для показа: предсказанная копия своего, настоящий — у остальных.
func inventory_of(drone: Drone) -> Inventory:
	if drone == null or _run == null or _ops.is_empty() or drone != _local_drone():
		return drone.inventory if drone != null else null
	_build()
	return _drone_inv if _drone_inv != null else drone.inventory


## Инвентарь здания для показа (пусто — у здания его нет).
func inventory_of_building(building: Building) -> Inventory:
	if building == null:
		return null
	if _run == null or _ops.is_empty():
		return building.get_inventory()
	_build()
	return _store_inv.get(building.id, building.get_inventory())


## Здание уже отмечено к сносу (команда в пути).
func is_removing(building: Building) -> bool:
	if building == null or _ops.is_empty():
		return false
	_build()
	return _removing.has(building.id)


## Здания, снос которых уже отдан командой (для пометки на экране).
func removing_buildings() -> Array[Building]:
	var out: Array[Building] = []
	if _ops.is_empty():
		return out
	_build()
	for id in _removing:
		var b := _building(int(id))
		if b != null:
			out.append(b)
	return out


## Тайл, который дрон вот-вот начнёт добывать (NO_TILE — такой команды в пути нет).
func mining_tile() -> Vector2i:
	if _ops.is_empty():
		return Drone.NO_TILE
	_build()
	return _mine_tile


## Рецепты, которые вот-вот встанут в очередь крафта: [[рецепт, сколько], …].
func pending_crafts() -> Array:
	if _ops.is_empty():
		return []
	_build()
	return _crafts


func _local_drone() -> Drone:
	var player := _run.get_local_player() if _run != null else null
	return player.drone if player != null else null


func _on_sent(cmd: Command) -> void:
	if _run == null or cmd.player != _run.local_player or not _is_predictable(cmd.kind):
		return
	_ops.append(cmd)
	_sent_tick[cmd.seq] = _run.get_tick()
	_changed()


func _on_applied(cmd: Command) -> void:
	if _run == null or cmd.player != _run.local_player or _ops.is_empty():
		return
	var before := _ops.size()
	_ops = _ops.filter(func(op: Command) -> bool: return op.seq != cmd.seq)
	# Потерявшиеся предсказания (команду отвергли, мир починили снимком) убираем по времени.
	var oldest := _run.get_tick() - KEEP_TICKS
	_ops = _ops.filter(func(op: Command) -> bool: return int(_sent_tick.get(op.seq, 0)) > oldest)
	if _ops.size() != before:
		_sent_tick.erase(cmd.seq)
		_changed()


static func _is_predictable(kind: Command.Kind) -> bool:
	return kind in [Command.Kind.TAKE, Command.Kind.PUT, Command.Kind.TAKE_OUTPUT, Command.Kind.FILL,
		Command.Kind.BUILD, Command.Kind.REMOVE, Command.Kind.MINE, Command.Kind.CRAFT]


func _changed() -> void:
	revision += 1
	_built_frame = -1


func _drop_all() -> void:
	_ops.clear()
	_sent_tick.clear()
	_store_inv.clear()
	_removing.clear()
	_crafts.clear()
	_drone_inv = null
	_mine_tile = Drone.NO_TILE
	_built_frame = -1


## Пересчитать копии: берём настоящее состояние и проигрываем по нему свои команды в пути.
## Раз в кадр — мир под ними меняется (добыча, крафт), и копии должны идти за ним.
func _build() -> void:
	var frame := int(Engine.get_process_frames())
	var drone := _local_drone()
	var revision := drone.inventory.revision if drone != null else -1
	if _built_frame == frame and _built_revision == revision:
		return
	_built_frame = frame
	_built_revision = revision
	_store_inv.clear()
	_removing.clear()
	_crafts.clear()
	_mine_tile = Drone.NO_TILE
	if drone == null:
		_drone_inv = null
		return
	_drone_inv = _copy(drone.inventory)
	for op in _ops:
		_apply(op, drone)


static func _copy(inventory: Inventory) -> Inventory:
	var copy := Inventory.new(inventory.size(), inventory.auto_sort)
	var slots := inventory.save_slots()
	copy.load_slots(slots["slot_items"], slots["slot_counts"], slots["hints"])
	return copy


## Копия инвентаря здания (пусто — у здания его нет, тогда предсказываем только свою сторону).
func _store_of(building: Building) -> Inventory:
	if building == null:
		return null
	if _store_inv.has(building.id):
		return _store_inv[building.id]
	var real := building.get_inventory()
	if real == null:
		return null
	var copy := _copy(real)
	_store_inv[building.id] = copy
	return copy


func _building(id: int) -> Building:
	var drone := _local_drone()
	if drone == null or drone.world == null or drone.world.buildings == null:
		return null
	return drone.world.buildings.get_by_id(id)


func _apply(cmd: Command, drone: Drone) -> void:
	var args := cmd.args
	match cmd.kind:
		Command.Kind.TAKE:
			_take(_building(int(args.get("id", 0))), int(args.get("item", -1)), int(args.get("amount", 0)))
		Command.Kind.TAKE_OUTPUT:
			var b := _building(int(args.get("id", 0)))
			if b != null:
				for stack in b.get_player_output_stacks():
					_take(b, stack.x, stack.y)
		Command.Kind.PUT:
			_put(_building(int(args.get("id", 0))), int(args.get("item", -1)), int(args.get("amount", 0)))
		Command.Kind.FILL:
			var b := _building(int(args.get("id", 0)))
			if b != null and b.accepts_player_items():
				for item in _drone_inv.totals.size():
					if _drone_inv.count(item) > 0 and b.accept_item(null, item):
						_put(b, item, _drone_inv.count(item))
		Command.Kind.BUILD:
			if drone.world != null and drone.world.creative:
				return
			for entry in (args.get("places", []) as Array):
				var def := Registry.get_building(StringName((entry as Dictionary).get("def", "")))
				if def != null and def.item != null:
					_drone_inv.remove(def.item.index, 1)
		Command.Kind.REMOVE:
			for id in (args.get("ids", PackedInt32Array()) as PackedInt32Array):
				var b := _building(id)
				if b == null:
					continue
				_removing[b.id] = true
				if b.def.item != null and not (drone.world != null and drone.world.creative):
					_drone_inv.add(b.def.item.index, 1)
		Command.Kind.MINE:
			_mine_tile = args.get("tile", Drone.NO_TILE)
		Command.Kind.CRAFT:
			var recipe := Registry.get_hand_recipe(int(args.get("item", -1)))
			if recipe != null:
				_crafts.append([recipe, int(args.get("count", 1))])


## Забрать из здания в инвентарь — как player_take, но по копиям.
func _take(building: Building, item: int, amount: int) -> void:
	if building == null or item < 0 or amount <= 0:
		return
	var room := _drone_inv.space_for(item)
	if room <= 0:
		return
	var have := 0
	var store := _store_of(building)
	if store != null:
		have = store.count(item)
	else:
		for stack in building.get_player_stacks():
			if stack.x == item:
				have = stack.y
				break
	var taken := mini(mini(amount, room), have)
	if taken <= 0:
		return
	if store != null:
		store.remove(item, taken)
	_drone_inv.add(item, taken)


## Положить в здание — как player_put, но по копиям. Сколько примет здание, у которого нет своего
## инвентаря (печь, турель), заранее не известно: считаем, что примет, — это лишь показ.
func _put(building: Building, item: int, amount: int) -> void:
	if building == null or item < 0 or amount <= 0:
		return
	var limit := mini(amount, _drone_inv.count(item))
	var store := _store_of(building)
	if store != null:
		limit = mini(limit, store.space_for(item))
	if limit <= 0:
		return
	_drone_inv.remove(item, limit)
	if store != null:
		store.add(item, limit)
