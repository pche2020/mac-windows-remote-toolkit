@echo off
chcp 65001 >nul
title ComfyUI 局域网模式 - 开启 v1.3
rem ============================================================
rem  ComfyUI 局域网模式 - 开启工具 v1.3
rem  作用：portproxy 8188 转 8189 + 模型目录联接
rem        + 核心脚本启动后端（后台运行） + 启用后端自启任务
rem  v1.3 变更：后端改由 comfy-backend.ps1 统一启动（无黑窗口）；
rem        新增启用 ComfyUI-Backend-Autostart 计划任务一步；
rem        失败处理改为「跟助手说一句报错了，助手自己读日志」。
rem  全过程（成功/失败/原始报错）写入脚本同目录日志：
rem  ComfyUI模式切换日志.txt
rem ============================================================
fltmc >nul 2>&1
if %errorlevel% neq 0 (
  echo 正在请求管理员权限...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "VER=1.3"
set "INSTALL=H:\Comfy-Desktop\ComfyUI-Installs\ComfyUI\ComfyUI"
set "SHARED=H:\Comfy-Desktop\ComfyUI-Shared"
set "CORE=%SHARED%\tools\comfy-backend.ps1"
set "TASK=ComfyUI-Backend-Autostart"
set "LOG=%~dp0ComfyUI模式切换日志.txt"

echo.>> "%LOG%"
echo ==================================================>> "%LOG%"
echo [%date% %time%] 开启局域网模式 v%VER% 开始执行>> "%LOG%"

echo ============================================
echo   ComfyUI 局域网模式 - 开启
echo ============================================
echo.

echo [1/6] 检查 8188 是否被 Desktop 后端占用...
powershell -NoProfile -Command "$c=Get-NetTCPConnection -LocalPort 8188 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1; if($c){ $p=Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue; if($p -and $p.ProcessName -eq 'python'){ exit 3 } }"
if %errorlevel% equ 3 (
  set "FAILSTEP=步骤1 端口检查"
  set "FAILREASON=ComfyUI Desktop 的后端正在运行，占用了 8188 端口；请先完全退出 Desktop 再运行本工具"
  goto :Fail
)
echo [OK] 步骤1 端口检查通过>> "%LOG%"
echo     OK
echo.

echo [2/6] 停止旧的局域网后端（8189）...
powershell -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -Action stop >> "%LOG%" 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8189 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"
  echo [警告] 核心脚本停后端失败，已用按端口强杀兜底>> "%LOG%"
)
echo [OK] 步骤2 已清理 8189 上的旧后端进程（若有）>> "%LOG%"
echo     OK
echo.

echo [3/6] 设置端口转发 8188 转 8189 ...
netsh interface portproxy delete v4tov4 listenport=8188 listenaddress=0.0.0.0 >nul 2>&1
netsh interface portproxy add v4tov4 listenport=8188 listenaddress=0.0.0.0 connectport=8189 connectaddress=localhost >> "%LOG%" 2>&1
if %errorlevel% neq 0 (
  set "FAILSTEP=步骤3 设置端口转发"
  set "FAILREASON=netsh 添加 portproxy 规则失败，netsh 的原始输出已写入日志"
  goto :Fail
)
netsh interface portproxy show v4tov4 | findstr /C:"8188" >nul
if %errorlevel% neq 0 (
  set "FAILSTEP=步骤3 设置端口转发"
  set "FAILREASON=portproxy 规则添加后校验不到，可能 IP Helper 服务未运行"
  goto :Fail
)
echo [OK] 步骤3 portproxy 已设置并校验通过>> "%LOG%"
echo     OK
echo.

echo [4/6] 检查模型目录联接...
set "JFAIL="
call :EnsureJunction diffusion_models
call :EnsureJunction loras
call :EnsureJunction vae
call :EnsureJunction text_encoders
if defined JFAIL (
  set "FAILSTEP=步骤4 模型目录联接"
  set "FAILREASON=目录 %JFAIL% 未能建立联接，具体报错已写入日志"
  goto :Fail
)
echo [OK] 步骤4 四个模型目录联接就绪>> "%LOG%"
echo     OK
echo.

echo [5/6] 启动 ComfyUI 后端（后台运行，没有窗口要守）...
if not exist "%CORE%" (
  set "FAILSTEP=步骤5 启动后端"
  set "FAILREASON=核心脚本不存在：%CORE%，请让助手重新同步工具"
  goto :Fail
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -Action start >> "%LOG%" 2>&1
if %errorlevel% neq 0 (
  set "FAILSTEP=步骤5 启动后端"
  set "FAILREASON=核心脚本启动后端失败，输出已写入日志；后端自身日志在 %SHARED%\comfy-backend.log"
  goto :Fail
)
echo     等待后端就绪，最长约 2 分钟...
powershell -NoProfile -Command "for($i=0;$i -lt 60;$i++){ try{ $r=Invoke-WebRequest -UseBasicParsing -Uri 'http://localhost:8189/system_stats' -TimeoutSec 2; if($r.StatusCode -eq 200){ exit 0 } }catch{}; Start-Sleep -Seconds 2 }; exit 1"
if %errorlevel% neq 0 (
  set "FAILSTEP=步骤5 启动后端"
  set "FAILREASON=后端在约 2 分钟内没有就绪；后端日志在 %SHARED%\comfy-backend.log，助手读日志即可定位"
  goto :Fail
)
echo [OK] 步骤5 后端已就绪>> "%LOG%"
echo     OK
echo.

echo [6/6] 启用后端开机自启任务...
set "TASKWARN="
schtasks /Query /TN "%TASK%" >nul 2>&1
if %errorlevel% neq 0 (
  set "TASKWARN=自启任务 %TASK% 不存在，已记入日志，请让助手补建"
  echo [警告] 自启任务不存在，跳过启用>> "%LOG%"
) else (
  schtasks /Change /TN "%TASK%" /ENABLE >> "%LOG%" 2>&1
  if %errorlevel% neq 0 (
    set "TASKWARN=自启任务启用失败，已记入日志，请让助手处理"
    echo [警告] 自启任务启用失败>> "%LOG%"
  ) else (
    echo [OK] 步骤6 自启任务已启用>> "%LOG%"
  )
)
echo     OK
echo.

echo [%date% %time%] 开启局域网模式 执行成功>> "%LOG%"
echo ============================================
echo   执行成功！
powershell -NoProfile -Command "$lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.PrefixOrigin -eq 'Dhcp' -and $_.IPAddress -notlike '169.*' } | Select-Object -First 1).IPAddress; if (-not $lan) { $lan = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.*' -and $_.IPAddress -notlike '100.*' } | Select-Object -First 1).IPAddress }; if (-not $lan) { $lan = '<Windows 局域网 IP>' }; $ts = ''; $exe = Join-Path $env:ProgramFiles 'Tailscale	ailscale.exe'; if (Test-Path $exe) { $ts = (& $exe ip -4 2>$null | Select-Object -First 1) }; Write-Host ('  在家用 Mac 打开：http://' + $lan + ':8188'); if ($ts) { Write-Host ('  在外先连 Tailscale，再打开：http://' + $ts + ':8188') } else { Write-Host '  在外先连 Tailscale，再打开：http://<Windows Tailscale IP>:8188' }"
echo   后端在后台运行，没有窗口需要关照；
echo   想关后端用桌面的「关闭ComfyUI后端.bat」。
if defined TASKWARN echo   [注意] %TASKWARN%
echo   本次记录已写入日志：ComfyUI模式切换日志.txt
echo ============================================
echo.
pause
exit /b 0

:Fail
echo [%date% %time%] [失败] %FAILSTEP% ：%FAILREASON%>> "%LOG%"
echo.
echo ============================================
echo   执行失败！
echo   失败步骤：%FAILSTEP%
echo   失败原因：%FAILREASON%
echo   详细记录已写入日志文件：
echo   %LOG%
echo   你什么都不用做：在聊天里跟助手说一句
echo   「报错了」，助手会自己来读这份日志处理。
echo ============================================
echo.
explorer /select,"%LOG%"
pause
exit /b 1

:EnsureJunction
set "M=%INSTALL%\models\%~1"
set "T=%SHARED%\models\%~1"
if not exist "%T%" (
  echo [失败] %~1 ：Shared 里不存在目标目录>> "%LOG%"
  set "JFAIL=%~1"
  goto :eof
)
fsutil reparsepoint query "%M%" >nul 2>&1
if %errorlevel% equ 0 (
  echo [OK] %~1 已是联接>> "%LOG%"
  goto :eof
)
if exist "%M%" (
  if exist "%M%_bak" (
    ren "%M%" "%~1_old_%RANDOM%" >> "%LOG%" 2>&1
  ) else (
    ren "%M%" "%~1_bak" >> "%LOG%" 2>&1
  )
)
mklink /J "%M%" "%T%" >> "%LOG%" 2>&1
fsutil reparsepoint query "%M%" >nul 2>&1
if %errorlevel% neq 0 (
  echo [失败] %~1 ：mklink 之后校验仍不是联接>> "%LOG%"
  set "JFAIL=%~1"
  goto :eof
)
echo [OK] %~1 联接已建立>> "%LOG%"
goto :eof
