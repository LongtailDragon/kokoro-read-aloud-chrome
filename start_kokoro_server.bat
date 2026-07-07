@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
pushd "%SCRIPT_DIR%"

rem Exit quietly if the local server is already listening on the default port.
powershell.exe -NoProfile -Command "try { $listener = Get-NetTCPConnection -LocalPort 8765 -State Listen -ErrorAction Stop; if ($listener) { exit 0 } } catch { } exit 1"
if "%ERRORLEVEL%"=="0" (
	popd
	exit /b 0
)

set "PYTHON_CMD="
if exist "%SCRIPT_DIR%.venv\Scripts\python.exe" set "PYTHON_CMD=%SCRIPT_DIR%.venv\Scripts\python.exe"
if not defined PYTHON_CMD where python >nul 2>nul && set "PYTHON_CMD=python"
if not defined PYTHON_CMD where py >nul 2>nul && set "PYTHON_CMD=py -3"
if not defined PYTHON_CMD (
	echo Python 3 was not found. Install Python or create a .venv folder in the repository root.
	popd
	exit /b 1
)

if exist "%SCRIPT_DIR%.venv\Scripts\activate.bat" call "%SCRIPT_DIR%.venv\Scripts\activate.bat"
set PYTHONDONTWRITEBYTECODE=1
%PYTHON_CMD% -u kokoro_server.py
set "EXIT_CODE=%ERRORLEVEL%"
popd
exit /b %EXIT_CODE%
