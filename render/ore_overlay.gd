class_name OreOverlay
extends Sprite2D
## Оверлей «карта ресурсов»: руда подсвечена ярким цветом, остальное затемнено.
## Одна текстура на всю карту, строится один раз.


func setup(grid: WorldGrid) -> void:
	centered = false
	scale = Vector2(GameConst.TILE_SIZE, GameConst.TILE_SIZE)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture = ImageTexture.create_from_image(
		MapPreview.build_ore_overlay_image(grid.width, grid.height, grid.floors, grid.ores))
	visible = false
