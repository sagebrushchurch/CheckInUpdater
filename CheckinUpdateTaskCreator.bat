@echo off
setlocal enabledelayedexpansion

REM Get the directory where this batch file is located
set "SCRIPT_DIR=%~dp0"
set "PS_SCRIPT=%SCRIPT_DIR%CheckinUpdateInstaller.ps1"

for %%I in ("%PS_SCRIPT%") do set "PS_SCRIPT=%%~sI"

REM Create the task scheduler task and set close time to 5 minutes
schtasks /create /tn "CheckInUpdater" /tr "powershell.exe -ExecutionPolicy Bypass -File %PS_SCRIPT%" /sc daily /st 05:00 /rl highest /du 00:05 /ri 0  /f
powershell -Command "Set-ScheduledTask -TaskName 'CheckInUpdater' -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 5))"

if %errorlevel% equ 0 (
    echo Task created successfully!
) else (
    echo Error creating task. Please run this batch file as Administrator.
)

pause