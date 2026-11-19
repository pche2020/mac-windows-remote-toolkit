@echo off
chcp 65001 >nul
title ComfyUI 恢复 Desktop 模式 v1.3
rem ============================================================
rem  ComfyUI 恢复 Desktop 模式工具 v1.3
rem  作用：停用后端自启任务 + 停局域网后端 + 删 portproxy
rem        + 模型目录改回原样
rem  v1.3 变更：新增停用 ComfyUI-Backend-Autostart 计划任务
rem        一步（否则下次登录后端会被自启拉回局域网模式）；
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
echo [%date% %time%] 恢复Desktop模式 v%VER% 开始执行>> "%LOG%"

echo ============================================
echo   ComfyUI 恢复 Desktop 模式
echo ============================================
echo.

echo [1/4] 停用后端开机自启任务...
schtasks /Query /TN "%TASK%" >nul 2>&1
if %errorlevel% neq 0 (
  echo [OK] 自启任务不存在，无需停用>> "%LOG%"
  echo     OK（自启任务不存在，跳过）
) else (
  schtasks /Change /TN "%TASK%" /DISABLE >> "%LOG%" 2>&1
  if %errorlevel% neq 0 (
    echo [警告] 自启任务停用失败，原始输出已写入日志>> "%LOG%"
    echo     [警告] 自启任务停用失败，详见日志；不影响本次恢复，但下次登录前请让助手处理
  ) else (
    echo [OK] 步骤1 自启任务已停用>> "%LOG%"
    echo     OK
  )
)
echo.

echo [2/4] 停止局域网后端（8189）...
if exist "%CORE%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%CORE%" -Action stop >> "%LOG%" 2>&1
)
powershell -NoProfile -Command "Get-NetTCPConnection -LocalPort 8189 -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"
echo [OK] 步骤2 已停止 8189 上的后端进程（若有）>> "%LOG%"
echo     OK
echo.

echo [3/4] 删除端口转发规则（8188）...
netsh interface portproxy delete v4tov4 listenport=8188 listenaddress=0.0.0.0 >> "%LOG%" 2>&1
netsh interface portproxy show v4tov4 | findstr /C:"8188" >nul
if %errorlevel% equ 0 (
  set "FAILSTEP=步骤3 删除端口转发"
  set "FAILREASON=portproxy 规则删除后仍然存在，netsh 的原始输出已写入日志"
  goto :Fail
)
echo [OK] 步骤3 portproxy 规则已清除并校验通过>> "%LOG%"
echo     OK
echo.

echo [4/4] 还原模型目录（移除联接，改回原目录）...
set "RFAIL="
call :RestoreDir diffusion_models
call :RestoreDir loras
call :RestoreDir vae
call :RestoreDir text_encoders
if defined RFAIL (
  set "FAILSTEP=步骤4 还原模型目录"
  set "FAILREASON=目录 %RFAIL% 未能还原，具体报错已写入日志"
  goto :Fail
)
echo [OK] 步骤4 四个模型目录已还原>> "%LOG%"
echo [%date% %time%] 恢复Desktop模式 执行成功>> "%LOG%"
echo.
echo ============================================
echo   执行成功！现在可以正常打开 ComfyUI Desktop 使用。
echo   Mac 局域网控制已停用，后端自启也已停用；
echo   想切回来时运行「开启局域网模式.bat」即可，
echo   它会自动把自启重新启用。
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

:RestoreDir
set "M=%INSTALL%\models\%~1"
fsutil reparsepoint query "%M%" >nul 2>&1
if %errorlevel% equ 0 (
  rmdir "%M%" >> "%LOG%" 2>&1
)
fsutil reparsepoint query "%M%" >nul 2>&1
if %errorlevel% equ 0 (
  echo [失败] %~1 ：联接未能移除>> "%LOG%"
  set "RFAIL=%~1"
  goto :eof
)
if exist "%M%_bak" (
  ren "%M%_bak" "%~1" >> "%LOG%" 2>&1
  if exist "%M%_bak" (
    echo [失败] %~1 ：备份目录改名还原失败>> "%LOG%"
    set "RFAIL=%~1"
    goto :eof
  )
  echo [OK] %~1 已改回原目录>> "%LOG%"
  goto :eof
)
if not exist "%M%" (
  echo [警告] %~1 ：原目录和备份都不存在，Desktop 首次启动时一般会自己重建空目录>> "%LOG%"
  echo     [警告] %~1 目录不见了，Desktop 首次启动时一般会自己重建
) else (
  echo [OK] %~1 本来就是原目录，无需还原>> "%LOG%"
)
goto :eof
