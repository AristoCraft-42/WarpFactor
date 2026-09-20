class_name DebugOverlay
extends PanelContainer
## Отладочная информация (F3): FPS, время кадра, вызовы отрисовки, число зданий и чанков.
## Обновляется 4 раза в секунду, а не каждый кадр.

const REFRESH_INTERVAL := 0.25

var _game: Game
var _label: Label
var _timer: float = 0.0


func setup(game: Game) -> void:
	_game = game
	theme_type_variation = &"HudPanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", UiTheme.AQUA)
	add_child(_label)
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH_INTERVAL
	var world := _game.world
	var lines := PackedStringArray()
	lines.append("FPS: %d   frame: %.2f ms" % [Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	lines.append("draw calls: %d   objects: %d" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_COUNT)])
	lines.append("memory: %.1f MB   video: %.1f MB" % [
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	lines.append("map: %d×%d   chunks: %d×%d" % [world.grid.width, world.grid.height, world.grid.chunks_x(), world.grid.chunks_y()])
	lines.append("buildings: %d   building chunks: %d   tile chunks: %d" % [
		world.buildings.get_count(), _game.building_layer.get_view_count(), _game.terrain.get_filled_chunk_count()])
	lines.append("zoom: %.2f   camera tile: %s" % [_game.camera.user_zoom, Vector2i(_game.camera.position / GameConst.TILE_SIZE)])
	var sim := world.simulation
	lines.append("tick: %d   x%d   ticks/frame: %d   tick time: %.3f ms (avg %.3f)" % [
		sim.tick, _game.clock.get_speed(), _game.clock.ticks_last_frame,
		sim.last_tick_usec / 1000.0, sim.avg_tick_usec / 1000.0])
	if Session.net.is_networked():
		# Сеть: запас подтверждённых тиков и темп времени — по ним видно, догоняет ли клиент.
		lines.append("net: %s   запас %d из %.1f тиков   темп x%.2f   задержка ввода %d" % [
			"хост" if Session.net.is_host() else "клиент", Session.net.ready_ticks(),
			Session.net.buffer_target(), _game.clock.get_time_scale(), Session.net.predicted_delay()])
		lines.append("net: задержка ввода %d тиков (%.0f мс) — измерена по своим командам" % [
			Session.net.predicted_delay(), Session.net.predicted_delay() * GameConst.TICK_DT * 1000.0])
		lines.append("net: я — игрок %d%s   игроков %d" % [_game.run.local_player,
			"" if Session.net.is_host() or Session.net.local_player_id() == _game.run.local_player
				else " (ЖДУ СВОЕГО, играю за чужого дрона!)",
			_game.run.players.size()])
		lines.append("net: починок снимком %d   последнее расхождение: %s   часов в сцене %d" % [
			Session.net.repairs, Session.net.last_desync if not Session.net.last_desync.is_empty() else "нет",
			_count_clocks()])
	lines.append("conveyors: %d (awake %d)   items on belts: %d   drawn: %d" % [
		sim.conveyors.count, sim.conveyors.last_updated, sim.conveyors.get_item_count(), _game.item_renderer.drawn_count])
	lines.append("awake buildings: %d" % sim.last_awake_buildings)
	var planet := _game.run.planet
	var enemies := planet.enemies
	var flow := planet.flow
	lines.append("turrets: %d   projectiles: %d (fired %d, hits %d)" % [planet.turrets.size(), planet.projectiles.count,
		planet.projectiles.fired, planet.projectiles.hits])
	lines.append("enemies: %d (spawned %d, killed %d)   update: %.3f ms   drawn: %d" % [
		enemies.count, enemies.spawned, enemies.killed, enemies.last_update_usec / 1000.0,
		_game.planet_view.enemy_renderer.drawn_count])
	if flow != null:
		lines.append("flow: v%d %s   last recompute: %d ticks" % [flow.version,
			"computing" if flow.is_computing() else ("dirty" if flow.is_dirty() else "ready"), flow.last_compute_ticks])
	if planet.threat != null:
		lines.append("threat: wave %d   next in %d ticks   budget %.1f   queued %d   N — call wave" % [
			planet.threat.wave, planet.threat.get_ticks_to_next_wave(planet.simulation.tick), planet.threat.last_budget,
			planet.threat.get_pending_spawns()])
	_label.text = "\n".join(lines)


## Сколько узлов часов живёт в сцене: их всегда должно быть ровно одни.
## Вторые часы означали бы, что мир шагает дважды (так ломалась пересборка после починки).
func _count_clocks() -> int:
	var found := 0
	for child in _game.get_children():
		if child is SimClock:
			found += 1
	return found
