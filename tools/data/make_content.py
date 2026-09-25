"""Генерирует весь контент ранней игры WarpFactor (этап Д): жидкости, предметы, месторождения, рецепты,
постройки и предметы-постройки, исследования, стартовые наборы забега и тестовых уровней.
Старые файлы данных в этих папках удаляются."""
import glob
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def color(h):
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    return f"Color({r:.3f}, {g:.3f}, {b:.3f}, 1)"


def fmt(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, float):
        return repr(v)
    return str(v)


def write(path, lines):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def clear(pattern):
    for p in glob.glob(os.path.join(ROOT, pattern)):
        os.remove(p)


# --- Жидкости ---
FLUIDS = [("water", "FLUID_WATER", "3c78d8", 10), ("steam", "FLUID_STEAM", "d8dde3", 20)]

# --- Предметы: id, форма иконки, цвет, порядок, стак, топливо (кДж), уровень набора ---
# Формы: CIRCLE 0, SQUARE 1, DIAMOND 2, TRIANGLE 3, HEXAGON 4, CROSS 5, RING 6, BAR 7, STAR 8, FRAME 9, INGOT 10
ITEMS = [
    ("hematite", 2, "7a3f3a", 10, 50, 0.0, 0),
    ("stone", 4, "8b8a84", 20, 50, 0.0, 0),
    ("coal", 1, "2e2b2a", 30, 50, 4000.0, 0),
    ("malachite", 2, "2f8f5b", 40, 50, 0.0, 0),
    ("sphalerite", 2, "6b5f7a", 50, 50, 0.0, 0),
    ("iron_ingot", 10, "a3adb5", 100, 100, 0.0, 0),
    ("brick", 7, "a4553a", 110, 100, 0.0, 0),
    ("copper_ingot", 10, "d7843f", 120, 100, 0.0, 0),
    ("gear", 8, "8d969d", 200, 100, 0.0, 0),
    ("copper_cable", 6, "e0914c", 210, 200, 0.0, 0),
    ("zinc_plate", 10, "9aa7b5", 130, 100, 0.0, 0),
    ("galvanized_steel", 7, "b5c0cc", 220, 100, 0.0, 0),
    ("microchip", 9, "5f9e7a", 230, 100, 0.0, 0),
    ("science_kit", 9, "d9534f", 300, 100, 0.0, 1),
    ("science_kit_2", 9, "5f7fd9", 301, 100, 0.0, 2),
    ("resistor", 7, "c8b27a", 310, 100, 0.0, 0),
    ("casing_mg", 3, "c9a227", 400, 100, 0.0, 0),
    ("cartridge_stone", 3, "9a998f", 410, 200, 0.0, 0),
    ("cartridge_iron", 3, "b8c2ca", 411, 200, 0.0, 0),
    ("cartridge_coal", 3, "e3632f", 412, 200, 0.0, 0),
    ("cartridge_copper", 3, "e7a15a", 413, 200, 0.0, 0),
    ("cartridge_brick", 3, "c0654a", 414, 200, 0.0, 0),
]

# --- Месторождения: id, предмет или жидкость, твёрдость, порядок ---
ORES = [
    ("hematite", ("item", "hematite"), 1, 10),
    ("stone", ("item", "stone"), 1, 20),
    ("coal", ("item", "coal"), 1, 30),
    ("malachite", ("item", "malachite"), 2, 40),
    ("sphalerite", ("item", "sphalerite"), 2, 45),
    ("water", ("fluid", "water"), 0, 50),
]

# --- Рецепты: id, входы, выходы, время, вручную ли, порядок ---
FILLERS = [("stone", "cartridge_stone"), ("iron_ingot", "cartridge_iron"), ("coal", "cartridge_coal"),
           ("copper_ingot", "cartridge_copper"), ("brick", "cartridge_brick")]
RECIPES = [
    ("smelt_iron", [("hematite", 1)], [("iron_ingot", 1)], 3.2, False, 10),
    ("smelt_brick", [("stone", 2)], [("brick", 1)], 3.2, False, 20),
    ("smelt_copper", [("malachite", 1)], [("copper_ingot", 1)], 3.2, False, 30),
    ("gear", [("iron_ingot", 2)], [("gear", 1)], 0.5, True, 100),
    ("copper_cable", [("copper_ingot", 1)], [("copper_cable", 2)], 0.5, True, 110),
    ("science_kit", [("iron_ingot", 1), ("gear", 1)], [("science_kit", 1)], 5.0, True, 120),
    ("resistor", [("iron_ingot", 1), ("copper_cable", 3)], [("resistor", 1)], 2.0, True, 130),
    ("smelt_zinc", [("sphalerite", 1)], [("zinc_plate", 1)], 3.2, False, 40),
    ("galvanized_steel", [("iron_ingot", 2), ("zinc_plate", 1)], [("galvanized_steel", 1)], 1.5, False, 140),
    ("microchip", [("galvanized_steel", 1), ("copper_cable", 4), ("resistor", 2)], [("microchip", 1)], 3.0, False, 150),
    ("science_kit_2", [("microchip", 1), ("galvanized_steel", 2)], [("science_kit_2", 1)], 6.0, False, 160),
    ("casing_mg", [("copper_ingot", 1)], [("casing_mg", 2)], 1.0, True, 200),
] + [(out, [("casing_mg", 1), (filler, 1)], [(out, 4)], 2.0, True, 210 + i) for i, (filler, out) in enumerate(FILLERS)]
RECIPE_IDS = {r[0] for r in RECIPES}

DEF_SCRIPTS = {
    "base": ("BuildingDef", "res://buildings/building_def.gd"),
    "conveyor": ("ConveyorDef", "res://buildings/transport/conveyor_def.gd"),
    "drill": ("DrillDef", "res://buildings/production/drill_def.gd"),
    "storage": ("StorageDef", "res://buildings/storage/storage_def.gd"),
    "logistic": ("LogisticDef", "res://buildings/transport/logistic_def.gd"),
    "crafter": ("CrafterDef", "res://buildings/production/crafter_def.gd"),
    "gateway": ("GatewayDef", "res://buildings/gateway/gateway_def.gd"),
    "turret": ("TurretDef", "res://buildings/defense/turret_def.gd"),
    "pole": ("PowerPoleDef", "res://buildings/power/power_pole_def.gd"),
    "generator": ("GeneratorDef", "res://buildings/power/generator_def.gd"),
    "fluid": ("FluidBuildingDef", "res://buildings/fluid/fluid_building_def.gd"),
    "workshop": ("ScienceWorkshopDef", "res://buildings/production/science_workshop_def.gd"),
    "accumulator": ("AccumulatorDef", "res://buildings/power/accumulator_def.gd"),
    "lift": ("LiftDef", "res://buildings/gateway/lift_def.gd"),
    "platform": ("PlatformDef", "res://buildings/gateway/platform_def.gd"),
    "creative": ("CreativeBlockDef", "res://buildings/creative/creative_block_def.gd"),
}
LOGIC = {
    "conveyor": "res://buildings/transport/conveyor.gd",
    "drill": "res://buildings/production/drill.gd",
    "storage": "res://buildings/storage/storage_building.gd",
    "junction": "res://buildings/transport/junction.gd",
    "router": "res://buildings/transport/router.gd",
    "sorter": "res://buildings/transport/sorter.gd",
    "bridge": "res://buildings/transport/bridge_conveyor.gd",
    "unloader": "res://buildings/transport/unloader.gd",
    "crafter": "res://buildings/production/crafter.gd",
    "gateway": "res://buildings/gateway/gateway.gd",
    "turret": "res://buildings/defense/turret.gd",
    "pole": "res://buildings/power/power_pole.gd",
    "generator": "res://buildings/power/generator.gd",
    "pipe": "res://buildings/fluid/pipe.gd",
    "underground_pipe": "res://buildings/fluid/underground_pipe.gd",
    "pump": "res://buildings/fluid/pump.gd",
    "boiler": "res://buildings/fluid/boiler.gd",
    "workshop": "res://buildings/production/science_workshop.gd",
    "accumulator": "res://buildings/power/accumulator.gd",
    "lift": "res://buildings/gateway/lift.gd",
    "shaft": "res://buildings/gateway/shaft.gd",
    "platform_console": "res://buildings/gateway/platform_console.gd",
    "platform_core": "res://buildings/gateway/platform_core.gd",
    "creative": "res://buildings/creative/creative_block.gd",
}

# Категории: TRANSPORT 0, PRODUCTION 1, POWER 2, DEFENSE 3.
# Глифы: CHEVRONS 1, CROSS 2, ROUTER 3, FILTER 4, BRIDGE 6, UNLOAD 7, DRILL 8, GEAR 9, FLAME 11, BOX 14, CORE 15,
# WALL 16, TURRET 17, PIPE 19, PUMP 20, BOILER 21, TURBINE 22, POLE 23, FLASK 24, GENERATOR 25, UNDERGROUND_PIPE 26,
# BATTERY 27, LIFT 28, TANK 29, SOURCE 30, SINK 31.
# Патроны пулемёта: предмет, выстрелов, урон, взрыв (тайлы), скорость (тайл/с), множитель паузы, цвет, горение/с, горение с.
MG_AMMO = [
    ("cartridge_stone", 4, 7.0, 0.0, 14.0, 1.0, "b5b3a8", 0.0, 0.0),
    ("cartridge_iron", 4, 14.0, 0.0, 14.0, 1.0, "c8d0d8", 0.0, 0.0),
    ("cartridge_coal", 4, 6.0, 0.0, 14.0, 1.0, "fe8019", 3.0, 3.0),
    ("cartridge_copper", 4, 9.0, 0.0, 16.0, 0.77, "e7a15a", 0.0, 0.0),
    ("cartridge_brick", 4, 8.0, 0.8, 14.0, 1.0, "d06a4a", 0.0, 0.0),
]

# id, вид, логика, категория, размер, линией, сносится, строится, глиф, цвет, порядок, стоимость, параметры,
# (прочность, твёрдая), (время крафта, партия, стак)
BUILDINGS = [
    # Транспорт
    ("conveyor", "conveyor", "conveyor", 0, 1, True, True, True, 1, "4f4a45", 10, [("iron_ingot", 1), ("gear", 1)],
     {"tiles_per_second": 2.4}, (45, False), (0.5, 2, 100)),
    ("junction", "logistic", "junction", 0, 1, False, True, True, 2, "6b5f53", 20, [("conveyor", 2), ("iron_ingot", 2)],
     {"transfer_ticks": 8, "capacity": 6, "throughput": "conveyor"}, (60, False), (0.5, 1, 50)),
    ("router", "logistic", "router", 0, 1, False, True, True, 3, "7a6b4f", 30, [("conveyor", 1), ("gear", 1)],
     {"capacity": 1, "throughput": "conveyor"}, (60, False), (0.5, 1, 50)),
    ("sorter", "logistic", "sorter", 0, 1, False, True, True, 4, "5f7050", 40, [("router", 1), ("resistor", 1)],
     {"throughput": "conveyor"}, (60, False), (0.5, 1, 50)),
    ("bridge_conveyor", "logistic", "bridge", 0, 1, False, True, True, 6, "6a5a4a", 50, [("conveyor", 4), ("iron_ingot", 6)],
     {"transfer_ticks": 6, "capacity": 10, "link_range": 4, "throughput": "conveyor"}, (70, False), (1.0, 2, 50)),
    ("unloader", "logistic", "unloader", 0, 1, False, True, True, 7, "4f7272", 60, [("copper_cable", 4), ("conveyor", 1), ("gear", 2)],
     {"throughput": "conveyor"}, (70, False), (1.0, 1, 50)),
    ("steel_conveyor", "conveyor", "conveyor", 0, 1, True, True, True, 1, "8d99a6", 11,
     [("galvanized_steel", 1), ("gear", 1)], {"tiles_per_second": 4.8}, (70, False), (0.5, 2, 100)),
    ("steel_junction", "logistic", "junction", 0, 1, False, True, True, 2, "9aa6b2", 21,
     [("steel_conveyor", 2), ("galvanized_steel", 2)],
     {"transfer_ticks": 4, "capacity": 8, "throughput": "steel_conveyor"}, (90, False), (0.5, 1, 50)),
    ("steel_router", "logistic", "router", 0, 1, False, True, True, 3, "a6b0ba", 31,
     [("steel_conveyor", 1), ("gear", 2)], {"capacity": 1, "throughput": "steel_conveyor"}, (90, False), (0.5, 1, 50)),
    ("lift", "lift", "lift", 0, 3, False, True, True, 28, "6a6f7a", 80, [("iron_ingot", 30), ("gear", 15), ("resistor", 6)],
     {"buffer_capacity": 10, "throughput": "conveyor"}, (600, True), (5.0, 1, 10)),
    ("container", "storage", "storage", 0, 1, False, True, True, 14, "6a6a5a", 70, [("iron_ingot", 12)],
     {"slots": 16}, (180, True), (1.5, 1, 20)),
    ("large_container", "storage", "storage", 0, 1, False, True, True, 14, "8a8560", 75,
     [("galvanized_steel", 8), ("iron_ingot", 12)], {"slots": 32}, (300, True), (3.0, 1, 20)),
    # Производство
    ("furnace", "crafter", "crafter", 1, 2, False, True, True, 11, "7a5a48", 10, [("stone", 10)],
     {"recipes": ["smelt_iron", "smelt_brick", "smelt_copper", "smelt_zinc"], "recipe_mode": 1, "item_capacity": 10,
      "fuel_use": 90.0, "fuel_capacity": 10}, (200, True), (1.0, 1, 20)),
    ("coal_drill", "drill", "drill", 1, 1, False, True, True, 8, "5f4a38", 15, [("iron_ingot", 6)],
     {"tier": 1, "base_seconds": 6.0, "hardness_seconds": 1.5, "item_capacity": 10,
      "fuel_use": 45.0, "fuel_capacity": 5}, (140, True), (1.5, 1, 20)),
    ("drill", "drill", "drill", 1, 2, False, True, True, 8, "8a6d4e", 20, [("iron_ingot", 8), ("gear", 4)],
     {"tier": 2, "base_seconds": 6.0, "hardness_seconds": 1.5, "item_capacity": 10, "power_use": 90.0}, (180, True), (2.0, 1, 20)),
    ("assembler", "crafter", "crafter", 1, 2, False, True, True, 9, "5e6670", 30, [("resistor", 4), ("gear", 6), ("copper_ingot", 10)],
     {"recipes": ["gear", "copper_cable", "science_kit", "resistor", "casing_mg",
                  "galvanized_steel", "microchip", "science_kit_2"] + [out for _, out in FILLERS],
      "recipe_mode": 2, "item_capacity": 20, "power_use": 75.0}, (220, True), (3.0, 1, 20)),
    ("smeltery", "crafter", "crafter", 1, 2, False, True, True, 11, "a5714f", 11,
     [("brick", 20), ("galvanized_steel", 10), ("gear", 10)],
     {"recipes": ["smelt_iron", "smelt_brick", "smelt_copper", "smelt_zinc"], "recipe_mode": 1, "item_capacity": 20,
      "craft_speed": 2.0, "fuel_use": 270.0, "fuel_capacity": 20}, (320, True), (4.0, 1, 20)),
    ("fast_drill", "drill", "drill", 1, 2, False, True, True, 8, "b0894f", 21,
     [("galvanized_steel", 12), ("gear", 10), ("microchip", 2)],
     {"tier": 2, "base_seconds": 3.0, "hardness_seconds": 0.75, "item_capacity": 20, "power_use": 270.0},
     (260, True), (4.0, 1, 20)),
    ("fabricator", "crafter", "crafter", 1, 2, False, True, True, 9, "7b8796", 31,
     [("microchip", 4), ("gear", 20), ("galvanized_steel", 12)],
     {"recipes": ["gear", "copper_cable", "science_kit", "resistor", "casing_mg",
                  "galvanized_steel", "microchip", "science_kit_2"] + [out for _, out in FILLERS],
      "recipe_mode": 2, "item_capacity": 30, "craft_speed": 2.0, "power_use": 225.0}, (300, True), (5.0, 1, 20)),
    ("science_workshop", "workshop", "workshop", 1, 2, False, True, True, 24, "6a5a7a", 40,
     [("copper_cable", 10), ("iron_ingot", 10), ("resistor", 5)],
     {"seconds_per_kit": 2.0, "kit_capacity": 10, "power_use": 60.0}, (220, True), (3.0, 1, 10)),
    # Энергия
    ("small_power_pole", "pole", "pole", 2, 1, False, True, True, 23, "7a6a55", 10, [("iron_ingot", 2)],
     {"wire_range": 7.5, "supply_size": 5, "max_links": 5, "rotatable": False}, (60, False), (0.5, 2, 50)),
    ("thermal_generator", "generator", "generator", 2, 2, False, True, True, 25, "8a4f3a", 20,
     [("brick", 10), ("iron_ingot", 8), ("gear", 4)],
     {"kind": 0, "max_output": 150.0, "efficiency": 0.5, "fuel_capacity": 10}, (220, True), (2.0, 1, 10)),
    ("pipe", "fluid", "pipe", 2, 1, True, True, True, 19, "5d6a74", 30, [("iron_ingot", 1)],
     {"role": 0, "fluid_capacity": 100.0, "rotatable": False, "allowed_on_fluid": True}, (50, False), (0.25, 2, 100)),
    ("underground_pipe", "fluid", "underground_pipe", 2, 1, True, True, True, 26, "4f5d66", 35, [("pipe", 10), ("iron_ingot", 5)],
     {"role": 3, "fluid_capacity": 100.0, "underground_range": 10, "allowed_on_fluid": True}, (80, False), (1.0, 2, 50)),
    ("water_tank", "fluid", "pipe", 2, 2, False, True, True, 29, "4a6b7a", 36, [("iron_ingot", 12), ("brick", 8)],
     {"role": 0, "fluid_capacity": 4000.0, "rotatable": False, "allowed_on_fluid": True}, (260, True), (3.0, 1, 10)),
    ("pump", "fluid", "pump", 2, 1, False, True, True, 20, "3f6f8f", 40, [("iron_ingot", 5), ("gear", 3), ("pipe", 2)],
     {"role": 1, "pump_per_tile": 120.0, "rotatable": False, "allowed_on_fluid": True}, (100, True), (1.0, 1, 20)),
    ("boiler", "fluid", "boiler", 2, 2, False, True, True, 21, "7a4a3a", 50, [("brick", 12), ("iron_ingot", 6), ("pipe", 4)],
     {"role": 2, "fuel_power": 1000.0, "steam_per_second": 60.0, "fuel_capacity": 10,
      "water_fluid": "water", "steam_fluid": "steam"}, (240, True), (2.0, 1, 10)),
    ("steam_generator", "generator", "generator", 2, 2, False, True, True, 22, "6a7280", 60,
     [("iron_ingot", 12), ("gear", 8), ("copper_cable", 12), ("pipe", 4)],
     {"kind": 1, "max_output": 500.0, "steam_energy": 16.667, "steam_fluid": "steam"}, (260, True), (3.0, 1, 10)),
    ("accumulator", "accumulator", "accumulator", 2, 2, False, True, True, 27, "5d6b4f", 70,
     [("iron_ingot", 10), ("copper_cable", 20), ("resistor", 5)],
     {"capacity_kj": 5000.0, "max_rate": 300.0, "rotatable": False}, (200, True), (3.0, 1, 10)),
    # Оборона
    ("stone_wall", "base", None, 3, 1, True, True, True, 16, "8b8a84", 10, [("brick", 6)],
     {"rotatable": False}, (360, True), (0.5, 1, 100)),
    ("machine_gun", "turret", "turret", 3, 1, False, True, True, 17, "7a6a55", 20, [("iron_ingot", 10), ("gear", 5), ("resistor", 3)],
     {"rotatable": False, "shoot_range": 8.5, "reload_seconds": 0.3, "rotate_speed": 540.0, "shoot_cone": 12.0,
      "inaccuracy": 3.0, "max_ammo": 40, "artillery": False, "barrel_length": 13.0, "ammo": MG_AMMO}, (220, True), (1.5, 1, 20)),
    # Тесла-турель: молния прыгает по цепи врагов, патронов не просит, но ест ток.
    ("tesla_turret", "turret", "turret", 3, 2, False, True, True, 32, "83a598", 30,
     [("galvanized_steel", 15), ("copper_cable", 25), ("microchip", 4)],
     {"kind": 1, "rotatable": False, "shoot_range": 7.0, "reload_seconds": 0.8, "rotate_speed": 720.0,
      "shoot_cone": 20.0, "inaccuracy": 0.0, "max_ammo": 0, "barrel_length": 10.0, "power_use": 180.0,
      "chain_damage": 18.0, "chain_targets": 4, "chain_falloff": 0.65, "chain_jump": 3.5}, (320, True), (3.0, 1, 10)),
    # Ремонтная турель: чинит самую побитую постройку рядом, а если все целы — дрона.
    ("repair_turret", "turret", "turret", 3, 2, False, True, True, 33, "8ec07c", 32,
     [("galvanized_steel", 10), ("gear", 10), ("microchip", 2)],
     {"kind": 2, "rotatable": False, "shoot_range": 9.0, "reload_seconds": 1.0, "rotate_speed": 360.0,
      "shoot_cone": 20.0, "inaccuracy": 0.0, "max_ammo": 0, "barrel_length": 9.0, "power_use": 120.0,
      "repair_amount": 60.0}, (300, True), (3.0, 1, 10)),
    # Жидкостная турель: поливает область из труб. Вода замедляет, пар жжёт.
    ("fluid_turret", "turret", "turret", 3, 2, False, True, True, 34, "458588", 34,
     [("iron_ingot", 20), ("gear", 8), ("pipe", 6), ("galvanized_steel", 6)],
     {"kind": 3, "rotatable": False, "shoot_range": 8.0, "reload_seconds": 1.2, "rotate_speed": 400.0,
      "shoot_cone": 20.0, "inaccuracy": 0.0, "max_ammo": 0, "barrel_length": 12.0,
      "spray_use": 60.0, "spray_radius": 2.5, "slow_factor": 0.45, "slow_seconds": 4.0,
      "steam_dps": 14.0, "steam_seconds": 4.0}, (300, True), (3.0, 1, 10)),
    # Творческий режим
    ("creative_item_source", "creative", "creative", 0, 1, False, True, True, 30, "b16286", 900, [],
     {"kind": 0, "rates": [1.0, 2.0, 5.0, 10.0, 20.0, 50.0, 100.0, 200.0], "default_rate": 3, "rotatable": False,
      "creative_only": True}, (400, True), (0.5, 1, 20)),
    ("creative_power_source", "creative", "creative", 2, 1, False, True, True, 30, "d79921", 900, [],
     {"kind": 1, "rates": [100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0, 25000.0], "default_rate": 2,
      "rotatable": False, "creative_only": True}, (400, True), (0.5, 1, 20)),
    ("creative_fluid_source", "creative", "creative", 2, 1, False, True, True, 30, "458588", 901, [],
     {"kind": 2, "rates": [30.0, 60.0, 120.0, 300.0, 600.0, 1200.0, 3000.0, 6000.0], "default_rate": 2,
      "rotatable": False, "creative_only": True}, (400, True), (0.5, 1, 20)),
    ("creative_void", "creative", "creative", 0, 1, False, True, True, 31, "504945", 901, [],
     {"kind": 3, "rates": [100.0, 250.0, 500.0, 1000.0, 2500.0, 5000.0, 10000.0, 25000.0], "default_rate": 2,
      "rotatable": False, "creative_only": True, "power_use": 1.0}, (400, True), (0.5, 1, 20)),
    ("shaft", "lift", "shaft", 0, 4, False, False, False, 28, "7a7f8a", 4, [],
     {"buffer_capacity": 20, "throughput": "conveyor"}, (2000, True), None),
    ("boiler_shaft", "lift", "shaft", 0, 4, False, False, False, 28, "8a7a6a", 5, [],
     {"buffer_capacity": 20, "throughput": "conveyor", "energy_link": True}, (2000, True), None),
    # Платформа добычи: пульт в комнате и якорь на платформе (ставятся сами вместе с комнатой)
    ("platform_console", "platform", "platform_console", 0, 2, False, False, False, 28, "4f7a6a", 2, [],
     {"buffer_capacity": 20, "throughput": "conveyor", "deploy_seconds": 6.0, "is_core": False,
      "rotatable": False}, (1200, True), None),
    ("platform_core", "platform", "platform_core", 0, 2, False, False, False, 15, "9a6a3a", 3, [],
     {"buffer_capacity": 20, "throughput": "conveyor", "deploy_seconds": 6.0, "is_core": True,
      "rotatable": False}, (1500, True), None),
    # Шлюзы (не строятся)
    ("central_gateway", "gateway", "gateway", 0, 4, False, False, False, 15, "b0601c", 0, [],
     {"in_base": False, "inbound_side": 2, "outbound_side": 0, "buffer_capacity": 10, "throughput": "conveyor",
      "start_size": 2, "grown_size": 4}, (1800, True), None),
    ("base_gateway", "gateway", "gateway", 0, 4, False, False, False, 15, "5f7f9a", 1, [],
     {"in_base": True, "inbound_side": 2, "outbound_side": 0, "buffer_capacity": 10, "throughput": "conveyor",
      "start_size": 2, "grown_size": 4}, (3000, True), None),
]
BUILDING_IDS = {b[0] for b in BUILDINGS}

# --- Автосборка: сборщик делает сами постройки ---
# Рецепт повторяет ручной крафт: те же входы, тот же выход и то же время. Открывается одним
# исследованием «Автосборка» — до него сборщик делает только компоненты.
AUTOBUILD_MAKERS = ("assembler", "fabricator")
BUILD_RECIPES = []
for _b in BUILDINGS:
    _bid, _kind, _cost, _order, _craft = _b[0], _b[1], _b[11], _b[10], _b[14]
    # Сборщик не делает сам себя: его описание ссылалось бы на рецепт, рецепт — на предмет,
    # а предмет — обратно на описание, и Godot не смог бы загрузить такой круг.
    if not _b[7] or not _cost or _craft is None or _kind == "creative" or _bid in AUTOBUILD_MAKERS:
        continue
    BUILD_RECIPES.append(("build_%s" % _bid, list(_cost), [(_bid, _craft[1])], float(_craft[0]), False, 300 + _order))
BUILD_RECIPE_IDS = [r[0] for r in BUILD_RECIPES]
RECIPES += BUILD_RECIPES
RECIPE_IDS = {r[0] for r in RECIPES}
for _b in BUILDINGS:
    if _b[0] in AUTOBUILD_MAKERS:
        _b[12]["recipes"] = _b[12]["recipes"] + BUILD_RECIPE_IDS

# id, порядок, стоимость (наборов), предшествующие, постройки, рецепты, эффекты
# Эффекты: underground — подземный этаж; underground_size, pad_size — шаг расширения этажа и площадки;
# gateway_items, gateway_ports, gateway_power, gateway_fluids — что передаёт шлюз (и лифты);
# drone_speed, drone_mining, drone_health, drone_gun, drone_repair — ступени улучшения дрона
# (шаг каждой ступени — в player/drone.tres).
# Ветка дрона: «Скорость дрона I» — корень, от неё расходятся остальные цепочки.
DRONE_CHAINS = [("drone_speed", "drone_speed"), ("drone_mining", "drone_mining"),
                ("drone_health", "drone_health"), ("drone_gun", "drone_gun"), ("drone_repair", "drone_repair")]
DRONE_RESEARCH = []
for _n, (_chain, _effect) in enumerate(DRONE_CHAINS):
    for _level in (1, 2, 3):
        _id = "%s_%d" % (_chain, _level)
        if _level > 1:
            _pre = ["%s_%d" % (_chain, _level - 1)]
        elif _chain == "drone_speed":
            _pre = []
        else:
            _pre = ["drone_speed_1"]
        DRONE_RESEARCH.append((_id, 200 + _n * 10 + _level, 10 * _level, _pre, [], [], [_effect]))

RESEARCH = [
    # Энергия
    ("electricity", 10, 10, [], ["thermal_generator", "small_power_pole"], [], []),
    ("fluid_handling", 20, 15, ["electricity"], ["pipe", "underground_pipe", "pump"], [], []),
    ("steam_power", 30, 25, ["fluid_handling"], ["boiler", "steam_generator"], [], []),
    ("accumulators", 40, 20, ["steam_power"], ["accumulator"], [], []),
    # Добыча и производство
    ("mining", 50, 15, ["electricity"], ["drill"], [], []),
    ("logistics", 60, 20, ["mining"], ["sorter", "unloader", "bridge_conveyor"], [], []),
    ("industry", 70, 30, ["mining"], ["assembler"], [], []),
    ("science_automation", 80, 35, ["industry"], ["science_workshop"], [], []),
    ("autobuild", 85, 40, ["industry"], [], BUILD_RECIPE_IDS, []),
    ("sphalerite", 86, 35, ["industry"], [], ["smelt_zinc", "galvanized_steel"], []),
    ("microchips", 87, 40, ["sphalerite", "science_automation"], [], ["microchip", "science_kit_2"], []),
    ("steel_logistics", 88, 45, ["microchips"], ["steel_conveyor", "steel_junction", "steel_router"], [], []),
    ("mining_floor", 169, 50, ["underground_1", "microchips"], [], [], ["mining_floor"]),
    ("boiler_floor", 180, 55, ["mining_floor", "steam_power"], [], [], ["boiler_floor"]),
] + [("boiler_size_%d" % i, 180 + i, 40 + 20 * i,
      ["boiler_size_%d" % (i - 1)] if i > 1 else ["boiler_floor"], [], [], ["boiler_size"])
     for i in range(1, 4)] + [
    ("compact_production", 89, 45, ["microchips"], ["smeltery", "fabricator", "fast_drill", "large_container"], [], []),
    # Оборона
    ("defense", 90, 25, ["electricity"], ["machine_gun"], ["casing_mg"] + [out for _, out in FILLERS], []),
    ("advanced_defense", 91, 45, ["microchips", "defense"],
     ["tesla_turret", "repair_turret", "fluid_turret"], [], []),
    # База: этажи, шлюз, лифты
    ("underground", 110, 15, ["mining"], [], [], ["underground"]),
    ("gateway_items", 120, 10, ["underground"], [], [], ["gateway_items"]),
    ("gateway_ports_1", 121, 20, ["gateway_items"], [], [], ["gateway_ports"]),
    ("gateway_ports_2", 122, 30, ["gateway_ports_1"], [], [], ["gateway_ports"]),
    ("gateway_power", 150, 25, ["underground"], [], [], ["gateway_power"]),
    ("gateway_fluids", 160, 25, ["gateway_power"], [], [], ["gateway_fluids"]),
    ("lift", 140, 30, ["underground_1"], ["lift"], [], []),
    # Полигон: бесконечное исследование для замеров скорости науки, видно только в творческом режиме.
    ("sandbox", 300, 1000000, [], [], [], []),
] + [("pad_%d" % i, 100 + i, 10 + 10 * i, ["pad_%d" % (i - 1)] if i > 1 else ["mining"], [], [], ["pad_size"]) for i in range(1, 6)] \
  + [("science_speed_%d" % i, 81 + i, 20 + 20 * i,
      ["science_speed_%d" % (i - 1)] if i > 1 else ["science_automation"], [], [], ["science_speed"])
     for i in range(1, 5)] \
  + [("gateway_speed_%d" % i, 123 + i, 20 + 20 * i,
      ["gateway_speed_%d" % (i - 1)] if i > 1 else ["gateway_items"], [], [], ["gateway_speed"])
     for i in range(1, 4)] \
  + [("star_scan_%d" % i, 111 + i, 20 + 20 * i,
      ["star_scan_%d" % (i - 1)] if i > 1 else ["pad_1"], [], [], ["star_scan"])
     for i in range(1, 3)]   + [("star_depth_%d" % i, 114 + i, 30 + 30 * i,
      ["star_depth_%d" % (i - 1)] if i > 1 else ["star_scan_2"], [], [], ["star_depth"])
     for i in range(1, 3)] \
  + [("warp_time_%d" % i, 105 + i, 15 + 15 * i, ["warp_time_%d" % (i - 1)] if i > 1 else ["pad_1"], [], [], ["planet_time"])
     for i in range(1, 6)] \
  + [("warp_charge_%d" % i, 108 + i, 15 + 15 * i, ["warp_charge_%d" % (i - 1)] if i > 1 else ["pad_1"], [], [], ["teleport_charge"])
     for i in range(1, 4)] \
  + [("underground_%d" % i, 130 + i, 10 + 10 * i, ["underground_%d" % (i - 1)] if i > 1 else ["underground"], [], [], ["underground_size"])
     for i in range(1, 6)]   + [("mining_room_%d" % i, 170 + i, 40 + 20 * i,
      ["mining_room_%d" % (i - 1)] if i > 1 else ["mining_floor"], [], [], ["mining_room"])
     for i in range(1, 5)] + DRONE_RESEARCH

START_ITEMS = [("conveyor", 20), ("furnace", 2), ("coal", 20)]
LEVELS = [
    ("01_first_steps", "first_steps", "LEVEL_FIRST_STEPS", 1, (48, 32)),
    ("02_rift", "rift", "LEVEL_RIFT", 2, (41, 96)),
]


# Исследования, которым вдобавок нужны наборы второго уровня: всё, что идёт после «Микросхем».
# Раньше них наборы второго уровня негде делать — это и задаёт порядок мидгейма.
KIT2_AFTER = {"steel_logistics", "compact_production", "mining_floor", "accumulators", "lift",
              "advanced_defense", "boiler_floor"}
KIT2_PREFIXES = ("mining_room_", "science_speed_", "gateway_speed_", "star_depth_", "boiler_size_")
KIT2_EXACT = {"warp_time_4", "warp_time_5", "warp_charge_3", "underground_4", "underground_5",
              "pad_4", "pad_5", "drone_speed_3", "drone_mining_3", "drone_health_3",
              "drone_gun_3", "drone_repair_3"}


def kit2_amount(rid, amount):
    """Сколько наборов второго уровня нужно исследованию (0 — не нужны)."""
    if rid in KIT2_AFTER or rid in KIT2_EXACT or rid.startswith(KIT2_PREFIXES):
        return max(5, amount // 2)
    return 0


def item_path(item):
    if item in BUILDING_IDS:
        return f"res://items/types/buildings/{item}.tres"
    return f"res://items/types/{item}.tres"


def write_fluids():
    clear("fluids/defs/*.tres")
    for fid, key, col, order in FLUIDS:
        write(f"fluids/defs/{fid}.tres", ['[gd_resource type="Resource" script_class="FluidDef" format=3]', "",
              '[ext_resource type="Script" path="res://fluids/fluid_def.gd" id="1_def"]', "", "[resource]",
              'script = ExtResource("1_def")', f'id = &"{fid}"', f'name_key = "{key}"', f"color = {color(col)}",
              f"sort_order = {order}", ""])


def write_items():
    clear("items/types/*.tres")
    for iid, shape, col, order, stack, fuel, tier in ITEMS:
        write(f"items/types/{iid}.tres", ['[gd_resource type="Resource" script_class="ItemType" format=3]', "",
              '[ext_resource type="Script" path="res://items/item_type.gd" id="1_script"]', "", "[resource]",
              'script = ExtResource("1_script")', f'id = &"{iid}"', f'name_key = "ITEM_{iid.upper()}"',
              f"color = {color(col)}", f"icon_shape = {shape}", f"sort_order = {order}", f"stack_size = {stack}",
              f"fuel_value = {fmt(fuel)}", f"science_tier = {tier}", ""])


def write_ores():
    clear("world/ores/*.tres")
    for oid, (kind, target), hardness, order in ORES:
        res_path = f"res://items/types/{target}.tres" if kind == "item" else f"res://fluids/defs/{target}.tres"
        write(f"world/ores/{oid}.tres", ['[gd_resource type="Resource" script_class="OreDef" format=3]', "",
              '[ext_resource type="Script" path="res://world/ore_def.gd" id="1_script"]',
              f'[ext_resource type="Resource" path="{res_path}" id="2_target"]', "", "[resource]",
              'script = ExtResource("1_script")', f'id = &"{oid}"', f'name_key = "ORE_{oid.upper()}"',
              f'{kind} = ExtResource("2_target")', f"hardness = {hardness}", f"sort_order = {order}", ""])


def write_recipes():
    clear("items/recipes/*.tres")
    for rid, inputs, outputs, time, hand, order in RECIPES:
        uniq = list(dict.fromkeys([i for i, _ in inputs] + [o for o, _ in outputs]))
        out = ['[gd_resource type="Resource" script_class="Recipe" format=3]', "",
               '[ext_resource type="Script" path="res://items/recipe.gd" id="1_recipe"]',
               '[ext_resource type="Script" path="res://items/consume.gd" id="2_consume"]',
               '[ext_resource type="Script" path="res://items/consume_items.gd" id="3_consume_items"]',
               '[ext_resource type="Script" path="res://items/produce.gd" id="4_produce"]',
               '[ext_resource type="Script" path="res://items/item_stack.gd" id="5_stack"]',
               '[ext_resource type="Script" path="res://items/produce_items.gd" id="6_produce_items"]']
        for item in uniq:
            out.append(f'[ext_resource type="Resource" path="{item_path(item)}" id="item_{item}"]')
        out.append("")
        for i, (item, amount) in enumerate(inputs):
            out += [f'[sub_resource type="Resource" id="in_{i}"]', 'script = ExtResource("5_stack")',
                    f'item = ExtResource("item_{item}")', f"amount = {amount}", ""]
        subs = ", ".join(f'SubResource("in_{i}")' for i in range(len(inputs)))
        out += ['[sub_resource type="Resource" id="consume_0"]', 'script = ExtResource("3_consume_items")',
                f'stacks = Array[ExtResource("5_stack")]([{subs}])', ""]
        for i, (item, amount) in enumerate(outputs):
            out += [f'[sub_resource type="Resource" id="out_{i}"]', 'script = ExtResource("5_stack")',
                    f'item = ExtResource("item_{item}")', f"amount = {amount}", ""]
        subs = ", ".join(f'SubResource("out_{i}")' for i in range(len(outputs)))
        out += ['[sub_resource type="Resource" id="produce_0"]', 'script = ExtResource("6_produce_items")',
                f'stacks = Array[ExtResource("5_stack")]([{subs}])', ""]
        out += ["[resource]", 'script = ExtResource("1_recipe")', f'id = &"{rid}"', f"sort_order = {order}",
                f"hand_craftable = {fmt(hand)}",
                'consumes = Array[ExtResource("2_consume")]([SubResource("consume_0")])',
                'produces = Array[ExtResource("4_produce")]([SubResource("produce_0")])',
                f"craft_time = {fmt(float(time))}", ""]
        write(f"items/recipes/{rid}.tres", out)


# Нарисованные спрайты: art/buildings/<id>.png — полоса кадров состояний (работа, простой,
# выключено). Файла нет — здание рисуется процедурным плейсхолдером, как раньше.
def sprite_path(bid):
    rel = "art/buildings/%s.png" % bid
    return "res://" + rel if os.path.exists(os.path.join(ROOT, rel)) else None


def write_building(b):
    bid, kind, logic, cat, size, line, removable, player, glyph, col, order, cost, params, health, craft = b
    cls, script = DEF_SCRIPTS[kind]
    ext = [("Script", script, "1_def")]
    sprite = sprite_path(bid)
    if sprite:
        ext.append(("Texture2D", sprite, "9_sprite"))
    if cost:
        ext.append(("Script", "res://items/item_stack.gd", "2_stack"))
    if logic:
        ext.append(("Script", LOGIC[logic], "3_logic"))
    if "throughput" in params:
        ext.append(("Resource", f"res://buildings/defs/{params['throughput']}.tres", "5_throughput"))
    ammo = params.get("ammo", [])
    if ammo:
        ext.append(("Script", "res://buildings/defense/turret_ammo.gd", "6_ammo"))
    if params.get("recipes"):
        ext.append(("Script", "res://items/recipe.gd", "7_recipe_script"))
    for i, rid in enumerate(params.get("recipes", [])):
        ext.append(("Resource", f"res://items/recipes/{rid}.tres", f"recipe_{rid}"))
    for key in ("water_fluid", "steam_fluid"):
        if key in params:
            ext.append(("Resource", f"res://fluids/defs/{params[key]}.tres", f"fluid_{params[key]}"))
    item_ids = []
    for item, _ in cost:
        if item not in item_ids:
            item_ids.append(item)
    for a in ammo:
        if a[0] not in item_ids:
            item_ids.append(a[0])
    for item in item_ids:
        ext.append(("Resource", item_path(item), f"item_{item}"))
    ext = list(dict.fromkeys(ext))

    out = [f'[gd_resource type="Resource" script_class="{cls}" format=3]', ""]
    for t, path, eid in ext:
        out.append(f'[ext_resource type="{t}" path="{path}" id="{eid}"]')
    out.append("")
    for i, (item, amount) in enumerate(cost):
        out += [f'[sub_resource type="Resource" id="cost_{i}"]', 'script = ExtResource("2_stack")',
                f'item = ExtResource("item_{item}")', f"amount = {amount}", ""]
    for i, (item, shots, damage, splash, speed, reload_mul, ammo_col, burn, burn_s) in enumerate(ammo):
        out += [f'[sub_resource type="Resource" id="ammo_{i}"]', 'script = ExtResource("6_ammo")',
                f'item = ExtResource("item_{item}")', f"shots_per_item = {shots}", f"damage = {fmt(damage)}",
                f"splash_radius = {fmt(splash)}", f"speed = {fmt(speed)}", f"reload_multiplier = {fmt(reload_mul)}",
                f"burn_dps = {fmt(burn)}", f"burn_seconds = {fmt(burn_s)}", f"color = {color(ammo_col)}", ""]
    up = bid.upper()
    out += ["[resource]", 'script = ExtResource("1_def")', f'id = &"{bid}"',
            f'name_key = "BUILDING_{up}"', f'description_key = "BUILDING_{up}_DESC"',
            f"category = {cat}", f"size = {size}", f"removable = {fmt(removable)}",
            f"player_buildable = {fmt(player)}", f"line_placement = {fmt(line)}", f"sort_order = {order}"]
    if cost:
        subs = ", ".join(f'SubResource("cost_{i}")' for i in range(len(cost)))
        out.append(f'cost = Array[ExtResource("2_stack")]([{subs}])')
    if craft:
        out += [f"craft_time = {fmt(float(craft[0]))}", f"craft_amount = {craft[1]}"]
    hp, solid = health
    out += [f"health = {fmt(float(hp))}", f"solid = {fmt(solid)}", f"color = {color(col)}", f"glyph = {glyph}"]
    if logic:
        out.append('logic_script = ExtResource("3_logic")')
    if sprite:
        out.append('sprite = ExtResource("9_sprite")')
    for k, v in params.items():
        if k == "ammo":
            subs = ", ".join(f'SubResource("ammo_{i}")' for i in range(len(v)))
            out.append(f'ammo = Array[ExtResource("6_ammo")]([{subs}])')
        elif k == "recipes":
            subs = ", ".join(f'ExtResource("recipe_{rid}")' for rid in v)
            out.append(f'recipes = Array[ExtResource("7_recipe_script")]([{subs}])')
        elif k == "throughput":
            out.append('throughput_of = ExtResource("5_throughput")')
        elif k in ("water_fluid", "steam_fluid"):
            out.append(f'{k} = ExtResource("fluid_{v}")')
        elif isinstance(v, list):
            out.append("%s = PackedFloat32Array(%s)" % (k, ", ".join(fmt(x) for x in v)))
        else:
            out.append(f"{k} = {fmt(v)}")
    out.append("")
    write(f"buildings/defs/{bid}.tres", out)


def write_building_item(b):
    bid, kind, logic, cat, size, line, removable, player, glyph, col, order, cost, params, health, craft = b
    if not player:
        return
    out = ['[gd_resource type="Resource" script_class="ItemType" format=3]', "",
           '[ext_resource type="Script" path="res://items/item_type.gd" id="1_script"]',
           f'[ext_resource type="Resource" path="res://buildings/defs/{bid}.tres" id="2_building"]', "",
           "[resource]", 'script = ExtResource("1_script")', f'id = &"{bid}"',
           f'name_key = "BUILDING_{bid.upper()}"', f"color = {color(col)}",
           f"sort_order = {1000 + cat * 100 + order}", f"stack_size = {craft[2]}",
           'building = ExtResource("2_building")', ""]
    write(f"items/types/buildings/{bid}.tres", out)


def write_research():
    clear("research/defs/*.tres")
    for rid, order, amount, prereqs, buildings, recipes, effects in RESEARCH:
        ext = ['[ext_resource type="Script" path="res://research/research_def.gd" id="1_def"]',
               '[ext_resource type="Resource" path="res://items/types/science_kit.tres" id="2_kit"]',
               '[ext_resource type="Script" path="res://buildings/building_def.gd" id="3_building_script"]',
               '[ext_resource type="Script" path="res://items/recipe.gd" id="4_recipe_script"]']
        for bid in buildings:
            ext.append(f'[ext_resource type="Resource" path="res://buildings/defs/{bid}.tres" id="b_{bid}"]')
        for rec in recipes:
            ext.append(f'[ext_resource type="Resource" path="res://items/recipes/{rec}.tres" id="r_{rec}"]')
        kit2 = kit2_amount(rid, amount)
        subs = []
        if kit2 > 0:
            ext.append('[ext_resource type="Script" path="res://items/item_stack.gd" id="5_stack"]')
            ext.append('[ext_resource type="Resource" path="res://items/types/science_kit_2.tres" id="6_kit2"]')
            subs = ['[sub_resource type="Resource" id="kit2"]', 'script = ExtResource("5_stack")',
                    'item = ExtResource("6_kit2")', f"amount = {kit2}", ""]
        out = ['[gd_resource type="Resource" script_class="ResearchDef" format=3]', ""] + ext + [""] + subs + ["[resource]",
               'script = ExtResource("1_def")', f'id = &"{rid}"', f'name_key = "RESEARCH_{rid.upper()}"',
               f'description_key = "RESEARCH_{rid.upper()}_DESC"', f"sort_order = {order}",
               'cost_item = ExtResource("2_kit")', f"cost_amount = {amount}"]
        if kit2 > 0:
            out.append('extra_costs = Array[ExtResource("5_stack")]([SubResource("kit2")])')
        pre = ", ".join(f'&"{p}"' for p in prereqs)
        out.append(f"prerequisites = Array[StringName]([{pre}])")
        subs = ", ".join(f'ExtResource("b_{bid}")' for bid in buildings)
        out.append(f'unlock_buildings = Array[ExtResource("3_building_script")]([{subs}])')
        subs = ", ".join(f'ExtResource("r_{rec}")' for rec in recipes)
        out.append(f'unlock_recipes = Array[ExtResource("4_recipe_script")]([{subs}])')
        eff = ", ".join(f'&"{e}"' for e in effects)
        out.append(f"effects = Array[StringName]([{eff}])")
        if rid == "sandbox":
            out.append("creative_only = true")
        out.append("")
        write(f"research/defs/{rid}.tres", out)


def stack_block(items):
    ext, subs = [], []
    for item, _ in items:
        ext.append(f'[ext_resource type="Resource" path="{item_path(item)}" id="item_{item}"]')
    for i, (item, amount) in enumerate(items):
        subs += [f'[sub_resource type="Resource" id="start_{i}"]', 'script = ExtResource("2_stack")',
                 f'item = ExtResource("item_{item}")', f"amount = {amount}", ""]
    refs = ", ".join(f'SubResource("start_{i}")' for i in range(len(items)))
    return ext, subs, refs


def write_levels_and_run():
    for fname, lid, key, order, spawn in LEVELS:
        ext, subs, refs = stack_block(START_ITEMS)
        out = ['[gd_resource type="Resource" script_class="LevelDef" format=3]', "",
               '[ext_resource type="Script" path="res://world/level_def.gd" id="1_level"]',
               '[ext_resource type="Script" path="res://items/item_stack.gd" id="2_stack"]'] + ext + [""] + subs
        out += ["[resource]", 'script = ExtResource("1_level")', f'id = &"{lid}"',
                f'title_key = "{key}_TITLE"', f'description_key = "{key}_DESC"', f"order = {order}",
                f'map_path = "res://levels/maps/{fname}.fwmap"', f"spawn = Vector2i({spawn[0]}, {spawn[1]})",
                f'starting_items = Array[ExtResource("2_stack")]([{refs}])', ""]
        write(f"levels/{fname}.tres", out)
    ext, subs, refs = stack_block(START_ITEMS)
    out = ['[gd_resource type="Resource" script_class="RunDef" format=3]', "",
           '[ext_resource type="Script" path="res://world/run_def.gd" id="1_def"]',
           '[ext_resource type="Script" path="res://items/item_stack.gd" id="2_stack"]',
           '[ext_resource type="Resource" path="res://world/planet_types/normal.tres" id="3_normal"]'] + ext + [""] + subs
    out += ["[resource]", 'script = ExtResource("1_def")', f'starting_items = Array[ExtResource("2_stack")]([{refs}])',
            "charge_seconds = 30.0", "planet_time_seconds = 600.0", "planet_time_step_seconds = 120.0",
            "teleport_cooldown_seconds = 300.0", "teleport_cooldown_step_seconds = 60.0",
            "teleport_cooldown_min_seconds = 60.0",
            'first_planet_type = ExtResource("3_normal")', "visible_depth = 3",
            "min_nodes_per_step = 2", "max_nodes_per_step = 3", ""]
    write("world/run.tres", out)


def patch_planet_types():
    p = os.path.join(ROOT, "world", "planet_types", "normal.tres")
    s = open(p, encoding="utf-8").read()
    lines = s.split("\n")
    for i, line in enumerate(lines):
        if line.startswith("ore_ids = "):
            lines[i] = ('ore_ids = Array[StringName]([&"hematite", &"stone", &"coal", &"malachite",'
                        ' &"sphalerite", &"water"])')
        elif line.startswith("ore_chances = "):
            lines[i] = "ore_chances = PackedFloat32Array(1, 1, 1, 0.9, 0.75, 0.8)"
    open(p, "w", encoding="utf-8", newline="\n").write("\n".join(lines))


write_fluids()
write_items()
write_ores()
write_recipes()
clear("buildings/defs/*.tres")
clear("items/types/buildings/*.tres")
for b in BUILDINGS:
    write_building(b)
    write_building_item(b)
write_research()
write_levels_and_run()
patch_planet_types()
print("fluids", len(FLUIDS), "items", len(ITEMS), "ores", len(ORES), "recipes", len(RECIPES),
      "buildings", len(BUILDINGS), "research", len(RESEARCH))
