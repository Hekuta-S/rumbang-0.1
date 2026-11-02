# Arranca el servidor dedicado de Rumbang en este PC y lo publica en internet con un túnel de Cloudflare
# (gratis, sin cuenta y sin abrir puertos del router). Si existe la versión web (build/web), también la sirve
# y da un único enlace para compartir: al abrirlo, el juego ya trae la dirección del servidor.
#
# Requisitos:
#   - Godot 4.7.x (la variable de entorno GODOT con la ruta del ejecutable *_console.exe, o en Descargas)
#   - cloudflared:   winget install --id Cloudflare.cloudflared
#   - Python (solo para servir la versión web)
#
# Uso: doble clic en "Servidor online.bat" (o: powershell -ExecutionPolicy Bypass -File tools\online\servidor_online.ps1)
# Para cerrarlo todo: Enter en esta ventana.

param(
	[int]$Port = 45680,
	[int]$WebPort = 8060
)

$ErrorActionPreference = "Stop"
$Project = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$Logs = Join-Path $env:TEMP "rumbang_online"
New-Item -ItemType Directory -Force $Logs | Out-Null

function Find-Godot {
	if ($env:GODOT -and (Test-Path $env:GODOT)) { return $env:GODOT }
	$found = Get-ChildItem -Path (Join-Path $env:USERPROFILE "Downloads") -Filter "Godot_v4.7*_console.exe" -Recurse -Depth 2 -ErrorAction SilentlyContinue |
		Sort-Object Name -Descending | Select-Object -First 1
	if ($found) { return $found.FullName }
	$cmd = Get-Command godot -ErrorAction SilentlyContinue
	if ($cmd) { return $cmd.Source }
	return $null
}

# Espera a que cloudflared escriba su dirección pública (https://algo.trycloudflare.com) en el registro.
function Wait-TunnelUrl([string]$log) {
	for ($i = 0; $i -lt 60; $i++) {
		Start-Sleep -Milliseconds 500
		if (Test-Path $log) {
			$m = Select-String -Path $log -Pattern "https://[a-z0-9-]+\.trycloudflare\.com" -AllMatches | Select-Object -First 1
			if ($m) { return $m.Matches[0].Value }
		}
	}
	return $null
}

$godot = Find-Godot
if (-not $godot) {
	Write-Host "No encuentro Godot. Pon la ruta de Godot_v4.7.x_console.exe en la variable GODOT." -ForegroundColor Red
	exit 1
}
$cloudflared = Get-Command cloudflared -ErrorAction SilentlyContinue
$procs = @()

Write-Host "Servidor: $godot"
$procs += Start-Process -FilePath $godot -ArgumentList "--headless", "--path", "`"$Project`"", "--", "--server", "--port=$Port" `
	-RedirectStandardOutput "$Logs\server.log" -RedirectStandardError "$Logs\server.err" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3
if ($procs[0].HasExited) {
	Write-Host "El servidor no arrancó. Mira $Logs\server.err" -ForegroundColor Red
	exit 1
}
Write-Host "Servidor escuchando en ws://localhost:$Port" -ForegroundColor Green
$lan = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notmatch "^(127|169\.254)\." } | Select-Object -First 1).IPAddress
if ($lan) { Write-Host "En tu wifi también vale:  $lan" }

$serverHost = $null
if ($cloudflared) {
	Remove-Item "$Logs\tunnel_ws.log" -ErrorAction SilentlyContinue
	$procs += Start-Process -FilePath $cloudflared.Source -ArgumentList "tunnel", "--no-autoupdate", "--url", "http://localhost:$Port" `
		-RedirectStandardError "$Logs\tunnel_ws.log" -RedirectStandardOutput "$Logs\tunnel_ws.out" -PassThru -WindowStyle Hidden
	$url = Wait-TunnelUrl "$Logs\tunnel_ws.log"
	if ($url) {
		$serverHost = $url.Substring(8)
		Write-Host ""
		Write-Host "Dirección del servidor (para el menú Multijugador):" -ForegroundColor Cyan
		Write-Host "    $serverHost" -ForegroundColor Yellow
	} else {
		Write-Host "El túnel no respondió. Mira $Logs\tunnel_ws.log" -ForegroundColor Red
	}
} else {
	Write-Host ""
	Write-Host "No está cloudflared: el servidor solo se ve en tu red local." -ForegroundColor Yellow
	Write-Host "Para jugar por internet instálalo con:  winget install --id Cloudflare.cloudflared"
}

# Versión web servida desde este PC (si se exportó a build/web)
$web = Join-Path $Project "build\web"
$python = Get-Command python -ErrorAction SilentlyContinue
if ((Test-Path (Join-Path $web "index.html")) -and $python) {
	$procs += Start-Process -FilePath $python.Source -ArgumentList "`"$PSScriptRoot\serve_web.py`"", "`"$web`"", "$WebPort" `
		-RedirectStandardOutput "$Logs\web.log" -RedirectStandardError "$Logs\web.err" -PassThru -WindowStyle Hidden
	Write-Host ""
	Write-Host "Versión web en este PC: http://localhost:$WebPort" -ForegroundColor Green
	if ($cloudflared -and $serverHost) {
		Remove-Item "$Logs\tunnel_web.log" -ErrorAction SilentlyContinue
		$procs += Start-Process -FilePath $cloudflared.Source -ArgumentList "tunnel", "--no-autoupdate", "--url", "http://localhost:$WebPort" `
			-RedirectStandardError "$Logs\tunnel_web.log" -RedirectStandardOutput "$Logs\tunnel_web.out" -PassThru -WindowStyle Hidden
		$webUrl = Wait-TunnelUrl "$Logs\tunnel_web.log"
		if ($webUrl) {
			Write-Host ""
			Write-Host "ENLACE PARA COMPARTIR (abre el juego ya conectado a tu servidor):" -ForegroundColor Cyan
			Write-Host "    $webUrl/?server=$serverHost" -ForegroundColor Yellow
		}
	}
}

Write-Host ""
Write-Host "Registros en $Logs. Pulsa Enter para cerrar el servidor y los túneles."
[void](Read-Host)
foreach ($p in $procs) {
	if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
}
Write-Host "Cerrado."
