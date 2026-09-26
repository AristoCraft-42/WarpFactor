class_name TurretDef
extends BuildingDef
## Параметры турели: дальность, скорострельность, поворот ствола, запас и виды патронов.
## artillery — снаряд летит в точку (с упреждением) и взрывается там, не задевая врагов по пути.
##
## Вид турели (kind) решает, чем она бьёт:
##   BULLET — патронами (пулемёт, артиллерия): нужен запас предметов;
##   CHAIN  — молнией по цепи целей: нужен ток, патроны не нужны;
##   REPAIR — чинит постройки и дронов в радиусе, тоже от тока;
##   SPRAY  — поливает область жидкостью из труб: вода замедляет, пар жжёт.

enum Kind { BULLET, CHAIN, REPAIR, SPRAY }

@export var kind: Kind = Kind.BULLET

@export_group("Молния и ремонт")
## Урон молнии по первой цели и сколько целей она задевает по цепи.
@export var chain_damage: float = 14.0
@export var chain_targets: int = 4
## Каждая следующая цель получает эту долю прошлого урона.
@export var chain_falloff: float = 0.7
## Дальность перескока молнии, тайлов.
@export var chain_jump: float = 3.5
## Сколько прочности возвращает ремонтная турель за раз.
@export var repair_amount: float = 40.0

@export_group("Полив")
## Сколько жидкости уходит на выстрел и радиус лужи, тайлов.
@export var spray_use: float = 20.0
@export var spray_radius: float = 2.5
## Вода: во сколько раз замедляет и на сколько секунд.
@export var slow_factor: float = 0.45
@export var slow_seconds: float = 3.0
## Пар: урон в секунду и длительность горения.
@export var steam_dps: float = 12.0
@export var steam_seconds: float = 3.0

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
## Прибавка урона за каждую ступень исследования «Урон турелей» (0.1 — +10 %): пули, снаряды,
## горение, молния и пар. Ремонтной турели не нужна.
@export var damage_per_upgrade: float = 0.0


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
	match kind:
		Kind.CHAIN:
			lines.append(tr("STAT_TURRET_CHAIN") % [roundi(chain_damage), chain_targets])
			if power_use > 0.0:
				lines.append(tr("STAT_POWER_USE") % roundi(power_use))
			return lines
		Kind.REPAIR:
			lines.append(tr("STAT_TURRET_REPAIR") % roundi(repair_amount))
			if power_use > 0.0:
				lines.append(tr("STAT_POWER_USE") % roundi(power_use))
			return lines
		Kind.SPRAY:
			lines.append(tr("STAT_TURRET_SPRAY") % [spray_radius, slow_seconds, roundi(steam_dps)])
			return lines
		_:
			pass
	var parts := PackedStringArray()
	for a in ammo:
		if a == null or a.item == null:
			continue
		var text := "%s %d" % [tr(a.item.name_key), roundi(a.damage)]
		if a.splash_radius > 0.0:
			text += " (%s)" % (tr("STAT_TURRET_SPLASH") % a.splash_radius)
		if a.burn_dps > 0.0:
			text += " (%s)" % (tr("STAT_TURRET_BURN") % [a.burn_dps, a.burn_seconds])
		if a.reload_multiplier < 1.0:
			text += " (%s)" % (tr("STAT_TURRET_FAST") % roundi((1.0 / a.reload_multiplier - 1.0) * 100.0))
		parts.append(text)
	lines.append(tr("STAT_TURRET_AMMO") % ", ".join(parts))
	return lines
