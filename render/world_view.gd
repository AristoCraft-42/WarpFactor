class_name WorldView
extends Node2D
## Все представления одного мира: террейн, сетка, граница карты, здания, предметы, оверлеи, площадка,
## точки появления, враги и бой (полоски прочности, вспышки атак, груз дрона).
## В забеге два вида (планета и база). Неактивный вид скрыт и не обрабатывается, но симуляция
## его мира идёт; изменения зданий копятся грязными чанками и дорисовываются при переключении.

var world: GameWorld
var terrain: TerrainView
var grid_overlay: GridOverlay
var building_layer: BuildingLayer
var item_renderer: ItemRenderer
var ore_overlay: OreOverlay
var belt_overlay: BeltLoadOverlay
var pad_overlay: PadOverlay
var spawn_markers: SpawnMarkers
var enemy_renderer: EnemyRenderer
var combat_overlay: CombatOverlay
var turret_view: TurretView


func setup(p_world: GameWorld, camera: CameraController, clock: SimClock) -> void:
	world = p_world

	terrain = TerrainView.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.setup(world.grid)

	grid_overlay = GridOverlay.new()
	grid_overlay.name = "Grid"
	add_child(grid_overlay)
	grid_overlay.setup(world.grid)

	var border := MapBorder.new()
	border.name = "MapBorder"
	add_child(border)
	border.setup(world.grid)

	building_layer = BuildingLayer.new()
	building_layer.name = "Buildings"
	add_child(building_layer)
	building_layer.setup(world)

	item_renderer = ItemRenderer.new()
	item_renderer.name = "Items"
	add_child(item_renderer)
	item_renderer.setup(world, camera, clock)

	pad_overlay = PadOverlay.new()
	pad_overlay.name = "Pad"
	add_child(pad_overlay)
	pad_overlay.setup(world)

	spawn_markers = SpawnMarkers.new()
	spawn_markers.name = "SpawnMarkers"
	add_child(spawn_markers)
	spawn_markers.setup(world)

	enemy_renderer = EnemyRenderer.new()
	enemy_renderer.name = "Enemies"
	add_child(enemy_renderer)
	enemy_renderer.setup(world, camera, clock)

	turret_view = TurretView.new()
	turret_view.name = "Turrets"
	add_child(turret_view)
	turret_view.setup(world, camera)

	combat_overlay = CombatOverlay.new()
	combat_overlay.name = "Combat"
	add_child(combat_overlay)
	combat_overlay.setup(world, camera, clock)

	ore_overlay = OreOverlay.new()
	ore_overlay.name = "OreOverlay"
	add_child(ore_overlay)
	ore_overlay.setup(world.grid)

	belt_overlay = BeltLoadOverlay.new()
	belt_overlay.name = "BeltLoadOverlay"
	add_child(belt_overlay)
	belt_overlay.setup(world, camera)


## Активный вид виден и обрабатывается; неактивный — скрыт и заморожен.
func set_active(active: bool) -> void:
	visible = active
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
