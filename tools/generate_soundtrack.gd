extends SceneTree

## Sintetiza el tema de la mazmorra: darksynth / synthwave oscuro (estilo Katana Zero), en bucle.
## Sale a assets/audio/dungeon_theme.wav (estéreo, 32 kHz, 16 bits) y dura 32 compases a 112 BPM (~69 s).
##
## Estructura (un acorde por compás, La menor):
##   0-3   intro: pads y arpegio con el filtro abriéndose
##   4-11  A: batería, bajo pulsante a semicorcheas, arpegio con eco      Am F C G ×2
##   12-19 B: melodía principal                                           Dm Am F E ×2
##   20-23 puente: sin bombo, pads y arpegio, subida de ruido al final   F G Am Am
##   24-31 A': todo, con la melodía en notas largas y agudas             Am F C G ×2
## Bombo a negras con "sidechain" (bajo, pads y arpegio se agachan con cada bombo), caja con reverb cortada
## (gated) en 2 y 4, charles a corcheas. Eco ping-pong y una reverb sencilla (Schroeder) en un envío.
## Semilla fija: el fichero sale siempre igual.
## Uso: godot --headless --path . --script res://tools/generate_soundtrack.gd  (y luego --import)

const RATE := 32000
const BPM := 112.0
const BARS := 32
const OUT := "res://assets/audio/dungeon_theme.wav"

var beat := 60.0 / BPM
var bar := beat * 4.0
var n := 0
var L := PackedFloat32Array()
var R := PackedFloat32Array()
var rev_send := PackedFloat32Array()      # envío mono a la reverb
var dly_send := PackedFloat32Array()      # envío mono al eco
var duck := PackedFloat32Array()          # ganancia del sidechain (1 = sin agachar)
var rng := RandomNumberGenerator.new()

# Acordes: [bajo, notas del pad] (MIDI)
const CH := {
	"Am": [45, [57, 60, 64]], "F": [41, [53, 57, 60]], "C": [48, [55, 60, 64]], "G": [43, [55, 59, 62]],
	"Dm": [38, [57, 62, 65]], "E": [40, [56, 59, 64]],
}
const PROG := ["Am", "F", "C", "G", "Am", "F", "C", "G", "Am", "F", "C", "G",
	"Dm", "Am", "F", "E", "Dm", "Am", "F", "E",
	"F", "G", "Am", "Am",
	"Am", "F", "C", "G", "Am", "F", "C", "G"]
# Melodía de B (compases 12-19): [nota, corcheas]; 8 corcheas por compás
const MELODY_B := [
	[[69, 2], [72, 2], [74, 3], [76, 1]],
	[[76, 4], [72, 2], [69, 2]],
	[[77, 3], [76, 1], [72, 2], [69, 2]],
	[[71, 4], [68, 2], [76, 2]],
	[[77, 2], [76, 2], [74, 2], [72, 2]],
	[[76, 3], [74, 1], [72, 2], [71, 2]],
	[[81, 4], [79, 2], [77, 2]],
	[[76, 6], [74, 1], [71, 1]],
]
# Melodía de A' (24-31): notas largas
const MELODY_A2 := [
	[[81, 8]], [[77, 6], [76, 2]], [[79, 8]], [[74, 4], [76, 4]],
	[[81, 6], [84, 2]], [[77, 4], [76, 2], [74, 2]], [[79, 6], [76, 2]], [[74, 4], [71, 2], [69, 2]],
]

func _initialize() -> void:
	rng.seed = 2024
	n = int(bar * BARS * RATE)
	for buf in [L, R, rev_send, dly_send]:
		buf.resize(n)
	duck.resize(n)
	duck.fill(1.0)
	print("Generando tema: ", BARS, " compases, ", "%.1f" % (float(n) / RATE), " s…")
	_drums()
	_bass()
	_pads()
	_arp()
	_lead()
	_riser(20 * 4 * beat + 3 * bar, bar)
	_apply_delay()
	_apply_reverb()
	_master()
	_write_wav()
	print("Tema escrito en ", OUT)
	quit(0)

# ───────────────────────────── Utilidades ─────────────────────────────

static func freq(m: float) -> float:
	return 440.0 * pow(2.0, (m - 69.0) / 12.0)

func _idx(t: float) -> int:
	return int(t * RATE)

## Suma una muestra a L/R con paneo (-1 izquierda … 1 derecha) y ganancia de sidechain opcional.
func _put(i: int, v: float, pan: float, ducked: bool) -> void:
	if i < 0 or i >= n:
		return
	if ducked:
		v *= duck[i]
	L[i] += v * (1.0 - maxf(pan, 0.0))
	R[i] += v * (1.0 + minf(pan, 0.0))

# ───────────────────────────── Batería ─────────────────────────────

func _drums() -> void:
	for b in BARS:
		var t0 := b * bar
		var full := b >= 4 and not (b >= 20 and b < 24)
		var hats := b >= 4
		for q in 4:
			var t := t0 + q * beat
			if full:
				_kick(t)
				if q == 1 or q == 3:
					_snare(t)
			if hats:
				var steps := 4 if b >= 24 else 2
				for s in steps:
					_hat(t + s * beat / steps, 0.10 if s % 2 == 0 else 0.06, s % 2 == 1 and steps == 2)
		# Redoble de caja antes de cada sección
		if b in [3, 11, 19, 23]:
			for k in 4:
				_snare(t0 + 3.0 * beat + k * beat / 4.0, 0.5 + 0.12 * k)

func _kick(t: float) -> void:
	var i0 := _idx(t)
	var len := int(0.42 * RATE)
	var ph := 0.0
	for k in len:
		var tt := float(k) / RATE
		var f := 45.0 + 110.0 * exp(-tt * 28.0)
		ph += TAU * f / RATE
		var v := sin(ph) * exp(-tt * 6.5) * 0.95 + (rng.randf_range(-1, 1) * exp(-tt * 300.0)) * 0.15
		_put(i0 + k, tanh(v * 1.6) * 0.5, 0.0, false)
	# Sidechain: todo lo demás se agacha y vuelve en ~0,25 s
	for k in int(beat * RATE):
		var i := i0 + k
		if i < n:
			duck[i] = minf(duck[i], 1.0 - 0.7 * exp(-float(k) / RATE * 9.0))

func _snare(t: float, vel: float = 1.0) -> void:
	var i0 := _idx(t)
	var len := int(0.32 * RATE)
	var ph := 0.0
	var hp_prev := 0.0
	for k in len:
		var tt := float(k) / RATE
		ph += TAU * 190.0 / RATE
		var body := sin(ph) * exp(-tt * 22.0) * 0.5
		var nz := rng.randf_range(-1, 1)
		var hp := nz - hp_prev      # ruido más brillante
		hp_prev = nz
		# Reverb "cortada": la cola de ruido se sostiene y se corta de golpe (sonido de los 80)
		var gate := 1.0 if tt < 0.2 else maxf(0.0, 1.0 - (tt - 0.2) / 0.03)
		var tail := hp * 0.35 * exp(-tt * 4.0) * gate
		var snap := hp * exp(-tt * 40.0) * 0.6
		var v := (body + tail + snap) * 0.42 * vel
		_put(i0 + k, v, 0.0, false)
		if i0 + k < n:
			rev_send[i0 + k] += v * 0.35

func _hat(t: float, vol: float, open: bool) -> void:
	var i0 := _idx(t)
	var len := int((0.12 if open else 0.035) * RATE)
	var prev := 0.0
	for k in len:
		var tt := float(k) / RATE
		var nz := rng.randf_range(-1, 1)
		var hp := nz - prev
		prev = nz
		_put(i0 + k, hp * vol * exp(-tt * (18.0 if open else 90.0)), 0.25, false)

# ───────────────────────────── Bajo ─────────────────────────────

func _bass() -> void:
	for b in range(4, BARS):
		var root: int = CH[PROG[b]][0]
		var t0 := b * bar
		var sparse := b >= 20 and b < 24
		for s in 16:
			if sparse and s % 4 != 0:
				continue
			var octave := 12 if (s % 4 == 2 and not sparse) else 0
			_bass_note(t0 + s * beat / 4.0, beat / 4.0 * (3.6 if sparse else 0.92), root + octave)

func _bass_note(t: float, dur: float, m: int) -> void:
	var i0 := _idx(t)
	var len := int(dur * RATE)
	var f := freq(m)
	var ph1 := 0.0
	var ph2 := 0.0
	var lp := 0.0
	for k in len:
		var tt := float(k) / RATE
		ph1 = fmod(ph1 + f / RATE, 1.0)
		ph2 = fmod(ph2 + f * 1.006 / RATE, 1.0)
		var saw := (ph1 * 2.0 - 1.0) * 0.6 + (ph2 * 2.0 - 1.0) * 0.4
		var sub := sin(TAU * ph1) * 0.3
		var cutoff := 300.0 + 2200.0 * exp(-tt * 18.0)
		var a := 1.0 - exp(-TAU * cutoff / RATE)
		lp += (saw - lp) * a
		var env := minf(tt / 0.003, 1.0) * (1.0 if tt < dur - 0.01 else maxf(0.0, (dur - tt) / 0.01))
		_put(i0 + k, (lp + sub) * env * 0.2, 0.0, true)

# ───────────────────────────── Pads ─────────────────────────────

func _pads() -> void:
	for b in BARS:
		var notes: Array = CH[PROG[b]][1]
		var vol := 0.075 if (b < 4 or (b >= 20 and b < 24)) else 0.065
		for m in notes:
			_pad_note(b * bar, bar * 1.02, int(m), vol)

func _pad_note(t: float, dur: float, m: int, vol: float) -> void:
	var i0 := _idx(t)
	var len := int(dur * RATE)
	var f := freq(m)
	var p := [0.0, 0.0, 0.0, 0.0]
	var det := [0.994, 1.0, 1.004, 1.009]
	var lpl := 0.0
	var lpr := 0.0
	var a := 1.0 - exp(-TAU * 1500.0 / RATE)
	for k in len:
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
		var env := minf(tt / 0.25, 1.0) * minf(1.0, (dur - tt) / 0.2)
		var i := i0 + k
		if i >= n:
			break
		var d := duck[i]
		L[i] += lpl * env * vol * d
		R[i] += lpr * env * vol * d
		rev_send[i] += (lpl + lpr) * env * vol * 0.6

# ───────────────────────────── Arpegio ─────────────────────────────

func _arp() -> void:
	var pattern := [0, 1, 2, 3, 2, 1, 2, 3]
	for b in BARS:
		var notes: Array = CH[PROG[b]][1]
		var tones := [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[0] + 24]
		for s in 16:
			var t := b * bar + s * beat / 4.0
			# Filtro: en la intro se va abriendo; en el puente se cierra un poco
			var bright := 1.0
			if b < 4:
				bright = 0.15 + 0.85 * (float(b * 16 + s) / 64.0)
			elif b >= 20 and b < 24:
				bright = 0.55
			_arp_note(t, beat / 4.0 * 0.8, int(tones[pattern[s % 8]]), bright, -0.35 if s % 2 == 0 else 0.35)

func _arp_note(t: float, dur: float, m: int, bright: float, pan: float) -> void:
	var i0 := _idx(t)
	var len := int(dur * RATE)
	var f := freq(m)
	var ph := 0.0
	var lp := 0.0
	var cutoff := 600.0 + 5200.0 * bright
	var a := 1.0 - exp(-TAU * cutoff / RATE)
	for k in len:
		var tt := float(k) / RATE
		ph = fmod(ph + f / RATE, 1.0)
		var sq := 1.0 if ph < 0.35 else -1.0             # pulso estrecho, tono "chiptune" oscuro
		lp += (sq - lp) * a
		var v := lp * exp(-tt * 14.0) * 0.14
		_put(i0 + k, v, pan, true)
		if i0 + k < n:
			dly_send[i0 + k] += v * 0.8

# ───────────────────────────── Melodía ─────────────────────────────

func _lead() -> void:
	_lead_phrase(12, MELODY_B, 0.16, 0.0)
	_lead_phrase(24, MELODY_A2, 0.13, 0.0)

func _lead_phrase(first_bar: int, phrase: Array, vol: float, _shift: float) -> void:
	for bi in phrase.size():
		var t := (first_bar + bi) * bar
		for note in phrase[bi]:
			var d: float = float(note[1]) * beat / 2.0
			_lead_note(t, d * 0.95, int(note[0]), vol)
			t += d

func _lead_note(t: float, dur: float, m: int, vol: float) -> void:
	var i0 := _idx(t)
	var len := int((dur + 0.25) * RATE)
	var f := freq(m)
	var p1 := 0.0
	var p2 := 0.0
	var lp := 0.0
	var a := 1.0 - exp(-TAU * 2600.0 / RATE)
	for k in len:
		var tt := float(k) / RATE
		var vib := 1.0 + 0.004 * sin(TAU * 5.5 * tt) * minf(tt / 0.4, 1.0)
		p1 = fmod(p1 + f * vib / RATE, 1.0)
		p2 = fmod(p2 + f * vib * 1.0058 / RATE, 1.0)
		var s := (p1 * 2.0 - 1.0) * 0.55 + (1.0 if p2 < 0.5 else -1.0) * 0.35
		lp += (s - lp) * a
		var env := minf(tt / 0.015, 1.0) * (1.0 if tt < dur else maxf(0.0, 1.0 - (tt - dur) / 0.25))
		var v := lp * env * vol
		_put(i0 + k, v, 0.0, false)
		if i0 + k < n:
			dly_send[i0 + k] += v * 0.5
			rev_send[i0 + k] += v * 0.5

## Subida de ruido filtrado antes de la última sección.
func _riser(t: float, dur: float) -> void:
	var i0 := _idx(t)
	var len := int(dur * RATE)
	var lp := 0.0
	for k in len:
		var x := float(k) / len
		var a := 1.0 - exp(-TAU * (300.0 + 7000.0 * x * x) / RATE)
		lp += (rng.randf_range(-1, 1) - lp) * a
		var v := lp * x * x * 0.22
		_put(i0 + k, v, sin(x * 12.0) * 0.5, false)
		if i0 + k < n:
			rev_send[i0 + k] += v * 0.4

# ───────────────────────────── Efectos ─────────────────────────────

## Eco ping-pong a corchea con puntillo.
func _apply_delay() -> void:
	var d := int(beat * 0.75 * RATE)
	var bl := PackedFloat32Array()
	var br := PackedFloat32Array()
	bl.resize(n)
	br.resize(n)
	var lp_l := 0.0
	var lp_r := 0.0
	for i in n:
		var inl := dly_send[i] + (br[i - d] * 0.42 if i >= d else 0.0)
		var inr := (bl[i - d] * 0.42 if i >= d else 0.0)
		lp_l += (inl - lp_l) * 0.35
		lp_r += (inr - lp_r) * 0.35
		bl[i] = lp_l
		br[i] = lp_r
		L[i] += bl[i] * 0.6
		R[i] += br[i] * 0.6
		rev_send[i] += (bl[i] + br[i]) * 0.15

## Reverb Schroeder: 4 filtros peine en paralelo y 2 pasa-todo, con tiempos distintos por canal.
func _apply_reverb() -> void:
	var outs := []
	for ch in 2:
		var combs := [1557, 1617, 1491, 1422] if ch == 0 else [1601, 1557, 1453, 1381]
		var acc := PackedFloat32Array()
		acc.resize(n)
		for c in combs:
			var dl: int = int(c * RATE / 44100.0 * 1.6)
			var buf := PackedFloat32Array()
			buf.resize(dl)
			var pos := 0
			var damp := 0.0
			for i in n:
				var y := buf[pos]
				damp = y * 0.6 + damp * 0.4
				buf[pos] = rev_send[i] + damp * 0.84
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
		L[i] += outs[0][i] * 0.09
		R[i] += outs[1][i] * 0.09

## Saturación suave y normalización a -1 dB. El bucle empieza y acaba en silencio relativo (sin chasquido).
func _master() -> void:
	var peak := 0.0001
	for i in n:
		L[i] = tanh(L[i] * 1.3)
		R[i] = tanh(R[i] * 1.3)
		peak = maxf(peak, maxf(absf(L[i]), absf(R[i])))
	var g := 0.89 / peak
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
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_buffer(data)
