class_name DroneView
extends Node2D
## Отрисовка дронов игроков в показанном сейчас мире: корпус по интерполированной позиции,
## луч добычи с прогрессом, круг радиуса строительства (только у своего дрона, пока в руке постройка),
## полоска прочности при уроне. Сбитый дрон не рисуется; после появления мигает, пока неуязвим.
## Зелёный луч — ремонт постройки, вспышка у корпуса — выстрел автопушки.
## Чужие дроны рисуются цветом своего игрока и подписаны именем.
## В сетевой игре свой дрон рисуется с упреждением: команда движения применится через задержку
## ввода, а показать отклик надо сразу. Упреждение только в отрисовке — симуляция не трогается.
## Плейсхолдер рисуется примитивами; спрайт из DroneDef.sprite подменяет его без правки логики.

const BODY_RADIUS := 13.0
const RANGE_COLOR := Color(0.98, 0.74, 0.18, 0.35)
## Сколько тиков висит надпись о добыче.
const MINED_TICKS := 45
const BEAM_COLOR := Color(0.99, 0.5, 0.1, 0.9)
const TURN_SPEED := 14.0
## Дальше этого упреждение не растёт. Оно живёт, только пока держишь клавишу, и на стоящем дроне
## сходит в ноль, — но на совсем плохой связи рисовать дрона в трёх тайлах от настоящего места
## уже вредно: у края радиуса строительства клик не пройдёт там, где его ждут.
const PREDICT_MAX_TICKS := 16.0

var _run: Run
var _world: GameWorld
var _clock: SimClock
var _tools: ToolController
## Сглаженный угол корпуса по id игрока.
var _angles: Dictionary[int, float] = {}
var _time: float = 0.0
## Упреждение своего дрона, накопленное по тикам (см. advance_lead).
var _lead: Vector2 = Vector2.ZERO
## Вклад последнего тика — для плавной отрисовки между тиками.
var _last_gap: Vector2 = Vector2.ZERO
## Чьё и в каком мире упреждение: сменился дрон или мир — копить заново.
var _lead_drone: Drone
var _lead_world: GameWorld
## Дрон, который рисуется прямо сейчас (у отрисовки много мелких шагов, чтобы не таскать его всюду).
var _drone: Drone


func setup(run: Run, world: GameWorld, clock: SimClock, tools: ToolController) -> void:
	_run = run
	_world = world
	_clock = clock
	_tools = tools
	z_index = 5


func set_world(world: GameWorld) -> void:
	_world = world


func _process(delta: float) -> void:
	if _run == null:
		return
	_time += delta
	for player in _run.players:
		var drone := player.drone
		if drone == null:
			continue
		var angle: float = _angles.get(player.id, drone.facing)
		var facing := drone.facing
		# Свой дрон в сетевой игре поворачивается сразу по нажатию: в симуляции поворот придёт
		# только через задержку ввода, и корпус летел бы боком.
		if player.id == _run.local_player and Session.net.is_networked() and drone.local_input != Vector2.ZERO:
			facing = drone.local_input.angle()
		_angles[player.id] = lerp_angle(angle, facing, 1.0 - exp(-delta * TURN_SPEED))
	queue_redraw()


## Упреждение своего дрона — точная разница между тем, куда он сдвинулся бы по нажатиям,
## и тем, куда сдвинулся на самом деле.
##
## После каждого тика симуляции (Game зовёт after_tick) к упреждению прибавляется
## «нажато × скорость» и вычитается настоящий сдвиг дрона за этот тик. Пока команда в пути,
## разница растёт; когда она применилась, сдвиг совпадает с нажатием и разница стоит; после
## отпускания она тает ровно с той скоростью, с какой дрон ещё летит по очереди команд.
## Нарисованный дрон (настоящий + упреждение) всегда там, где он был бы без задержки.
##
## Задержку при этом знать не нужно вовсе. Прежние схемы считали, что команда применится ровно
## через оценённые D тиков, а сеть гуляет на тик-два: пришла позже — дрон в конце движения
## вставал и доезжал вперёд, раньше — в начале откидывало. Здесь ошибка оценки невозможна:
## считается то, что уже случилось.
func after_tick() -> void:
	var local := _run.get_local_player() if _run != null else null
	var drone: Drone = local.drone if local != null else null
	if drone == null or drone.dead or drone.world == null or not Session.net.is_networked() \
			or drone != _lead_drone or drone.world != _lead_world:
		_lead = Vector2.ZERO
		_last_gap = Vector2.ZERO
		_lead_drone = drone
		_lead_world = drone.world if drone != null else null
		return
	var speed := drone.get_speed_per_tick()
	var moved := drone.position - drone.prev_position
	# Скачок положения — появление после гибели, переход, телепорт: копить заново.
	if moved.length() > speed * 1.5:
		_lead = Vector2.ZERO
		_last_gap = Vector2.ZERO
		return
	var idle := drone.local_input == Vector2.ZERO and drone.move_input == Vector2.ZERO \
		and not Session.net.has_pending_moves()
	var before := _lead
	_lead = advance_lead(_lead, drone.local_input.limit_length(1.0) * speed, moved, idle)
	_last_gap = _lead - before
	# Дрон не вылетает за открытую часть мира — и упреждение тоже.
	var bounds := drone.world.get_play_rect_px()
	_lead = (drone.position + _lead).clamp(bounds.position, bounds.end) - drone.position
	_lead = _lead.limit_length(speed * PREDICT_MAX_TICKS)


## Упреждение после тика: + нажатое, − сделанное. idle — нажатого нет, команд в пути нет и дрон
## стоит: упреждения быть не должно, остаток — накопленная погрешность, её гасим.
static func advance_lead(lead: Vector2, pressed_step: Vector2, moved: Vector2, idle: bool) -> Vector2:
	lead += pressed_step - moved
	# Гасим мягко: остаток бывает в несколько тиков полёта (команда опоздала, сменился запас),
	# и погасить его за тик — это тот самый рывок, от которого упреждение и спасает.
	if idle:
		lead *= 0.7
		if lead.length() < 0.25:
			lead = Vector2.ZERO
	return lead


## Смещение для отрисовки между тиками: отрисовка показывает отрезок прошлого тика по alpha,
## поэтому его вклад в упреждение берётся в той же доле.
static func lead_at(lead: Vector2, last_gap: Vector2, alpha: float) -> Vector2:
	return lead - (1.0 - alpha) * last_gap


## Текущее упреждение своего дрона: на столько же смещается камера, чтобы дрон не уезжал от центра.
##
## Считается по запросу, а не хранится с прошлого кадра. Камера обновляется раньше отрисовки дрона,
## и с запасённым значением она брала бы упреждение прошлого кадра, а дрон рисовался бы с новым:
## дрон дрожал бы относительно мира ровно тогда, когда упреждение меняется, — в начале и конце
## движения. Теперь оба берут одно и то же число.
func local_offset() -> Vector2:
	var local := _run.get_local_player() if _run != null else null
	var drone: Drone = local.drone if local != null else null
	if drone == null or drone != _lead_drone or drone.world == null or not Session.net.is_networked():
		return Vector2.ZERO
	var offset := lead_at(_lead, _last_gap, _clock.alpha)
	var base := drone.get_draw_position(_clock.alpha)
	var bounds := drone.world.get_play_rect_px()
	return (base + offset).clamp(bounds.position, bounds.end) - base


func _draw() -> void:
	if _run == null or _world == null:
		return
	for player in _run.players:
		if player.drone != null and player.drone.world == _world:
			_draw_drone(player)
	_draw_cursors()


## Курсоры напарников: видно, куда смотрит и что собирается делать напарник.
func _draw_cursors() -> void:
	if not Session.net.is_networked():
		return
	var font := ThemeDB.fallback_font
	var cursors := Session.net.cursors_in(_world == _run.base)
	for id in cursors:
		var player := _run.get_player(id)
		if player == null:
			continue
		var at: Vector2 = cursors[id]
		var color := player.color
		draw_line(at + Vector2(0, -9), at + Vector2(0, 9), Color(0, 0, 0, 0.5), 3.0)
		draw_line(at + Vector2(-9, 0), at + Vector2(9, 0), Color(0, 0, 0, 0.5), 3.0)
		draw_line(at + Vector2(0, -8), at + Vector2(0, 8), color, 1.5)
		draw_line(at + Vector2(-8, 0), at + Vector2(8, 0), color, 1.5)
		draw_circle(at, 2.5, color)
		if font != null and not player.name.is_empty():
			draw_string_outline(font, at + Vector2(10, -6), player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
			draw_string(font, at + Vector2(10, -6), player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, color)


func _draw_drone(player: Player) -> void:
	_drone = player.drone
	var local := player.id == _run.local_player
	if _drone.dead or _drone.world == null:
		return
	var pos := _drone.get_draw_position(_clock.alpha)
	if local:
		pos += local_offset()
	var tick := _drone.world.simulation.tick
	if tick < _drone.invulnerable_until and fmod(_time, 0.24) < 0.12:
		return
	if _drone.health < _drone.get_max_health():
		var fraction := clampf(_drone.health / _drone.get_max_health(), 0.0, 1.0)
		var bar := Rect2(pos + Vector2(-16, BODY_RADIUS + 8), Vector2(32, 4))
		draw_rect(bar.grow(1.0), Color(0, 0, 0, 0.7), true)
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), CombatOverlay.bar_color(fraction), true)
	if local and _tools != null and _tools.mode != ToolController.Mode.NONE and not _drone.world.creative:
		_draw_range(pos)
	# Луч включается сразу по клику: команда добычи применится только через задержку ввода,
	# а без луча клик выглядит несработавшим.
	var mine_tile := _drone.mine_tile
	if local and Session.net.is_networked():
		var wanted := Session.predict.mining_tile()
		if wanted != Drone.NO_TILE:
			mine_tile = wanted
	if mine_tile != Drone.NO_TILE:
		_draw_beam(pos, mine_tile)
	if local:
		_draw_mined_label()
		_draw_move_label()
	if _drone.is_repairing():
		_draw_repair(pos)
	_draw_body(pos, player)
	if not local:
		_draw_name(pos, player)
	var since := tick - _drone.last_gun_tick
	if since < 3:
		var muzzle := pos + Vector2.from_angle(_drone.gun_angle) * (BODY_RADIUS + 4.0)
		draw_line(pos, muzzle, Color(_drone.def.gun_color.lightened(0.2), 0.9), 2.5)
		draw_circle(muzzle, 3.5 - since, Color(_drone.def.gun_color.lightened(0.5), 0.9))


## Имя чужого игрока над дроном.
func _draw_name(pos: Vector2, player: Player) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var width := font.get_string_size(player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
	var at := pos + Vector2(-width * 0.5, -BODY_RADIUS - 8.0)
	draw_string_outline(font, at, player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.85))
	draw_string(font, at, player.name, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, player.color)


func _draw_range(pos: Vector2) -> void:
	var radius := _drone.get_reach_px()
	var segments := 64
	for i in segments:
		if i % 2 == 1:
			continue
		var a0 := TAU * i / segments + _time * 0.15
		var a1 := TAU * (i + 1) / segments + _time * 0.15
		draw_arc(pos, radius, a0, a1, 4, RANGE_COLOR, 2.0)


func _draw_repair(pos: Vector2) -> void:
	var building := _drone.world.buildings.get_by_id(_drone.repair_target)
	if building == null:
		return
	var rect := building.get_world_rect()
	var target := rect.get_center() + Vector2(sin(_time * 7.0), cos(_time * 5.0)) * rect.size * 0.25
	var flicker := 0.7 + 0.3 * sin(_time * 25.0)
	draw_line(pos, target, Color(0.56, 0.75, 0.49, 0.75 * flicker), 3.0)
	draw_line(pos, target, Color(0.85, 1.0, 0.8, 0.8 * flicker), 1.2)
	draw_circle(target, 4.0 * flicker, Color(0.72, 0.9, 0.6, 0.9))
	draw_rect(rect.grow(1.0), Color(0.56, 0.75, 0.49, 0.6), false, 2.0)


## Надпись «Камень +20» над зданием, из которого забрали (или в которое положили) предметы.
## Без неё быстрые перекладывания выглядят так, будто ничего не произошло.
func _draw_move_label() -> void:
	if _drone.last_move_items.is_empty() or _drone.world == null:
		return
	var age := _drone.world.simulation.tick - _drone.last_move_tick
	if age < 0 or age >= MINED_TICKS:
		return
	var fade := 1.0 - float(age) / MINED_TICKS
	# Видов может быть несколько — пишем все, строка под строкой.
	for k in _drone.last_move_items.size():
		var text := "%s %+d" % [tr(Registry.items[_drone.last_move_items[k]].name_key), _drone.last_move_counts[k]]
		_draw_float_label(text, _drone.last_move_tile, fade, k * 14.0)


## Надпись «Камень ×11» над последним добытым тайлом: всплывает и гаснет за MINED_TICKS тиков.
func _draw_mined_label() -> void:
	if _drone.last_mined_item < 0 or _drone.world == null:
		return
	var age := _drone.world.simulation.tick - _drone.last_mined_tick
	if age < 0 or age >= MINED_TICKS:
		return
	var text := "%s ×%d" % [tr(Registry.items[_drone.last_mined_item].name_key), _drone.last_mined_count]
	_draw_float_label(text, _drone.last_mined_tile, 1.0 - float(age) / MINED_TICKS)


## Всплывающая надпись над тайлом: поднимается и гаснет вместе с fade (1 — только появилась).
func _draw_float_label(text: String, tile: Vector2i, fade: float, lift: float = 0.0) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var t := float(GameConst.TILE_SIZE)
	var pos := Vector2(tile) * t + Vector2(t * 0.5, -10.0 - lift - 14.0 * (1.0 - fade))
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	var at := pos - Vector2(width * 0.5, 0.0)
	draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.85 * fade))
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.98, 0.94, 0.78, fade))


func _draw_beam(pos: Vector2, mine_tile: Vector2i) -> void:
	var t := float(GameConst.TILE_SIZE)
	var target := Vector2(mine_tile) * t + Vector2(t, t) * 0.5
	var tile_rect := Rect2(Vector2(mine_tile) * t, Vector2(t, t))
	if _drone.mine_blocked and mine_tile == _drone.mine_tile:
		draw_line(pos, target, Color(UiTheme.GRAY, 0.5), 1.5)
		draw_rect(tile_rect.grow(-2.0), Color(UiTheme.RED, 0.8), false, 2.0)
		return
	var flicker := 0.75 + 0.25 * sin(_time * 30.0)
	draw_line(pos, target, Color(BEAM_COLOR, BEAM_COLOR.a * flicker), 2.5)
	draw_circle(target, 3.0 + 1.5 * flicker, Color(1.0, 0.85, 0.4, 0.9))
	draw_rect(tile_rect.grow(-2.0), Color(BEAM_COLOR, 0.7), false, 2.0)
	# Полоска прогресса добычи над тайлом.
	var fraction := _drone.get_mine_fraction()
	var bar := Rect2(tile_rect.position + Vector2(3, -6), Vector2(t - 6, 3))
	draw_rect(bar, Color(0, 0, 0, 0.6), true)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * fraction, bar.size.y)), UiTheme.YELLOW, true)


func _draw_body(pos: Vector2, player: Player) -> void:
	var def := _drone.def
	var angle: float = _angles.get(player.id, _drone.facing)
	draw_set_transform(pos, angle, Vector2.ONE)
	if def.sprite != null:
		var size := def.sprite.get_size()
		draw_texture(def.sprite, -size * 0.5, player.color)
	else:
		var r := BODY_RADIUS
		var moving := _drone.move_input != Vector2.ZERO
		if moving:
			var glow := 0.6 + 0.4 * sin(_time * 40.0)
			draw_circle(Vector2(-r * 0.95, 0), 4.0 * glow + 2.0, Color(0.55, 0.75, 1.0, 0.7))
		# Тень под корпусом.
		var hull := PackedVector2Array([
			Vector2(r * 1.15, 0), Vector2(-r * 0.7, r * 0.85), Vector2(-r * 0.35, 0), Vector2(-r * 0.7, -r * 0.85)])
		var shadow := PackedVector2Array()
		for p in hull:
			shadow.append(p + Vector2(3, 3).rotated(-angle))
		draw_colored_polygon(shadow, Color(0, 0, 0, 0.35))
		draw_colored_polygon(hull, player.color.darkened(0.15))
		var outline := hull.duplicate()
		outline.append(hull[0])
		draw_polyline(outline, player.color.lightened(0.35), 2.0)
		draw_circle(Vector2(r * 0.15, 0), 3.5, Color(0.2, 0.9, 1.0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
