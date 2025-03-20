@echo off
:menu
cls
echo =====================================
echo    CSM Installation Menu
echo =====================================
echo.
echo YouTube: @HowToIn1Minute
echo.
echo 1. Full Installation (Recommended)
echo.
echo Individual Components:
echo 2. Git Installation
echo 3. Python ^& FFmpeg Installation
echo 4. Project Setup
echo 5. Download Models
echo.
echo 0. Exit
echo =====================================
echo.
set /p choice="Select an option (0-5): "

if "%choice%"=="0" exit /b 0
if "%choice%"=="1" (
    powershell -ExecutionPolicy Bypass -File "%~dp0run-setup.ps1"
    exit /b %errorlevel%
)
if "%choice%"=="2" powershell -ExecutionPolicy Bypass -File "%~dp0install-git.ps1"
if "%choice%"=="3" powershell -ExecutionPolicy Bypass -File "%~dp0install-dependencies.ps1"
if "%choice%"=="4" powershell -ExecutionPolicy Bypass -File "%~dp0installation.ps1"
if "%choice%"=="5" powershell -ExecutionPolicy Bypass -File "%~dp0download-models.ps1"

if "%choice%"=="2" goto menu
if "%choice%"=="3" goto menu
if "%choice%"=="4" goto menu
if "%choice%"=="5" goto menu

echo Invalid option. Please try again.
timeout /t 2 >nul
goto menu
