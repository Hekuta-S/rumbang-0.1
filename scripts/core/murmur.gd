class_name Murmur
extends RefCounted

## "Voz" de balbuceo para los subtítulos (sin doblaje): sílabas sintetizadas con dos formantes de vocal
## sobre una onda glotal, con la entonación de la frase. Cada personaje tiene su timbre (VOICES).
## El resultado se cachea por texto y voz.

const RATE := 22050
const HARMONICS := 10
## tono base (Hz), variación de tono, aspereza (ruido), segundos por letra
const VOICES := {
	"rey": {"pitch": 105.0, "range": 0.22, "rough": 0.05, "speed": 0.04, "gain": 0.55},
	"mago": {"pitch": 165.0, "range": 0.3, "rough": 0.12, "speed": 0.04, "gain": 0.45},
}
## formantes (F1, F2) de a, e, i, o, u
const VOWELS := [[750.0, 1250.0], [500.0, 1900.0], [320.0, 2300.0], [500.0, 900.0], [350.0, 750.0]]

static var _cache: Dictionary = {}
static var _mutex := Mutex.new()

## Lo ya generado (o null si aún no está: prepare() lo genera en un hilo).
static func cached(text: String, voice: String) -> AudioStreamWAV:
	_mutex.lock()
	var w: AudioStreamWAV = _cache.get(voice + "|" + text)
	_mutex.unlock()
	return w

## Genera en segundo plano las voces de [[voz, texto], ...].
static func prepare(lines: Array) -> void:
	WorkerThreadPool.add_task(func():
		for l in lines:
			make(String(l[1]), String(l[0]))
	)

static func make(text: String, voice: String) -> AudioStreamWAV:
	var key := voice + "|" + text
	var hit := cached(text, voice)
	if hit:
		return hit
	var v: Dictionary = VOICES.get(voice, VOICES["rey"])
	var rnd := RandomNumberGenerator.new()
	rnd.seed = hash(key)
	var total := maxf(0.5, text.length() * float(v["speed"]))
	var n := int(total * RATE)
	var data := PackedByteArray()
	data.resize(n * 2)
	var ask := text.ends_with("?")
	var shout := text.ends_with("!")
	# sílabas: una cada ~3 letras, con pausa en los signos de puntuación
	var syl: Array[Dictionary] = []
	var t := 0.0
	var i := 0
	while i < text.length():
		var ch := text[i]
		if ch in ",.;:":
			t += 0.12
			i += 1
			continue
		if ch in " ¡¿!?":
			i += 1
			continue
		var d := rnd.randf_range(0.085, 0.14)
		syl.append({"t": t, "d": d, "vow": rnd.randi_range(0, VOWELS.size() - 1), "p": rnd.randf_range(-1.0, 1.0)})
		t += d + rnd.randf_range(0.0, 0.025)
		i += 3
	var scale_t := total / maxf(t, 0.01)
	var phase := 0.0
	var lp := 0.0
	var f1s := 0.0
	var f2s := 0.0
	var k := 0
	var weights := PackedFloat32Array()
	weights.resize(HARMONICS)
	for s in range(n):
		var time := float(s) / RATE
		# sílaba activa
		while k < syl.size() - 1 and time > (float(syl[k]["t"]) + float(syl[k]["d"])) * scale_t:
			k += 1
		var amp := 0.0
		var vow: Array = VOWELS[0]
		var pv := 0.0
		if not syl.is_empty():
			var sy: Dictionary = syl[k]
			var st := float(sy["t"]) * scale_t
			var sd := float(sy["d"]) * scale_t
			var u := (time - st) / sd
			if u >= 0.0 and u <= 1.0:
				amp = sin(PI * u) ** 0.6
			vow = VOWELS[int(sy["vow"])]
			pv = float(sy["p"])
		var prog := time / total
		var contour := 1.0 + float(v["range"]) * (0.35 * pv - 0.25 * prog)
		if ask and prog > 0.75:
			contour += (prog - 0.75) * 1.6
		if shout:
			contour += 0.12 * sin(prog * PI)
		var f0 := float(v["pitch"]) * contour * (1.0 + 0.015 * sin(time * 31.0))
		phase = fmod(phase + f0 / RATE, 1.0)
		# formantes suavizados entre sílabas
		f1s = lerpf(f1s, float(vow[0]), 0.004) if f1s > 0.0 else float(vow[0])
		f2s = lerpf(f2s, float(vow[1]), 0.004) if f2s > 0.0 else float(vow[1])
		# suma de armónicos pesados por la envolvente de formantes (los pesos se recalculan cada 64 muestras)
		if s % 64 == 0:
			for h in range(1, HARMONICS + 1):
				var fh := f0 * h
				weights[h - 1] = exp(-pow((fh - f1s) / 180.0, 2.0)) + 0.6 * exp(-pow((fh - f2s) / 260.0, 2.0)) + 0.08 / h
		var smp := 0.0
		if amp > 0.0:
			for h in range(HARMONICS):
				smp += weights[h] * sin(TAU * phase * (h + 1))
		smp += rnd.randf_range(-1.0, 1.0) * float(v["rough"])
		lp = lerpf(lp, smp, 0.6)
		var out := clampf(lp * amp * float(v["gain"]) * 0.22, -1.0, 1.0)
		data.encode_s16(s * 2, int(out * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	_mutex.lock()
	_cache[key] = w
	_mutex.unlock()
	return w
