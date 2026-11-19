<#
  setup-windows.ps1  --  One-shot Windows setup for the
  "Mac + AI assistant remotely operate this Windows PC" kit.

  What it configures (idempotent, safe to re-run):
    1. OpenSSH Server installed, auto-start, assistant public key installed
    2. Remote Desktop (RDP) enabled with NLA; firewall scoped to LAN + Tailnet
    3. Optional dedicated local RDP account (default: rdp)
    4. ComfyUI LAN backend (optional): model junctions, portproxy 8188->8189,
       firewall rules, backend autostart + watchdog scheduled tasks,
       desktop tools copied to the Public Desktop

  Usage (in an ADMIN PowerShell, from the folder containing this script):
    powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
  Optional parameters:
    -SshPublicKey "ssh-ed25519 AAAA... assistant"   (otherwise you are prompted)
    -RdpUser rdp                                     (dedicated RDP account name)
    -SkipRdpUser                                     (do not create the account)
    -SkipComfy                                       (skip all ComfyUI parts)
    -ComfyInstall "H:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI"
    -ComfyShared  "H:\Comfy-Desktop\ComfyUI-Shared"

  ASCII-only on purpose (Windows PowerShell 5.1 encoding safety).
  Full step-by-step guide and troubleshooting: see docs/setup-guide.md
  shipped with this kit.
#>
[CmdletBinding()]
param(
  [string]$SshPublicKey = '',
  [string]$RdpUser = 'rdp',
  [switch]$SkipRdpUser,
  [switch]$SkipComfy,
  [string]$ComfyInstall = 'H:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI',
  [string]$ComfyShared  = 'H:\Comfy-Desktop\ComfyUI-Shared'
)

$ErrorActionPreference = 'Stop'
$TailnetRange = '100.64.0.0/10'

function Step([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
function Ok([string]$t)   { Write-Host "  [OK] $t" -ForegroundColor Green }
function Warn([string]$t) { Write-Host "  [!!] $t" -ForegroundColor Yellow }
function Info([string]$t) { Write-Host "  $t" }

# --- 0. Must be elevated -------------------------------------------------
Step '0. Administrator check'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
         ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) {
  Warn 'Not elevated. Relaunching as administrator...'
  Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
  exit
}
Ok 'Running as administrator'

# --- 1. OpenSSH Server ----------------------------------------------------
Step '1. OpenSSH Server'
$cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($cap.State -ne 'Installed') {
  Info 'Installing OpenSSH Server (needs internet, may take a few minutes)...'
  Add-WindowsCapability -Online -Name $cap.Name | Out-Null
}
Set-Service sshd -StartupType Automatic
Start-Service sshd -ErrorAction SilentlyContinue
Ok 'sshd installed, auto-start, running'

if (-not $SshPublicKey) {
  Info 'Paste the ASSISTANT public key (one line, starts with ssh-ed25519 or ssh-rsa).'
  Info 'Get it from the assistant: it is the .pub file of its SSH key pair.'
  $SshPublicKey = Read-Host 'Public key (leave empty to skip)'
}
if ($SshPublicKey) {
  # The account running this script is expected to be an administrator,
  # whose keys live in the administrators_authorized_keys file.
  $keyFile = "$env:ProgramData\ssh\administrators_authorized_keys"
  if (-not (Test-Path $keyFile) -or -not (Select-String -Path $keyFile -SimpleMatch $SshPublicKey -Quiet)) {
    Add-Content -Path $keyFile -Value $SshPublicKey -Encoding ascii
  }
  icacls $keyFile /inheritance:r /grant 'SYSTEM:F' /grant 'Administrators:F' | Out-Null
  Ok "Public key installed in $keyFile"
} else {
  Warn 'No public key given - SSH key login not configured (see doc section 3).'
}

# --- 2. Remote Desktop -----------------------------------------------------
Step '2. Remote Desktop (RDP) + firewall scoping'
$ts = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
Set-ItemProperty $ts -Name fDenyTSConnections -Value 0
Set-ItemProperty "$ts\WinStations\RDP-Tcp" -Name UserAuthentication -Value 1
Set-Service TermService -StartupType Automatic
Start-Service TermService -ErrorAction SilentlyContinue
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction SilentlyContinue |
  Get-NetFirewallAddressFilter |
  Set-NetFirewallAddressFilter -RemoteAddress @('LocalSubnet', $TailnetRange)
Ok 'RDP on, NLA on, firewall limited to LAN + Tailnet (100.64.0.0/10). No public exposure.'

# --- 3. Dedicated RDP account ----------------------------------------------
if (-not $SkipRdpUser) {
  Step "3. Dedicated RDP account '$RdpUser'"
  $exists = Get-LocalUser -Name $RdpUser -ErrorAction SilentlyContinue
  if (-not $exists) {
    Info "Create local account '$RdpUser'. Choose its password now"
    Info '(type it here on THIS machine - never send it in chat).'
    $pw = Read-Host 'Password for the new account' -AsSecureString
    New-LocalUser -Name $RdpUser -Password $pw -PasswordNeverExpires -AccountNeverExpires | Out-Null
    Ok "Account '$RdpUser' created"
  } else {
    Ok "Account '$RdpUser' already exists"
  }
  foreach ($sid in 'S-1-5-32-544', 'S-1-5-32-555') {  # Administrators, Remote Desktop Users
    $grp = Get-LocalGroup -SID $sid
    if (-not (Get-LocalGroupMember -Group $grp.Name -Member $RdpUser -ErrorAction SilentlyContinue)) {
      Add-LocalGroupMember -Group $grp.Name -Member $RdpUser
    }
  }
  Ok "'$RdpUser' is in Administrators + Remote Desktop Users"
  Info 'Why a dedicated account: a Microsoft-account main user cannot log in'
  Info 'to RDP with a PIN, and its password is your Microsoft password -'
  Info 'do not type that into other machines. Use this local account instead.'
}

# --- 4. ComfyUI backend ------------------------------------------------------
if (-not $SkipComfy) {
  Step '4. ComfyUI LAN backend'
  if (-not (Test-Path "$ComfyInstall\main.py")) {
    Warn "ComfyUI not found at $ComfyInstall - skipping ComfyUI parts."
    Warn 'Re-run with -ComfyInstall pointing at your ComfyUI folder, or see doc section 5.'
  } else {
    # 4a. Model junctions: a manually started backend only sees the install
    #     models folder, while ComfyUI Desktop keeps models in Shared.
    #     Junction the four big folders to Shared so both see one copy.
    foreach ($d in 'diffusion_models', 'loras', 'vae', 'text_encoders') {
      $m = Join-Path "$ComfyInstall\models" $d
      $t = Join-Path "$ComfyShared\models" $d
      if (-not (Test-Path $t)) { Warn "Shared target missing, skipped: $t"; continue }
      $isJunction = $false
      if (Test-Path $m) {
        $isJunction = [bool]((Get-Item $m -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
      }
      if (-not $isJunction) {
        if (Test-Path $m) {
          $bak = "$m`_bak"
          if (Test-Path $bak) { $bak = "$m`_old_$((Get-Date).ToString('HHmmss'))" }
          Rename-Item $m $bak
        }
        New-Item -ItemType Junction -Path $m -Target $t | Out-Null
        Ok "Junction: $d -> Shared"
      } else { Ok "Junction already in place: $d" }
    }
    # 4b. Core controller script to Shared\tools
    $coreSrc = Join-Path $PSScriptRoot 'comfy-backend.ps1'
    $coreDst = Join-Path $ComfyShared 'tools\comfy-backend.ps1'
    New-Item -ItemType Directory -Force (Split-Path $coreDst) | Out-Null
    if (Test-Path $coreSrc) { Copy-Item $coreSrc $coreDst -Force; Ok 'comfy-backend.ps1 -> Shared\tools' }
    else { Warn "comfy-backend.ps1 not found next to this script - copy it manually to $coreDst" }
    # NOTE: comfy-backend.ps1 has Install/Shared paths baked in at the top.
    # If your ComfyUI lives elsewhere, edit those two lines after copying.
    # 4c. portproxy 8188 -> 8189 (8188 cannot be bound by the backend itself
    #     when IP Helper owns it; the backend listens on 8189, proxy on 8188)
    netsh interface portproxy delete v4tov4 listenport=8188 listenaddress=0.0.0.0 2>$null | Out-Null
    netsh interface portproxy add v4tov4 listenport=8188 listenaddress=0.0.0.0 connectport=8189 connectaddress=127.0.0.1 | Out-Null
    Ok 'portproxy 8188 -> 127.0.0.1:8189'
    # 4d. Firewall: LAN on 8188, Tailnet on 8188
    foreach ($r in @(
      @{ N = 'ComfyUI-LAN';     A = 'LocalSubnet' },
      @{ N = 'ComfyUI-Tailnet'; A = $TailnetRange })) {
      if (-not (Get-NetFirewallRule -DisplayName $r.N -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $r.N -Direction Inbound -Protocol TCP -LocalPort 8188 `
          -RemoteAddress $r.A -Action Allow | Out-Null
      }
    }
    Ok 'Firewall rules ComfyUI-LAN / ComfyUI-Tailnet (TCP 8188)'
    # 4e. Scheduled tasks: autostart at logon + watchdog every 5 minutes
    $me = "$env:USERDOMAIN\$env:USERNAME"
    $act = New-ScheduledTaskAction -Execute 'powershell.exe' `
      -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$coreDst`" -Action start"
    $trg = New-ScheduledTaskTrigger -AtLogOn -User $me
    Register-ScheduledTask -TaskName 'ComfyUI-Backend-Autostart' -Action $act -Trigger $trg `
      -Principal (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest) -Force | Out-Null
    $trg2 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
      -RepetitionInterval (New-TimeSpan -Minutes 5)
    Register-ScheduledTask -TaskName 'ComfyUI-Backend-Watchdog' -Action $act -Trigger $trg2 `
      -Principal (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Highest) -Force | Out-Null
    Ok 'Scheduled tasks: ComfyUI-Backend-Autostart + ComfyUI-Backend-Watchdog (5 min)'
    # 4f. Desktop tools to the Public Desktop (visible to every account)
    $pub = "$env:PUBLIC\Desktop"
    foreach ($f in 'comfy-backend.ps1') { } # core stays in Shared\tools, not on the desktop
    Get-ChildItem $PSScriptRoot -Filter *.bat -ErrorAction SilentlyContinue |
      ForEach-Object { Copy-Item $_.FullName (Join-Path $pub $_.Name) -Force }
    Ok 'Desktop .bat tools copied to the Public Desktop'
    Info 'Keep the MASTER copies with this kit; after any edit, re-copy and verify.'
  }
}

# --- 5. Summary ---------------------------------------------------------------
Step 'Done - what remains manual (see the configuration document)'
$tsExe = "$env:ProgramFiles\Tailscale\tailscale.exe"
if (Test-Path $tsExe) {
  $ip = (& $tsExe ip -4 2>$null | Select-Object -First 1)
  Info "This PC's Tailnet IP: $ip"
} else {
  Warn 'Tailscale not detected. Install it and sign in on BOTH machines (doc section 2).'
}
Info '1) Tailscale: install + sign in with the SAME account on Windows and Mac.'
Info '2) Mac: install Microsoft "Windows App", add this PC by its Tailnet IP,'
Info '   sign in with the dedicated local account, save the credential and BIND'
Info '   it in the PC settings (Credentials dropdown), trust the certificate.'
Info '3) Mac Windows App -> PC settings -> Folders: redirect one folder for'
Info '   file transfer (direct file copy/paste between the desktops is unreliable).'
Info '4) ComfyUI in browser: LAN http://<this PC LAN IP>:8188 ; away: http://<Tailnet IP>:8188'
Write-Host "`nSetup finished." -ForegroundColor Cyan
