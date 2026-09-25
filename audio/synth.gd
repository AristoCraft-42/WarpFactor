class_name Synth
extends RefCounted
## Простой синтезатор для звуков-заглушек и музыки: всё пишется в моно-буфер PackedFloat32Array
## с частотой RATE и потом превращается в AudioStreamWAV (to_stream). Как PlaceholderArt для
## картинок: пока своих файлов нет, звук собирается кодом — одинаково при каждом запуске
## (шум берёт сид из аргументов).
##
## Все функции добавляют звук в буфер out с отсчёта at (в сэмплах) и не выходят за конец буфера,
## если не сказано иначе. wrap = true — хвост, вышедший за конец, продолжается с начала (петли музыки).
##
## Внутренние циклы написаны без вызовов функций на сэмпл (огибающие наращиваются, шум — свой
## xorshift): вызов в GDScript стоит дороже самой арифметики, а сэмплов — миллионы.

const RATE := 22050

enum Wave { SINE, SQUARE, SAW, TRIANGLE }


static func buffer(seconds: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(roundi(seconds * RATE), 1))
	return out


static func samples(seconds: float) -> int:
	return roundi(seconds * RATE)


## Нота из MIDI-номера (69 — ля первой октавы, 440 Гц).
static func midi_hz(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)


## Тон: частота скользит по экспоненте от f0 к f1, огибающая — линейная атака и экспоненциальный
## спад с постоянной tau (секунд; чем меньше, тем короче звук). В последние 4 мс — затухание в ноль.
static func tone(out: PackedFloat32Array, at: int, seconds: float, f0: float, f1: float, amp: float,
		wave: Wave = Wave.SINE, attack: float = 0.004, tau: float = 0.1, wrap: bool = false) -> void:
	var n := samples(seconds)
	var size := out.size()
	var kind := int(wave)
	var phase := 0.0
	# Экспоненциальное скольжение частоты — умножением на шаг, без pow на каждый сэмпл.
	var step := f0 / RATE
	var glide := pow(f1 / maxf(f0, 1.0), 1.0 / maxf(n, 1))
	var attack_step := 1.0 / maxf(attack * RATE, 1.0)
	var fade_n := maxf(minf(0.004 * RATE, n * 0.5), 1.0)
	var fade_start := n - int(fade_n)
	var decay := exp(-1.0 / maxf(tau * RATE, 1.0))
	var level := amp
	var ramp := 0.0
	for i in n:
		var j := at + i
		if j >= size:
			if not wrap:
				break
			j %= size
		phase += step
		step *= glide
		if phase >= 1.0:
			phase -= int(phase)
		var v: float
		if kind == 0:
			v = sin(phase * TAU)
		elif kind == 1:
			v = 1.0 if phase < 0.5 else -1.0
		elif kind == 2:
			v = phase * 2.0 - 1.0
		else:
			v = 4.0 * (phase - 0.5 if phase > 0.5 else 0.5 - phase) - 1.0
		if ramp < 1.0:
			ramp += attack_step
			if ramp > 1.0:
				ramp = 1.0
		var env := level * ramp
		if i >= fade_start:
			env *= (n - i) / fade_n
		out[j] += v * env
		level *= decay


## Шум: lowpass (0..1, меньше — глуше) и highpass (0..1, больше — звонче) — однополюсные фильтры.
static func noise(out: PackedFloat32Array, at: int, seconds: float, amp: float, lowpass: float = 1.0,
		highpass: float = 0.0, attack: float = 0.002, tau: float = 0.1, seed_value: int = 1, wrap: bool = false) -> void:
	var state := (seed_value * 2654435761 + 1) & 0x7fffffff
	if state == 0:
		state = 1
	var n := samples(seconds)
	var size := out.size()
	var lp := 0.0
	var hp_prev := 0.0
	var attack_step := 1.0 / maxf(attack * RATE, 1.0)
	var fade_n := maxf(minf(0.004 * RATE, n * 0.5), 1.0)
	var fade_start := n - int(fade_n)
	var decay := exp(-1.0 / maxf(tau * RATE, 1.0))
	var level := amp
	var ramp := 0.0
	for i in n:
		var j := at + i
		if j >= size:
			if not wrap:
				break
			j %= size
		# xorshift32: белый шум без вызовов.
		state ^= (state << 13) & 0xffffffff
		state ^= state >> 17
		state ^= (state << 5) & 0xffffffff
		var white := float(state & 0xffff) / 32767.5 - 1.0
		lp += (white - lp) * lowpass
		var s := lp - hp_prev * highpass
		hp_prev = lp
		if ramp < 1.0:
			ramp += attack_step
			if ramp > 1.0:
				ramp = 1.0
		var env := level * ramp
		if i >= fade_start:
			env *= (n - i) / fade_n
		out[j] += s * env
		level *= decay


## Щипок струны (Karplus–Strong): шумовой всплеск в линии задержки, усредняемый по кругу.
## damping 0..1 — насколько быстро гаснут верха (больше — глуше).
static func pluck(out: PackedFloat32Array, at: int, freq: float, seconds: float, amp: float,
		damping: float = 0.5, seed_value: int = 1, wrap: bool = false) -> void:
	var period := maxi(roundi(RATE / maxf(freq, 20.0)), 2)
	var line := PackedFloat32Array()
	line.resize(period)
	# Всплеск чуть приглушён: иначе у каждой ноты резкий щелчок во всю полосу.
	noise(line, 0, float(period) / RATE + 0.01, 1.0, 0.6, 0.0, 0.0, 1000.0, seed_value)
	var n := samples(seconds)
	var size := out.size()
	var fade_n := maxf(minf(0.02 * RATE, n * 0.5), 1.0)
	var fade_start := n - int(fade_n)
	var keep := 0.5 + 0.5 * (1.0 - clampf(damping, 0.0, 1.0)) * 0.99
	var index := 0
	var prev := 0.0
	for i in n:
		var j := at + i
		if j >= size:
			if not wrap:
				break
			j %= size
		var current := line[index]
		line[index] = (current * keep + prev * (1.0 - keep)) * 0.998
		prev = current
		index += 1
		if index >= period:
			index = 0
		var gain := amp
		if i >= fade_start:
			gain *= (n - i) / fade_n
		out[j] += current * gain


## Колокол: частотная модуляция (несущая f, модулятор f × ratio), глубина модуляции гаснет быстрее звука.
static func bell(out: PackedFloat32Array, at: int, freq: float, seconds: float, amp: float,
		ratio: float = 3.5, index: float = 2.0, tau: float = 0.6, wrap: bool = false) -> void:
	var n := samples(seconds)
	var size := out.size()
	var w_c := TAU * freq / RATE
	var w_m := TAU * freq * ratio / RATE
	var decay := exp(-1.0 / maxf(tau * RATE, 1.0))
	var mod_decay := exp(-1.0 / maxf(tau * 0.4 * RATE, 1.0))
	var level := amp
	var mod_level := index
	var fade_n := maxf(minf(0.01 * RATE, n * 0.5), 1.0)
	var fade_start := n - int(fade_n)
	var ramp := 0.0
	for i in n:
		var j := at + i
		if j >= size:
			if not wrap:
				break
			j %= size
		if ramp < 1.0:
			ramp += 1.0 / 30.0
		var env := level * (ramp if ramp < 1.0 else 1.0)
		if i >= fade_start:
			env *= (n - i) / fade_n
		out[j] += sin(w_c * i + mod_level * sin(w_m * i)) * env
		level *= decay
		mod_level *= mod_decay


## Пэд: две расстроенные пилы через два фильтра, медленная атака и затухание в конце.
## cutoff — коэффициент фильтра 0..1 (меньше — мягче).
static func pad(out: PackedFloat32Array, at: int, freq: float, seconds: float, amp: float,
		attack: float = 0.8, release: float = 1.2, cutoff: float = 0.06, wrap: bool = false) -> void:
	var n := samples(seconds)
	var size := out.size()
	var f1 := freq * 0.997 / RATE
	var f2 := freq * 1.003 / RATE
	var p1 := 0.0
	var p2 := 0.37
	var lp := 0.0
	var lp2 := 0.0
	var attack_step := 1.0 / maxf(attack * RATE, 1.0)
	var release_n := maxf(minf(release * RATE, n * 0.5), 1.0)
	var release_start := n - int(release_n)
	var ramp := 0.0
	for i in n:
		var j := at + i
		if j >= size:
			if not wrap:
				break
			j %= size
		p1 += f1
		if p1 >= 1.0:
			p1 -= 1.0
		p2 += f2
		if p2 >= 1.0:
			p2 -= 1.0
		lp += (p1 + p2 - 1.0 - lp) * cutoff
		lp2 += (lp - lp2) * cutoff
		if ramp < 1.0:
			ramp += attack_step
			if ramp > 1.0:
				ramp = 1.0
		var env := amp * ramp
		if i >= release_start:
			env *= (n - i) / release_n
		out[j] += lp2 * env


## Бас-бочка: синус, падающий по частоте, с коротким щелчком.
static func kick(out: PackedFloat32Array, at: int, amp: float, wrap: bool = false) -> void:
	tone(out, at, 0.32, 140.0, 42.0, amp, Wave.SINE, 0.001, 0.09, wrap)
	noise(out, at, 0.012, amp * 0.3, 0.6, 0.0, 0.0005, 0.004, at + 7, wrap)


static func snare(out: PackedFloat32Array, at: int, amp: float, seed_value: int = 3, wrap: bool = false) -> void:
	tone(out, at, 0.12, 220.0, 160.0, amp * 0.4, Wave.TRIANGLE, 0.001, 0.04, wrap)
	noise(out, at, 0.22, amp, 0.55, 0.5, 0.001, 0.06, seed_value, wrap)


static func hat(out: PackedFloat32Array, at: int, amp: float, seconds: float = 0.05, seed_value: int = 5, wrap: bool = false) -> void:
	noise(out, at, seconds, amp, 1.0, 0.95, 0.0005, seconds * 0.35, seed_value, wrap)


## Средняя громкость (RMS) к target — слои музыки разной природы звучат ровно; пик потом ограничивает limit.
static func normalize_rms(buf: PackedFloat32Array, target: float) -> void:
	var sum := 0.0
	for s in buf:
		sum += s * s
	var rms := sqrt(sum / maxi(buf.size(), 1))
	if rms <= 0.000001:
		return
	var k := target / rms
	for i in buf.size():
		buf[i] *= k


static func rms_of(buf: PackedFloat32Array) -> float:
	var sum := 0.0
	for s in buf:
		sum += s * s
	return sqrt(sum / maxi(buf.size(), 1))


## Громкость к пику peak, если буфер громче (тихие не усиливаются).
static func limit(buf: PackedFloat32Array, peak: float = 0.9) -> void:
	var top := peak_of(buf)
	if top <= peak or top <= 0.0:
		return
	var k := peak / top
	for i in buf.size():
		buf[i] *= k


static func peak_of(buf: PackedFloat32Array) -> float:
	var top := 0.0
	for s in buf:
		if s > top:
			top = s
		elif -s > top:
			top = -s
	return top


## 16-битный моно AudioStreamWAV. loop — бесшовная петля на весь буфер.
static func to_stream(buf: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(buf.size() * 2)
	for i in buf.size():
		var s := buf[i]
		if s > 1.0:
			s = 1.0
		elif s < -1.0:
			s = -1.0
		data.encode_s16(i * 2, int(s * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = false
	stream.data = data
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream
