#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$CheckOnly,
    [switch]$DownloadOnly,
    [ValidateSet('none', 'codex', 'claude', 'pi', 'antigravity')]
    [string]$Runtime = 'none',
    [ValidateRange(0, 4096)]
    [double]$MinimumRamGiB = 0,
    [ValidateRange(0, 4096)]
    [double]$MinimumVramGiB = 0,
    [ValidateRange(-1, 255)]
    [int]$GpuIndex = -1
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$version = '0.1.6'
$asset = "Linger-$version-windows-x64-setup.exe"
$sha256 = 'abb37f58143bf1bbd77e616d498ecc45388e44d4bd8aa76deb0e4eb66ce2be54'
$release = "https://github.com/simplexai-labs/linger/releases/download/desktop-v$version"

if ($CheckOnly -and $DownloadOnly) { throw 'Choose one check or download mode.' }
if (($CheckOnly -or $DownloadOnly) -and $Runtime -ne 'none') {
    throw '-Runtime is available in install mode.'
}
if (-not $CheckOnly -and ($MinimumRamGiB -gt 0 -or $MinimumVramGiB -gt 0 -or $GpuIndex -ge 0)) {
    throw 'Memory thresholds and GPU selection require -CheckOnly.'
}
if ($env:OS -ne 'Windows_NT') { throw 'Run this script on the target Windows computer.' }

$os = Get-CimInstance -ClassName Win32_OperatingSystem
$cpu = @(Get-CimInstance -ClassName Win32_Processor)
if ($os.ProductType -ne 1 -or [int]$os.BuildNumber -lt 22000 -or
    -not [Environment]::Is64BitOperatingSystem -or $cpu.Count -eq 0 -or $cpu[0].Architecture -ne 9) {
    throw 'This Linger release requires Windows 11 x64.'
}

function Get-NvidiaMemory {
    $tool = Get-Command nvidia-smi.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    $candidates = @()
    if ($tool) { $candidates += $tool.Source }
    $candidates += (Join-Path $env:SystemRoot 'System32\nvidia-smi.exe')
    $candidates += (Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe')
    $smi = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    if (-not $smi) { return }

    $query = '--query-gpu=index,name,driver_version,memory.total,memory.free'
    $output = @(& $smi $query '--format=csv,noheader,nounits' 2>$null)
    if ($LASTEXITCODE -ne 0) { return }
    foreach ($line in $output) {
        if ($line -match '^\s*(\d+)\s*,\s*([^,]+)\s*,\s*([^,]+)\s*,\s*(\d+)\s*,\s*(\d+)\s*$') {
            [pscustomobject]@{
                Index = [int]$Matches[1]
                GPU = $Matches[2].Trim()
                Driver = $Matches[3].Trim()
                TotalGiB = [double]$Matches[4] / 1024
                FreeGiB = [double]$Matches[5] / 1024
            }
        }
    }
}

if ($CheckOnly) {
    $windows = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    Write-Host "$($os.Caption) $($windows.DisplayVersion) (build $($os.BuildNumber).$($windows.UBR))"
    $cpu | ForEach-Object { Write-Host "CPU: $($_.Name)" }
    $modules = Get-CimInstance -ClassName Win32_PhysicalMemory -ErrorAction SilentlyContinue
    $installed = ($modules | Measure-Object -Property Capacity -Sum).Sum
    $perf = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
    $available = if ($null -ne $perf) { [double]$perf.AvailableBytes / 1GB } else { [double]$os.FreePhysicalMemory / 1MB }
    if ($installed) { Write-Host ('Physical RAM installed: {0:F2} GiB' -f ($installed / 1GB)) }
    Write-Host ('OS-visible RAM: {0:F2} GiB' -f ($os.TotalVisibleMemorySize / 1MB))
    Write-Host ('RAM available: {0:F2} GiB' -f $available)
    Get-CimInstance -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' |
        Select-Object DeviceID, @{n='FreeGiB';e={ '{0:F2}' -f ($_.FreeSpace / 1GB) }} |
        Format-Table -AutoSize | Out-Host

    $gpus = @(Get-NvidiaMemory)
    if ($gpus.Count -gt 0) {
        $gpus | Format-Table -AutoSize | Out-Host
    } else {
        Get-CimInstance -ClassName Win32_VideoController | Select-Object Name, DriverVersion | Format-Table -AutoSize | Out-Host
        Write-Warning 'Dedicated VRAM measurement is unavailable. Check the NVIDIA driver and nvidia-smi.'
    }

    $shortfall = $false
    if ($available -lt $MinimumRamGiB) {
        Write-Warning ('RAM shortfall: {0:F2} GiB.' -f ($MinimumRamGiB - $available))
        $shortfall = $true
    }
    if ($MinimumVramGiB -gt 0) {
        $selected = if ($GpuIndex -ge 0) { @($gpus | Where-Object Index -eq $GpuIndex) } else { $gpus }
        if (@($selected).Count -ne 1) {
            Write-Warning 'Could not verify a single NVIDIA GPU. On a multi-GPU host, specify the plan GPU with -GpuIndex.'
            $shortfall = $true
        } elseif ($selected.FreeGiB -lt $MinimumVramGiB) {
            Write-Warning ('GPU {0} VRAM shortfall: {1:F2} GiB.' -f $selected.Index, ($MinimumVramGiB - $selected.FreeGiB))
            $shortfall = $true
        }
    }
    if ($shortfall) {
        Write-Warning 'Pause the load. Release resources yourself and rerun the check.'
        exit 2
    }
    exit 0
}

function Receive-HttpsFile([string]$Uri, [string]$Destination) {
    $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
    & $curl --fail --show-error --location --proto '=https' --proto-redir '=https' --retry 3 --connect-timeout 20 $Uri --output $Destination
    if ($LASTEXITCODE -ne 0) { throw 'Download failed. Run the same command to retry.' }
}

function Install-SelectedRuntime {
    if ($Runtime -eq 'none') { return }
    $executable = @{ codex='codex'; claude='claude'; pi='pi'; antigravity='agy' }[$Runtime]
    if (Get-Command $executable -ErrorAction SilentlyContinue) {
        Write-Host "Runtime already installed: $executable"
        return
    }
    if ($Runtime -eq 'antigravity') {
        $installedAgy = Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe'
        if (Test-Path -LiteralPath $installedAgy -PathType Leaf) {
            Write-Host 'Antigravity CLI is installed. Open a new terminal to load PATH.'
            return
        }
        $vendorTemp = Join-Path ([IO.Path]::GetTempPath()) ('linger-agy-' + [guid]::NewGuid())
        New-Item -ItemType Directory -Path $vendorTemp | Out-Null
        try {
            Receive-HttpsFile 'https://antigravity.google/cli/install.cmd' (Join-Path $vendorTemp 'install.cmd')
            Push-Location -LiteralPath $vendorTemp
            try {
                & $env:ComSpec /d /c 'install.cmd'
                if ($LASTEXITCODE -ne 0) { throw "Antigravity installer exited $LASTEXITCODE." }
            } finally { Pop-Location }
        } finally { Remove-Item -LiteralPath $vendorTemp -Recurse -Force }
    } else {
        $npm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $npm) { throw 'Install Node.js with npm first, or see the runtime installation guide.' }
        $package = @{ codex='@openai/codex'; claude='@anthropic-ai/claude-code'; pi='@earendil-works/pi-coding-agent' }[$Runtime]
        $arguments = @('install', '--global', '--registry=https://registry.npmjs.org')
        if ($Runtime -eq 'pi') { $arguments += '--ignore-scripts' }
        & $npm.Source @arguments $package
        if ($LASTEXITCODE -ne 0) { throw "Runtime installer exited $LASTEXITCODE." }
    }
    Write-Host "Runtime installer finished: $executable. Open a new terminal to verify the version and sign in if needed."
}

if (-not $DownloadOnly) {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            throw 'Run the installer from an ordinary user PowerShell.'
        }
    } finally { $identity.Dispose() }

    $programs = Join-Path $env:LOCALAPPDATA 'Programs'
    $installedPaths = @('Linger\Linger.exe', 'Simplex\Linger.exe', 'Simplex\Simplex.exe')
    $knownInstall = $installedPaths | Where-Object { Test-Path -LiteralPath (Join-Path $programs $_) }
    $registered = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -match '^Linger(?:\s+\d[\d.]*)?$' } |
        Select-Object -First 1
    if ($knownInstall -or $registered -or (Get-Process -Name Linger,Simplex -ErrorAction SilentlyContinue)) {
        Write-Host 'Existing Linger detected. Open it from the Start menu.'
        Install-SelectedRuntime
        exit 0
    }
}

$cache = Join-Path $env:LOCALAPPDATA 'LingerDeployCache'
$package = Join-Path $cache $asset
New-Item -ItemType Directory -Path $cache -Force | Out-Null
if (-not (Test-Path -LiteralPath $package -PathType Leaf) -or
    (Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ine $sha256) {
    $partial = Join-Path $cache "$asset.$([guid]::NewGuid()).partial"
    try {
        Receive-HttpsFile "$release/$asset" $partial
        if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ine $sha256) {
            throw 'SHA-256 mismatch. The download was discarded.'
        }
        Move-Item -LiteralPath $partial -Destination $package -Force
    } finally {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
    }
}
if ((Get-FileHash -LiteralPath $package -Algorithm SHA256).Hash -ine $sha256) {
    throw 'Cached installer did not pass SHA-256 verification.'
}
Write-Host "SHA-256 verified: $package"
if ($DownloadOnly) { exit 0 }

$setup = Start-Process -FilePath $package -PassThru
$setup.WaitForExit()
if ($setup.ExitCode -ne 0) { throw "Linger setup exited $($setup.ExitCode)." }
Write-Host 'Linger setup completed. Open Linger and confirm the model plan in the app.'
Install-SelectedRuntime
