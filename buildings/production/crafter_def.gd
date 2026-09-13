class_name CrafterDef
extends BuildingDef
## Параметры завода: рецепт и вместимость буферов.

@export var recipe: Recipe
## Базовая вместимость входного буфера на предмет (не меньше двойной потребности) и выходного буфера.
@export var item_capacity: int = 10


func get_stat_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	if recipe == null:
		return lines
	lines.append(tr("STAT_RECIPE_IN") % _stacks_text(_consume_stacks()))
	lines.append(tr("STAT_RECIPE_OUT") % _produce_text())
	lines.append(tr("STAT_RECIPE_TIME") % recipe.craft_time)
	return lines


func _consume_stacks() -> Array[ItemStack]:
	var result: Array[ItemStack] = []
	for c in recipe.consumes:
		result.append_array(c.display_stacks())
	return result


func _produce_text() -> String:
	var parts := PackedStringArray()
	for p in recipe.produces:
		var stacks := p.display_stacks()
		var chances := p.display_chances()
		for i in stacks.size():
			var text := "%d %s" % [stacks[i].amount, tr(stacks[i].item.name_key)]
			if i < chances.size():
				text += " (%d%%)" % roundi(chances[i] * 100.0)
			parts.append(text)
	return ", ".join(parts)


static func _stacks_text(stacks: Array[ItemStack]) -> String:
	var parts := PackedStringArray()
	for s in stacks:
		parts.append("%d %s" % [s.amount, TranslationServer.translate(s.item.name_key)])
	return ", ".join(parts)
