class_name Turret
extends Building
## Турель: принимает патроны (предметы из TurretDef.ammo) с ленты и руками, стреляет по ближайшему врагу.
##
## Запас — стопка видов патронов: последний пришедший вид стреляет первым (как в Mindustry).
## Без патронов турель спит до прихода предмета; без врагов на планете — проверяет раз в IDLE_TICKS;
## без цели в радиусе — ищет раз в SEARCH_TICKS; с целью — бодрствует, поворачивает ствол и стреляет,
## когда ствол смотрит на цель с упреждением. Разброс выстрела — от RNG мира (сохраняется).

const SEARCH_TICKS := 10
const IDLE_TICKS := 15

## Виды патронов (индексы TurretDef.ammo) и число выстрелов каждого; последний — текущий.
var ammo_types := PackedInt32Array()
var ammo_shots := PackedInt32Array()
var total_shots: int = 0
## Направление ствола, радианы.
var angle: float = -PI * 0.5
var reload_until: int = 0
var target_uid: int = 0
var target_index: int = -1
var last_shot_tick: int = -1000
var status: Status = Status.NO_AMMO

## Описание и центр турели кешируются: она не двигается, а тик у неё горячий — при сотне турелей
## в бою эти вызовы складывались в миллисекунды.
var _def: TurretDef
var _center := Vector2.INF


func get_turret_def() -> TurretDef:
	if _def == null:
		_def = def as TurretDef
	return _def


## Середина турели в мире (кешируется).
func center() -> Vector2:
	if _center == Vector2.INF:
		_center = get_world_center()
	return _center


func on_placed() -> void:
	_def = def as TurretDef
	_center = get_world_center()
	world.turrets[id] = self
	wake()


func on_removed() -> void:
	world.turrets.erase(id)


func has_target() -> bool:
	return target_index >= 0


# --- Патроны ---

func accept_item(_source: Building, item: int) -> bool:
	var d := get_turret_def()
	if d.kind != TurretDef.Kind.BULLET:
		return false
	var index := d.find_ammo(item)
	return index >= 0 and total_shots + d.ammo[index].shots_per_item <= d.max_ammo


func handle_item(_source: Building, item: int) -> void:
	var d := get_turret_def()
	var index := d.find_ammo(item)
	if index < 0:
		return
	var shots := d.ammo[index].shots_per_item
	total_shots += shots
	var pos := ammo_types.find(index)
	if pos >= 0 and pos == ammo_types.size() - 1:
		ammo_shots[pos] += shots
	else:
		if pos >= 0:
			shots += ammo_shots[pos]
			ammo_types.remove_at(pos)
			ammo_shots.remove_at(pos)
		ammo_types.append(index)
		ammo_shots.append(shots)
	wake()


## Турель полива подключается к трубам всеми сторонами: одна сеть, любая жидкость.
func get_fluid_ports() -> Array[FluidGraph.Port]:
	var ports: Array[FluidGraph.Port] = []
	if get_turret_def().kind != TurretDef.Kind.SPRAY:
		return ports
	for side in 4:
		ports.append(FluidGraph.Port.new(side, null, 0))
	return ports


func get_current_ammo() -> TurretAmmo:
	if ammo_types.is_empty():
		return null
	return get_turret_def().ammo[ammo_types[ammo_types.size() - 1]]


func accepts_player_items() -> bool:
	return true


## В окне турели видны патроны (в предметах, с округлением вверх); забрать их нельзя.
func get_player_stacks() -> Array[Vector2i]:
	var stacks: Array[Vector2i] = []
	var d := get_turret_def()
	for k in range(ammo_types.size() - 1, -1, -1):
		var a := d.ammo[ammo_types[k]]
		stacks.append(Vector2i(a.item.index, ceili(float(ammo_shots[k]) / a.shots_per_item)))
	return stacks


## При сносе целые предметы возвращаются.
func collect_contents(out: PackedInt32Array) -> void:
	var d := get_turret_def()
	for k in ammo_types.size():
		var a := d.ammo[ammo_types[k]]
		out[a.item.index] += ammo_shots[k] / a.shots_per_item


# --- Бой ---

func update_tick(tick: int) -> bool:
	match get_turret_def().kind:
		TurretDef.Kind.CHAIN:
			return _tick_chain(tick)
		TurretDef.Kind.REPAIR:
			return _tick_repair(tick)
		TurretDef.Kind.SPRAY:
			return _tick_spray(tick)
		_:
			pass
	if total_shots <= 0:
		_lose_target()
		status = Status.NO_AMMO
		return false
	var enemies := world.enemies
	if enemies.count == 0:
		_lose_target()
		status = Status.IDLE
		sleep_until(tick + IDLE_TICKS)
		return false
	var d := get_turret_def()
	var center := center()
	if not _target_valid(enemies, center, d):
		target_index = enemies.find_nearest(center.x, center.y, d.get_range_px(), d.get_min_range_px())
		target_uid = enemies.uid[target_index] if target_index >= 0 else 0
		if target_index < 0:
			status = Status.IDLE
			sleep_until(tick + SEARCH_TICKS)
			return false
	status = Status.WORKING
	var ammo_type := get_current_ammo()
	var speed := ammo_type.get_speed_per_tick()
	# Упреждение: куда враг сместится за время полёта.
	var tx := enemies.pos_x[target_index]
	var ty := enemies.pos_y[target_index]
	var flight := Vector2(tx, ty).distance_to(center) / maxf(speed, 0.01)
	tx += (tx - enemies.prev_x[target_index]) * flight
	ty += (ty - enemies.prev_y[target_index]) * flight
	var desired := atan2(ty - center.y, tx - center.x)
	var step := d.get_rotate_per_tick()
	angle = wrapf(angle + clampf(wrapf(desired - angle, -PI, PI), -step, step), -PI, PI)
	if tick >= reload_until and absf(wrapf(desired - angle, -PI, PI)) <= deg_to_rad(d.shoot_cone):
		_shoot(tick, d, ammo_type, center, Vector2(tx, ty))
	return true


## Тесла-турель: бьёт молнией по ближайшему врагу и перескакивает на соседей.
## Патронов не просит, но без тока молчит; при нехватке питания перезаряжается дольше.
func _tick_chain(tick: int) -> bool:
	var d := get_turret_def()
	var enemies := world.enemies
	power_request = 0.0
	if enemies.count == 0:
		status = Status.IDLE
		sleep_until(tick + IDLE_TICKS)
		return false
	var center := center()
	var first := enemies.find_nearest(center.x, center.y, d.get_range_px(), d.get_min_range_px())
	if first < 0:
		status = Status.IDLE
		sleep_until(tick + SEARCH_TICKS)
		return false
	power_request = d.power_use
	var rate := get_power_satisfaction() if d.power_use > 0.0 else 1.0
	if rate <= 0.01:
		status = Status.NO_POWER
		return true
	status = Status.WORKING
	if tick < reload_until:
		return true
	# Цепь: каждый следующий враг ближе предыдущего не дальше chain_jump.
	var damage := d.chain_damage
	var from := center
	var index := first
	var hit := {}
	for k in maxi(d.chain_targets, 1):
		if index < 0 or hit.has(enemies.uid[index]):
			break
		hit[enemies.uid[index]] = true
		var to := enemies.get_position(index)
		world.projectiles.push_beam(from, to, tick, Color(0.55, 0.8, 1.0))
		angle = atan2(to.y - center.y, to.x - center.x)
		enemies.hurt(index, damage)
		last_shot_tick = tick
		damage *= d.chain_falloff
		from = to
		index = enemies.find_nearest(to.x, to.y, d.chain_jump * GameConst.TILE_SIZE)
		if index >= 0 and hit.has(enemies.uid[index]):
			index = -1
	# Погибших убирает симуляция в конце тика, как после снарядов: find_nearest их уже не видит.
	reload_until = tick + maxi(roundi(d.reload_seconds * GameConst.TICK_RATE / maxf(rate, 0.05)), 1)
	return true


## Ремонтная турель: чинит самую побитую постройку в радиусе, а если целых нет — дронов.
func _tick_repair(tick: int) -> bool:
	var d := get_turret_def()
	power_request = 0.0
	var center := center()
	var target_building := _most_damaged(center, d.get_range_px())
	var target_drone := _hurt_drone(center, d.get_range_px()) if target_building == null else null
	if target_building == null and target_drone == null:
		status = Status.IDLE
		sleep_until(tick + IDLE_TICKS)
		return false
	power_request = d.power_use
	var rate := get_power_satisfaction() if d.power_use > 0.0 else 1.0
	if rate <= 0.01:
		status = Status.NO_POWER
		return true
	status = Status.WORKING
	if tick < reload_until:
		return true
	var amount := d.repair_amount * rate
	if target_building != null:
		world.repair_building(target_building, amount)
		world.projectiles.push_beam(center, target_building.get_world_center(), tick, Color(0.55, 0.9, 0.55))
		angle = (target_building.get_world_center() - center).angle()
	else:
		target_drone.heal(amount)
		world.projectiles.push_beam(center, target_drone.position, tick, Color(0.55, 0.9, 0.55))
		angle = (target_drone.position - center).angle()
	last_shot_tick = tick
	reload_until = tick + maxi(roundi(d.reload_seconds * GameConst.TICK_RATE), 1)
	return true


## Жидкостная турель: поливает область тем, что пришло по трубам. Вода замедляет, пар жжёт.
func _tick_spray(tick: int) -> bool:
	var d := get_turret_def()
	var enemies := world.enemies
	power_request = 0.0
	if enemies.count == 0:
		status = Status.IDLE
		sleep_until(tick + IDLE_TICKS)
		return false
	var center := center()
	var index := enemies.find_nearest(center.x, center.y, d.get_range_px(), d.get_min_range_px())
	if index < 0:
		status = Status.IDLE
		sleep_until(tick + SEARCH_TICKS)
		return false
	status = Status.WORKING
	if tick < reload_until:
		return true
	var net := world.fluids.get_port_network(self, 0)
	if net == null or net.fluid < 0 or net.amount < d.spray_use:
		# Труб нет или они пусты: спим и проверяем снова, как при поиске цели.
		status = Status.NO_FLUID
		sleep_until(tick + SEARCH_TICKS)
		return false
	var fluid := Registry.fluids[net.fluid]
	net.extract(net.fluid, d.spray_use)
	var at := enemies.get_position(index)
	angle = (at - center).angle()
	var hits := PackedInt32Array()
	enemies.query_circle(at.x, at.y, d.spray_radius * GameConst.TILE_SIZE, hits)
	var steam := fluid != null and fluid.id == &"steam"
	for j in hits:
		if steam:
			enemies.ignite(j, d.steam_dps, tick + roundi(d.steam_seconds * GameConst.TICK_RATE))
		else:
			enemies.slow(j, d.slow_factor, tick + roundi(d.slow_seconds * GameConst.TICK_RATE))
	var color := fluid.color if fluid != null else Color(0.4, 0.7, 1.0)
	world.projectiles.push_beam(center, at, tick, color)
	world.projectiles.push_splash(at, d.spray_radius * GameConst.TILE_SIZE, tick, color)
	last_shot_tick = tick
	reload_until = tick + maxi(roundi(d.reload_seconds * GameConst.TICK_RATE), 1)
	return true


## Самая побитая постройка в радиусе (кроме себя).
func _most_damaged(center: Vector2, radius: float) -> Building:
	var best: Building = null
	var best_fraction := 1.0
	for id in world.damaged:
		var b := world.buildings.get_by_id(id)
		if b == null or b == self or not b.is_damaged():
			continue
		var rect := b.get_world_rect()
		var closest := center.clamp(rect.position, rect.end)
		if closest.distance_to(center) > radius:
			continue
		var fraction := b.health / b.get_max_health()
		if fraction < best_fraction:
			best_fraction = fraction
			best = b
	return best


## Побитый дрон в радиусе.
func _hurt_drone(center: Vector2, radius: float) -> Drone:
	for d in world.drones:
		if d.dead or d.health >= d.get_max_health():
			continue
		if d.position.distance_to(center) <= radius:
			return d
	return null


func _target_valid(enemies: EnemySystem, center: Vector2, d: TurretDef) -> bool:
	if target_index < 0 or target_index >= enemies.count or enemies.uid[target_index] != target_uid:
		return false
	if not enemies.is_alive(target_index):
		return false
	# Без Vector2: этот расчёт идёт у каждой турели в каждом тике боя.
	var dx := enemies.pos_x[target_index] - center.x
	var dy := enemies.pos_y[target_index] - center.y
	var dist := maxf(sqrt(dx * dx + dy * dy) - enemies.get_radius(target_index), 0.0)
	return dist <= d.get_range_px() and dist >= d.get_min_range_px()


func _lose_target() -> void:
	target_index = -1
	target_uid = 0


func _shoot(tick: int, d: TurretDef, ammo_type: TurretAmmo, center: Vector2, aim: Vector2) -> void:
	var spread := deg_to_rad(d.inaccuracy)
	var shot_angle := angle + world.rng.randf_range(-spread, spread)
	var dir := Vector2.from_angle(shot_angle)
	var muzzle := center + dir * d.barrel_length
	var speed := ammo_type.get_speed_per_tick()
	if d.artillery:
		var distance := maxf(muzzle.distance_to(aim), 1.0)
		world.projectiles.spawn_shell(muzzle, muzzle + dir * distance, ceili(distance / speed), ammo_type.damage,
			ammo_type.get_splash_px(), ammo_type.color)
	else:
		var ticks := ceili((d.get_range_px() + GameConst.TILE_SIZE) / speed)
		var bullet := world.projectiles.spawn_bullet(muzzle, dir * speed, ammo_type.damage, ticks, ammo_type.color)
		world.projectiles.set_effects(bullet, ammo_type.get_splash_px(), ammo_type.burn_dps, ammo_type.get_burn_ticks())
	var last := ammo_types.size() - 1
	ammo_shots[last] -= 1
	total_shots -= 1
	if ammo_shots[last] <= 0:
		ammo_types.remove_at(last)
		ammo_shots.remove_at(last)
	reload_until = tick + d.get_reload_ticks(ammo_type)
	last_shot_tick = tick
	# Освободилось место под патроны — ленты у турели могут подавать дальше.
	notify_space()


# --- Состояние ---

func save_state() -> Dictionary:
	var items := PackedInt32Array()
	var d := get_turret_def()
	for index in ammo_types:
		items.append(d.ammo[index].item.index)
	return {"ammo_items": items, "ammo_shots": ammo_shots.duplicate(), "angle": angle, "reload": reload_until,
		"target_uid": target_uid, "target_index": target_index, "last_shot": last_shot_tick, "status": status,
		"power": power_request}


func load_state(state: Dictionary) -> void:
	var d := get_turret_def()
	ammo_types.clear()
	ammo_shots.clear()
	total_shots = 0
	var items: PackedInt32Array = state.get("ammo_items", PackedInt32Array())
	var shots: PackedInt32Array = state.get("ammo_shots", PackedInt32Array())
	for k in mini(items.size(), shots.size()):
		var index := d.find_ammo(SaveContext.item(items[k]))
		if index < 0 or shots[k] <= 0:
			continue
		ammo_types.append(index)
		ammo_shots.append(shots[k])
		total_shots += shots[k]
	angle = float(state.get("angle", angle))
	reload_until = int(state.get("reload", 0))
	target_uid = int(state.get("target_uid", 0))
	target_index = int(state.get("target_index", -1))
	last_shot_tick = int(state.get("last_shot", -1000))
	status = int(state.get("status", Status.NO_AMMO)) as Status
	power_request = float(state.get("power", 0.0))
	wake()


# --- Интерфейс ---

func get_status() -> Status:
	return status


func get_info_lines() -> PackedStringArray:
	var d := get_turret_def()
	var lines := PackedStringArray()
	var ammo_type := get_current_ammo()
	var ammo_name := tr(ammo_type.item.name_key) if ammo_type != null else "—"
	lines.append(tr("INFO_TURRET_AMMO") % [total_shots, d.max_ammo, ammo_name])
	return lines


# --- Окно ---

## Патроны (забрать нельзя) и запас выстрелов.
func get_window_sections() -> Array[WindowSection]:
	var d := get_turret_def()
	var stacks := get_player_stacks()
	var hints := PackedInt32Array()
	for st in stacks:
		hints.append(st.x)
	if stacks.is_empty():
		stacks.append(Vector2i(-1, 0))
		hints.append(d.ammo[0].item.index if not d.ammo.is_empty() else -1)
	var stock := WindowSection.bar(tr("WINDOW_AMMO_STOCK"), float(total_shots) / maxi(d.max_ammo, 1), "%d / %d" % [total_shots, d.max_ammo])
	return [WindowSection.slots(tr("WINDOW_AMMO"), stacks, hints, false), stock]
