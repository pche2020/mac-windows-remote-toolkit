@echo off
chcp 65001 >nul
title 关闭 ComfyUI 后端 v1.0
rem ============================================================
rem  手动关闭 ComfyUI 后端（局域网模式）v1.0
rem  调用核心脚本 comfy-backend.ps1 按端口停后端并校验。
rem  注意：关闭前确认没有正在生成的任务。
rem ============================================================
fltmc >nul 2>&1
if %errorlevel% neq 0 (
  echo 正在请求管理员权限...
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================
echo   关闭 ComfyUI 后端
echo ============================================
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "H:\Comfy-Desktop\ComfyUI-Shared\tools\comfy-backend.ps1" -Action stop
if %errorlevel% neq 0 (
  echo.
  echo [失败] 后端未能停干净。
  echo 在聊天里跟助手说一句「报错了」，其余交给助手。
  echo.
  pause
  exit /b 1
)

echo.
echo ============================================
echo   [成功] 后端已关闭。
echo   想再用时双击桌面的「启动ComfyUI后端.bat」，
echo   或者重启电脑登录后也会自动启动。
echo ============================================
echo.
pause
exit /b 0
