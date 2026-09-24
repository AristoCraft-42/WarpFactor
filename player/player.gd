class_name Player
extends RefCounted
## Игрок забега: свой дрон с инвентарём и очередью крафта. Планета, подземный этаж, постройки,
## исследования и улучшения дрона — общие на всех. Игроки могут находиться на разных этажах.
##
## id стабилен внутри забега и не переиспользуется: по нему сортируются команды в тике,
## поэтому порядок применения одинаков у всех участников сетевой игры.

## Цвета игроков: первый по номеру игрока, дальше — по кругу. Игрок может выбрать любой
## в окне инвентаря; выбор идёт командой, поэтому одинаков у всех участников.
static var COLORS := PackedColorArray([
	Color(0.98, 0.74, 0.18), Color(0.51, 0.65, 0.60), Color(0.84, 0.53, 0.60),
	Color(0.72, 0.73, 0.15), Color(0.98, 0.29, 0.20), Color(0.55, 0.69, 0.84),
	Color(0.62, 0.84, 0.55), Color(0.80, 0.62, 0.95),
])
## Сколько значков на выбор: кружок, треугольник, квадрат, ромб, крест, звезда.
const ICONS := 6

var id: int = 0
var name: String = ""
## Выбранный цвет (индекс в COLORS) и значок на корпусе дрона.
var color_index: int = 0
var icon: int = 0
var color: Color = Color.WHITE
var drone: Drone
## Номер следующей команды игрока (для устойчивого порядка в тике).
var next_seq: int = 0
## Последний поставленный игроком мост: следующий мост связывается с ним.
## Состояние выводится из команд, поэтому одинаково у всех участников.
var last_bridge: BridgeConveyor


static func create(p_id: int, p_name: String, p_drone: Drone) -> Player:
	var player := Player.new()
	player.id = p_id
	player.name = p_name
	player.color_index = posmod(p_id - 1, COLORS.size())
	player.icon = posmod(p_id - 1, ICONS)
	player.color = COLORS[player.color_index]
	player.drone = p_drone
	p_drone.player_id = p_id
	return player


static func color_for(p_id: int) -> Color:
	return COLORS[posmod(p_id - 1, COLORS.size())]


## Сменить облик: цвет из палитры и значок. Числа приходят командой, поэтому подрезаются здесь.
func set_style(p_color: int, p_icon: int) -> void:
	color_index = posmod(p_color, COLORS.size())
	icon = posmod(p_icon, ICONS)
	color = COLORS[color_index]


## floor_of: 0 — планета, 1 — подземный этаж, 2 — этаж добычи.
func save_data(floor_of: int) -> Dictionary:
	return {"id": id, "name": name, "in_base": floor_of == 1, "floor": floor_of,
		"color": color_index, "icon": icon, "drone": drone.save_data()}
