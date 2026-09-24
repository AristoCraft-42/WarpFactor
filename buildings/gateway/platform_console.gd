class_name PlatformConsole
extends PlatformEnd
## Пульт платформы добычи. С него платформу наводят на планету (вид со спутника) и отзывают
## обратно в комнату. Сам перенос построек делает забег (Run.platform_deploy/platform_fold):
## платформа стоит сразу в двух мирах только на словах — постройки всегда в одном.
##
## Состояния: стоит в комнате → разворачивается (пауза) → стоит на планете → сворачивается (пауза).
## Новая цель во время работы платформы означает «сверни и развернись на новом месте».

enum State { DOCKED, DEPLOYING, DEPLOYED, FOLDING }

const NO_TILE := Vector2i(-1000000, -1000000)

var state: State = State.DOCKED
## Куда целится игрок (центр платформы на планете); NO_TILE — отозвать в комнату.
var aim: Vector2i = NO_TILE
## Где платформа стоит сейчас (NO_TILE — в комнате).
var deployed_at: Vector2i = NO_TILE
## Тиков осталось до конца разворачивания или сворачивания.
var timer: int = 0


func is_deployed() -> bool:
	return state == State.DEPLOYED or state == State.FOLDING


func is_busy() -> bool:
	return state == State.DEPLOYING or state == State.FOLDING


## Доля выполнения текущей паузы 0..1 (для полоски в окне).
func progress() -> float:
	var total := get_platform_def().get_deploy_ticks()
	return clampf(1.0 - float(timer) / maxf(float(total), 1.0), 0.0, 1.0)


## Навести платформу на тайл планеты или отозвать её (NO_TILE). Меняет только цель:
## разворачиванием и сворачиванием занимается сам пульт, тик за тиком.
func set_aim(tile: Vector2i) -> void:
	if aim == tile:
		return
	aim = tile
	wake()


func has_player_window() -> bool:
	return true


func update_tick(tick: int) -> bool:
	var busy := _advance()
	var moved := super.update_tick(tick)
	return busy or moved


## Шаг состояния. true — пульт остаётся бодрствовать (идёт пауза или ждём следующего шага).
func _advance() -> bool:
	var run := world.run if world != null else null
	if run == null:
		return false
	match state:
		State.DOCKED:
			if aim == NO_TILE:
				return false
			state = State.DEPLOYING
			timer = get_platform_def().get_deploy_ticks()
			return true
		State.DEPLOYING:
			timer -= 1
			if timer > 0:
				return true
			if run.platform_deploy(self, aim):
				state = State.DEPLOYED
				deployed_at = aim
			else:
				# Место занято или не годится: платформа остаётся в комнате, цель снимается.
				state = State.DOCKED
				deployed_at = NO_TILE
				aim = NO_TILE
			return false
		State.DEPLOYED:
			if aim == deployed_at:
				return false
			state = State.FOLDING
			timer = get_platform_def().get_deploy_ticks()
			return true
		State.FOLDING:
			timer -= 1
			if timer > 0:
				return true
			run.platform_fold(self)
			state = State.DOCKED
			deployed_at = NO_TILE
			# Цель новая — со следующего тика начнём разворачиваться там.
			return aim != NO_TILE
	return false


## Аварийный отзыв: якорь добили, платформа сворачивается в ближайшем тике без паузы.
## Сам перенос делает update_tick пульта — менять миры посреди боя на планете нельзя.
func recall() -> void:
	if not is_deployed():
		return
	aim = NO_TILE
	state = State.FOLDING
	timer = 1
	wake()


## Свернуть платформу немедленно, без паузы (перелёт на другую планету).
func fold_now() -> void:
	var run := world.run if world != null else null
	if run != null and is_deployed():
		run.platform_fold(self)
	state = State.DOCKED
	deployed_at = NO_TILE
	aim = NO_TILE
	timer = 0
	wake()


func save_state() -> Dictionary:
	var data := {"room": room, "state": int(state), "aim": aim, "at": deployed_at, "timer": timer,
		"next_out": _next_out}
	if link != null:
		data["link"] = link.save_data()
	return data


func load_state(data: Dictionary) -> void:
	room = int(data.get("room", room))
	state = int(data.get("state", State.DOCKED)) as State
	aim = data.get("aim", NO_TILE)
	deployed_at = data.get("at", NO_TILE)
	timer = int(data.get("timer", 0))
	_next_out = int(data.get("next_out", 0))
	if link != null and data.has("link"):
		link.load_data(data["link"])
	wake()


func get_info_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	match state:
		State.DOCKED:
			lines.append(tr("INFO_PLATFORM_DOCKED"))
		State.DEPLOYING:
			lines.append(tr("INFO_PLATFORM_DEPLOYING") % roundi(progress() * 100.0))
		State.DEPLOYED:
			lines.append(tr("INFO_PLATFORM_DEPLOYED") % [deployed_at.x, deployed_at.y])
		State.FOLDING:
			lines.append(tr("INFO_PLATFORM_FOLDING") % roundi(progress() * 100.0))
	lines.append_array(super.get_info_lines())
	return lines
