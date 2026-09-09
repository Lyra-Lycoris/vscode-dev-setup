@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1"
set "result=%errorlevel%"
echo.
if "%result%"=="0" (echo Setup completed.) else (echo Setup failed. Please check the log shown above.)
pause
exit /b %result%
