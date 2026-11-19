@echo off
chcp 65001 >nul
title 启动 ComfyUI 后端 v1.0
rem ============================================================
rem  手动启动 ComfyUI 后端（局域网模式）v1.0
rem  调用核心脚本 comfy-backend.ps1，后端在后台运行，
rem  没有黑窗口需要守着；日志：
rem  H:\Comfy-Desktop\ComfyUI-Shared\comfy-backend.log
rem ============================================================
fltmc >nul 2>&1
if %errorlevel% neq 0 (
  echo 正在请求管理员权限...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================
echo   启动 ComfyUI 后端
echo ============================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "H:\Comfy-Desktop\ComfyUI-Shared\tools\comfy-backend.ps1" -Action start
if %errorlevel% neq 0 (
  echo.
  echo [失败] 核心脚本启动后端失败。
  echo 在聊天里跟助手说一句「报错了」，其余交给助手。
  echo.
  pause
  exit /b 1
)

echo 正在等待后端就绪（最长约 2 分钟）...
powershell -NoProfile -Command "for($i=0;$i -lt 60;$i++){ try{ $r=Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8189/system_stats' -TimeoutSec 2; if($r.StatusCode -eq 200){ exit 0 } }catch{}; Start-Sleep -Seconds 2 }; exit 1"
if %errorlevel% neq 0 (
  echo.
  echo [失败] 后端在约 2 分钟内没有就绪。后端日志在：
  echo H:\Comfy-Desktop\ComfyUI-Shared\comfy-backend.log
  echo 在聊天里跟助手说一句「报错了」，其余交给助手。
  echo.
  pause
  exit /b 1
)

echo.
echo ============================================
echo   [成功] 后端已就绪，在后台运行。
powershell -NoProfile -Command "$lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress; if (-not $lan) { $lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' -and $_.IPAddress -notlike '100.*' } | Select-Object -First 1).IPAddress }; if (-not $lan) { $lan = '<Windows 局域网 IP>' }; $ts = ''; $exe = Join-Path $env:ProgramFiles 'Tailscale\tailscale.exe'; if (Test-Path $exe) { $ts = (& $exe ip -4 2>$null | Select-Object -First 1) }; Write-Host ('  在家用 Mac 打开：http://' + $lan + ':8188'); if ($ts) { Write-Host ('  在外先连 Tailscale，再打开：http://' + $ts + ':8188') } else { Write-Host '  在外先连 Tailscale，再打开：http://<Windows Tailscale IP>:8188' }"
echo   不用了就双击桌面的「关闭ComfyUI后端.bat」。
echo ============================================
echo.
pause
exit /b 0
