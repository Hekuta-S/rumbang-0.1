# Graba una toma de supervivencia jugada a mano en vertical y la deja lista como reel 1080x1920.
#   powershell -ExecutionPolicy Bypass -File tools/reel_play.ps1 [-Name toma1] [-Seconds 30] [-FromMin 2] [-Shot play|loadout]
# -Shot loadout: el arsenal cambia cada 10 s (3 armas por tramo, LOADOUTS en tests/reel_shot.gd).
# -Shot random: cada -LoadoutS s (20 por defecto) sortea 4 armas al azar. -Day: luz de día aunque -FromMin sea alto.
#   Ej.: tools/reel_play.ps1 -Name random60 -Seconds 60 -FromMin 5 -Shot random -Day
# Movie Maker graba al tamaño base del proyecto (ignora --resolution y cambiar la ventana): mientras graba se pone
# un override.cfg temporal (base 1080x1920, ventana 540x960) que se borra al terminar.
# Se abre el juego en una ventana vertical 540x960: juegas, a los -Seconds s de control se cierra solo.
# Movie Maker graba cada fotograma (con audio) en reel/raw/<Name>.avi; se recorta la carga y se reescala a
# reel/<Name>.mp4 (H.264 + AAC, 30 fps).
param(
	[string]$Name = ("play_" + (Get-Date -Format "MMdd_HHmmss")),
	[float]$Seconds = 30,
	[float]$FromMin = 2,
	[string]$Shot = "play",
	[float]$LoadoutS = 0,
	[switch]$Day
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$godot = "C:\Users\cabeu\Downloads\Godot_v4.7.1-stable_win64.exe\Godot_v4.7.1-stable_win64_console.exe"
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { throw "No se encuentra ffmpeg en el PATH" }
$raw = Join-Path $root "reel\raw\$Name.avi"
$out = Join-Path $root "reel\$Name.mp4"
$log = Join-Path $env:TEMP "reel_play_$Name.log"

$env:REEL_SIZE = ""
$env:REEL_SECONDS = "$Seconds"
$env:REEL_FROM_MIN = "$FromMin"
$env:REEL_LOADOUT_S = if ($LoadoutS -gt 0) { "$LoadoutS" } else { "" }
$env:REEL_DAY = if ($Day) { "1" } else { "" }
Write-Host "Abriendo el juego: tienes $Seconds s desde que aparece el personaje."
$override = Join-Path $root "override.cfg"
if (Test-Path $override) { throw "Ya existe ${override} (no se toca)" }
Set-Content -Path $override -Encoding ascii -Value @("[display]", "window/size/viewport_width=1080", "window/size/viewport_height=1920",
	"window/size/window_width_override=540", "window/size/window_height_override=960")
try {
$p = Start-Process -FilePath $godot -Wait -PassThru -NoNewWindow -RedirectStandardOutput $log -RedirectStandardError "$log.err" `
	-ArgumentList @("--path", "`"$root`"", "--write-movie", "`"$raw`"", "--fixed-fps", "30", "res://tests/reel_shot.tscn", "--", $Shot)
} finally {
	Remove-Item $override -Confirm:$false
}

$startLine = Select-String -Path $log -Pattern "REEL_START=(\d+)" | Select-Object -First 1
if (-not $startLine) { throw "La toma no llegó a empezar (ver $log)" }
$startFrame = [int]$startLine.Matches[0].Groups[1].Value
$ss = [math]::Round($startFrame / 30.0, 3)
Write-Host "Recortando la carga ($ss s) y reescalando a 1080x1920..."
& $ffmpeg -y -v error -ss $ss -i $raw -t $Seconds -vf "scale=1080:1920:force_original_aspect_ratio=increase:flags=lanczos,crop=1080:1920" `
	-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -r 30 -c:a aac -b:a 192k -movflags +faststart $out
Write-Host "Listo: $out"
