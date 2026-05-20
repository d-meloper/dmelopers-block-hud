@echo off
setlocal EnableExtensions

set "launcherPath=%~dp0tools\ImportFromOldVersionLauncher.ps1"
if not exist "%launcherPath%" (
    echo Snapshot import launcher was not found:
    echo(%launcherPath%
    echo Reinstall the v1.2.0 skin package or restore the tools folder.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%launcherPath%" -TargetRoot "%~dp0."
exit /b %ERRORLEVEL%
