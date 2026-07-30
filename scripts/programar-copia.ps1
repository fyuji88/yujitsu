# ============================================================
#  Deja programada la copia semanal
#
#    powershell -ExecutionPolicy Bypass -File scripts\programar-copia.ps1
#
#  Crea una tarea de Windows que corre `scripts/copia.sh` todos los domingos a
#  las 20:00 — justo después del open mat, cuando ya está registrado lo de la
#  semana.
#
#  NO HACE FALTA SER ADMINISTRADOR: la tarea se registra para el usuario
#  actual, que es lo que se puede hacer en un portátil corporativo.
#
#  `-StartWhenAvailable` importa más de lo que parece: si el domingo a las
#  20:00 el portátil está apagado —que es lo normal—, la tarea se ejecuta la
#  próxima vez que se encienda en vez de perderse. Sin eso, la copia se salta
#  las semanas en que más falta haría.
# ============================================================

$ErrorActionPreference = 'Stop'

$raiz  = Split-Path -Parent $PSScriptRoot
$bash  = 'C:\Program Files\Git\bin\bash.exe'
$tarea = 'yujitsu-copia-semanal'

if (-not (Test-Path $bash)) {
  Write-Error "No encuentro bash en $bash. Ajusta la ruta en este script."
}

$accion   = New-ScheduledTaskAction -Execute $bash `
              -Argument "-lc 'cd ""$($raiz -replace '\\','/')"" && scripts/copia.sh'"
$cuando   = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 20:00
$ajustes  = New-ScheduledTaskSettingsSet -StartWhenAvailable `
              -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries `
              -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $tarea -Action $accion -Trigger $cuando `
  -Settings $ajustes -Description 'Copia semanal de la base de yujitsu' -Force | Out-Null

Write-Host "Programada '$tarea': domingos a las 20:00."
Write-Host "  Comprobarla:  Get-ScheduledTask -TaskName $tarea"
Write-Host "  Lanzarla ya:  Start-ScheduledTask -TaskName $tarea"
Write-Host "  Quitarla:     Unregister-ScheduledTask -TaskName $tarea -Confirm:`$false"
