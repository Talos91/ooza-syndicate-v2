extends SceneTree
## Decodes every assets/audio/sfx/**.ogg through Godot's own Vorbis playback (mix_audio) and saves a 16-bit WAV
## at the AudioServer's mix rate (mix_audio resamples to it) next to it (or into --out=<dir>, mirrored paths) - no external tools.
func _init() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var root := "res://assets/audio/sfx/"
	var n := 0
	for sub in DirAccess.get_directories_at(root):
		for f in DirAccess.get_files_at(root + sub):
			if not f.ends_with(".ogg"):
				continue
			var st: AudioStreamOggVorbis = load(root + sub + "/" + f)
			var rate := int(AudioServer.get_mix_rate())      # mix_audio resamples to the server's rate, whatever the file's
			var frames := int(ceil(st.get_length() * rate)) + 64
			var pb: AudioStreamPlayback = st.instantiate_playback()
			pb.start(0.0)
			var buf: PackedVector2Array = pb.mix_audio(1.0, frames)
			pb.stop()
			# trim the silent tail past the stream's length (mix pads with zeros)
			var last := buf.size() - 1
			while last > 0 and absf(buf[last].x) < 1e-4 and absf(buf[last].y) < 1e-4:
				last -= 1
			var stereo := false
			var peak := 0.0
			for i in range(last + 1):
				if absf(buf[i].x - buf[i].y) > 1e-3:
					stereo = true
				peak = maxf(peak, maxf(absf(buf[i].x), absf(buf[i].y)))
			var w := AudioStreamWAV.new()
			w.format = AudioStreamWAV.FORMAT_16_BITS
			w.mix_rate = rate
			w.stereo = stereo
			var data := PackedByteArray()
			data.resize((last + 1) * 2 * (2 if stereo else 1))
			var o := 0
			for i in range(last + 1):
				var l := int(clampf(buf[i].x, -1.0, 1.0) * 32767.0)
				data.encode_s16(o, l); o += 2
				if stereo:
					data.encode_s16(o, int(clampf(buf[i].y, -1.0, 1.0) * 32767.0)); o += 2
			w.data = data
			var dst := (out + "/" + sub + "/" + f.get_basename() + ".wav") if out != "" else (root + sub + "/" + f.get_basename() + ".wav")
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			var err := w.save_to_wav(dst)
			print("%s -> %s  %d Hz %s %.2fs peak %.2f err %d" % [sub + "/" + f, dst.get_file(), rate, "stereo" if stereo else "mono", float(last + 1) / rate, peak, err])
			n += 1
	print("converted ", n)
	quit()
