"""Генерирует .tres врагов и кривых угрозы (dev-скрипт, этап 9)."""
import os

NL = chr(10)

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def color(h):
    r, g, b = int(h[0:2], 16) / 255, int(h[2:4], 16) / 255, int(h[4:6], 16) / 255
    return f"Color({r:.3f}, {g:.3f}, {b:.3f}, 1)"


# id, порядок, прочность, скорость (тайл/с), радиус (px), урон, пауза (с), дальность (тайлы), стоимость, цвет, форма, размер
ENEMIES = [
    ("crawler", 10, 70.0, 8.5, 9.0, 5.0, 0.4, 0.15, 0.7, "cc5a3a", 0, 32.0),
    ("soldier", 20, 160.0, 5.1, 11.0, 9.0, 0.9, 3.5, 2.1, "b8483f", 1, 38.0),
    ("brute", 30, 900.0, 3.2, 15.0, 45.0, 1.4, 0.2, 7.0, "8f3a4a", 2, 54.0),
]

os.makedirs(os.path.join(ROOT, "enemies", "defs"), exist_ok=True)
for e in ENEMIES:
    eid, order, hp, speed, radius, dmg, interval, rng, cost, col, shape, size = e
    out = ['[gd_resource type="Resource" script_class="EnemyDef" format=3]', "",
           '[ext_resource type="Script" path="res://enemies/enemy_def.gd" id="1_def"]', "",
           "[resource]", 'script = ExtResource("1_def")', f'id = &"{eid}"',
           f'name_key = "ENEMY_{eid.upper()}"', f"sort_order = {order}",
           f"health = {hp!r}", f"speed = {speed!r}", f"radius = {radius!r}", f"damage = {dmg!r}",
           f"attack_interval = {interval!r}", f"attack_range = {rng!r}", f"threat_cost = {cost!r}",
           f"color = {color(col)}", f"shape = {shape}", f"draw_size = {size!r}", ""]
    with open(os.path.join(ROOT, "enemies", "defs", f"{eid}.tres"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(out))

os.makedirs(os.path.join(ROOT, "enemies", "threats"), exist_ok=True)
# Кривые угрозы: обычная планета и рудная (богаче, но волны идут раньше и злее).
THREATS = {
    "normal": {},
    "rich": {"first_wave_seconds": 420.0, "first_gap_seconds": 180.0, "budget_base": 5.0,
             "budget_per_wave": 3.4, "budget_per_minute": 0.55, "spawn_point_count": 4},
}

threat = """[gd_resource type="Resource" script_class="ThreatDef" format=3]

[ext_resource type="Script" path="res://enemies/threat_def.gd" id="1_def"]

[resource]
script = ExtResource("1_def")
first_wave_seconds = 600.0
first_gap_seconds = 240.0
gap_multiplier = 0.85
continuous_below_seconds = 10.0
spawn_seconds = 8.0
spawn_seconds_per_wave = 2.5
max_spawn_seconds = 45.0
warning_seconds = 15.0
budget_base = 4.0
budget_per_wave = 2.6
budget_per_minute = 0.4
enemy_ids = Array[StringName]([&"crawler", &"soldier", &"brute"])
enemy_from_wave = PackedInt32Array(1, 4, 8)
enemy_weights = PackedFloat32Array(3, 2, 1)
spawn_point_count = 3
max_alive = 1500
"""
for name, overrides in THREATS.items():
    text = threat
    for key, value in overrides.items():
        start = text.index(NL + "%s = " % key) + 1
        end = text.index(NL, start) + 1
        text = text[:start] + "%s = %r" % (key, value) + NL + text[end:]
    path = os.path.join(ROOT, "enemies", "threats", "%s.tres" % name)
    with open(path, "w", encoding="utf-8", newline=NL) as f:
        f.write(text)

# Тип «обычная» ссылается на кривую угрозы.
p = os.path.join(ROOT, "world", "planet_types", "normal.tres")
s = open(p, encoding="utf-8").read()
if "threat = " not in s:
    s = s.replace('[ext_resource type="Script" path="res://world/planet_type_def.gd" id="1_def"]',
                  '[ext_resource type="Script" path="res://world/planet_type_def.gd" id="1_def"]\n'
                  '[ext_resource type="Resource" path="res://enemies/threats/normal.tres" id="2_threat"]')
    s = s.replace("safe = false\n", 'safe = false\nthreat = ExtResource("2_threat")\n')
    open(p, "w", encoding="utf-8", newline="\n").write(s)
print("enemies:", len(ENEMIES))
