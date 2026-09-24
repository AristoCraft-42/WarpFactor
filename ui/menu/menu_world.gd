class_name MenuWorld
extends RefCounted
## Живая фабрика для фона главного меню: маленькая карта и собранный на ней завод, который
## кормит сам себя. Мир обычный, но вне забега: ни дрона, ни врагов, ни исследований — только
## симуляция, которую крутит фон (MenuBackground).
##
## Чертёж задан кодом в локальных координатах (ORIGIN — его левый верхний угол на карте), а не
## картой уровня: фон должен быть одинаково живым, какие бы уровни ни лежали в игре.
## Устройство завода сверху вниз:
##   - угольное поле и общая шина угля, идущая вниз через весь завод;
##   - три линии: бур на гематите → лента → развилка на две печи; уголь к печам — отводами с шины,
##     слитки уходят вправо через перекрёстки на шине;
##   - колонна справа собирает слитки и ведёт их в сборщик шестерён, готовое — в ящик;
##   - внизу три термогенератора на той же шине: они питают буры и сборщик, лишний уголь — в ящик.
## Расходы подобраны так, чтобы ленты не вставали: печи съедают чуть больше руды, чем даёт бур,
## а лишнему углю всегда есть куда ссыпаться.

const WIDTH := 72
const HEIGHT := 48
## Левый верхний угол чертежа на карте.
const ORIGIN := Vector2i(21, 9)
## Ряды производственных линий в координатах чертежа (у линии две печи: на row и на row + 4).
const LINES: Array[int] = [4, 12, 20]
## Столбец угольной шины и ряд, на котором она поворачивает к генераторам.
const BUS_X := 16
const BUS_BOTTOM := 29

var world: GameWorld
## Прямоугольник завода в пикселях мира: по нему летает камера.
var factory_rect: Rect2
## Сколько зданий чертежа не встало (в норме 0 — проверяется тестом).
var failed: int = 0

## Здания, которым при постройке кладут уголь (буры, печи, генераторы).
var _fuelled: Array[Building] = []


func _init(p_seed: int = 0) -> void:
	Registry.ensure_loaded()
	world = GameWorld.create(null, _build_map(p_seed), false, null, false)
	_build_coal_bus()
	for row in LINES:
		_build_line(row)
	_build_collector()
	_build_power()
	_prime()
	var rect := Rect2i(ORIGIN + Vector2i(-3, -2), Vector2i(34, 36))
	var tile := float(GameConst.TILE_SIZE)
	factory_rect = Rect2(Vector2(rect.position) * tile, Vector2(rect.size) * tile)


func dispose() -> void:
	if world != null:
		world.dispose()
		world = null


## Один тик фабрики.
func step() -> void:
	world.simulation.step()


## Розжиг: тот, кто построил этот завод, оставил в бурах, печах и генераторах немного угля.
## Без него завод мёртв: угольному буру нечего жечь, чтобы добыть свой первый уголь.
func _prime() -> void:
	var coal := Registry.get_item(&"coal")
	if coal == null:
		return
	for building in _fuelled:
		while building.accept_item(null, coal.index):
			building.handle_item(null, coal.index)
		building.wake()


# --- Карта ---

## Пейзаж: пятна пола шумом, скалы по краям (у завода их нет), декоративные залежи
## и руда под бурами завода.
func _build_map(p_seed: int) -> LevelMap:
	var base := _floor_index(&"stone")
	var map := LevelMap.new(WIDTH, HEIGHT, base)
	var patch := _floor_index(&"gravel")
	var dark := _floor_index(&"dark_stone")
	var rock := _floor_index(&"rock")
	var ground := FastNoiseLite.new()
	ground.seed = p_seed
	ground.frequency = 0.05
	var stones := FastNoiseLite.new()
	stones.seed = p_seed + 17
	stones.frequency = 0.09
	var clear := Rect2i(ORIGIN + Vector2i(-5, -4), Vector2i(38, 40))
	for y in HEIGHT:
		for x in WIDTH:
			var v := ground.get_noise_2d(x, y)
			var index := base
			if v > 0.2:
				index = patch
			elif v < -0.28:
				index = dark
			if stones.get_noise_2d(x, y) > 0.42 and not clear.has_point(Vector2i(x, y)):
				index = rock
			map.set_floor(x, y, index)

	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed + 101
	var decor: Array[StringName] = [&"hematite", &"coal", &"stone", &"malachite"]
	for i in 8:
		var at := Vector2(rng.randf_range(4.0, WIDTH - 4.0), rng.randf_range(4.0, HEIGHT - 4.0))
		if clear.grow(5).has_point(Vector2i(at)):
			continue
		_blob(map, at, rng.randf_range(3.0, 6.0), _ore_value(decor[i % decor.size()]))

	var hematite := _ore_value(&"hematite")
	for row in LINES:
		_blob(map, Vector2(ORIGIN) + Vector2(1.5, row + 1.5), 4.0, hematite)
	_blob(map, Vector2(ORIGIN) + Vector2(BUS_X, 1.0), 3.6, _ore_value(&"coal"))
	return map


## Клякса руды; на скалах руды не бывает.
func _blob(map: LevelMap, center: Vector2, radius: float, ore_value: int) -> void:
	if ore_value <= 0:
		return
	var rock := _floor_index(&"rock")
	var r := ceili(radius)
	for y in range(floori(center.y) - r, floori(center.y) + r + 1):
		for x in range(floori(center.x) - r, floori(center.x) + r + 1):
			if not map.in_bounds(x, y) or map.get_floor(x, y) == rock:
				continue
			# Край кляксы «жуётся» синусом, иначе залежь выглядит нарисованной циркулем.
			var to := Vector2(x, y) - center
			var edge := radius * (0.82 + 0.18 * sin(to.angle() * 3.0))
			if to.length() <= edge:
				map.set_ore(x, y, ore_value)


static func _floor_index(id: StringName) -> int:
	var def := Registry.get_floor(id)
	return def.index if def != null else 0


static func _ore_value(id: StringName) -> int:
	var def := Registry.get_ore(id)
	return def.index + 1 if def != null else 0


# --- Чертёж ---

## Здание чертежа. Координаты локальные, ORIGIN прибавляется здесь.
func _put(id: StringName, tile: Vector2i, rotation: int = 0, config: Variant = null) -> Building:
	var def := Registry.get_building(id)
	var building := world.buildings.place(def, ORIGIN + tile, rotation) if def != null else null
	if building == null:
		failed += 1
		push_warning("MenuWorld: не встало %s в %s" % [id, tile])
		return null
	if building is PowerPole:
		world.power.auto_link(building)
	if id == &"coal_drill" or id == &"thermal_generator" or id == &"furnace":
		_fuelled.append(building)
	if config != null:
		world.configure(building, config)
	return building


## Прямая лента от from до to включительно; вся смотрит в сторону движения.
func _belt(from: Vector2i, to: Vector2i) -> void:
	var step := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	if step == Vector2i.ZERO:
		return
	var dir := GameConst.dir_from_vector(step)
	var at := from
	while true:
		_put(&"conveyor", at, dir)
		if at == to:
			return
		at += step


## Угольное поле наверху, шина вниз и генераторы под ней.
func _build_coal_bus() -> void:
	for y in 2:
		_put(&"coal_drill", Vector2i(BUS_X - 1, y), GameConst.Dir.RIGHT)
		_put(&"coal_drill", Vector2i(BUS_X + 1, y), GameConst.Dir.LEFT)

	# На рядах печей шина отдаёт уголь в отвод (маршрутизатор), на рядах вывоза слитков
	# её пересекает поперёк перекрёсток.
	var spurs := PackedInt32Array()
	var crossings := PackedInt32Array()
	for row in LINES:
		spurs.append(row)
		spurs.append(row + 4)
		crossings.append(row + 2)
		crossings.append(row + 6)
	for y in BUS_BOTTOM:
		var tile := Vector2i(BUS_X, y)
		if spurs.has(y):
			_put(&"router", tile)
		elif crossings.has(y):
			_put(&"junction", tile)
		else:
			_put(&"conveyor", tile, GameConst.Dir.DOWN)

	var bottom := BUS_BOTTOM
	_put(&"conveyor", Vector2i(BUS_X, bottom), GameConst.Dir.LEFT)
	_belt(Vector2i(BUS_X - 1, bottom), Vector2i(BUS_X - 2, bottom))
	_put(&"router", Vector2i(13, bottom))
	_put(&"thermal_generator", Vector2i(13, bottom + 1))
	_belt(Vector2i(12, bottom), Vector2i(10, bottom))
	_put(&"router", Vector2i(9, bottom))
	_put(&"thermal_generator", Vector2i(9, bottom + 1))
	_belt(Vector2i(8, bottom), Vector2i(7, bottom))
	_put(&"router", Vector2i(6, bottom))
	_put(&"thermal_generator", Vector2i(6, bottom + 1))
	_belt(Vector2i(5, bottom), Vector2i(4, bottom))
	_put(&"router", Vector2i(3, bottom))
	_put(&"thermal_generator", Vector2i(3, bottom + 1))
	_put(&"conveyor", Vector2i(2, bottom), GameConst.Dir.LEFT)
	# Ящик на конце: лишний уголь всегда есть куда деть, поэтому шина не встаёт.
	_put(&"container", Vector2i(1, bottom))


## Линия: бур на гематите, развилка и две печи; уголь приходит с шины, слитки уходят вправо.
func _build_line(row: int) -> void:
	_put(&"drill", Vector2i(2, row), GameConst.Dir.RIGHT)
	# Второй бур подаёт руду в ту же ленту снизу: две печи съедают меньше, чем дают два бура,
	# поэтому лента всегда полная — завод на фоне выглядит работающим, а не простаивающим.
	_put(&"drill", Vector2i(2, row + 2), GameConst.Dir.RIGHT)
	_belt(Vector2i(4, row + 2), Vector2i(4, row + 1))
	_belt(Vector2i(4, row), Vector2i(9, row))
	_put(&"router", Vector2i(10, row))
	_put(&"conveyor", Vector2i(11, row), GameConst.Dir.RIGHT)
	_put(&"furnace", Vector2i(12, row))
	_belt(Vector2i(10, row + 1), Vector2i(10, row + 3))
	_put(&"conveyor", Vector2i(10, row + 4), GameConst.Dir.RIGHT)
	_put(&"conveyor", Vector2i(11, row + 4), GameConst.Dir.RIGHT)
	_put(&"furnace", Vector2i(12, row + 4))
	for y in [row, row + 4]:
		_belt(Vector2i(BUS_X - 1, y), Vector2i(BUS_X - 2, y))
	for y in [row + 2, row + 6]:
		_belt(Vector2i(12, y), Vector2i(BUS_X - 1, y))
		_belt(Vector2i(BUS_X + 1, y), Vector2i(19, y))


## Колонна слитков и сборщик шестерён.
func _build_collector() -> void:
	_belt(Vector2i(20, LINES[0] + 2), Vector2i(20, 27))
	_belt(Vector2i(20, 28), Vector2i(21, 28))
	_put(&"assembler", Vector2i(22, 28), 0, &"gear")
	_belt(Vector2i(24, 28), Vector2i(26, 28))
	_put(&"container", Vector2i(27, 28))


## Опоры ЛЭП цепочкой от буров к генераторам: каждая новая сама цепляется к предыдущей.
func _build_power() -> void:
	var poles: Array[Vector2i] = [Vector2i(5, 6), Vector2i(5, 10), Vector2i(5, 14), Vector2i(5, 18),
		Vector2i(5, 22), Vector2i(5, 26), Vector2i(5, 28), Vector2i(8, 28), Vector2i(12, 28),
		Vector2i(17, 27), Vector2i(21, 27)]
	for tile in poles:
		_put(&"small_power_pole", tile)
