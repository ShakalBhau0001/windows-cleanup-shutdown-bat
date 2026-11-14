@echo off
setlocal enabledelayedexpansion
title Advanced Cleanup and Shutdown
color 0A

:: Does NOT touch: Recycle Bin, Downloads folder, Documents, browser passwords / cookies / history

set RUN_CLEANMGR=1
set RUN_DISM=0
set CLEAN_BROWSERS=1
set KILL_BROWSERS=0
set FLUSH_DNS=1
set POWER_DELAY=5

:: RUN_DISM = component store cleanup, slow but frees a lot
:: KILL_BROWSERS = force close browsers so their cache files are not locked
:: Auto-elevate to Administrator

net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting Administrator rights...
  powershell -NoProfile -Command "Start-Process '%~f0' -Verb RunAs"
  exit /b
)

echo ============================================================
echo  ADVANCED CLEANUP STARTED
echo ============================================================
echo.

:: Free space before cleanup

for /f %%a in ('powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1MB)"') do set BEFORE=%%a

:: ---- 1) Temp folders ----

echo [1] Temp folders...
call :cleandir "%TEMP%"
call :cleandir "%LOCALAPPDATA%\Temp"
call :cleandir "%SystemRoot%\Temp"
call :cleandir "%SystemRoot%\Temp\*"

:: ---- 2) Prefetch ----

echo [2] Prefetch...
del /s /f /q "%SystemRoot%\Prefetch\*.*" >nul 2>&1

:: ---- 3) Windows Update cache + Delivery Optimization ----

echo [3] Windows Update and Delivery Optimization cache...
net stop wuauserv >nul 2>&1
net stop bits >nul 2>&1
net stop dosvc >nul 2>&1
call :cleandir "%SystemRoot%\SoftwareDistribution\Download"
call :cleandir "%SystemRoot%\SoftwareDistribution\DeliveryOptimization"
call :cleandir "%ProgramData%\Microsoft\Windows\DeliveryOptimization\Cache"
net start wuauserv >nul 2>&1
net start bits >nul 2>&1
net start dosvc >nul 2>&1

:: ---- 4) Crash dumps and error reports ----

echo [4] Crash dumps and error reports...
call :cleandir "%LOCALAPPDATA%\CrashDumps"
call :cleandir "%SystemRoot%\Minidump"
call :cleandir "%ProgramData%\Microsoft\Windows\WER\ReportArchive"
call :cleandir "%ProgramData%\Microsoft\Windows\WER\ReportQueue"
call :cleandir "%LOCALAPPDATA%\Microsoft\Windows\WER"
del /f /q "%SystemRoot%\MEMORY.DMP" >nul 2>&1

:: ---- 5) Windows logs ----

echo [5] Old Windows logs...
del /s /f /q "%SystemRoot%\Logs\CBS\*.log" >nul 2>&1
del /s /f /q "%SystemRoot%\Logs\DISM\*.log" >nul 2>&1
del /s /f /q "%SystemRoot%\Panther\*.log" >nul 2>&1
del /s /f /q "%SystemRoot%\Logs\WindowsUpdate\*.etl" >nul 2>&1

:: ---- 6) Thumbnail cache and shader caches ----

echo [6] Thumbnail and GPU shader caches...
del /f /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db" >nul 2>&1
call :cleandir "%LOCALAPPDATA%\D3DSCache"
call :cleandir "%LOCALAPPDATA%\NVIDIA\DXCache"
call :cleandir "%LOCALAPPDATA%\NVIDIA\GLCache"
call :cleandir "%LOCALAPPDATA%\AMD\DxCache"
call :cleandir "%LOCALAPPDATA%\AMD\GLCache"

:: ---- 7) Other app caches ----

echo [7] Other caches...
call :cleandir "%LOCALAPPDATA%\Microsoft\Windows\INetCache"
call :cleandir "%LOCALAPPDATA%\Microsoft\Windows\Temporary Internet Files"
call :cleandir "%LOCALAPPDATA%\pip\cache"
call :cleandir "%LOCALAPPDATA%\Package Cache"

:: ---- 8) Browser caches ----

if "%CLEAN_BROWSERS%"=="1" (
  echo [8] Browser caches...
  if "%KILL_BROWSERS%"=="1" (
    taskkill /f /im chrome.exe >nul 2>&1
    taskkill /f /im msedge.exe >nul 2>&1
    taskkill /f /im firefox.exe >nul 2>&1
  )
  for /d %%p in ("%LOCALAPPDATA%\Google\Chrome\User Data\Default" "%LOCALAPPDATA%\Google\Chrome\User Data\Profile *") do (
    call :cleandir "%%~p\Cache"
    call :cleandir "%%~p\Code Cache"
    call :cleandir "%%~p\GPUCache"
  )
  for /d %%p in ("%LOCALAPPDATA%\Microsoft\Edge\User Data\Default" "%LOCALAPPDATA%\Microsoft\Edge\User Data\Profile *") do (
    call :cleandir "%%~p\Cache"
    call :cleandir "%%~p\Code Cache"
    call :cleandir "%%~p\GPUCache"
  )
  for /d %%p in ("%LOCALAPPDATA%\Mozilla\Firefox\Profiles\*") do (
    call :cleandir "%%~p\cache2"
  )
)

:: ---- 9) DNS cache ----

if "%FLUSH_DNS%"=="1" (
  echo [9] Flushing DNS cache...
  ipconfig /flushdns >nul 2>&1
)

:: ---- 10) Windows Disk Cleanup in silent mode ----
:: Recycle Bin and Downloads are deliberately NOT selected

if "%RUN_CLEANMGR%"=="1" (
  echo [10] Running Windows Disk Cleanup, this may take a few minutes...
  for %%k in (
    "Active Setup Temp Folders"
    "BranchCache"
    "D3D Shader Cache"
    "Delivery Optimization Files"
    "Device Driver Packages"
    "Diagnostic Data Viewer database files"
    "Downloaded Program Files"
    "Internet Cache Files"
    "Old ChkDsk Files"
    "Setup Log Files"
    "System error memory dump files"
    "System error minidump files"
    "Temporary Files"
    "Temporary Setup Files"
    "Thumbnail Cache"
    "Update Cleanup"
    "Windows Defender"
    "Windows Error Reporting Files"
    "Windows ESD installation files"
    "Windows Upgrade Log Files"
    ) do (
    reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches\%%~k" /v StateFlags1337 /t REG_DWORD /d 2 /f >nul 2>&1
  )
  cleanmgr /sagerun:1337
)

:: ---- 11) Component store cleanup ----

if "%RUN_DISM%"=="1" (
  echo [11] DISM component cleanup, please wait...
  dism /online /cleanup-image /startcomponentcleanup >nul 2>&1
)

:: Free space after cleanup

for /f %%a in ('powershell -NoProfile -Command "[math]::Round((Get-PSDrive C).Free/1MB)"') do set AFTER=%%a
set /a FREED=AFTER-BEFORE

echo.
echo ============================================================
echo  CLEANUP COMPLETE
echo  Space freed on C: about !FREED! MB
echo  Recycle Bin and Downloads were NOT touched.
echo ============================================================

:: ---- Ask the user what to do next ----

:ask_shutdown
echo.
choice /c YN /n /m "Do you want to SHUTDOWN the PC now? (Y/N): "
if errorlevel 2 goto ask_restart
echo Shutting down in %POWER_DELAY% seconds... (run "shutdown /a" to cancel)
shutdown /s /f /t %POWER_DELAY%
timeout /t %POWER_DELAY% >nul
exit /b

:ask_restart
choice /c YN /n /m "Do you want to RESTART the PC now? (Y/N): "
if errorlevel 2 goto keep_using
echo Restarting in %POWER_DELAY% seconds... (run "shutdown /a" to cancel)
shutdown /r /f /t %POWER_DELAY%
timeout /t %POWER_DELAY% >nul
exit /b

:keep_using
echo.
echo No shutdown or restart selected. You can continue using your PC.
pause
exit /b

:: Helper: delete all files and subfolders inside a folder

:cleandir
if not exist "%~1" exit /b
del /s /f /q "%~1\*.*" >nul 2>&1
for /d %%x in ("%~1\*") do rd /s /q "%%x" >nul 2>&1
exit /b
