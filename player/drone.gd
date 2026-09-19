class_name Drone
extends RefCounted
## Дрон игрока — модель без нод: позиция, инвентарь, добыча руды, очередь ручного крафта,
## автопушка (бьёт ближайшего врага в радиусе) и бесплатный ремонт построек в радиусе строительства.
## Обновляется в тике симуляции; отрисовка интерполирует между prev_position и position.
## Все действия игрока в мире проверяют радиус дрона (can_reach_*).

const NO_TILE := Vector2i(-1, -1)

var def: DroneDef
## id игрока, которому принадлежит дрон (0 — ничей, например в тестовом мире).
var player_id: int = 0
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
## Последняя добыча для надписи над тайлом (только отрисовка, в сохранение не идёт):
## что добыли, сколько его стало в инвентаре, где и в каком тике.
var last_mined_item: int = -1
var last_mined_count: int = 0
var last_mined_tile: Vector2i = NO_TILE
var last_mined_tick: int = -100000
var health: float = 0.0
## Дрон сбит и ждёт появления у шлюза (respawn_tick).
var dead: bool = false
var respawn_tick: int = 0
## До этого тика враги дрона не трогают (после появления).
var invulnerable_until: int = 0
var gun_ready_tick: int = 0
## Для отрисовки: куда смотрит пушка и когда был выстрел (не сохраняется).
var gun_angle: float = 0.0
var last_gun_tick: int = -1000
## Чинимое здание (0 — нет) и тик следующего поиска повреждённых.
var repair_target: int = 0
var repair_search_tick: int = 0
## Ступени улучшений из исследований (Run.apply_research_effects, в сохранение не пишутся).
var upgrade_speed: int = 0
var upgrade_mining: int = 0
var upgrade_health: int = 0
var upgrade_gun: int = 0
var upgrade_repair: int = 0

## Раз в сколько тиков дрон ищет, что починить, если чинить нечего.
const REPAIR_SEARCH_TICKS := 10


func _init(p_def: DroneDef, p_world: GameWorld, spawn: Vector2) -> void:
	def = p_def
	world = p_world
	position = spawn
	prev_position = spawn
	health = def.health
	inventory = Inventory.new(def.inventory_slots, true)
	crafting = CraftQueue.new(inventory, def.craft_speed)


## Пересчитать ступени улучшений по исследованиям. heal — подлечить дрона на прирост прочности
## (при завершении исследования); на загрузке heal = false, иначе разойдётся сохранение.
func apply_upgrades(research: ResearchState, heal: bool) -> void:
	var was_max := get_max_health()
	upgrade_speed = research.count_effect(&"drone_speed")
	upgrade_mining = research.count_effect(&"drone_mining")
	upgrade_health = research.count_effect(&"drone_health")
	upgrade_gun = research.count_effect(&"drone_gun")
	upgrade_repair = research.count_effect(&"drone_repair")
	var grown := get_max_health() - was_max
	if heal and grown > 0.0 and not dead:
		health += grown
	health = minf(health, get_max_health())


func get_speed() -> float:
	return def.speed + def.speed_step * upgrade_speed


func get_speed_per_tick() -> float:
	return get_speed() * GameConst.TILE_SIZE / GameConst.TICK_RATE


func get_max_health() -> float:
	return def.health + def.health_step * upgrade_health


func get_gun_damage() -> float:
	return def.gun_damage + def.gun_damage_step * upgrade_gun


func get_repair_per_second() -> float:
	return def.repair_per_second + def.repair_step * upgrade_repair


## Тиков на один предмет с учётом улучшений добычи.
func get_mine_ticks(ore: OreDef) -> int:
	return maxi(1, roundi(def.mine_ticks(ore) / (1.0 + def.mine_speed_step * upgrade_mining)))


## Переезд в другой мир: мир держит список своих дронов, поэтому менять world напрямую нельзя.
func move_to_world(next: GameWorld) -> void:
	if world == next:
		return
	if world != null:
		world.remove_drone(self)
	world = next
	if next != null:
		next.add_drone(self)


func is_alive() -> bool:
	return not dead


## Могут ли враги атаковать дрона в этот тик.
func is_targetable(tick: int) -> bool:
	return not dead and tick >= invulnerable_until


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
	return clampf(float(mine_progress) / get_mine_ticks(ore), 0.0, 1.0)


func save_data() -> Dictionary:
	return {"position": position, "prev_position": prev_position, "facing": facing,
		"mine_tile": mine_tile, "mine_progress": mine_progress,
		"health": health, "dead": dead, "respawn_tick": respawn_tick, "invulnerable_until": invulnerable_until,
		"gun_ready": gun_ready_tick, "repair_target": repair_target, "repair_search": repair_search_tick,
		"inventory": inventory.save_slots(), "crafting": crafting.save_data()}


func load_data(data: Dictionary) -> void:
	position = data.get("position", position)
	prev_position = data.get("prev_position", position)
	facing = float(data.get("facing", 0.0))
	mine_tile = data.get("mine_tile", NO_TILE)
	mine_progress = int(data.get("mine_progress", 0))
	health = float(data.get("health", get_max_health()))
	dead = bool(data.get("dead", false))
	respawn_tick = int(data.get("respawn_tick", 0))
	invulnerable_until = int(data.get("invulnerable_until", 0))
	gun_ready_tick = int(data.get("gun_ready", 0))
	repair_target = int(data.get("repair_target", 0))
	repair_search_tick = int(data.get("repair_search", 0))
	move_input = Vector2.ZERO
	var slots: Dictionary = data.get("inventory", {})
	inventory.load_slots(slots.get("slot_items", PackedInt32Array()), slots.get("slot_counts", PackedInt32Array()),
		slots.get("hints", PackedInt32Array()))
	crafting.load_data(data.get("crafting", {}))


func get_draw_position(alpha: float) -> Vector2:
	return prev_position.lerp(position, alpha)


func update_tick(tick: int) -> void:
	prev_position = position
	if dead:
		if tick >= respawn_tick:
			world.respawn_drone(self, tick)
		return
	if move_input != Vector2.ZERO:
		var step := move_input.limit_length(1.0) * get_speed_per_tick()
		var bounds := world.get_play_rect_px()
		position = (position + step).clamp(bounds.position, bounds.end)
		facing = move_input.angle()
	if is_mining():
		_mine()
	crafting.update_tick()
	if not world.crates.is_empty():
		world.pickup_crates()
	if get_gun_damage() > 0.0 and world.enemies.count > 0 and tick >= gun_ready_tick:
		_shoot(tick)
	if get_repair_per_second() > 0.0 and (repair_target != 0 or not world.damaged.is_empty()):
		_repair(tick)


func is_repairing() -> bool:
	return repair_target != 0


func _shoot(tick: int) -> void:
	var enemies := world.enemies
	var target := enemies.find_nearest(position.x, position.y, def.get_gun_range_px())
	if target < 0:
		gun_ready_tick = tick + 5
		return
	var dir := (enemies.get_position(target) - position).normalized()
	if dir == Vector2.ZERO:
		dir = Vector2.RIGHT
	var speed := def.get_gun_speed_per_tick()
	world.projectiles.spawn_bullet(position + dir * 10.0, dir * speed, get_gun_damage(),
		ceili((def.get_gun_range_px() + GameConst.TILE_SIZE) / speed), def.gun_color)
	gun_angle = dir.angle()
	last_gun_tick = tick
	gun_ready_tick = tick + def.get_gun_ticks()


## Бесплатный ремонт: одна постройка за раз, ближайшая повреждённая в радиусе строительства.
func _repair(tick: int) -> void:
	var building := world.buildings.get_by_id(repair_target) if repair_target != 0 else null
	if building != null and (not building.is_damaged() or not can_reach_tiles(building.get_rect())):
		building = null
	if building == null:
		repair_target = 0
		if tick < repair_search_tick:
			return
		repair_search_tick = tick + REPAIR_SEARCH_TICKS
		var best_d := INF
		for id in world.damaged:
			var candidate := world.buildings.get_by_id(id)
			if candidate == null or not candidate.is_damaged() or not can_reach_tiles(candidate.get_rect()):
				continue
			var d := candidate.get_world_center().distance_squared_to(position)
			if d < best_d:
				best_d = d
				building = candidate
		if building == null:
			return
		repair_target = building.id
	world.repair_building(building, get_repair_per_second() / GameConst.TICK_RATE)
	if not building.is_damaged():
		repair_target = 0


func _mine() -> void:
	var ore := get_mineable_ore(mine_tile)
	var tile_rect := Rect2i(mine_tile, Vector2i.ONE)
	mine_blocked = ore == null or not can_reach_tiles(tile_rect) or inventory.space_for(ore.item.index) <= 0
	if mine_blocked:
		return
	mine_progress += 1
	if mine_progress >= get_mine_ticks(ore):
		mine_progress = 0
		inventory.add(ore.item.index, 1)
		last_mined_item = ore.item.index
		last_mined_count = inventory.count(ore.item.index)
		last_mined_tile = mine_tile
		last_mined_tick = world.simulation.tick
