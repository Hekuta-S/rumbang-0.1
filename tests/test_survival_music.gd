extends Node

## Música adaptativa de supervivencia (SurvivalMusic): las 4 capas existen, duran lo mismo y hacen bucle,
## el arranque solo tiene la base (chill) y las capas entran en orden hasta sonar todas (hard).
var _fail := false
var _n := 0

func _check(ok: bool, msg: String) -> void:
	_n += 1
	print("CHECK %d %s: %s" % [_n, "PASSED" if ok else "FAILED", msg])
	if not ok:
		_fail = true

func _wait(secs: float) -> void:
	await get_tree().create_timer(secs).timeout

func _ready() -> void:
	_check(SurvivalMusic.available(), "las 4 pistas están importadas")
	var lens: Array[float] = []
	var loops := true
	for p in SurvivalMusic.STEMS:
		var s: AudioStreamWAV = load(p)
		lens.append(s.get_length())
		loops = loops and s.loop_mode == AudioStreamWAV.LOOP_FORWARD
	_check(loops, "todas las capas hacen bucle")
	_check(lens.max() - lens.min() < 0.01, "todas las capas duran lo mismo (%s)" % str(lens))

	var w0 := SurvivalMusic.layer_weights(0.0, false)
	_check(w0 == ([1.0, 0.0, 0.0, 0.0] as Array[float]), "al empezar solo suena la base chill (%s)" % str(w0))
	_check(SurvivalMusic.layer_db(1, w0) <= SurvivalMusic.SILENT_DB, "las capas sin entrar están en silencio")
	var prev := 1.0
	var ordered := true
	var t := 0.0
	while t <= 400.0:
		var w := SurvivalMusic.layer_weights(t, false)
		var e := 0.0
		for x in w:
			e += x
		ordered = ordered and e >= prev - 0.0001
		prev = e
		t += 5.0
	_check(ordered, "la intensidad nunca baja con el tiempo")
	var w3 := SurvivalMusic.layer_weights(320.0, false)
	_check(w3 == ([1.0, 1.0, 1.0, 1.0] as Array[float]), "a los 5:20 suenan las 4 capas (hard)")
	var mid := SurvivalMusic.layer_weights(170.0, false)
	_check(mid[1] == 1.0 and mid[2] > 0.0 and mid[2] < 1.0 and mid[3] == 0.0, "a los 2:50 entra el drive (%s)" % str(mid))
	_check(SurvivalMusic.layer_weights(10.0, true) == ([1.0, 1.0, 1.0, 1.0] as Array[float]), "modo infinito: todo a tope")
	_check(SurvivalMusic.layer_db(0, w0) > SurvivalMusic.layer_db(0, w3), "el arranque chill se compensa en volumen")

	# En marcha: al empezar solo se decodifica la base; con el tiempo entran las demás alineadas con ella
	var gs := GameState.get_instance()
	gs.elapsed_time = 0.0
	var mus := SurvivalMusic.new()
	add_child(mus)
	mus.play()
	await _wait(1.0)
	_check(mus.active_layers() == 1, "al empezar solo se decodifica 1 capa (%d)" % mus.active_layers())
	gs.elapsed_time = 330.0
	await _wait(4.0)
	_check(mus.active_layers() == 4, "a los 5:30 suenan las 4 capas (%d)" % mus.active_layers())
	var base := mus.players[0].get_playback_position()
	var worst := 0.0
	for p in mus.players:
		var d := absf(p.get_playback_position() - base)
		worst = maxf(worst, minf(d, mus._length - d))
	_check(base > 0.5 and worst <= SurvivalMusic.MAX_DRIFT, "las capas van sincronizadas con la base (base %.2f s, desfase %.3f s)" % [base, worst])
	gs.elapsed_time = 0.0
	await _wait(5.0)
	_check(mus.active_layers() == 1, "al volver a calma las capas mudas se paran (%d)" % mus.active_layers())
	mus.stop()
	print("ALL PASSED" if not _fail else "SOME FAILED")
	get_tree().quit(1 if _fail else 0)
