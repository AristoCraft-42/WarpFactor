class_name LinePlanner
extends RefCounted
## Геометрия протягивания: L-трасса для лент (с мостами и перекрёстками через препятствия),
## трасса труб (подземные через препятствия), ряд подземных труб на максимальном шаге
## и прямой ряд для остальных зданий.


## L-трасса от start до end (включительно). x_first — сначала идём по X, потом по Y.
## Каждый шаг — Vector3i(x, y, направление): направление к следующему тайлу,
## у последнего — направление последнего отрезка (или fallback_dir, если тайл один).
static func l_path(start: Vector2i, end: Vector2i, x_first: bool, fallback_dir: int) -> Array[Vector3i]:
	var tiles: Array[Vector2i] = [start]
	var corner := Vector2i(end.x, start.y) if x_first else Vector2i(start.x, end.y)
	_walk(tiles, start, corner)
	_walk(tiles, corner, end)

	var result: Array[Vector3i] = []
	var last_dir := fallback_dir
	for i in tiles.size():
		var dir := last_dir
		if i < tiles.size() - 1:
			dir = GameConst.dir_from_vector(tiles[i + 1] - tiles[i])
			last_dir = dir
		result.append(Vector3i(tiles[i].x, tiles[i].y, dir))
	return result


## Прямой ряд позиций с шагом step вдоль доминирующей оси смещения.
static func straight_line(start: Vector2i, end: Vector2i, step: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var delta := end - start
	var axis := Vector2i(signi(delta.x), 0) if absi(delta.x) >= absi(delta.y) else Vector2i(0, signi(delta.y))
	var distance := maxi(absi(delta.x), absi(delta.y))
	var count := distance / maxi(step, 1)
	for i in count + 1:
		result.append(start + axis * step * i)
	return result


## Трасса ленты с обходом препятствий. На прямых участках внутри трассы:
## - постройку или непригодную землю (скала, вода) перекрывает мостовой конвейер — вход перед препятствием,
##   выход сразу за ним (если хватает дальности моста);
## - поперечную ленту пересекает перекрёсток; стоящий перекрёсток остаётся как есть.
## Существующее не ломается: если мостов или перекрёстков в инвентаре не хватает, препятствие остаётся
## препятствием (лента на нём не строится), а пересекаемая лента — нетронутой. Чужие постройки на концах
## и углах трассы тоже не заменяются (заменить здание лентой можно одиночным кликом).
static func plan_belt(world: GameWorld, def: BuildingDef, path: Array[Vector3i], budget: Inventory.Budget) -> Array[PlacementPreview.Ghost]:
	const BELT := 0
	const OBSTACLE := 1
	const CROSS := 2
	const KEEP := 3
	var n := path.size()
	var bridge_def := Registry.get_building(&"bridge_conveyor") as LogisticDef
	var junction_def := Registry.get_building(&"junction")
	var bridges_left := _available(world, bridge_def)
	var junctions_left := _available(world, junction_def)

	var kinds := PackedInt32Array()
	kinds.resize(n)
	for i in n:
		var tile := Vector2i(path[i].x, path[i].y)
		kinds[i] = BELT
		var straight := i > 0 and i < n - 1 and path[i - 1].z == path[i].z
		var check := world.buildings.check_place(def, tile, path[i].z)
		var existing := world.buildings.get_at(tile)
		if not straight:
			# Концы и углы трассы: чужую постройку лента не заменяет (перекрыть её нечем).
			if check == BuildingManager.Check.REPLACE and not (existing is Conveyor):
				kinds[i] = OBSTACLE
			continue
		if existing is Conveyor and existing.rotation % 2 != path[i].z % 2:
			kinds[i] = CROSS
		elif existing is Junction:
			kinds[i] = KEEP
		elif check == BuildingManager.Check.OCCUPIED or check == BuildingManager.Check.BAD_TERRAIN \
				or check == BuildingManager.Check.ON_FLUID \
				or (check == BuildingManager.Check.REPLACE and not (existing is Conveyor)):
			kinds[i] = OBSTACLE

	# Мосты над сплошными участками препятствий: tile_def / tile_config по индексу трассы.
	var bridge_at: Dictionary[int, Variant] = {}
	var covered: Dictionary[int, bool] = {}
	var i := 0
	while i < n:
		if kinds[i] != OBSTACLE:
			i += 1
			continue
		var first := i
		while i < n and kinds[i] == OBSTACLE and path[i].z == path[first].z:
			i += 1
		var entry := first - 1
		var exit := i
		if bridge_def == null or entry < 0 or exit >= n or kinds[exit] != BELT or kinds[entry] != BELT:
			continue
		var dir := path[first].z
		if path[entry].z != dir or exit - entry > bridge_def.link_range:
			continue
		var entry_tile := Vector2i(path[entry].x, path[entry].y)
		var exit_tile := Vector2i(path[exit].x, path[exit].y)
		if not BuildingManager.is_valid_check(world.buildings.check_place(bridge_def, entry_tile, dir)) \
				or not BuildingManager.is_valid_check(world.buildings.check_place(bridge_def, exit_tile, dir)):
			continue
		var need := 1 if bridge_at.has(entry) else 2
		if bridges_left < need:
			continue
		bridges_left -= need
		bridge_at[entry] = exit_tile - entry_tile
		if not bridge_at.has(exit):
			bridge_at[exit] = null
		for k in range(first, exit):
			covered[k] = true

	var ghosts: Array[PlacementPreview.Ghost] = []
	for k in n:
		var origin := Vector2i(path[k].x, path[k].y)
		var rot := path[k].z
		if bridge_at.has(k):
			var ghost := PlacementPreview.Ghost.new(bridge_def, origin, rot, world.check_build(bridge_def, origin, rot, budget))
			ghost.config = bridge_at[k]
			ghosts.append(ghost)
		elif covered.has(k) or kinds[k] == KEEP:
			continue
		elif kinds[k] == CROSS:
			if junctions_left > 0:
				junctions_left -= 1
				ghosts.append(PlacementPreview.Ghost.new(junction_def, origin, 0, world.check_build(junction_def, origin, 0, budget)))
		elif kinds[k] == OBSTACLE:
			# Не перекрыто мостом: препятствие остаётся — лента его не заменит.
			var blocked := world.buildings.check_place(def, origin, rot)
			if BuildingManager.is_valid_check(blocked):
				blocked = BuildingManager.Check.OCCUPIED
			ghosts.append(PlacementPreview.Ghost.new(def, origin, rot, blocked))
		else:
			ghosts.append(PlacementPreview.Ghost.new(def, origin, rot, world.check_build(def, origin, rot, budget)))
	return ghosts


## Трасса трубы с обходом препятствий: сплошной участок, где труба не ставится, перекрывается парой
## подземных труб (вход перед участком, выход сразу за ним), если хватает дальности и самих труб.
## Стоящие трубы на трассе остаются как есть. Ничего чужого не ломается: если подземных не хватает,
## препятствие так и остаётся препятствием.
static func plan_pipe(world: GameWorld, def: BuildingDef, path: Array[Vector3i], budget: Inventory.Budget) -> Array[PlacementPreview.Ghost]:
	const PIPE := 0
	const OBSTACLE := 1
	const KEEP := 2
	var n := path.size()
	var under_def := Registry.get_building(&"underground_pipe") as FluidBuildingDef
	var under_left := _available(world, under_def)
	var under_range := under_def.underground_range if under_def != null else 0

	var kinds := PackedInt32Array()
	kinds.resize(n)
	for i in n:
		var tile := Vector2i(path[i].x, path[i].y)
		var check := world.buildings.check_place(def, tile, path[i].z)
		var existing := world.buildings.get_at(tile)
		if existing is Pipe:
			kinds[i] = KEEP
		elif check == BuildingManager.Check.OCCUPIED or check == BuildingManager.Check.BAD_TERRAIN \
				or check == BuildingManager.Check.OUT_OF_BOUNDS or check == BuildingManager.Check.LOCKED \
				or (check == BuildingManager.Check.REPLACE and existing != null):
			kinds[i] = OBSTACLE
		else:
			kinds[i] = PIPE

	# Подземные пары над сплошными участками препятствий.
	var under_at: Dictionary[int, int] = {}
	var covered: Dictionary[int, bool] = {}
	var i := 0
	while i < n:
		if kinds[i] != OBSTACLE:
			i += 1
			continue
		var first := i
		while i < n and kinds[i] == OBSTACLE and path[i].z == path[first].z:
			i += 1
		var entry := first - 1
		var exit := i
		if under_def == null or entry < 0 or exit >= n or kinds[exit] == OBSTACLE or kinds[entry] == OBSTACLE:
			continue
		var dir: int = path[first].z
		if path[entry].z != dir or exit - entry > under_range:
			continue
		var entry_tile := Vector2i(path[entry].x, path[entry].y)
		var exit_tile := Vector2i(path[exit].x, path[exit].y)
		if not BuildingManager.is_valid_check(world.buildings.check_place(under_def, entry_tile, dir)) \
				or not BuildingManager.is_valid_check(world.buildings.check_place(under_def, exit_tile, (dir + 2) % 4)):
			continue
		if under_left < 2:
			continue
		under_left -= 2
		under_at[entry] = dir
		under_at[exit] = (dir + 2) % 4
		for k in range(first, exit):
			covered[k] = true

	var ghosts: Array[PlacementPreview.Ghost] = []
	for k in n:
		var origin := Vector2i(path[k].x, path[k].y)
		if under_at.has(k):
			var rot: int = under_at[k]
			ghosts.append(PlacementPreview.Ghost.new(under_def, origin, rot, world.check_build(under_def, origin, rot, budget)))
		elif covered.has(k) or kinds[k] == KEEP:
			continue
		elif kinds[k] == OBSTACLE:
			var blocked := world.buildings.check_place(def, origin, 0)
			if BuildingManager.is_valid_check(blocked):
				blocked = BuildingManager.Check.OCCUPIED
			ghosts.append(PlacementPreview.Ghost.new(def, origin, 0, blocked))
		else:
			ghosts.append(PlacementPreview.Ghost.new(def, origin, 0, world.check_build(def, origin, 0, budget)))
	return ghosts


## Ряд подземных труб вдоль одной оси: вход и выход на наибольшем расстоянии, следующая пара
## начинается сразу за предыдущей — получается сплошная подземная линия из минимума труб
## (так же, как опоры ЛЭП протягиваются через wire_range).
static func plan_underground(world: GameWorld, def: FluidBuildingDef, start: Vector2i, end: Vector2i,
		fallback_dir: int, budget: Inventory.Budget) -> Array[PlacementPreview.Ghost]:
	var ghosts: Array[PlacementPreview.Ghost] = []
	var delta := end - start
	var axis_x := absi(delta.x) >= absi(delta.y)
	var length := absi(delta.x) if axis_x else absi(delta.y)
	var dir := fallback_dir
	if length > 0:
		if axis_x:
			dir = GameConst.Dir.RIGHT if delta.x > 0 else GameConst.Dir.LEFT
		else:
			dir = GameConst.Dir.DOWN if delta.y > 0 else GameConst.Dir.UP
	var step := GameConst.dir_vector(dir)
	var back := (dir + 2) % 4
	var span := maxi(def.underground_range, 1)
	if length == 0:
		# Одиночный клик: выход сам разворачивается ко входу (placement_rotation).
		var rot := def.placement_rotation(world, start, fallback_dir)
		ghosts.append(PlacementPreview.Ghost.new(def, start, rot, world.check_build(def, start, rot, budget)))
		return ghosts
	var at := 0
	while at <= length:
		var entry := start + step * at
		ghosts.append(PlacementPreview.Ghost.new(def, entry, dir, world.check_build(def, entry, dir, budget)))
		if at == length:
			break
		var exit_at := mini(at + span, length)
		var exit_tile := start + step * exit_at
		ghosts.append(PlacementPreview.Ghost.new(def, exit_tile, back, world.check_build(def, exit_tile, back, budget)))
		at = exit_at + 1
	return ghosts


## Сколько построек def можно поставить из инвентаря (в творческом режиме — без ограничений).
static func _available(world: GameWorld, def: BuildingDef) -> int:
	if def == null:
		return 0
	if world.creative:
		return 1 << 30
	if world.drone == null or def.item == null:
		return 0
	return Session.predict.inventory_of(world.drone).count(def.item.index)


## Добавляет тайлы от a (не включая) до b (включая) по одной оси.
static func _walk(tiles: Array[Vector2i], a: Vector2i, b: Vector2i) -> void:
	var delta := b - a
	var step := Vector2i(signi(delta.x), signi(delta.y))
	var pos := a
	while pos != b:
		pos += step
		tiles.append(pos)
