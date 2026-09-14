class_name TurretDef
extends BuildingDef
## Параметры турели: дальность, скорострельность, поворот ствола, запас и виды патронов.
## artillery — снаряд летит в точку (с упреждением) и взрывается там, не задевая врагов по пути.

@export_group("Турель")
## Дальность, тайлов (от центра турели до края тела врага).
@export var shoot_range: float = 8.5
## Ближе этого турель не стреляет (артиллерия), тайлов.
@export var min_range: float = 0.0
@export var reload_seconds: float = 0.3
## Скорость поворота ствола, градусов в секунду.
@export var rotate_speed: float = 540.0
## Стреляет, когда ствол смотрит на цель с этой точностью, градусов.
@export var shoot_cone: float = 12.0
## Разброс выстрела, градусов.
@export var inaccuracy: float = 3.0
## Запас патронов, выстрелов.
@export var max_ammo: int = 40
@export var artillery: bool = false
## Длина ствола на рисунке, пикселей (от центра турели до дула).
@export var barrel_length: float = 13.0
@export var ammo: Array[TurretAmmo] = []


func get_range_px() -> float:
	return shoot_range * GameConst.TILE_SIZE


func get_min_range_px() -> float:
	return min_range * GameConst.TILE_SIZE


func get_reload_ticks(ammo_type: TurretAmmo) -> int:
	var multiplier := ammo_type.reload_multiplier if ammo_type != null else 1.0
	return maxi(1, roundi(reload_seconds * multiplier * GameConst.TICK_RATE))


func get_rotate_per_tick() -> float:
	return deg_to_rad(rotate_speed) / GameConst.TICK_RATE


## Индекс вида патронов для предмета (-1 — не патрон).
func find_ammo(item: int) -> int:
	for i in ammo.size():
		if ammo[i] != null and ammo[i].item != null and ammo[i].item.index == item:
			return i
	return -1


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	lines.append(tr("STAT_TURRET_RANGE") % shoot_range if min_range <= 0.0 else tr("STAT_TURRET_RANGE_MIN") % [min_range, shoot_range])
	lines.append(tr("STAT_TURRET_RELOAD") % reload_seconds)
	var parts := PackedStringArray()
	for a in ammo:
		if a == null or a.item == null:
			continue
		var text := "%s %d" % [tr(a.item.name_key), roundi(a.damage)]
		if a.splash_radius > 0.0:
			text += " (%s)" % (tr("STAT_TURRET_SPLASH") % a.splash_radius)
		parts.append(text)
	lines.append(tr("STAT_TURRET_AMMO") % ", ".join(parts))
	return lines
