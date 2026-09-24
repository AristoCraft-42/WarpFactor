class_name CrafterDef
extends BuildingDef
## Параметры завода: рецепты, как выбирается рецепт, вместимость буферов, топливо.
## Электричество — BuildingDef.power_use.

## FIXED — единственный рецепт; AUTO — по пришедшему сырью (печь); SELECT — выбирает игрок (сборщик).
enum RecipeMode { FIXED, AUTO, SELECT }

@export var recipes: Array[Recipe] = []
@export var recipe_mode: RecipeMode = RecipeMode.FIXED
## Базовая вместимость входного буфера на предмет (не меньше двойной потребности) и выходного буфера.
@export var item_capacity: int = 10
## Во сколько раз завод быстрее времени рецепта: улучшенные версии занимают ту же клетку,
## но выдают больше. Топливо и ток они тратят пропорционально (fuel_use, power_use — уже итоговые).
@export var craft_speed: float = 1.0

@export_group("Топливо")
## Мощность сжигания топлива во время работы, кВт (0 — топливо не нужно).
@export var fuel_use: float = 0.0
## Сколько предметов топлива держит.
@export var fuel_capacity: int = 10


func find_recipe_index(id: StringName) -> int:
	for i in recipes.size():
		if recipes[i] != null and recipes[i].id == id:
			return i
	return -1


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for recipe in recipes:
		if recipe == null:
			continue
		lines.append(tr("STAT_RECIPE") % [_stacks_text(_consume_stacks(recipe)), _produce_text(recipe),
			recipe.craft_time / maxf(craft_speed, 0.01)])
	if power_use > 0.0:
		lines.append(tr("STAT_POWER_USE") % roundi(power_use))
	if fuel_use > 0.0:
		lines.append(tr("STAT_FUEL_USE") % roundi(fuel_use))
	return lines


static func _consume_stacks(recipe: Recipe) -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for c in recipe.consumes:
		result.append_array(c.display_stacks())
	return result


static func _produce_text(recipe: Recipe) -> String:
	var parts := PackedStringArray()
	for p in recipe.produces:
		var stacks := p.display_stacks()
		var chances := p.display_chances()
		for i in stacks.size():
			var text := "%d %s" % [stacks[i].amount, TranslationServer.translate(stacks[i].item.name_key)]
			if i < chances.size():
				text += " (%d%%)" % roundi(chances[i] * 100.0)
			parts.append(text)
	return ", ".join(parts)


static func _stacks_text(stacks: Array[ItemStack]) -> String:
	var parts := PackedStringArray()
	for s in stacks:
		parts.append("%d %s" % [s.amount, TranslationServer.translate(s.item.name_key)])
	return ", ".join(parts)
