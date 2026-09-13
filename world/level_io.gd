class_name LevelIO
extends RefCounted
## Чтение и запись карт уровней (.fwmap).
## Формат бинарный, сжатый ZSTD, с явной версией. Типы полов/руд/зданий хранятся
## таблицами строковых id, поэтому добавление новых .tres не ломает старые карты.
##
## Версия 1:
##   magic "FWMP", u16 версия, u32 ширина, u32 высота,
##   таблица полов, таблица руд, таблица зданий (u16 count + строки),
##   слой полов (w*h байт, индексы таблицы полов),
##   слой руд (w*h байт, 0 — нет, иначе индекс таблицы руд + 1),
##   u32 число зданий, для каждого: u16 индекс таблицы зданий, i32 x, i32 y, u8 поворот.

const MAGIC := "FWMP"
const VERSION := 1


static func save_map(map: LevelMap, path: String) -> Error:
	Registry.ensure_loaded()
	var file := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		return FileAccess.get_open_error()

	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_16(VERSION)
	file.store_32(map.width)
	file.store_32(map.height)

	# В файл пишем полные текущие таблицы — индексы слоёв совпадают с Registry.
	var floor_ids := PackedStringArray()
	for f in Registry.floors:
		floor_ids.append(f.id)
	var ore_ids := PackedStringArray()
	for o in Registry.ores:
		ore_ids.append(o.id)
	var building_ids := PackedStringArray()
	for b in Registry.buildings:
		building_ids.append(b.id)
	_store_table(file, floor_ids)
	_store_table(file, ore_ids)
	_store_table(file, building_ids)

	file.store_buffer(map.floors)
	file.store_buffer(map.ores)

	file.store_32(map.placements.size())
	for p in map.placements:
		file.store_16(p.def.index)
		file.store_32(p.origin.x)
		file.store_32(p.origin.y)
		file.store_8(p.rotation)

	var error := file.get_error()
	file.close()
	return error


## Возвращает null при ошибке (подробности — в push_error).
static func load_map(path: String) -> LevelMap:
	Registry.ensure_loaded()
	var file := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if file == null:
		push_error("LevelIO: не удалось открыть %s (%s)" % [path, error_string(FileAccess.get_open_error())])
		return null

	if file.get_buffer(4).get_string_from_ascii() != MAGIC:
		push_error("LevelIO: %s — не файл карты" % path)
		return null
	var version := file.get_16()
	if version < 1 or version > VERSION:
		push_error("LevelIO: %s — неподдерживаемая версия %d" % [path, version])
		return null

	var width := file.get_32()
	var height := file.get_32()
	if width < GameConst.MIN_LEVEL_SIZE or height < GameConst.MIN_LEVEL_SIZE \
			or width > GameConst.MAX_LEVEL_SIZE or height > GameConst.MAX_LEVEL_SIZE:
		push_error("LevelIO: %s — недопустимый размер %dx%d" % [path, width, height])
		return null

	var floor_ids := _get_table(file)
	var ore_ids := _get_table(file)
	var building_ids := _get_table(file)

	var map := LevelMap.new()
	map.width = width
	map.height = height
	map.floors = file.get_buffer(width * height)
	map.ores = file.get_buffer(width * height)
	if map.floors.size() != width * height or map.ores.size() != width * height:
		push_error("LevelIO: %s — файл обрезан" % path)
		return null

	_remap_layer(map.floors, _build_floor_lut(floor_ids))
	_remap_layer(map.ores, _build_ore_lut(ore_ids))

	var placement_count := file.get_32()
	for i in placement_count:
		var table_index := file.get_16()
		var x := file.get_32()
		var y := file.get_32()
		var rotation := file.get_8()
		# get_32 возвращает беззнаковое значение — восстанавливаем знак.
		if x >= 0x80000000:
			x -= 0x100000000
		if y >= 0x80000000:
			y -= 0x100000000
		if table_index >= building_ids.size():
			continue
		var def := Registry.get_building(StringName(building_ids[table_index]))
		if def == null:
			push_warning("LevelIO: %s — неизвестное здание %s пропущено" % [path, building_ids[table_index]])
			continue
		map.add_placement(def, Vector2i(x, y), rotation % 4)

	if file.get_error() != OK and file.get_error() != ERR_FILE_EOF:
		push_error("LevelIO: %s — ошибка чтения" % path)
		return null
	return map


static func _store_table(file: FileAccess, ids: PackedStringArray) -> void:
	file.store_16(ids.size())
	for id in ids:
		file.store_pascal_string(id)


static func _get_table(file: FileAccess) -> PackedStringArray:
	var ids := PackedStringArray()
	var count := file.get_16()
	for i in count:
		ids.append(file.get_pascal_string())
	return ids


## LUT: индекс в файле → индекс в Registry. Неизвестный пол заменяется первым.
static func _build_floor_lut(ids: PackedStringArray) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(256)
	lut.fill(0)
	for i in ids.size():
		var def := Registry.get_floor(StringName(ids[i]))
		if def != null:
			lut[i] = def.index
		else:
			push_warning("LevelIO: неизвестный пол %s заменён" % ids[i])
	return lut


## LUT для руд: значение 0 остаётся 0, значение i+1 → индекс Registry + 1.
static func _build_ore_lut(ids: PackedStringArray) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(256)
	lut.fill(0)
	for i in ids.size():
		if i + 1 > 255:
			break
		var def := Registry.get_ore(StringName(ids[i]))
		if def != null:
			lut[i + 1] = def.index + 1
		else:
			push_warning("LevelIO: неизвестная руда %s удалена" % ids[i])
	return lut


## Переназначает значения слоя по LUT. Если для всех встречающихся значений
## LUT тождественна (обычный случай) — слой не трогается.
static func _remap_layer(layer: PackedByteArray, lut: PackedByteArray) -> void:
	var used := PackedByteArray()
	used.resize(256)
	used.fill(0)
	var n := layer.size()
	for i in n:
		used[layer[i]] = 1
	var needs := false
	for v in 256:
		if used[v] == 1 and lut[v] != v:
			needs = true
			break
	if not needs:
		return
	for i in n:
		layer[i] = lut[layer[i]]
