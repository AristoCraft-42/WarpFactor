class_name PlaceholderSounds
extends RefCounted
## Звуки-заглушки: каждый собирается синтезатором (Synth) по своему рецепту. Свой файл в
## audio/sfx/<id>.ogg (или .wav) заменяет заглушку — см. audio/README.md.

## Все звуки игры. Порядок не важен: звук ищется по id.
const IDS: Array[StringName] = [
	&"ui_click", &"ui_error", &"ui_success", &"ui_notify",
	&"build", &"deconstruct", &"rotate", &"building_destroyed",
	&"shot", &"shell", &"explosion", &"hit", &"zap", &"repair", &"spray",
	&"enemy_death", &"enemy_melee", &"enemy_shot",
	&"mine", &"crate", &"drone_destroyed", &"drone_respawn",
	&"wave_warning", &"wave_start", &"research_done", &"teleport",
	&"factory_loop",
]

## Звуки-петли (фон): играют непрерывно, громкость меняет режиссёр.
const LOOPS: Array[StringName] = [&"factory_loop"]


static func make(id: StringName) -> PackedFloat32Array:
	var seed_value := hash(String(id)) & 0xffff
	var out: PackedFloat32Array
	match id:
		&"ui_click":
			out = Synth.buffer(0.04)
			Synth.tone(out, 0, 0.04, 1900.0, 1500.0, 0.35, Synth.Wave.SINE, 0.001, 0.012)
			Synth.noise(out, 0, 0.01, 0.12, 1.0, 0.8, 0.0005, 0.003, seed_value)
		&"ui_error":
			out = Synth.buffer(0.26)
			Synth.tone(out, 0, 0.11, 330.0, 320.0, 0.22, Synth.Wave.SQUARE, 0.002, 0.2)
			Synth.tone(out, Synth.samples(0.13), 0.13, 247.0, 240.0, 0.22, Synth.Wave.SQUARE, 0.002, 0.2)
		&"ui_success":
			out = Synth.buffer(0.45)
			Synth.bell(out, 0, Synth.midi_hz(76), 0.3, 0.3, 2.0, 1.2, 0.15)
			Synth.bell(out, Synth.samples(0.09), Synth.midi_hz(83), 0.36, 0.3, 2.0, 1.2, 0.2)
		&"ui_notify":
			out = Synth.buffer(0.3)
			Synth.bell(out, 0, Synth.midi_hz(81), 0.3, 0.25, 2.0, 0.8, 0.12)
		&"build":
			out = Synth.buffer(0.22)
			Synth.tone(out, 0, 0.18, 170.0, 70.0, 0.6, Synth.Wave.SINE, 0.001, 0.05)
			Synth.noise(out, 0, 0.06, 0.35, 0.5, 0.3, 0.0005, 0.015, seed_value)
			Synth.tone(out, Synth.samples(0.035), 0.05, 900.0, 700.0, 0.12, Synth.Wave.TRIANGLE, 0.001, 0.015)
		&"deconstruct":
			out = Synth.buffer(0.24)
			Synth.noise(out, 0, 0.18, 0.3, 0.35, 0.2, 0.08, 0.2, seed_value)
			Synth.tone(out, Synth.samples(0.09), 0.14, 180.0, 360.0, 0.3, Synth.Wave.TRIANGLE, 0.002, 0.05)
		&"rotate":
			out = Synth.buffer(0.05)
			Synth.tone(out, 0, 0.05, 950.0, 1100.0, 0.25, Synth.Wave.TRIANGLE, 0.001, 0.01)
			Synth.noise(out, 0, 0.015, 0.1, 0.8, 0.5, 0.0005, 0.004, seed_value)
		&"building_destroyed":
			out = Synth.buffer(0.9)
			Synth.tone(out, 0, 0.6, 110.0, 38.0, 0.6, Synth.Wave.SINE, 0.002, 0.18)
			Synth.noise(out, 0, 0.9, 0.55, 0.12, 0.0, 0.002, 0.22, seed_value)
			Synth.noise(out, Synth.samples(0.05), 0.4, 0.25, 0.6, 0.4, 0.001, 0.07, seed_value + 1)
		&"shot":
			out = Synth.buffer(0.1)
			Synth.noise(out, 0, 0.08, 0.4, 0.7, 0.3, 0.0005, 0.018, seed_value)
			Synth.tone(out, 0, 0.07, 700.0, 180.0, 0.3, Synth.Wave.SQUARE, 0.0005, 0.02)
		&"shell":
			out = Synth.buffer(0.35)
			Synth.tone(out, 0, 0.3, 95.0, 40.0, 0.7, Synth.Wave.SINE, 0.001, 0.08)
			Synth.noise(out, 0, 0.3, 0.4, 0.25, 0.0, 0.001, 0.06, seed_value)
		&"explosion":
			out = Synth.buffer(0.7)
			Synth.tone(out, 0, 0.45, 80.0, 30.0, 0.6, Synth.Wave.SINE, 0.001, 0.14)
			Synth.noise(out, 0, 0.7, 0.6, 0.18, 0.0, 0.001, 0.16, seed_value)
		&"hit":
			out = Synth.buffer(0.05)
			Synth.noise(out, 0, 0.05, 0.25, 0.9, 0.6, 0.0005, 0.01, seed_value)
			Synth.tone(out, 0, 0.03, 1300.0, 900.0, 0.1, Synth.Wave.TRIANGLE, 0.0005, 0.01)
		&"zap":
			out = Synth.buffer(0.22)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var at := 0
			# Треск: цепочка коротких жужжащих всплесков со случайной высотой.
			while at < Synth.samples(0.18):
				var length := rng.randf_range(0.015, 0.035)
				Synth.tone(out, at, length, rng.randf_range(300.0, 900.0), rng.randf_range(150.0, 600.0), 0.28,
					Synth.Wave.SAW, 0.0005, 0.02)
				at += Synth.samples(length * rng.randf_range(0.6, 1.1))
			Synth.noise(out, 0, 0.2, 0.18, 1.0, 0.9, 0.0005, 0.08, seed_value + 1)
		&"repair":
			out = Synth.buffer(0.3)
			Synth.tone(out, 0, 0.28, 520.0, 880.0, 0.22, Synth.Wave.SINE, 0.03, 0.2)
			Synth.tone(out, 0, 0.28, 1040.0, 1760.0, 0.06, Synth.Wave.SINE, 0.03, 0.12)
		&"spray":
			out = Synth.buffer(0.35)
			Synth.noise(out, 0, 0.35, 0.35, 0.5, 0.7, 0.04, 0.2, seed_value)
		&"enemy_death":
			out = Synth.buffer(0.3)
			Synth.tone(out, 0, 0.26, 340.0, 70.0, 0.4, Synth.Wave.SAW, 0.002, 0.09)
			Synth.noise(out, 0, 0.2, 0.3, 0.3, 0.2, 0.001, 0.05, seed_value)
		&"enemy_melee":
			out = Synth.buffer(0.09)
			Synth.noise(out, 0, 0.09, 0.3, 0.6, 0.6, 0.004, 0.03, seed_value)
			Synth.tone(out, 0, 0.06, 260.0, 190.0, 0.15, Synth.Wave.SAW, 0.001, 0.02)
		&"enemy_shot":
			out = Synth.buffer(0.12)
			Synth.tone(out, 0, 0.11, 1400.0, 380.0, 0.25, Synth.Wave.SINE, 0.001, 0.04)
		&"mine":
			out = Synth.buffer(0.09)
			Synth.tone(out, 0, 0.08, 520.0, 1040.0, 0.28, Synth.Wave.TRIANGLE, 0.001, 0.03)
			Synth.noise(out, 0, 0.02, 0.1, 0.7, 0.4, 0.0005, 0.006, seed_value)
		&"crate":
			out = Synth.buffer(0.3)
			Synth.bell(out, 0, Synth.midi_hz(72), 0.2, 0.25, 1.0, 1.0, 0.1)
			Synth.bell(out, Synth.samples(0.07), Synth.midi_hz(79), 0.22, 0.25, 1.0, 1.0, 0.12)
		&"drone_destroyed":
			out = Synth.buffer(1.0)
			Synth.tone(out, 0, 0.5, 880.0, 220.0, 0.25, Synth.Wave.SQUARE, 0.002, 0.3)
			Synth.tone(out, Synth.samples(0.1), 0.6, 110.0, 35.0, 0.6, Synth.Wave.SINE, 0.002, 0.2)
			Synth.noise(out, Synth.samples(0.1), 0.9, 0.5, 0.15, 0.0, 0.002, 0.2, seed_value)
		&"drone_respawn":
			out = Synth.buffer(0.7)
			for k in 3:
				Synth.bell(out, Synth.samples(0.08 * k), Synth.midi_hz([62, 66, 69][k]), 0.5, 0.2, 1.0, 0.6, 0.25)
			Synth.tone(out, 0, 0.6, 200.0, 800.0, 0.08, Synth.Wave.SINE, 0.2, 0.4)
		&"wave_warning":
			out = Synth.buffer(1.6)
			# Сирена: два тона по очереди, мягкий вход и выход.
			for k in 4:
				var f := 620.0 if k % 2 == 0 else 820.0
				Synth.tone(out, Synth.samples(0.38 * k), 0.4, f, f * 0.98, 0.16, Synth.Wave.TRIANGLE, 0.03, 0.6)
				Synth.tone(out, Synth.samples(0.38 * k), 0.4, f * 2.0, f * 1.96, 0.04, Synth.Wave.SINE, 0.03, 0.4)
		&"wave_start":
			out = Synth.buffer(1.8)
			# Рог: низкая пила с квинтой, медленная атака.
			Synth.pad(out, 0, 110.0, 1.8, 0.5, 0.12, 0.7, 0.08)
			Synth.pad(out, 0, 165.0, 1.8, 0.35, 0.16, 0.7, 0.08)
			Synth.pad(out, 0, 55.0, 1.8, 0.4, 0.1, 0.7, 0.05)
		&"research_done":
			out = Synth.buffer(1.1)
			var notes := [72, 76, 79, 84]
			for k in notes.size():
				Synth.bell(out, Synth.samples(0.09 * k), Synth.midi_hz(notes[k]), 0.8, 0.2, 2.0, 1.0, 0.3)
		&"teleport":
			out = Synth.buffer(2.2)
			Synth.tone(out, 0, 2.0, 160.0, 1400.0, 0.2, Synth.Wave.SAW, 0.5, 3.0)
			Synth.tone(out, 0, 2.0, 240.0, 2100.0, 0.1, Synth.Wave.SINE, 0.5, 3.0)
			Synth.noise(out, 0, 2.2, 0.15, 0.3, 0.5, 1.2, 3.0, seed_value)
			Synth.bell(out, Synth.samples(1.85), Synth.midi_hz(84), 0.35, 0.3, 1.5, 2.0, 0.15)
		&"factory_loop":
			out = _factory_loop(seed_value)
		_:
			out = Synth.buffer(0.05)
	Synth.limit(out, 0.9)
	return out


## Фон цеха (4 с, петля): низкий гул с обертоном и мерный стук механизмов.
static func _factory_loop(seed_value: int) -> PackedFloat32Array:
	var out := Synth.buffer(4.0)
	var n := out.size()
	# 55 и 110 Гц укладываются в 4 с целым числом периодов — петля без щелчка на стыке.
	var w1 := TAU * 55.0 / Synth.RATE
	var w2 := TAU * 110.0 / Synth.RATE
	var w3 := TAU * 165.0 / Synth.RATE
	for i in n:
		var wobble := 0.8 + 0.2 * sin(TAU * i / n * 2.0)
		out[i] = (sin(w1 * i) * 0.22 + sin(w2 * i) * 0.12 * wobble + sin(w3 * i) * 0.05)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for k in 8:
		var at := Synth.samples(0.5 * k + rng.randf_range(0.0, 0.05))
		Synth.noise(out, at, 0.08, 0.16, 0.35, 0.3, 0.001, 0.02, seed_value + k, true)
		if k % 2 == 1:
			Synth.tone(out, at, 0.06, 420.0, 380.0, 0.05, Synth.Wave.TRIANGLE, 0.001, 0.02, true)
	return out
