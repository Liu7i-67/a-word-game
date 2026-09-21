@echo off
REM ============================================================
REM  Build + bump version: produces a signed Android APK.
REM
REM  Usage:
REM    build.bat                    bump patch version (default)
REM    build.bat -VersionBump minor bump minor version
REM    build.bat -VersionBump major bump major version
REM    build.bat -VersionBump none  rebuild without version change
REM
REM  All extra args are passed through to scripts\build_apk.ps1
REM ============================================================
setlocal
cd /d "%~dp0"

powershell -NoProfile -ExecutionPolicy Bypass -File "scripts\build_apk.ps1" %*

echo.
pause
endlocal
