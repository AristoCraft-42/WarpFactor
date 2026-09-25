class_name PlaceholderMusic
extends RefCounted
## Музыка-заглушка: одна петля из четырёх слоёв одинаковой длины, которые играют вместе и
## смешиваются по обстановке (AudioDirector): в покое — пэд и мелодия, перед волной добавляется
## пульсирующий бас, в бою — ударные. Слои синхронны, поэтому переход — просто смена громкостей.
##
## Ля минор, 90 ударов в минуту, 16 тактов (≈ 43 с): Am F C G | Am F Dm E, по два такта на аккорд.
## Всё, что звучит за концом петли, переносится в её начало — стык не слышен.

enum Layer { PAD, MELODY, BASS, DRUMS }

const LAYER_COUNT := 4
const BPM := 90.0
const BARS := 16
const BEATS_PER_BAR := 4

## Аккорды по два такта: бас (MIDI) и три ноты пэда.
const CHORDS := [
	[45, [57, 60, 64]], # Am
	[41, [53, 57, 60]], # F
	[48, [55, 60, 64]], # C
	[43, [55, 59, 62]], # G
	[45, [57, 60, 64]], # Am
	[41, [53, 57, 60]], # F
	[38, [53, 57, 62]], # Dm
	[40, [56, 59, 64]], # E
]
## Средняя громкость слоёв (RMS) до смешивания: пэд — основа, мелодия — чуть тише.
const LAYER_RMS := [0.09, 0.06, 0.08, 0.09]
## Пентатоника ля минор для мелодии (две октавы).
const SCALE := [69, 72, 74, 76, 79, 81, 84, 86, 88]


static func beat_samples() -> int:
	return roundi(60.0 / BPM * Synth.RATE)


static func length_samples() -> int:
	return beat_samples() * BEATS_PER_BAR * BARS


## Все слои по порядку Layer. seed_value меняет мелодию и сбивки ударных.
static func make_layers(seed_value: int = 42) -> Array[PackedFloat32Array]:
	var layers: Array[PackedFloat32Array] = []
	for k in LAYER_COUNT:
		var buf := PackedFloat32Array()
		buf.resize(length_samples())
		layers.append(buf)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	_make_pad(layers[Layer.PAD])
	_make_melody(layers[Layer.MELODY], rng)
	_make_bass(layers[Layer.BASS])
	_make_drums(layers[Layer.DRUMS], rng)
	for k in LAYER_COUNT:
		Synth.normalize_rms(layers[k], LAYER_RMS[k])
		Synth.limit(layers[k], 0.85)
	return layers


static func _chord_at_bar(bar: int) -> Array:
	return CHORDS[(bar / 2) % CHORDS.size()]


static func _make_pad(out: PackedFloat32Array) -> void:
	var bar_n := beat_samples() * BEATS_PER_BAR
	var seconds := float(bar_n * 2) / Synth.RATE + 1.4
	for c in CHORDS.size():
		var chord: Array = CHORDS[c]
		var at := c * bar_n * 2
		for note: int in chord[1]:
			Synth.pad(out, at, Synth.midi_hz(note), seconds, 0.11, 0.9, 1.4, 0.05, true)
		# Тихий низ на октаву ниже баса — объём без мути.
		Synth.pad(out, at, Synth.midi_hz(chord[0]), seconds, 0.07, 0.9, 1.4, 0.03, true)


static func _make_melody(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var eighth := beat_samples() / 2
	var last := 4
	for bar in BARS:
		var chord := _chord_at_bar(bar)
		var chord_tones: Array = chord[1]
		for step in 8:
			# Реже на сильных долях первой половины фразы, гуще ближе к концу.
			var chance := 0.35 + 0.15 * float(bar % 4) / 3.0
			if rng.randf() > chance:
				continue
			var note: int
			if rng.randf() < 0.55:
				note = int(chord_tones[rng.randi() % chord_tones.size()]) + 12
			else:
				# Мелодия ходит по гамме маленькими шагами.
				last = clampi(last + rng.randi_range(-2, 2), 0, SCALE.size() - 1)
				note = SCALE[last]
			var at := (bar * 8 + step) * eighth
			Synth.pluck(out, at, Synth.midi_hz(note), 1.6, rng.randf_range(0.18, 0.3), 0.5, rng.randi(), true)
		# Колокол в начале каждой четвёртой фразы.
		if bar % 4 == 0:
			Synth.bell(out, bar * 8 * eighth, Synth.midi_hz(int(chord_tones[2]) + 12), 2.5, 0.08, 3.5, 1.5, 1.2, true)


static func _make_bass(out: PackedFloat32Array) -> void:
	var eighth := beat_samples() / 2
	for bar in BARS:
		var root: int = _chord_at_bar(bar)[0]
		for step in 8:
			var accent := 1.0 if step % 2 == 0 else 0.6
			var note := root if step != 7 else root + 12
			var at := (bar * 8 + step) * eighth
			Synth.tone(out, at, 0.3, Synth.midi_hz(note), Synth.midi_hz(note), 0.32 * accent, Synth.Wave.SAW, 0.004, 0.09, true)
			Synth.tone(out, at, 0.3, Synth.midi_hz(note - 12), Synth.midi_hz(note - 12), 0.25 * accent, Synth.Wave.SINE, 0.004, 0.12, true)


static func _make_drums(out: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	var beat := beat_samples()
	var sixteenth := beat / 4
	for bar in BARS:
		var bar_at := bar * beat * BEATS_PER_BAR
		Synth.kick(out, bar_at, 0.7, true)
		Synth.kick(out, bar_at + beat * 2, 0.7, true)
		if rng.randf() < 0.4:
			Synth.kick(out, bar_at + beat * 2 - sixteenth * 2, 0.45, true)
		Synth.snare(out, bar_at + beat, 0.4, rng.randi(), true)
		Synth.snare(out, bar_at + beat * 3, 0.4, rng.randi(), true)
		var hats := 16 if bar % 8 >= 6 else 8
		for h in hats:
			var at := bar_at + h * (beat * BEATS_PER_BAR / hats)
			Synth.hat(out, at, 0.08 if h % 2 == 0 else 0.05, 0.04, rng.randi(), true)
		if bar % 8 == 0:
			Synth.noise(out, bar_at, 1.4, 0.1, 0.8, 0.7, 0.002, 0.5, rng.randi(), true)
		# Сбивка в конце фразы.
		if bar % 4 == 3:
			for k in 3:
				Synth.snare(out, bar_at + beat * 3 + sixteenth * (k + 1), 0.22 + 0.06 * k, rng.randi(), true)
