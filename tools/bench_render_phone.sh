#!/usr/bin/env bash
# Bisección del render en el celular (calidad guardada en el dispositivo, APK de debug instalado).
# Uso: bash tools/bench_render_phone.sh [salida.txt]. Cada línea: opciones del banco | FPS | reparto del frame.
ADB="${ADB:-C:/Users/cabeu/AppData/Local/Android/Sdk/platform-tools/adb.exe}"
OUT="${1:-bench_render.txt}"; : > "$OUT"
run(){ "$ADB" shell "run-as com.example.rumbang sh -c 'echo \"$1\" > files/bench.txt'"; "$ADB" shell am force-stop com.example.rumbang; sleep 2; "$ADB" logcat -c
  "$ADB" shell monkey -p com.example.rumbang -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  for i in $(seq 1 35); do sleep 4; "$ADB" logcat -d | grep -q "RESUMEN" && break; done
  "$ADB" logcat -d > /tmp/rb.txt
  r=$(grep "RESUMEN" /tmp/rb.txt | sed 's/.*RESUMEN //' | grep -oE "fps_medio=[0-9.]+ fps_min=[0-9.]+|draws_medio=[0-9]+" | tr '\n' ' ')
  f=$(grep "\[FRAME\]" /tmp/rb.txt | tail -n +2 | grep -oE "frame=[0-9.]+|física=[0-9.]+|proceso=[0-9.]+|resto=[0-9.]+" | awk -F= '{s[$1]+=$2; n[$1]++} END{for(k in s) printf "%s=%.1f ", k, s[k]/n[k]}')
  echo "$1 | $r | $f" | tee -a "$OUT"; }
B="420 20 u pc s=0.5"
run "$B"; run "420 20 u pc s=0.25"; run "$B h=ground"; run "$B h=hud"; run "$B h=env_tone"; run "$B h=enemies"
run "$B h=props"; run "$B h=lights,sun"; run "$B h=env,lights,sun,ground,props,enemies,hud,critters,player"; run "$B"
"$ADB" shell "run-as com.example.rumbang rm -f files/bench.txt"; "$ADB" shell am force-stop com.example.rumbang
"$ADB" shell dumpsys battery | grep -E "level|temperature" | tee -a "$OUT"
