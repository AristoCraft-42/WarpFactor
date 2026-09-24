class_name Player
extends RefCounted
## Игрок забега: свой дрон с инвентарём и очередью крафта. Планета, подземный этаж, постройки,
## исследования и улучшения дрона — общие на всех. Игроки могут находиться на разных этажах.
##
## id стабилен внутри забега и не переиспользуется: по нему сортируются команды в тике,
## поэтому порядок применения одинаков у всех участников сетевой игры.

## Цвета игроков по порядку (дальше — по кругу).
static var COLORS := PackedColorArray([
	Color(0.98, 0.74, 0.18), Color(0.51, 0.65, 0.60), Color(0.84, 0.53, 0.60),
	Color(0.72, 0.73, 0.15), Color(0.98, 0.29, 0.20), Color(0.55, 0.69, 0.84),
])

var id: int = 0
var name: String = ""
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
	player.color = color_for(p_id)
	player.drone = p_drone
	p_drone.player_id = p_id
	return player


static func color_for(p_id: int) -> Color:
	return COLORS[posmod(p_id - 1, COLORS.size())]


## floor_of: 0 — планета, 1 — подземный этаж, 2 — этаж добычи.
func save_data(floor_of: int) -> Dictionary:
	return {"id": id, "name": name, "in_base": floor_of == 1, "floor": floor_of,
		"drone": drone.save_data()}
