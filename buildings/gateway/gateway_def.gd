class_name GatewayDef
extends BuildingDef
## Центральный шлюз (на планете) и его пара на подземном этаже.
## Порты — тайлы сторон inbound_side (в базу) и outbound_side (наружу): сначала открыт средний, исследования
## «Порты шлюза» открывают крайние (до трёх на сторону). Пара зеркальна: предмет, вошедший в шлюз с западной
## стороны, выходит из западной стороны пары; вошедший в пару с восточной — выходит из шлюза на восток.

## Здание стоит в базе (пара), а не на планете.
@export var in_base: bool = false
@export var inbound_side: int = GameConst.Dir.LEFT
@export var outbound_side: int = GameConst.Dir.RIGHT
## Сколько предметов ждёт перехода в каждую сторону.
@export var buffer_capacity: int = 10

## Сколько портов бывает у шлюза: пара в начале и четыре после второй ступени исследования.
## Число всегда чётное — иначе порты не встают симметрично на сторону.
const START_PORTS := 2
const MAX_PORTS := 4


## Сколько портов открыто на steps ступенях исследования «Порты шлюза».
static func ports_for(steps: int) -> int:
	return MAX_PORTS if steps >= 2 else START_PORTS
## Сторона шлюза в начале забега и после «Портов шлюза II» (size в данных — наибольший из них).
@export var start_size: int = 2
@export var grown_size: int = 4
## Скорость портов — как у этой ленты.
@export var throughput_of: ConveyorDef


func get_ticks_per_item() -> int:
	return throughput_of.get_ticks_per_item() if throughput_of != null else 1


## Тайл снаружи середины стороны side для здания размером gate_size с левым верхним тайлом origin.
func get_port_tile(origin: Vector2i, gate_size: int, side: int) -> Vector2i:
	var tiles := get_port_tiles(origin, gate_size, side, 1)
	return tiles[0] if not tiles.is_empty() else origin


## Тайлы снаружи стороны side в порядке «от середины к краям», первые count штук.
## При чётном размере середин две — сначала они, потом по краям.
func get_port_tiles(origin: Vector2i, gate_size: int, side: int, count: int) -> Array[Vector2i]:
	var dir := GameConst.dir_vector(side)
	var outside := origin
	if dir.x > 0:
		outside = origin + Vector2i(gate_size, 0)
	elif dir.x < 0:
		outside = origin + Vector2i(-1, 0)
	elif dir.y > 0:
		outside = origin + Vector2i(0, gate_size)
	else:
		outside = origin + Vector2i(0, -1)
	var step := Vector2i(0, 1) if dir.x != 0 else Vector2i(1, 0)
	var all: Array[Vector2i] = []
	for i in gate_size:
		all.append(outside + step * i)
	var result: Array[Vector2i] = []
	var lo := (gate_size - 1) / 2
	var hi := lo + 1 if gate_size % 2 == 0 else lo
	result.append(all[lo])
	if hi != lo:
		result.append(all[hi])
	while result.size() < gate_size:
		lo -= 1
		hi += 1
		if lo >= 0:
			result.append(all[lo])
		if hi < gate_size and result.size() < gate_size:
			result.append(all[hi])
	return result.slice(0, clampi(count, 0, result.size()))


func get_stat_lines() -> PackedStringArray:
	return PackedStringArray([tr("STAT_THROUGHPUT") % (float(GameConst.TICK_RATE) / get_ticks_per_item())])
