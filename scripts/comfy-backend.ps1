[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('start', 'stop', 'status')]
  [string]$Action
)

# Core controller for the LAN-mode ComfyUI backend (port 8189).
# Single entry point used by: the autostart scheduled task, the desktop
# start/stop .bat buttons, and the mode-switch tools. ASCII-only on purpose
# (Windows PowerShell 5.1 encoding safety).
# Master copy lives in this repo: scripts/comfy-backend.ps1

$Install    = 'H:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI'
$Shared     = 'H:\Comfy-Desktop\ComfyUI-Shared'
$Port       = 8189
$BackendLog = Join-Path $Shared 'comfy-backend.log'
$ControlLog = Join-Path $Shared 'comfy-backend-control.log'

function Write-Ctl([string]$Msg) {
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Msg
  Write-Output $line
  Add-Content -Path $ControlLog -Value $line -Encoding ASCII
}

function Get-BackendPid {
  $c = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue |
       Select-Object -First 1
  if ($c) { return [int]$c.OwningProcess }
  return 0
}

switch ($Action) {
  'start' {
    $pid0 = Get-BackendPid
    if ($pid0 -ne 0) {
      Write-Ctl "start: already running, PID $pid0, nothing to do"
      exit 0
    }
    $cmd = 'cmd /c cd /d ' + $Install +
           ' && .venv\Scripts\python.exe main.py --port ' + $Port +
           ' --input-directory ' + $Shared + '\input' +
           ' --output-directory ' + $Shared + '\output' +
           ' > ' + $BackendLog + ' 2>&1'
    $res = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{ CommandLine = $cmd }
    if ($res.ReturnValue -eq 0) {
      Write-Ctl "start: backend launched via WMI, PID $($res.ProcessId)"
      exit 0
    }
    Write-Ctl "start: FAILED, WMI ReturnValue=$($res.ReturnValue)"
    exit 1
  }
  'stop' {
    $pid0 = Get-BackendPid
    if ($pid0 -eq 0) {
      Write-Ctl 'stop: backend not running, nothing to do'
      exit 0
    }
    Stop-Process -Id $pid0 -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    if ((Get-BackendPid) -eq 0) {
      Write-Ctl "stop: backend PID $pid0 stopped"
      exit 0
    }
    Write-Ctl "stop: FAILED, PID $pid0 still listening on $Port"
    exit 1
  }
  'status' {
    $pid0 = Get-BackendPid
    if ($pid0 -ne 0) {
      Write-Ctl "status: RUNNING, PID $pid0, port $Port"
    } else {
      Write-Ctl 'status: STOPPED'
    }
    exit 0
  }
}
