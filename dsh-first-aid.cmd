@echo off
chcp 65001 >nul
rem dsh-first-aid 双击入口
rem 优先 PowerShell 7，没有就用系统自带的 Windows PowerShell 5.1
set "PWSH=C:\Program Files\PowerShell\7\pwsh.exe"
if not exist "%PWSH%" set "PWSH=powershell.exe"

if "%~1"=="" (
  "%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh-first-aid.ps1" -Action help
  echo.
  echo 常用：
  echo   %~nx0 snapshot   只备份
  echo   %~nx0 rescue     备份 + 回滚配置 + 启动
  echo   %~nx0 minimal    极简启动
  echo   %~nx0 check      体检
  pause
  exit /b 0
)

"%PWSH%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0dsh-first-aid.ps1" -Action %1
pause
