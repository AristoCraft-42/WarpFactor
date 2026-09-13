class_name MapPreview
extends RefCounted
## Картинка карты «1 пиксель = 1 тайл»: обзорный LOD при сильном отдалении, превью в меню,
## оверлей руд. Строится один раз из упакованных массивов, без обхода в каждом кадре.


## Цвет тайла: пол, поверх — руда; скалы затемнены сильнее.
static func build_terrain_image(width: int, height: int, floors: PackedByteArray, ores: PackedByteArray) -> Image:
	ArtRegistry.ensure_built()
	var floor_lut := PackedByteArray()
	floor_lut.resize(256 * 4)
	for i in ArtRegistry.floor_colors.size():
		var c := ArtRegistry.floor_colors[i]
		if Registry.floor_buildable[i] == 0:
			c = c.darkened(0.35)
		_write_color(floor_lut, i, c)
	var ore_lut := PackedByteArray()
	ore_lut.resize(256 * 4)
	for i in ArtRegistry.ore_colors.size():
		_write_color(ore_lut, i + 1, ArtRegistry.ore_colors[i].darkened(0.1))

	var data := PackedByteArray()
	var n := width * height
	data.resize(n * 4)
	for i in n:
		var ore := ores[i]
		var src := ore_lut if ore != 0 else floor_lut
		var o := (ore if ore != 0 else floors[i]) * 4
		var d := i * 4
		data[d] = src[o]
		data[d + 1] = src[o + 1]
		data[d + 2] = src[o + 2]
		data[d + 3] = 255
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)


## Оверлей руд: руда — яркий цвет, всё остальное — полупрозрачное затемнение.
static func build_ore_overlay_image(width: int, height: int, floors: PackedByteArray, ores: PackedByteArray) -> Image:
	ArtRegistry.ensure_built()
	var ore_lut := PackedByteArray()
	ore_lut.resize(256 * 4)
	for i in ArtRegistry.ore_colors.size():
		_write_color(ore_lut, i + 1, ArtRegistry.ore_overlay_color(i))
	var data := PackedByteArray()
	var n := width * height
	data.resize(n * 4)
	for i in n:
		var d := i * 4
		var ore := ores[i]
		if ore != 0:
			var o := ore * 4
			data[d] = ore_lut[o]
			data[d + 1] = ore_lut[o + 1]
			data[d + 2] = ore_lut[o + 2]
			data[d + 3] = 245
		elif Registry.floor_buildable[floors[i]] == 0:
			data[d + 3] = 215
		else:
			data[d + 3] = 165
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)


## Добавляет на картинку здания уровня (для превью в меню).
static func draw_placements(img: Image, placements: Array[LevelMap.Placement]) -> void:
	for p in placements:
		var col := p.def.color.lightened(0.2)
		img.fill_rect(Rect2i(p.origin, Vector2i(p.def.size, p.def.size)).intersection(Rect2i(Vector2i.ZERO, img.get_size())), col)


static func _write_color(lut: PackedByteArray, index: int, c: Color) -> void:
	lut[index * 4] = c.r8
	lut[index * 4 + 1] = c.g8
	lut[index * 4 + 2] = c.b8
	lut[index * 4 + 3] = 255
