class_name PlaceholderArt
extends RefCounted
## Процедурные плейсхолдеры: тайлы пола и руды, иконки предметов, спрайты зданий.
## Всё рисуется в Image при запуске. Если в .tres задан готовый спрайт — плейсхолдер не используется
## (см. ArtRegistry), поэтому замена графики на Aseprite не требует правки логики.

const T := 32

const INK := Color("1d2021")
const LIGHT := Color("ebdbb2")
const ACCENT := Color("fabd2f")
const FIRE := Color("fe8019")


# --- Утилиты ---

## Детерминированный хеш координат (без глобального RNG).
static func hash3(x: int, y: int, s: int) -> int:
	var h: int = x * 374761393 + y * 668265263 + s * 982451653
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return h & 0x7fffffff


static func _blank(w: int, h: int) -> Image:
	var img := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


static func _put(img: Image, x: int, y: int, col: Color) -> void:
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		if col.a >= 0.999:
			img.set_pixel(x, y, col)
		else:
			img.set_pixel(x, y, img.get_pixel(x, y).blend(col))


static func _rect(img: Image, r: Rect2i, col: Color) -> void:
	var clipped := r.intersection(Rect2i(0, 0, img.get_width(), img.get_height()))
	if clipped.size.x <= 0 or clipped.size.y <= 0:
		return
	if col.a >= 0.999:
		img.fill_rect(clipped, col)
	else:
		for y in range(clipped.position.y, clipped.end.y):
			for x in range(clipped.position.x, clipped.end.x):
				_put(img, x, y, col)


static func _frame(img: Image, r: Rect2i, width: int, col: Color) -> void:
	_rect(img, Rect2i(r.position.x, r.position.y, r.size.x, width), col)
	_rect(img, Rect2i(r.position.x, r.end.y - width, r.size.x, width), col)
	_rect(img, Rect2i(r.position.x, r.position.y, width, r.size.y), col)
	_rect(img, Rect2i(r.end.x - width, r.position.y, width, r.size.y), col)


static func _circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	for y in range(floori(c.y - r), ceili(c.y + r) + 1):
		for x in range(floori(c.x - r), ceili(c.x + r) + 1):
			var dx := x + 0.5 - c.x
			var dy := y + 0.5 - c.y
			if dx * dx + dy * dy <= r * r:
				_put(img, x, y, col)


static func _ring(img: Image, c: Vector2, r_outer: float, r_inner: float, col: Color) -> void:
	for y in range(floori(c.y - r_outer), ceili(c.y + r_outer) + 1):
		for x in range(floori(c.x - r_outer), ceili(c.x + r_outer) + 1):
			var dx := x + 0.5 - c.x
			var dy := y + 0.5 - c.y
			var d2 := dx * dx + dy * dy
			if d2 <= r_outer * r_outer and d2 >= r_inner * r_inner:
				_put(img, x, y, col)


static func _poly(img: Image, pts: PackedVector2Array, col: Color) -> void:
	var bounds := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		bounds = bounds.expand(p)
	for y in range(floori(bounds.position.y), ceili(bounds.end.y) + 1):
		for x in range(floori(bounds.position.x), ceili(bounds.end.x) + 1):
			if Geometry2D.is_point_in_polygon(Vector2(x + 0.5, y + 0.5), pts):
				_put(img, x, y, col)


static func _line(img: Image, a: Vector2, b: Vector2, width: float, col: Color) -> void:
	var length := a.distance_to(b)
	var steps := maxi(ceili(length * 2.0), 1)
	for i in steps + 1:
		var p := a.lerp(b, float(i) / steps)
		_circle(img, p, width * 0.5, col)


## Правильный многоугольник или звезда вокруг центра.
static func _ngon(c: Vector2, r: float, sides: int, rotation: float = 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in sides:
		var a := rotation + TAU * i / sides
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _star(c: Vector2, r_outer: float, r_inner: float, points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := -PI * 0.5 + PI * i / points
		var r := r_outer if i % 2 == 0 else r_inner
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func _scale_pts(pts: PackedVector2Array, c: Vector2, k: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(c + (p - c) * k)
	return out


# --- Враги ---

## Враг в ячейке size×size, нарисован «вправо» (как здания). Масштаб на экране — EnemyDef.draw_size.
static func make_enemy(def: EnemyDef, size: int = 48) -> Image:
	var img := _blank(size, size)
	var c := Vector2(size, size) * 0.5
	var col := def.color
	var dark := col.darkened(0.45)
	var light := col.lightened(0.35)
	match def.shape:
		EnemyDef.Shape.BUG:
			# Ползун: овальное тело, лапки, жвала вперёд.
			for i in 3:
				var x := c.x - 8.0 + i * 7.0
				_line(img, Vector2(x, c.y - 4), Vector2(x - 4, c.y - 15), 2.5, INK)
				_line(img, Vector2(x, c.y + 4), Vector2(x - 4, c.y + 15), 2.5, INK)
			_poly(img, _ngon(c, 13.0, 10), INK)
			_poly(img, _scale_pts(_ngon(c, 13.0, 10), c, 0.82), col)
			_circle(img, c + Vector2(-3, 0), 5.0, dark)
			_line(img, c + Vector2(9, -4), c + Vector2(18, -7), 2.5, light)
			_line(img, c + Vector2(9, 4), c + Vector2(18, 7), 2.5, light)
			_circle(img, c + Vector2(7, -3), 1.6, FIRE)
			_circle(img, c + Vector2(7, 3), 1.6, FIRE)
		EnemyDef.Shape.SOLDIER:
			# Стрелок: квадратный корпус на гусеницах, ствол вперёд.
			_rect(img, Rect2i(int(c.x) - 14, int(c.y) - 15, 26, 6), INK)
			_rect(img, Rect2i(int(c.x) - 14, int(c.y) + 9, 26, 6), INK)
			_rect(img, Rect2i(int(c.x) - 12, int(c.y) - 11, 22, 22), INK)
			_rect(img, Rect2i(int(c.x) - 10, int(c.y) - 9, 18, 18), col)
			_rect(img, Rect2i(int(c.x) + 2, int(c.y) - 2, 20, 5), INK)
			_rect(img, Rect2i(int(c.x) + 3, int(c.y) - 1, 18, 3), light)
			_circle(img, c + Vector2(-1, 0), 5.0, dark)
			_circle(img, c + Vector2(-1, 0), 2.0, FIRE)
		EnemyDef.Shape.BRUTE:
			# Громила: массивный шестиугольник с бронеплитами и рогами.
			_poly(img, _ngon(c, 21.0, 6), INK)
			_poly(img, _ngon(c, 18.0, 6), col)
			_poly(img, _ngon(c + Vector2(-2, 0), 10.0, 6), dark)
			_line(img, c + Vector2(12, -10), c + Vector2(22, -17), 4.0, LIGHT)
			_line(img, c + Vector2(12, 10), c + Vector2(22, 17), 4.0, LIGHT)
			_circle(img, c + Vector2(8, -5), 2.2, FIRE)
			_circle(img, c + Vector2(8, 5), 2.2, FIRE)
	return img


# --- Пол ---

static func make_floor(def: FloorDef, variant: int) -> Image:
	var img := Image.create_empty(T, T, false, Image.FORMAT_RGBA8)
	var base := def.color
	img.fill(base)
	var seed_base := hash3(def.index, variant, 7)
	match def.pattern:
		FloorDef.Pattern.SPECKLED:
			for i in 18:
				var h := hash3(i, variant, seed_base)
				var x := h % T
				var y := (h >> 8) % T
				var col := base.lightened(0.10) if (h >> 16) % 3 == 0 else base.darkened(0.14)
				_put(img, x, y, col)
				if (h >> 20) % 4 == 0:
					_put(img, x + 1, y, col)
		FloorDef.Pattern.CRACKED:
			for i in 8:
				var h := hash3(i, variant, seed_base)
				_put(img, h % T, (h >> 8) % T, base.lightened(0.07))
			for crack in 2:
				var h := hash3(crack, variant, seed_base + 99)
				var p := Vector2(h % T, (h >> 8) % T)
				for step in 9:
					var hs := hash3(step, crack, h)
					p += Vector2(float(hs % 3) - 1.0, float((hs >> 4) % 3) - 1.0)
					_put(img, int(p.x) % T, int(p.y) % T, base.darkened(0.3))
		FloorDef.Pattern.ROCK:
			# Скала: крупные грани со светлым верхом и тёмным низом.
			for i in 5:
				var h := hash3(i, variant, seed_base)
				var c := Vector2(h % T, (h >> 8) % T)
				var r := 5.0 + float((h >> 16) % 5)
				_circle(img, c + Vector2(1, 1), r, base.darkened(0.35))
				_circle(img, c, r, base.lightened(0.10 + 0.04 * (i % 3)))
				_circle(img, c - Vector2(r * 0.35, r * 0.35), r * 0.35, base.lightened(0.22))
		FloorDef.Pattern.PLATES:
			_frame(img, Rect2i(0, 0, T, T), 1, base.darkened(0.3))
			_rect(img, Rect2i(1, 1, T - 2, 1), base.lightened(0.12))
			for corner in [Vector2i(3, 3), Vector2i(T - 5, 3), Vector2i(3, T - 5), Vector2i(T - 5, T - 5)]:
				_rect(img, Rect2i(corner, Vector2i(2, 2)), base.lightened(0.2))
		_:
			pass
	return img


# --- Руда ---

static func make_ore(def: OreDef, variant: int) -> Image:
	var img := _blank(T, T)
	var col := def.get_color()
	var outline := col.darkened(0.55)
	var highlight := col.lightened(0.35)
	var seed_base := hash3(def.index, variant, 31)
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < 4 and attempts < 40:
		var h := hash3(attempts, variant, seed_base)
		attempts += 1
		var c := Vector2(6 + h % 20, 6 + (h >> 8) % 20)
		var ok := true
		for other in placed:
			if other.distance_to(c) < 9.0:
				ok = false
				break
		if not ok:
			continue
		placed.append(c)
		var r := 3.0 + float((h >> 16) % 3)
		var pts := _ngon(c, r, 6, float((h >> 20) % 10) * 0.3)
		_poly(img, _scale_pts(pts, c, (r + 1.3) / r), outline)
		_poly(img, pts, col)
		_put(img, int(c.x - r * 0.4), int(c.y - r * 0.4), highlight)
		_put(img, int(c.x - r * 0.4) + 1, int(c.y - r * 0.4), highlight)
	return img


# --- Иконки предметов ---

static func make_item_icon(item: ItemType, size: int = 32) -> Image:
	var img := _blank(T, T)
	var c := Vector2(16, 16)
	var col := item.color
	var outline := col.darkened(0.6)
	var shade := col.darkened(0.2)
	var highlight := col.lightened(0.4)
	match item.icon_shape:
		ItemType.IconShape.CIRCLE:
			_circle(img, c, 12.5, outline)
			_circle(img, c, 10.5, col)
			_circle(img, c + Vector2(2, 2), 6.0, shade)
			_circle(img, c - Vector2(4, 4), 2.5, highlight)
		ItemType.IconShape.SQUARE:
			_rect(img, Rect2i(5, 5, 22, 22), outline)
			_rect(img, Rect2i(7, 7, 18, 18), col)
			_rect(img, Rect2i(15, 15, 10, 10), shade)
			_rect(img, Rect2i(8, 8, 4, 2), highlight)
		ItemType.IconShape.DIAMOND:
			var d := PackedVector2Array([Vector2(16, 3), Vector2(29, 16), Vector2(16, 29), Vector2(3, 16)])
			_poly(img, d, outline)
			_poly(img, _scale_pts(d, c, 0.8), col)
			_poly(img, PackedVector2Array([Vector2(16, 16), Vector2(26, 16), Vector2(16, 26)]), shade)
			_rect(img, Rect2i(12, 9, 3, 2), highlight)
		ItemType.IconShape.TRIANGLE:
			var tri := PackedVector2Array([Vector2(16, 3), Vector2(30, 28), Vector2(2, 28)])
			_poly(img, tri, outline)
			_poly(img, _scale_pts(tri, Vector2(16, 19.5), 0.78), col)
			_rect(img, Rect2i(14, 11, 3, 3), highlight)
		ItemType.IconShape.HEXAGON:
			var hex := _ngon(c, 13.5, 6, PI / 6.0)
			_poly(img, hex, outline)
			_poly(img, _scale_pts(hex, c, 0.82), col)
			_poly(img, _scale_pts(_ngon(c + Vector2(2, 2), 7.0, 6, PI / 6.0), c + Vector2(2, 2), 1.0), shade)
			_rect(img, Rect2i(9, 10, 4, 2), highlight)
		ItemType.IconShape.CROSS:
			_rect(img, Rect2i(11, 3, 10, 26), outline)
			_rect(img, Rect2i(3, 11, 26, 10), outline)
			_rect(img, Rect2i(13, 5, 6, 22), col)
			_rect(img, Rect2i(5, 13, 22, 6), col)
			_rect(img, Rect2i(13, 5, 2, 6), highlight)
		ItemType.IconShape.RING:
			_ring(img, c, 13.0, 5.0, outline)
			_ring(img, c, 11.0, 7.0, col)
			_put(img, 9, 10, highlight)
			_put(img, 10, 9, highlight)
		ItemType.IconShape.BAR:
			_rect(img, Rect2i(3, 9, 26, 14), outline)
			_rect(img, Rect2i(5, 11, 22, 10), col)
			_rect(img, Rect2i(5, 17, 22, 4), shade)
			_rect(img, Rect2i(7, 12, 8, 2), highlight)
		ItemType.IconShape.STAR:
			var star := _star(c + Vector2(0, 1), 14.5, 6.5, 5)
			_poly(img, star, outline)
			_poly(img, _scale_pts(star, c + Vector2(0, 1), 0.78), col)
			_put(img, 15, 9, highlight)
			_put(img, 16, 9, highlight)
		ItemType.IconShape.FRAME:
			_rect(img, Rect2i(4, 4, 24, 24), outline)
			_rect(img, Rect2i(6, 6, 20, 20), col)
			_rect(img, Rect2i(10, 10, 12, 12), Color(col.lightened(0.5), 0.9))
			_line(img, Vector2(12, 20), Vector2(20, 12), 1.5, Color(1, 1, 1, 0.9))
		ItemType.IconShape.INGOT:
			var ingot := PackedVector2Array([Vector2(8, 8), Vector2(24, 8), Vector2(30, 25), Vector2(2, 25)])
			_poly(img, ingot, outline)
			_poly(img, _scale_pts(ingot, Vector2(16, 16.5), 0.8), col)
			_rect(img, Rect2i(8, 20, 16, 3), shade)
			_rect(img, Rect2i(10, 11, 10, 2), highlight)
	if size != T:
		img.resize(size, size, Image.INTERPOLATE_NEAREST)
	return img


# --- Здания ---

static func make_building(def: BuildingDef) -> Image:
	var s := def.size * T
	var img := _blank(s, s)
	var body := def.color
	if def.glyph == BuildingDef.Glyph.CHEVRONS:
		_draw_conveyor(img, def)
		return img
	if def.glyph == BuildingDef.Glyph.WALL:
		_draw_wall(img, def)
		return img

	# Корпус с фаской
	_rect(img, Rect2i(1, 1, s - 2, s - 2), body.darkened(0.55))
	_rect(img, Rect2i(3, 3, s - 6, s - 6), body)
	_rect(img, Rect2i(3, 3, s - 6, 2), body.lightened(0.25))
	_rect(img, Rect2i(3, 3, 2, s - 6), body.lightened(0.15))
	_rect(img, Rect2i(3, s - 5, s - 6, 2), body.darkened(0.25))
	_rect(img, Rect2i(s - 5, 3, 2, s - 6), body.darkened(0.2))
	if def.size >= 2:
		for corner in [Vector2i(6, 6), Vector2i(s - 9, 6), Vector2i(6, s - 9), Vector2i(s - 9, s - 9)]:
			_rect(img, Rect2i(corner, Vector2i(3, 3)), body.darkened(0.45))
			_put(img, corner.x, corner.y, body.lightened(0.3))

	var c := Vector2(s, s) * 0.5
	var k := float(s) / T # масштаб глифа
	var glyph_col := LIGHT.lerp(body, 0.2)
	var dark := body.darkened(0.6)

	# Метка «лица» здания на правой грани: спрайты нарисованы «вправо», так виден поворот.
	var notch := 3.0 + def.size
	if def.rotatable:
		_poly(img, PackedVector2Array([Vector2(s - 2, c.y), Vector2(s - 2 - notch, c.y - notch), Vector2(s - 2 - notch, c.y + notch)]), ACCENT.darkened(0.15))
	match def.glyph:
		BuildingDef.Glyph.CROSS:
			_rect(img, Rect2i(Vector2i(c - Vector2(11, 3) * k), Vector2i(Vector2(22, 6) * k)), glyph_col)
			_rect(img, Rect2i(Vector2i(c - Vector2(3, 11) * k), Vector2i(Vector2(6, 22) * k)), glyph_col)
			_rect(img, Rect2i(Vector2i(c - Vector2(2, 2) * k), Vector2i(Vector2(4, 4) * k)), dark)
		BuildingDef.Glyph.ROUTER:
			_rect(img, Rect2i(Vector2i(c - Vector2(5, 5) * k), Vector2i(Vector2(10, 10) * k)), glyph_col)
			for dir in 4:
				var v := Vector2(GameConst.dir_vector(dir))
				var tip := c + v * 12.0 * k
				var side := Vector2(-v.y, v.x) * 3.5 * k
				_poly(img, PackedVector2Array([tip, c + v * 7.0 * k + side, c + v * 7.0 * k - side]), glyph_col)
		BuildingDef.Glyph.FILTER:
			var funnel := PackedVector2Array([c + Vector2(-10, -8) * k, c + Vector2(10, -8) * k, c + Vector2(2, 2) * k, c + Vector2(2, 9) * k, c + Vector2(-2, 9) * k, c + Vector2(-2, 2) * k])
			_poly(img, funnel, glyph_col)
			_circle(img, c + Vector2(0, -4) * k, 2.5 * k, dark)
		BuildingDef.Glyph.GATE:
			_line(img, c + Vector2(-10, 0) * k, c + Vector2(6, 0) * k, 3.0 * k, glyph_col)
			_poly(img, PackedVector2Array([c + Vector2(11, 0) * k, c + Vector2(4, -5) * k, c + Vector2(4, 5) * k]), glyph_col)
			_line(img, c + Vector2(-2, 0) * k, c + Vector2(-2, -9) * k, 2.0 * k, glyph_col)
			_line(img, c + Vector2(-2, 0) * k, c + Vector2(-2, 9) * k, 2.0 * k, glyph_col)
		BuildingDef.Glyph.BRIDGE:
			_rect(img, Rect2i(Vector2i(c + Vector2(-10, -2) * k), Vector2i(Vector2(4, 11) * k)), glyph_col)
			_rect(img, Rect2i(Vector2i(c + Vector2(6, -2) * k), Vector2i(Vector2(4, 11) * k)), glyph_col)
			_ring(img, c + Vector2(0, 2) * k, 10.0 * k, 6.5 * k, glyph_col)
			_rect(img, Rect2i(Vector2i(c + Vector2(-11, 3) * k), Vector2i(Vector2(22, 8) * k)), body)
		BuildingDef.Glyph.UNLOAD:
			_frame(img, Rect2i(Vector2i(c + Vector2(-9, -9) * k), Vector2i(Vector2(18, 18) * k)), maxi(int(2 * k), 2), glyph_col)
			_line(img, c + Vector2(0, 4) * k, c + Vector2(0, -6) * k, 2.5 * k, ACCENT)
			_poly(img, PackedVector2Array([c + Vector2(0, -11) * k, c + Vector2(-4, -5) * k, c + Vector2(4, -5) * k]), ACCENT)
		BuildingDef.Glyph.DRILL:
			_circle(img, c, 11.5 * k, dark)
			_circle(img, c, 9.5 * k, body.lightened(0.1))
			for i in 4:
				var a := PI * 0.25 + i * PI * 0.5
				_line(img, c, c + Vector2(cos(a), sin(a)) * 9.0 * k, 3.0 * k, glyph_col)
			_circle(img, c, 3.0 * k, ACCENT)
		BuildingDef.Glyph.GEAR:
			var gear := _star(c, 12.0 * k, 9.0 * k, 8)
			_poly(img, gear, glyph_col)
			_circle(img, c, 4.0 * k, dark)
		BuildingDef.Glyph.PRESS:
			_rect(img, Rect2i(Vector2i(c + Vector2(-10, -10) * k), Vector2i(Vector2(20, 5) * k)), glyph_col)
			_rect(img, Rect2i(Vector2i(c + Vector2(-10, 5) * k), Vector2i(Vector2(20, 5) * k)), glyph_col)
			_rect(img, Rect2i(Vector2i(c + Vector2(-6, -2) * k), Vector2i(Vector2(12, 4) * k)), dark)
			_poly(img, PackedVector2Array([c + Vector2(0, 3) * k, c + Vector2(-3, -1) * k, c + Vector2(3, -1) * k]), ACCENT)
		BuildingDef.Glyph.FLAME:
			var flame := PackedVector2Array([c + Vector2(0, -12) * k, c + Vector2(7, -1) * k, c + Vector2(7, 5) * k, c + Vector2(0, 10) * k, c + Vector2(-7, 5) * k, c + Vector2(-7, -1) * k])
			_poly(img, flame, FIRE)
			_poly(img, _scale_pts(flame, c + Vector2(0, 3) * k, 0.55), ACCENT)
		BuildingDef.Glyph.MIXER:
			_circle(img, c, 12.0 * k, dark)
			for i in 3:
				var a := i * TAU / 3.0
				var p := c + Vector2(cos(a), sin(a)) * 5.0 * k
				_circle(img, p, 5.0 * k, glyph_col)
			_circle(img, c, 3.0 * k, ACCENT)
		BuildingDef.Glyph.SPLIT:
			_line(img, c + Vector2(-11, 0) * k, c + Vector2(-2, 0) * k, 3.0 * k, glyph_col)
			for dy in [-8.0, 0.0, 8.0]:
				_line(img, c + Vector2(-2, 0) * k, c + Vector2(8, dy) * k, 2.5 * k, glyph_col)
				_circle(img, c + Vector2(9, dy) * k, 2.5 * k, ACCENT)
		BuildingDef.Glyph.BOX:
			_rect(img, Rect2i(Vector2i(c + Vector2(-10, -10) * k), Vector2i(Vector2(20, 20) * k)), dark)
			_rect(img, Rect2i(Vector2i(c + Vector2(-8, -8) * k), Vector2i(Vector2(16, 16) * k)), body.lightened(0.15))
			_line(img, c + Vector2(-8, -8) * k, c + Vector2(8, 8) * k, 2.0 * k, dark)
			_line(img, c + Vector2(8, -8) * k, c + Vector2(-8, 8) * k, 2.0 * k, dark)
		BuildingDef.Glyph.TURRET:
			# Основание турели: круглая площадка с болтами, ствол рисуется поверх (TurretView).
			_circle(img, c, 12.5 * k, dark)
			_circle(img, c, 10.5 * k, body.lightened(0.12))
			for i in 4:
				var a := PI * 0.25 + i * PI * 0.5
				_circle(img, c + Vector2(cos(a), sin(a)) * 8.0 * k, 1.5 * k, dark)
		BuildingDef.Glyph.ARTILLERY:
			_rect(img, Rect2i(Vector2i(c - Vector2(12, 12) * k), Vector2i(Vector2(24, 24) * k)), dark)
			_circle(img, c, 11.0 * k, body.lightened(0.1))
			_ring(img, c, 9.0 * k, 7.5 * k, dark)
			for i in 6:
				var a := i * TAU / 6.0
				_circle(img, c + Vector2(cos(a), sin(a)) * 10.0 * k, 1.2 * k, ACCENT.darkened(0.3))
		BuildingDef.Glyph.CORE:
			_rect(img, Rect2i(Vector2i(c + Vector2(-12, -12) * k), Vector2i(Vector2(24, 24) * k)), dark)
			var gem := PackedVector2Array([c + Vector2(0, -10) * k, c + Vector2(9, 0) * k, c + Vector2(0, 10) * k, c + Vector2(-9, 0) * k])
			_poly(img, gem, ACCENT)
			_poly(img, _scale_pts(gem, c, 0.5), LIGHT)
			_ring(img, c, 12.0 * k, 11.0 * k, ACCENT)
		_:
			pass
	return img


## Стена: кладка из блоков с фаской; у больших стен блоки крупнее.
static func _draw_wall(img: Image, def: BuildingDef) -> void:
	var s := def.size * T
	var body := def.color
	_rect(img, Rect2i(0, 0, s, s), body.darkened(0.6))
	var rows := 2 * def.size
	var row_h := s / rows
	for row in rows:
		var offset := 0 if row % 2 == 0 else row_h
		var x := -offset
		while x < s:
			var r := Rect2i(x + 1, row * row_h + 1, row_h * 2 - 2, row_h - 2).intersection(Rect2i(1, 1, s - 2, s - 2))
			if r.size.x > 2:
				_rect(img, r, body)
				_rect(img, Rect2i(r.position, Vector2i(r.size.x, 2)), body.lightened(0.25))
				_rect(img, Rect2i(r.position.x, r.end.y - 2, r.size.x, 2), body.darkened(0.25))
			x += row_h * 2
	_frame(img, Rect2i(0, 0, s, s), 1, INK)


## Лента: тёмное полотно, рельсы по краям, шевроны «вправо».
static func _draw_conveyor(img: Image, def: BuildingDef) -> void:
	var body := def.color
	_rect(img, Rect2i(0, 0, T, T), body.darkened(0.35))
	_rect(img, Rect2i(0, 4, T, T - 8), body)
	_rect(img, Rect2i(0, 1, T, 3), body.lightened(0.3))
	_rect(img, Rect2i(0, T - 4, T, 3), body.lightened(0.15))
	_rect(img, Rect2i(0, 0, T, 1), INK)
	_rect(img, Rect2i(0, T - 1, T, 1), INK)
	var chevron := ACCENT.darkened(0.25) if def.id == &"conveyor" else Color("83a598")
	for x0 in [5, 19]:
		_line(img, Vector2(x0, 9), Vector2(x0 + 6, 16), 2.5, chevron)
		_line(img, Vector2(x0 + 6, 16), Vector2(x0, 23), 2.5, chevron)
