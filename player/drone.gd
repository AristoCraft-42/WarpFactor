class_name Drone
extends RefCounted
## Дрон игрока — модель без нод: позиция, инвентарь, добыча руды, очередь ручного крафта.
## Обновляется в тике симуляции; отрисовка интерполирует между prev_position и position.
## Все действия игрока в мире проверяют радиус дрона (can_reach_*).

const NO_TILE := Vector2i(-1, -1)

var def: DroneDef
var world: GameWorld
## Центр дрона в пикселях мира.
var position: Vector2 = Vector2.ZERO
var prev_position: Vector2 = Vector2.ZERO
## Направление движения от ввода (длина ≤ 1); выставляется контроллером каждый кадр.
var move_input: Vector2 = Vector2.ZERO
## Угол, куда смотрит дрон (радианы).
var facing: float = 0.0
var inventory: Inventory
var crafting: CraftQueue
## Тайл, который дрон добывает (NO_TILE — не добывает).
var mine_tile: Vector2i = NO_TILE
var mine_progress: int = 0
## Добыча стоит: нет руды, далеко, мешает здание или инвентарь полон.
var mine_blocked: bool = false


func _init(p_def: DroneDef, p_world: GameWorld, spawn: Vector2) -> void:
	def = p_def
	world = p_world
	position = spawn
	prev_position = spawn
	inventory = Inventory.new(def.inventory_slots, true)
	crafting = CraftQueue.new(inventory, def.craft_speed)


func get_reach_px() -> float:
	return def.get_reach_px()


## Достаёт ли дрон до прямоугольника в пикселях (до его ближайшей точки).
func can_reach_rect(rect: Rect2) -> bool:
	var nearest := position.clamp(rect.position, rect.end)
	return nearest.distance_to(position) <= def.get_reach_px()


func can_reach_tiles(rect: Rect2i) -> bool:
	return can_reach_rect(Rect2(Vector2(rect.position * GameConst.TILE_SIZE), Vector2(rect.size * GameConst.TILE_SIZE)))


func get_tile() -> Vector2i:
	return GameConst.world_to_tile(position)


## Руда тайла, которую дрон в принципе может добывать (без учёта радиуса и места), или null.
func get_mineable_ore(tile: Vector2i) -> OreDef:
	if world == null or not world.grid.in_bounds_v(tile):
		return null
	var ore := world.grid.get_ore_def(tile.x, tile.y)
	if ore == null or ore.item == null or ore.hardness > def.mine_tier:
		return null
	if world.buildings.get_at(tile) != null:
		return null
	return ore


func set_mine_target(tile: Vector2i) -> void:
	if tile == mine_tile:
		return
	mine_tile = tile
	mine_progress = 0
	mine_blocked = false


func stop_mining() -> void:
	set_mine_target(NO_TILE)


func is_mining() -> bool:
	return mine_tile != NO_TILE


## Доля добычи текущего предмета (0..1).
func get_mine_fraction() -> float:
	var ore := get_mineable_ore(mine_tile) if is_mining() else null
	if ore == null:
		return 0.0
	return clampf(float(mine_progress) / def.mine_ticks(ore), 0.0, 1.0)


func save_data() -> Dictionary:
	return {"position": position, "prev_position": prev_position, "facing": facing,
		"mine_tile": mine_tile, "mine_progress": mine_progress,
		"inventory": inventory.save_slots(), "crafting": crafting.save_data()}


func load_data(data: Dictionary) -> void:
	position = data.get("position", position)
	prev_position = data.get("prev_position", position)
	facing = float(data.get("facing", 0.0))
	mine_tile = data.get("mine_tile", NO_TILE)
	mine_progress = int(data.get("mine_progress", 0))
	move_input = Vector2.ZERO
	var slots: Dictionary = data.get("inventory", {})
	inventory.load_slots(slots.get("slot_items", PackedInt32Array()), slots.get("slot_counts", PackedInt32Array()),
		slots.get("hints", PackedInt32Array()))
	crafting.load_data(data.get("crafting", {}))


func get_draw_position(alpha: float) -> Vector2:
	return prev_position.lerp(position, alpha)


func update_tick(_tick: int) -> void:
	prev_position = position
	if move_input != Vector2.ZERO:
		var step := move_input.limit_length(1.0) * def.get_speed_per_tick()
		position = (position + step).clamp(Vector2.ZERO, world.grid.get_pixel_size())
		facing = move_input.angle()
	if is_mining():
		_mine()
	crafting.update_tick()


func _mine() -> void:
	var ore := get_mineable_ore(mine_tile)
	var tile_rect := Rect2i(mine_tile, Vector2i.ONE)
	mine_blocked = ore == null or not can_reach_tiles(tile_rect) or inventory.space_for(ore.item.index) <= 0
	if mine_blocked:
		return
	mine_progress += 1
	if mine_progress >= def.mine_ticks(ore):
		mine_progress = 0
		inventory.add(ore.item.index, 1)
