class_name SoundLog
extends RefCounted
## Звуковые события мира: кольцевой буфер «что прозвучало и где», из которого режиссёр звука
## (AudioDirector) каждый кадр забирает новое. Симуляция только пишет сюда и ничего не читает —
## как лучи и вспышки в ProjectileSystem, это чистая картинка (точнее, звук): в сохранение и
## в сверку сетевой игры буфер не входит.
##
## Переполнение не страшно: при ускорении времени за кадр может набежать больше CAPACITY событий,
## тогда самые старые просто теряются — звучать им всё равно было бы некуда.

enum Kind {
	SHOT, ## выстрел пулей (турель, дрон)
	SHELL, ## выстрел артиллерии
	EXPLOSION, ## взрыв снаряда
	HIT, ## попадание пули
	ZAP, ## молния тесла-турели
	REPAIR, ## ремонтный луч
	SPRAY, ## жидкостная турель
	ENEMY_DEATH,
	ENEMY_MELEE,
	ENEMY_SHOT,
	MINE, ## дрон добыл предмет
	BUILD, ## игрок поставил здание
	DECONSTRUCT, ## игрок снёс здание
	ROTATE,
	DESTROYED, ## здание разрушено врагами
	DRONE_DOWN,
	DRONE_RESPAWN,
	CRATE, ## подобран груз
}

const CAPACITY := 512

## Сколько событий записано за всё время (номер следующего). Читатель помнит свой номер.
var written: int = 0
var kinds := PackedByteArray()
var xs := PackedFloat32Array()
var ys := PackedFloat32Array()


func _init() -> void:
	kinds.resize(CAPACITY)
	xs.resize(CAPACITY)
	ys.resize(CAPACITY)


func push(kind: Kind, at: Vector2) -> void:
	var slot := written % CAPACITY
	kinds[slot] = kind
	xs[slot] = at.x
	ys[slot] = at.y
	written += 1


## Самый старый номер, который ещё лежит в буфере.
func oldest() -> int:
	return maxi(written - CAPACITY, 0)
