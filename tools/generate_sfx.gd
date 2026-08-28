extends SceneTree

## generate_sfx.gd — One-shot tool: synthesizes placeholder SFX as 16-bit
## PCM WAV files into res://assets/sfx/. Run with:
##   godot --headless --path . --script res://tools/generate_sfx.gd
## then re-import the project once (godot --headless --path . --import).

const SAMPLE_RATE: int = 22050
const SFX_DIR := "res://assets/sfx"

func _initialize() -> void:
	randomize()
	var root := DirAccess.open("res://")
	if root:
		root.make_dir_recursive("assets")
	root = DirAccess.open("res://assets/")
	if root:
		root.make_dir_recursive("sfx")
	_synth_all()
	print("SFX generated: ", SFX_DIR)
	quit(0)

# ── Synthesis helpers ────────────────────────────────────────────────────────

func _sine(freq: float, dur: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * decay)
		out[i] = sin(TAU * freq * t) * vol * env
	return out

func _square(freq: float, dur: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * decay)
		out[i] = (1.0 if sin(TAU * freq * t) >= 0.0 else -1.0) * vol * env * 0.5
	return out

func _saw(freq: float, dur: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * decay)
		out[i] = (2.0 * (freq * t - floor(freq * t + 0.5))) * vol * env * 0.6
	return out

func _sweep(f0: float, f1: float, dur: float, vol: float, shape: String, decay: float) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var prog := float(i) / maxf(float(n - 1), 1.0)
		var f := lerpf(f0, f1, prog)
		var env: float = exp(-t * decay)
		var v: float = 0.0
		match shape:
			"sine":
				v = sin(TAU * f * t)
			"square":
				v = 1.0 if sin(TAU * f * t) >= 0.0 else -1.0
				v *= 0.5
			"saw":
				v = 2.0 * (f * t - floor(f * t + 0.5)) * 0.6
		out[i] = v * vol * env
	return out

func _noise_burst(dur: float, vol: float, decay: float) -> PackedFloat32Array:
	var n := int(dur * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SAMPLE_RATE
		var env: float = exp(-t * decay)
		out[i] = (randf() * 2.0 - 1.0) * vol * env
	return out

func _delay(samples: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var pad := int(seconds * SAMPLE_RATE)
	var out := PackedFloat32Array()
	out.resize(pad + samples.size())
	for i in samples.size():
		out[pad + i] = samples[i]
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var size := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(size)
	for i in size:
		var va := a[i] if i < a.size() else 0.0
		var vb := b[i] if i < b.size() else 0.0
		out[i] = clampf(va + vb, -1.0, 1.0)
	return out

func _arpeggio(freqs: Array, step: float, dur: float, vol: float) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for i in freqs.size():
		var note := _sine(freqs[i], dur, vol, 10.0)
		result = _mix(result, _delay(note, float(i) * step))
	return result

func _put_chars(data: PackedByteArray, offset: int, text: String) -> void:
	for i in text.length():
		data[offset + i] = text.unicode_at(i)

func _write_wav(name: String, samples: PackedFloat32Array) -> void:
	var num_samples := samples.size()
	var data := PackedByteArray()
	data.resize(44 + num_samples * 2)
	_put_chars(data, 0, "RIFF")
	data.encode_u32(4, 36 + num_samples * 2)
	_put_chars(data, 8, "WAVE")
	_put_chars(data, 12, "fmt ")
	data.encode_u32(16, 16)
	data.encode_u16(20, 1)                  # PCM
	data.encode_u16(22, 1)                  # mono
	data.encode_u32(24, SAMPLE_RATE)
	data.encode_u32(28, SAMPLE_RATE * 2)
	data.encode_u16(32, 2)                  # block align
	data.encode_u16(34, 16)                 # bits per sample
	_put_chars(data, 36, "data")
	data.encode_u32(40, num_samples * 2)
	for i in num_samples:
		data.encode_s16(44 + i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(SFX_DIR + "/" + name + ".wav", FileAccess.WRITE)
	if f:
		f.store_buffer(data)
	else:
		push_warning("Could not write " + name)

func _synth_all() -> void:
	_write_wav("ui_click", _square(880.0, 0.06, 0.45, 22.0))
	_write_wav("ui_select", _mix(_square(660.0, 0.07, 0.4, 16.0), _delay(_square(990.0, 0.1, 0.4, 12.0), 0.06)))
	_write_wav("shoot_plasma", _sweep(1400.0, 350.0, 0.11, 0.5, "square", 16.0))
	_write_wav("shoot_shotgun", _noise_burst(0.16, 0.7, 22.0))
	_write_wav("shoot_railgun", _sweep(150.0, 2400.0, 0.3, 0.55, "saw", 5.0))
	_write_wav("shoot_bazooka", _mix(_sweep(180.0, 55.0, 0.3, 0.8, "sine", 5.0), _noise_burst(0.12, 0.5, 18.0)))
	_write_wav("melee_swing", _noise_burst(0.1, 0.4, 30.0))
	_write_wav("melee_heavy", _mix(_noise_burst(0.18, 0.55, 24.0), _sine(90.0, 0.2, 0.4, 8.0)))
	_write_wav("daggers_cut", _noise_burst(0.07, 0.35, 40.0))
	_write_wav("flamethrower", _mix(_noise_burst(0.35, 0.4, 12.0), _saw(95.0, 0.35, 0.3, 6.0)))
	_write_wav("spear_throw", _sweep(300.0, 900.0, 0.18, 0.5, "saw", 12.0))
	_write_wav("explosion", _mix(_noise_burst(0.5, 0.9, 10.0), _sweep(120.0, 40.0, 0.5, 0.7, "sine", 4.0)))
	_write_wav("hit", _noise_burst(0.05, 0.5, 40.0))
	_write_wav("enemy_die", _sweep(420.0, 90.0, 0.22, 0.5, "square", 10.0))
	_write_wav("player_hurt", _mix(_square(220.0, 0.14, 0.5, 12.0), _noise_burst(0.08, 0.3, 30.0)))
	_write_wav("dodge", _sweep(200.0, 700.0, 0.12, 0.4, "sine", 16.0))
	_write_wav("coin", _sine(1318.5, 0.1, 0.4, 14.0))
	_write_wav("pickup", _arpeggio([660.0, 880.0, 1320.0], 0.05, 0.09, 0.4))
	_write_wav("boss_sting", _mix(_sine(55.0, 0.7, 0.7, 2.5), _saw(440.0, 0.7, 0.3, 3.0)))
	_write_wav("victory", _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.09, 0.16, 0.42))
	_write_wav("gameover", _arpeggio([392.0, 349.23, 293.66, 220.0], 0.12, 0.2, 0.45))