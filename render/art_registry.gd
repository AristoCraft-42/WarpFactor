class_name ArtRegistry
extends RefCounted
## Единая точка получения графики. Если в данных задан спрайт/текстура — используется он,
## иначе создаётся процедурный плейсхолдер (PlaceholderArt). Логика игры графику не трогает.
##
## Тайлы пола и руды собираются в общий атлас для TileSet: строка на тип, VARIANTS столбцов.
## Каждая ячейка — 34x34 с 1px «выдавленным» краем, чтобы при линейной фильтрации не было швов.
## Спрайты зданий (и плейсхолдеры, и готовые PNG) тоже упаковываются в один атлас:
## одна текстура на все здания позволяет рендеру объединять их в батчи.
## У здания три кадра состояния (работа, простой, выключено) — в атласе они лежат подряд,
## а полоса кадров берётся из BuildingDef.sprite (меньше трёх кадров — недостающие
## повторяют первый).

const VARIANTS := 4
const CELL := 34
const TERRAIN_SOURCE_ID := 0
const BUILDING_ATLAS_WIDTH := 512
const BUILDING_ATLAS_PADDING := 2
const ENEMY_CELL := 48
## Строк атласа на руду: по одной на богатство клетки (OreDef.Richness).
const RICHNESS_LEVELS := 4
## Сколько кадров состояния у здания (Building.ArtState).
const BUILDING_STATES := 3

static var terrain_tileset: TileSet
## Иконки всех предметов в одну полосу (ячейка на индекс предмета) — для MultiMesh предметов.
static var item_atlas: Texture2D
## Спрайты врагов в одну полосу (ячейка ENEMY_CELL на индекс EnemyDef) — для MultiMesh врагов.
static var enemy_atlas: Texture2D
static var _floor_row_offset: int = 0
static var _ore_row_offset: int = 0
## id здания → кадры состояний (BUILDING_STATES штук).
static var _building_textures: Dictionary[StringName, Array] = {}
static var _item_icons: Dictionary[StringName, Texture2D] = {}
## Цвет пола/руды для обзорной карты и оверлеев.
static var floor_colors: PackedColorArray = PackedColorArray()
static var ore_colors: PackedColorArray = PackedColorArray()
static var _built: bool = false


static func ensure_built() -> void:
	if _built:
		return
	_built = true
	Registry.ensure_loaded()
	_build_terrain()
	_build_building_atlas()
	_build_item_atlas()
	_build_enemy_atlas()


## Текстура здания в состоянии state (Building.ArtState) — область общего атласа.
static func get_building_texture(def: BuildingDef, state: int = 0) -> Texture2D:
	ensure_built()
	var frames: Array = _building_textures.get(def.id, [])
	if frames.is_empty():
		# Здание добавлено после сборки атласа — отдельные текстуры (без батчинга).
		frames = []
		for k in BUILDING_STATES:
			frames.append(ImageTexture.create_from_image(_building_image(def, k)))
		_building_textures[def.id] = frames
	return frames[clampi(state, 0, frames.size() - 1)]


static func get_item_icon(item: ItemType) -> Texture2D:
	if item.icon != null:
		return item.icon
	var tex: Texture2D = _item_icons.get(item.id)
	if tex == null:
		tex = ImageTexture.create_from_image(_item_image(item))
		_item_icons[item.id] = tex
	return tex


static func _build_item_atlas() -> void:
	var t := GameConst.TILE_SIZE
	var atlas := Image.create_empty(t * maxi(Registry.items.size(), 1), t, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for item in Registry.items:
		atlas.blit_rect(_item_image(item), Rect2i(0, 0, t, t), Vector2i(item.index * t, 0))
	item_atlas = ImageTexture.create_from_image(atlas)


static func _build_enemy_atlas() -> void:
	var cell := ENEMY_CELL
	var atlas := Image.create_empty(cell * maxi(Registry.enemies.size(), 1), cell, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for def in Registry.enemies:
		atlas.blit_rect(_enemy_image(def), Rect2i(0, 0, cell, cell), Vector2i(def.index * cell, 0))
	enemy_atlas = ImageTexture.create_from_image(atlas)


static func _enemy_image(def: EnemyDef) -> Image:
	if def.sprite != null:
		var img := def.sprite.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != ENEMY_CELL or img.get_height() != ENEMY_CELL:
				img.resize(ENEMY_CELL, ENEMY_CELL, Image.INTERPOLATE_NEAREST)
			return img
	return PlaceholderArt.make_enemy(def, ENEMY_CELL)


## Иконка 32x32: готовая текстура, уменьшенный спрайт постройки или процедурный плейсхолдер.
static func _item_image(item: ItemType) -> Image:
	var t := GameConst.TILE_SIZE
	if item.icon != null:
		var img := item.icon.get_image()
		if img != null:
			if img.is_compressed():
				img.decompress()
			img.convert(Image.FORMAT_RGBA8)
			if img.get_width() != t or img.get_height() != t:
				img.resize(t, t, Image.INTERPOLATE_NEAREST)
			return img
	if item.building != null:
		var building_img := _building_image(item.building)
		building_img.resize(t - 4, t - 4, Image.INTERPOLATE_BILINEAR)
		var framed := Image.create_empty(t, t, false, Image.FORMAT_RGBA8)
		framed.fill(Color(0, 0, 0, 0))
		framed.blit_rect(building_img, Rect2i(Vector2i.ZERO, building_img.get_size()), Vector2i(2, 2))
		return framed
	return PlaceholderArt.make_item_icon(item)


## Координаты тайла пола в атласе (вариант выбирается хешем позиции).
static func floor_atlas_coords(floor_index: int, x: int, y: int) -> Vector2i:
	return Vector2i(PlaceholderArt.hash3(x, y, 17) % VARIANTS, _floor_row_offset + floor_index)


## ore_value — значение слоя руды (индекс OreDef + 1), richness — богатство клетки (OreDef.Richness):
## у каждой руды по строке атласа на богатство.
static func ore_atlas_coords(ore_value: int, x: int, y: int, richness: int = 0) -> Vector2i:
	var level := clampi(richness, 0, RICHNESS_LEVELS - 1)
	return Vector2i(PlaceholderArt.hash3(x, y, 23) % VARIANTS, _ore_row_offset + (ore_value - 1) * RICHNESS_LEVELS + level)


## Цвет руды для оверлея: тёмные руды (уголь) осветляются, чтобы читаться на затемнённом фоне.
static func ore_overlay_color(ore_index: int) -> Color:
	var col := ore_colors[ore_index]
	if col.get_luminance() < 0.3:
		col = col.lightened(0.45)
	return col


static func _build_building_atlas() -> void:
	var defs := Registry.buildings.duplicate()
	defs.sort_custom(func(a: BuildingDef, b: BuildingDef) -> bool: return a.size > b.size)
	# Полочная упаковка: здания одного размера идут строками.
	var positions: Dictionary[StringName, Vector2i] = {}
	var images: Dictionary[StringName, Image] = {}
	var cursor := Vector2i(BUILDING_ATLAS_PADDING, BUILDING_ATLAS_PADDING)
	var row_height := 0
	for def in defs:
		for state in BUILDING_STATES:
			var key := _state_key(def.id, state)
			var img := _building_image(def, state)
			var w := img.get_width()
			if cursor.x + w + BUILDING_ATLAS_PADDING > BUILDING_ATLAS_WIDTH:
				cursor = Vector2i(BUILDING_ATLAS_PADDING, cursor.y + row_height + BUILDING_ATLAS_PADDING)
				row_height = 0
			positions[key] = cursor
			images[key] = img
			cursor.x += w + BUILDING_ATLAS_PADDING
			row_height = maxi(row_height, img.get_height())
	var height := nearest_po2(cursor.y + row_height + BUILDING_ATLAS_PADDING)
	var atlas := Image.create_empty(BUILDING_ATLAS_WIDTH, height, false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))
	for id in images:
		var img := images[id]
		atlas.blit_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), positions[id])
	var atlas_texture := ImageTexture.create_from_image(atlas)
	for def in defs:
		var frames: Array = []
		for state in BUILDING_STATES:
			var key := _state_key(def.id, state)
			var region := AtlasTexture.new()
			region.atlas = atlas_texture
			region.region = Rect2(positions[key], images[key].get_size())
			frames.append(region)
		_building_textures[def.id] = frames


static func _state_key(id: StringName, state: int) -> StringName:
	return StringName("%s#%d" % [id, state])


## Кадр здания в состоянии state: из полосы кадров спрайта (приводится к size*32)
## или процедурный плейсхолдер. Кадров в полосе может быть меньше — берётся первый.
static func _building_image(def: BuildingDef, state: int = 0) -> Image:
	var target := def.size * GameConst.TILE_SIZE
	if def.sprite != null:
		var src := def.sprite.get_image()
		if src != null:
			if src.is_compressed():
				src.decompress()
			src.convert(Image.FORMAT_RGBA8)
			# Кадры квадратные и лежат в ряд: сколько их, видно по ширине полосы.
			var side := src.get_height()
			var frames := maxi(src.get_width() / maxi(side, 1), 1)
			var frame := clampi(state, 0, frames - 1)
			var img := Image.create_empty(side, side, false, Image.FORMAT_RGBA8)
			img.blit_rect(src, Rect2i(frame * side, 0, side, side), Vector2i.ZERO)
			if side != target:
				img.resize(target, target, Image.INTERPOLATE_NEAREST)
			return img
	return PlaceholderArt.make_building(def)


static func _build_terrain() -> void:
	var rows := Registry.floors.size() + Registry.ores.size() * RICHNESS_LEVELS
	var atlas := Image.create_empty(CELL * VARIANTS, CELL * maxi(rows, 1), false, Image.FORMAT_RGBA8)
	atlas.fill(Color(0, 0, 0, 0))

	_floor_row_offset = 0
	_ore_row_offset = Registry.floors.size()

	floor_colors.resize(Registry.floors.size())
	for f in Registry.floors:
		floor_colors[f.index] = f.color
		for v in VARIANTS:
			var img := _variant_from_texture(f.texture, v)
			if img == null:
				img = PlaceholderArt.make_floor(f, v)
			_blit_cell(atlas, img, v, _floor_row_offset + f.index)

	ore_colors.resize(Registry.ores.size())
	for o in Registry.ores:
		ore_colors[o.index] = o.get_color()
		for level in RICHNESS_LEVELS:
			for v in VARIANTS:
				var img := _variant_from_texture(o.texture, v)
				if img == null:
					img = PlaceholderArt.make_ore(o, v, level)
				_blit_cell(atlas, img, v, _ore_row_offset + o.index * RICHNESS_LEVELS + level)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(atlas)
	source.margins = Vector2i(1, 1)
	source.separation = Vector2i(2, 2)
	source.texture_region_size = Vector2i(GameConst.TILE_SIZE, GameConst.TILE_SIZE)
	for row in rows:
		for col in VARIANTS:
			source.create_tile(Vector2i(col, row))

	terrain_tileset = TileSet.new()
	terrain_tileset.tile_size = Vector2i(GameConst.TILE_SIZE, GameConst.TILE_SIZE)
	terrain_tileset.add_source(source, TERRAIN_SOURCE_ID)


## Вариант v из готовой текстуры: полоса 32*N по горизонтали или одиночный тайл.
static func _variant_from_texture(texture: Texture2D, v: int) -> Image:
	if texture == null:
		return null
	var src := texture.get_image()
	if src == null:
		return null
	if src.is_compressed():
		src.decompress()
	src.convert(Image.FORMAT_RGBA8)
	var t := GameConst.TILE_SIZE
	var count := maxi(src.get_width() / t, 1)
	var region := Rect2i((v % count) * t, 0, t, t)
	var out := Image.create_empty(t, t, false, Image.FORMAT_RGBA8)
	out.blit_rect(src, region, Vector2i.ZERO)
	return out


## Копирует тайл 32x32 в ячейку атласа с выдавливанием края на 1px.
static func _blit_cell(atlas: Image, tile: Image, col: int, row: int) -> void:
	var t := GameConst.TILE_SIZE
	var ox := col * CELL
	var oy := row * CELL
	atlas.blit_rect(tile, Rect2i(0, 0, t, t), Vector2i(ox + 1, oy + 1))
	# Края
	atlas.blit_rect(tile, Rect2i(0, 0, t, 1), Vector2i(ox + 1, oy))
	atlas.blit_rect(tile, Rect2i(0, t - 1, t, 1), Vector2i(ox + 1, oy + t + 1))
	atlas.blit_rect(tile, Rect2i(0, 0, 1, t), Vector2i(ox, oy + 1))
	atlas.blit_rect(tile, Rect2i(t - 1, 0, 1, t), Vector2i(ox + t + 1, oy + 1))
	# Углы
	atlas.set_pixel(ox, oy, tile.get_pixel(0, 0))
	atlas.set_pixel(ox + t + 1, oy, tile.get_pixel(t - 1, 0))
	atlas.set_pixel(ox, oy + t + 1, tile.get_pixel(0, t - 1))
	atlas.set_pixel(ox + t + 1, oy + t + 1, tile.get_pixel(t - 1, t - 1))
