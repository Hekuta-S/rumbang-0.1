extends SceneTree

## Sintetiza los sonidos de los golpes de la espalanza (assets/sfx/*.wav, 44,1 kHz):
##   swing_light  silbido corto y agudo (estocada)
##   swing_sweep  silbido de barrido, algo más largo (tajos horizontales)
##   swing_spin   silbido largo que da la vuelta (slash giratorio)
##   slam_boom    golpe sordo grave con cola de polvo (clavado del salto)
## Un silbido de arma es ruido de aire filtrado por una banda que sube y baja de tono mientras la hoja pasa,
## con una envolvente que crece y cae. Se usa semilla fija: los ficheros salen siempre iguales.
## Uso: godot --headless --path . --script res://tools/generate_swing_sfx.gd  (y luego --import)

const RATE := 44100
const OUT := "res://assets/sfx/"

var _rng := RandomNumberGenerator.new()

func _initialize() -> void:
	_rng.seed = 7351
	_write("swing_light", _whoosh(0.22, 900.0, 3400.0, 1200.0, 5.0, 0.9, 0.35))
	_write("swing_sweep", _whoosh(0.36, 600.0, 2600.0, 700.0, 3.5, 0.95, 0.45))
	_write("swing_spin", _mix(_whoosh(0.55, 500.0, 2200.0, 600.0, 2.6, 0.85, 0.5),
		_delay(_whoosh(0.30, 700.0, 2000.0, 500.0, 3.0, 0.45, 0.4), 0.22)))
	_write("slam_boom", _boom())
	print("Sonidos de golpe generados en ", OUT)
	quit(0)

## Ruido filtrado por una banda (biquad) cuyo centro va f0 → f_peak → f1. `q`: estrechez de la banda.
## `peak_at`: en qué fracción del sonido está el máximo (cuando la hoja pasa más cerca).
func _whoosh(dur: float, f0: float, f_peak: float, f1: float, q: float, vol: float, peak_at: float) -> PackedFloat32Array:
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in n:
		var k := float(i) / float(n)
		# Envolvente: sube rápido hasta el pico y cae con una curva suave
		var env := (k / peak_at) if k < peak_at else pow(1.0 - (k - peak_at) / (1.0 - peak_at), 1.8)
		env = env * env * (3.0 - 2.0 * env)
		var f := lerpf(f0, f_peak, k / peak_at) if k < peak_at else lerpf(f_peak, f1, (k - peak_at) / (1.0 - peak_at))
		# Coeficientes de un paso-banda (RBJ, ganancia de pico constante)
		var w0 := TAU * f / RATE
		var alpha := sin(w0) / (2.0 * q)
		var a0 := 1.0 + alpha
		var b0 := alpha / a0
		var b2 := -alpha / a0
		var a1 := -2.0 * cos(w0) / a0
		var a2 := (1.0 - alpha) / a0
		var x := _rng.randf_range(-1.0, 1.0)
		var y := b0 * x + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		out[i] = y * env * vol * 3.2
	return _normalize(out, vol)

## Golpe grave: seno que cae de tono + ruido de grava filtrado.
func _boom() -> PackedFloat32Array:
	var dur := 0.9
	var n := int(dur * RATE)
	var out := PackedFloat32Array()
	out.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := lerpf(95.0, 38.0, minf(t / 0.35, 1.0))
		phase += TAU * f / RATE
		var body := sin(phase) * exp(-t * 5.5)
		var click := (_rng.randf_range(-1.0, 1.0)) * exp(-t * 60.0) * 0.6
		lp = lerpf(lp, _rng.randf_range(-1.0, 1.0), 0.08)        # ruido grave (polvo y piedras)
		var rumble := lp * exp(-t * 3.0) * 1.8
		out[i] = body + click + rumble
	return _normalize(out, 0.95)

func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in s:
		m = maxf(m, absf(v))
	for i in s.size():
		s[i] = s[i] / m * peak
	return s

func _delay(s: PackedFloat32Array, seconds: float) -> PackedFloat32Array:
	var pad := int(seconds * RATE)
	var out := PackedFloat32Array()
	out.resize(pad + s.size())
	for i in s.size():
		out[pad + i] = s[i]
	return out

func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(a.size(), b.size()))
	for i in out.size():
		out[i] = clampf((a[i] if i < a.size() else 0.0) + (b[i] if i < b.size() else 0.0), -1.0, 1.0)
	return out

func _write(name: String, samples: PackedFloat32Array) -> void:
	var count := samples.size()
	var data := PackedByteArray()
	data.resize(44 + count * 2)
	for i in 4:
		data[i] = "RIFF".unicode_at(i)
		data[8 + i] = "WAVE".unicode_at(i)
		data[12 + i] = "fmt ".unicode_at(i)
		data[36 + i] = "data".unicode_at(i)
	data.encode_u32(4, 36 + count * 2)
	data.encode_u32(16, 16)
	data.encode_u16(20, 1)
	data.encode_u16(22, 1)
	data.encode_u32(24, RATE)
	data.encode_u32(28, RATE * 2)
	data.encode_u16(32, 2)
	data.encode_u16(34, 16)
	data.encode_u32(40, count * 2)
	for i in count:
		data.encode_s16(44 + i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var f := FileAccess.open(OUT + name + ".wav", FileAccess.WRITE)
	f.store_buffer(data)
