@echo off
echo Activating virtual environment...
call .venv\Scripts\activate.bat
if %ERRORLEVEL% neq 0 (
    echo Error: Failed to activate virtual environment
    pause
    exit /b 1
)

echo Starting CSM Voice Cloning Interface...
python gui.py
if %ERRORLEVEL% neq 0 (
    echo Error: Failed to start the application
    pause
    exit /b 1
)
