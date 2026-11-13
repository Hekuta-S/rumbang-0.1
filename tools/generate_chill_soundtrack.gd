extends SceneTree

## Sintetiza los temas tranquilos: el del salón (hub, La menor, 78 BPM, lo-fi medieval) y el del patio del
## tutorial (patio, Do mayor, 100 BPM, más luminoso). Mismo método y misma familia de sonido que
## generate_soundtrack.gd (la mazmorra): pads de sierra filtrados, arpegio pulsado, bajo, reverb Schroeder y eco,
## pero sin el bombo con "sidechain" ni la caja: bombo suave, escobilla y shaker.
## Salida: assets/audio/hub_theme.wav / patio_theme.wav (estéreo, 32 kHz, 16 bits), 24 compases en bucle.
## Uso: godot --headless --path . --script res://tools/generate_chill_soundtrack.gd -- hub
##      godot --headless --path . --script res://tools/generate_chill_soundtrack.gd -- patio   (y luego --import)

const RATE := 32000
const BARS := 24

const CH := {
	"Am": [45, [57, 60, 64]], "F": [41, [53, 57, 60]], "C": [48, [55, 60, 64]], "G": [43, [55, 59, 62]],
	"Dm": [38, [57, 62, 65]], "E": [40, [56, 59, 64]], "Em": [40, [55, 59, 64]],
}

const THEMES := {
	"hub": {
		"out": "res://assets/audio/hub_theme.wav", "bpm": 78.0, "seed": 77,
		"prog": ["Am", "F", "C", "G", "Am", "F", "C", "G", "Am", "F", "C", "G",
			"Dm", "Am", "F", "E", "Dm", "Am", "F", "E",
			"Am", "F", "C", "G"],
		# 8 corcheas por compás, notas de [MIDI, corcheas]
		"melody": [
			[[74, 3], [72, 1], [69, 4]], [[72, 2], [76, 2], [74, 2], [72, 2]],
			[[69, 4], [72, 2], [74, 2]], [[71, 3], [68, 1], [71, 4]],
			[[74, 2], [77, 2], [76, 2], [74, 2]], [[72, 4], [69, 4]],
			[[72, 3], [74, 1], [76, 4]], [[76, 2], [74, 2], [71, 4]],
		],
		"arp_pattern": [0, 1, 2, 3, 2, 1, 2, 1], "arp_step": 2, "lp_pad": 1000.0, "kick": 0.28, "shaker": 0.05,
	},
	"patio": {
		"out": "res://assets/audio/patio_theme.wav", "bpm": 100.0, "seed": 4242,
		"prog": ["C", "G", "Am", "F", "C", "G", "Am", "F", "C", "G", "Am", "F",
			"F", "G", "Em", "Am", "F", "G", "C", "C",
			"C", "G", "Am", "F"],
		"melody": [
			[[72, 3], [69, 1], [72, 4]], [[71, 2], [74, 2], [71, 2], [67, 2]],
			[[76, 2], [74, 2], [71, 4]], [[72, 4], [69, 2], [72, 2]],
			[[77, 2], [76, 2], [72, 2], [69, 2]], [[74, 3], [71, 1], [67, 4]],
			[[72, 2], [76, 2], [79, 4]], [[76, 6], [72, 2]],
		],
		"arp_pattern": [0, 2, 1, 3, 2, 3, 1, 2], "arp_step": 2, "lp_pad": 1400.0, "kick": 0.36, "shaker": 0.08,
	},
}

var cfg: Dictionary
var beat := 0.0
var bar := 0.0
var n := 0
var prog: Array
var L := PackedFloat32Array()
var R := PackedFloat32Array()
var rev_send := PackedFloat32Array()
var dly_send := PackedFloat32Array()
var duck := PackedFloat32Array()
var rng := RandomNumberGenerator.new()

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var theme: String = args[0] if args.size() > 0 else "hub"
	if not THEMES.has(theme):
		push_error("Tema desconocido: " + theme)
		quit(1)
		return
	cfg = THEMES[theme]
	prog = cfg["prog"]
	beat = 60.0 / float(cfg["bpm"])
	bar = beat * 4.0
	rng.seed = int(cfg["seed"])
	n = int(bar * BARS * RATE)
	for buf in [L, R, rev_send, dly_send]:
		buf.resize(n)
	duck.resize(n)
	duck.fill(1.0)
	print("Generando '", theme, "': ", BARS, " compases, %.1f s…" % (float(n) / RATE))
	_drums()
	_bass()
	_pads()
	_arp()
	_lead()
	_apply_delay()
	_apply_reverb()
	_master()
	_write_wav()
	print("Escrito en ", cfg["out"])
	quit(0)

static func freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

func _idx(t: float) -> int:
	return int(t * RATE)

func _put(i: int, v: float, pan: float, ducked: bool) -> void:
	if i < 0 or i >= n:
		return
	if ducked:
		v *= duck[i]
	L[i] += v * (1.0 - maxf(pan, 0.0))
	R[i] += v * (1.0 + minf(pan, 0.0))

# ───────────────────────────── Ritmo ─────────────────────────────

func _drums() -> void:
	for b in BARS:
		if b < 4 or b >= 20:
			continue
		var t0 := b * bar
		for q in 4:
			var t := t0 + q * beat
			if q == 0 or q == 2:
				_kick(t)
			if q == 1 or q == 3:
				_brush(t)
			for s in 2:
				_shaker(t + s * beat / 2.0, float(cfg["shaker"]) * (1.0 if s == 0 else 0.6))

func _kick(t: float) -> void:
	var i0 := _idx(t)
	var ph := 0.0
	for k in int(0.35 * RATE):
		var tt := float(k) / RATE
		ph += TAU * (48.0 + 70.0 * exp(-tt * 30.0)) / RATE
		_put(i0 + k, sin(ph) * exp(-tt * 9.0) * float(cfg["kick"]), 0.0, false)
	for k in int(beat * RATE):
		var i := i0 + k
		if i < n:
			duck[i] = minf(duck[i], 1.0 - 0.25 * exp(-float(k) / RATE * 8.0))

func _brush(t: float) -> void:
	var i0 := _idx(t)
	var prev := 0.0
	for k in int(0.18 * RATE):
		var tt := float(k) / RATE
		var nz := rng.randf_range(-1, 1)
		var hp := nz - prev
		prev = nz
		var v := hp * exp(-tt * 18.0) * 0.07
		_put(i0 + k, v, 0.1, false)
		if i0 + k < n:
			rev_send[i0 + k] += v * 0.4

func _shaker(t: float, vol: float) -> void:
	var i0 := _idx(t)
	var prev := 0.0
	for k in int(0.05 * RATE):
		var tt := float(k) / RATE
		var nz := rng.randf_range(-1, 1)
		var hp := nz - prev
		prev = nz
		_put(i0 + k, hp * vol * exp(-tt * 55.0), 0.3, false)

# ───────────────────────────── Bajo ─────────────────────────────

func _bass() -> void:
	for b in range(2, BARS):
		var root: int = CH[prog[b]][0]
		var t0 := b * bar
		_bass_note(t0, beat * 1.9, root)
		if b >= 4 and b < 20:
			_bass_note(t0 + 2.0 * beat, beat * 1.4, root)
			_bass_note(t0 + 3.5 * beat, beat * 0.45, root + 12)

func _bass_note(t: float, dur: float, m: int) -> void:
	var i0 := _idx(t)
	var f := freq(m)
	var ph := 0.0
	for k in int(dur * RATE):
		var tt := float(k) / RATE
		ph = fmod(ph + f / RATE, 1.0)
		var s := sin(TAU * ph) * 0.8 + sin(TAU * ph * 2.0) * 0.12
		var env := minf(tt / 0.02, 1.0) * minf(1.0, (dur - tt) / 0.08) * exp(-tt * 0.9)
		_put(i0 + k, s * env * 0.26, 0.0, true)

# ───────────────────────────── Pads ─────────────────────────────

func _pads() -> void:
	for b in BARS:
		var notes: Array = CH[prog[b]][1]
		for m in notes:
			_pad_note(b * bar, bar * 1.05, int(m), 0.085)

func _pad_note(t: float, dur: float, m: int, vol: float) -> void:
	var i0 := _idx(t)
	var f := freq(m)
	var p := [0.0, 0.0, 0.0, 0.0]
	var det := [0.996, 1.0, 1.003, 1.007]
	var lpl := 0.0
	var lpr := 0.0
	var a := 1.0 - exp(-TAU * float(cfg["lp_pad"]) / RATE)
	for k in int(dur * RATE):
		var tt := float(k) / RATE
		var sl := 0.0
		var sr := 0.0
		for v in 4:
			p[v] = fmod(p[v] + f * det[v] / RATE, 1.0)
			var s: float = p[v] * 2.0 - 1.0
			if v % 2 == 0:
				sl += s
			else:
				sr += s
		lpl += (sl - lpl) * a
		lpr += (sr - lpr) * a
		var env := minf(tt / 0.6, 1.0) * minf(1.0, (dur - tt) / 0.4)
		var i := i0 + k
		if i >= n:
			break
		var d := duck[i]
		L[i] += lpl * env * vol * d
		R[i] += lpr * env * vol * d
		rev_send[i] += (lpl + lpr) * env * vol * 0.7

# ───────────────────────────── Arpegio pulsado ─────────────────────────────

func _arp() -> void:
	var pattern: Array = cfg["arp_pattern"]
	var step: int = cfg["arp_step"]       # semicorcheas por nota (2 = corcheas)
	for b in BARS:
		if b >= 22:
			continue
		var notes: Array = CH[prog[b]][1]
		var tones := [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
		var vol := 0.55 if b < 4 else 1.0
		var i := 0
		for s in range(0, 16, step):
			var t := b * bar + s * beat / 4.0
			_pluck(t, beat * 1.6, int(tones[pattern[i % pattern.size()]]), vol, -0.3 if i % 2 == 0 else 0.3)
			i += 1

func _pluck(t: float, dur: float, m: int, vol: float, pan: float) -> void:
	var i0 := _idx(t)
	var f := freq(m)
	var ph := 0.0
	var ph2 := 0.0
	for k in int(dur * RATE):
		var tt := float(k) / RATE
		ph = fmod(ph + f / RATE, 1.0)
		ph2 = fmod(ph2 + f * 2.0 / RATE, 1.0)
		var tri := absf(ph * 4.0 - 2.0) - 1.0
		var v := (tri * 0.7 + sin(TAU * ph2) * 0.25 * exp(-tt * 8.0)) * exp(-tt * 4.5) * minf(tt / 0.004, 1.0) * 0.14 * vol
		_put(i0 + k, v, pan, true)
		if i0 + k < n:
			dly_send[i0 + k] += v * 0.7
			rev_send[i0 + k] += v * 0.3

# ───────────────────────────── Melodía ─────────────────────────────

func _lead() -> void:
	var phrase: Array = cfg["melody"]
	for bi in phrase.size():
		var t := (12 + bi) * bar
		for note in phrase[bi]:
			var d: float = float(note[1]) * beat / 2.0
			_lead_note(t, d * 0.95, int(note[0]), 0.13)
			t += d

func _lead_note(t: float, dur: float, m: int, vol: float) -> void:
	var i0 := _idx(t)
	var f := freq(m)
	var ph := 0.0
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 1800.0 / RATE)
	for k in int((dur + 0.4) * RATE):
		var tt := float(k) / RATE
		var vib := 1.0 + 0.003 * sin(TAU * 5.0 * tt) * minf(tt / 0.5, 1.0)
		ph = fmod(ph + f * vib / RATE, 1.0)
		var s := (absf(ph * 4.0 - 2.0) - 1.0) * 0.7 + sin(TAU * ph) * 0.3
		lp += (s - lp) * a
		var env := minf(tt / 0.04, 1.0) * (1.0 if tt < dur else maxf(0.0, 1.0 - (tt - dur) / 0.4))
		var v := lp * env * vol
		_put(i0 + k, v, 0.0, false)
		if i0 + k < n:
			dly_send[i0 + k] += v * 0.5
			rev_send[i0 + k] += v * 0.6

# ───────────────────────────── Efectos ─────────────────────────────

func _apply_delay() -> void:
	var d := int(beat * 0.75 * RATE)
	var bl := PackedFloat32Array()
	var br := PackedFloat32Array()
	bl.resize(n)
	br.resize(n)
	var lp_l := 0.0
	var lp_r := 0.0
	for i in n:
		var inl := dly_send[i] + (br[i - d] * 0.45 if i >= d else 0.0)
		var inr := (bl[i - d] * 0.45 if i >= d else 0.0)
		lp_l += (inl - lp_l) * 0.3
		lp_r += (inr - lp_r) * 0.3
		bl[i] = lp_l
		br[i] = lp_r
		L[i] += bl[i] * 0.6
		R[i] += br[i] * 0.6
		rev_send[i] += (bl[i] + br[i]) * 0.15

func _apply_reverb() -> void:
	var outs := []
	for ch in 2:
		var combs := [1557, 1617, 1491, 1422] if ch == 0 else [1601, 1557, 1453, 1381]
		var acc := PackedFloat32Array()
		acc.resize(n)
		for c in combs:
			var dl: int = int(c * RATE / 44100.0 * 1.8)
			var buf := PackedFloat32Array()
			buf.resize(dl)
			var pos := 0
			var damp := 0.0
			for i in n:
				var y := buf[pos]
				damp = y * 0.6 + damp * 0.4
				buf[pos] = rev_send[i] + damp * 0.86
				pos = (pos + 1) % dl
				acc[i] += y
		for ap in ([556, 441] if ch == 0 else [579, 427]):
			var dl2: int = int(ap * RATE / 44100.0)
			var b2 := PackedFloat32Array()
			b2.resize(dl2)
			var p2 := 0
			for i in n:
				var bufout := b2[p2]
				var x := acc[i]
				b2[p2] = x + bufout * 0.5
				acc[i] = bufout - x
				p2 = (p2 + 1) % dl2
		outs.append(acc)
	for i in n:
		L[i] += outs[0][i] * 0.1
		R[i] += outs[1][i] * 0.1

func _master() -> void:
	var peak := 0.0001
	for i in n:
		L[i] = tanh(L[i] * 1.2)
		R[i] = tanh(R[i] * 1.2)
		peak = maxf(peak, maxf(absf(L[i]), absf(R[i])))
	var g := 0.85 / peak
	var fade := int(0.01 * RATE)
	for i in n:
		var e := 1.0
		if i < fade:
			e = float(i) / fade
		elif i > n - fade:
			e = float(n - i) / fade
		L[i] *= g * e
		R[i] *= g * e

func _write_wav() -> void:
	var data := PackedByteArray()
	data.resize(44 + n * 4)
	for i in 4:
		data[i] = "RIFF".unicode_at(i)
		data[8 + i] = "WAVE".unicode_at(i)
		data[12 + i] = "fmt ".unicode_at(i)
		data[36 + i] = "data".unicode_at(i)
	data.encode_u32(4, 36 + n * 4)
	data.encode_u32(16, 16)
	data.encode_u16(20, 1)
	data.encode_u16(22, 2)
	data.encode_u32(24, RATE)
	data.encode_u32(28, RATE * 4)
	data.encode_u16(32, 4)
	data.encode_u16(34, 16)
	data.encode_u32(40, n * 4)
	for i in n:
		data.encode_s16(44 + i * 4, int(clampf(L[i], -1.0, 1.0) * 32767.0))
		data.encode_s16(46 + i * 4, int(clampf(R[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(cfg["out"], FileAccess.WRITE)
	f.store_buffer(data)
