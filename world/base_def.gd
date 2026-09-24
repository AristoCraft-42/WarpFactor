class_name BaseDef
extends Resource
## Параметры подземного этажа мобильной базы (world/base.tres): размеры, пол и комнаты добычи.
## Этаж открывается исследованием «Подземный этаж» размером start_size и расширяется исследованиями
## «Расширение подземного этажа» на size_step (до center_max). Карта мира больше открытой части
## (size), за её краем — пустота (void_floor_id), на ней не строят. Пара центрального шлюза — в центре.
##
## Вокруг центральной части — комнаты добычи: по одной с каждой стороны, каждую открывает своё
## исследование. Комната соединена с центром туннелем, по которому игрок сам тянет ленты и трубы.
## В комнате стоит платформа добычи: её содержимое уезжает на планету, когда игрок наводит её
## с пульта (см. docs/ARCHITECTURE.md).

@export var id: StringName = &"base"
@export var title_key: String = "LOCATION_BASE"
## Сторона карты этажа (наибольший размер после всех расширений), тайлов.
@export var size: int = 46
## Сторона открытой части сразу после открытия этажа и прирост за шаг расширения.
@export var start_size: int = 16
@export var size_step: int = 6
## Наибольшая сторона центральной части (после всех расширений), тайлов: дальше неё идут комнаты.
@export var center_max: int = 46
@export var floor_id: StringName = &"metal_plates"
@export var void_floor_id: StringName = &"void"

@export_group("Комнаты добычи")
## Сторона комнаты и ширина туннеля до центра, тайлов.
@export var room_size: int = 16
@export var tunnel_width: int = 3
## Зазор между наибольшей центральной частью и комнатой, тайлов.
@export var room_gap: int = 6
## Сторона платформы в комнате: всё, что стоит на ней, уезжает на планету.
@export var platform_size: int = 10


## Куда смотрит комната с индексом index (0 — север, дальше по часовой стрелке).
static func room_dir(index: int) -> Vector2i:
	return GameConst.dir_vector(posmod(index + 3, 4))


## Комната добычи: квадрат room_size на расстоянии room_gap от наибольшей центральной части.
func room_rect(index: int) -> Rect2i:
	var center := Vector2i(size / 2, size / 2)
	var dir := room_dir(index)
	var away := center_max / 2 + room_gap + room_size / 2
	var room_center := center + dir * away
	return Rect2i(room_center - Vector2i.ONE * (room_size / 2), Vector2i.ONE * room_size)


## Туннель от комнаты к центру: идёт до самого центра, поэтому достаёт до центральной части
## любого размера (лишнее просто накрывается ею при расширении).
func tunnel_rect(index: int) -> Rect2i:
	var center := Vector2i(size / 2, size / 2)
	var room := room_rect(index)
	var dir := room_dir(index)
	var half := tunnel_width / 2
	if dir.x != 0:
		var x_from: int = mini(center.x, room.position.x if dir.x > 0 else room.end.x - 1)
		var x_to: int = maxi(center.x, room.position.x if dir.x > 0 else room.end.x - 1)
		return Rect2i(x_from, center.y - half, x_to - x_from + 1, tunnel_width)
	var y_from: int = mini(center.y, room.position.y if dir.y > 0 else room.end.y - 1)
	var y_to: int = maxi(center.y, room.position.y if dir.y > 0 else room.end.y - 1)
	return Rect2i(center.x - half, y_from, tunnel_width, y_to - y_from + 1)


## Платформа в центре комнаты: её содержимое и есть то, что уезжает на планету.
func platform_rect(index: int) -> Rect2i:
	var room := room_rect(index)
	var corner := room.position + (Vector2i.ONE * room_size - Vector2i.ONE * platform_size) / 2
	return Rect2i(corner, Vector2i.ONE * platform_size)


## Якорь платформы 2×2 — в её середине: он уезжает вместе со всем, что вокруг.
func core_origin(index: int) -> Vector2i:
	var plat := platform_rect(index)
	return plat.position + plat.size / 2 - Vector2i.ONE


## Пульт 2×2 — в комнате вплотную к платформе со стороны туннеля: ленты из туннеля идут прямо к нему.
func console_origin(index: int) -> Vector2i:
	var plat := platform_rect(index)
	var inward := -room_dir(index)
	var middle := plat.position + plat.size / 2
	if inward.x != 0:
		return Vector2i(plat.end.x if inward.x > 0 else plat.position.x - 2, middle.y - 1)
	return Vector2i(middle.x - 1, plat.end.y if inward.y > 0 else plat.position.y - 2)
