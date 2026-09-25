extends SceneTree
## Предпросмотр звука без игры: все звуки-заглушки и музыка каждого состояния в WAV.
## Запуск: godot --headless --path D:/Mind --script res://tools/preview_audio.gd [-- --out=D:/shots/audio]

var _out: String = "D:/shots/audio"


func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr("--out=".length())
	DirAccess.make_dir_recursive_absolute(_out)
	var started := Time.get_ticks_msec()
	for id in PlaceholderSounds.IDS:
		Synth.to_stream(PlaceholderSounds.make(id)).save_to_wav(_out.path_join("sfx_%s.wav" % id))
	print("звуков: %d за %d мс" % [PlaceholderSounds.IDS.size(), Time.get_ticks_msec() - started])
	started = Time.get_ticks_msec()
	var layers := PlaceholderMusic.make_layers()
	print("музыка: 4 слоя за %d мс" % (Time.get_ticks_msec() - started))
	# Каждое состояние — слои с громкостями режиссёра, петля дважды подряд (слышен стык).
	for state in AudioDirector.MUSIC_STATE_NAMES.size():
		var mix: Array = AudioDirector.LAYER_MIX[state]
		var n := PlaceholderMusic.length_samples()
		var out := PackedFloat32Array()
		out.resize(n * 2)
		for k in layers.size():
			var gain := float(mix[k])
			if gain <= 0.0:
				continue
			var layer := layers[k]
			for i in n * 2:
				out[i] += layer[i % n] * gain
		Synth.limit(out, 0.95)
		var path := _out.path_join("music_%s.wav" % AudioDirector.MUSIC_STATE_NAMES[state])
		Synth.to_stream(out).save_to_wav(path)
		print(path)
	quit()
