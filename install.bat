@echo off
:: Theos for Windows - Installer Launcher
:: Finds Git Bash and runs install.sh through it

setlocal

echo.
echo   Theos for Windows - Installer
echo   ==============================
echo.

:: Find Git Bash
set "GITBASH="
if exist "C:\Program Files\Git\bin\bash.exe" set "GITBASH=C:\Program Files\Git\bin\bash.exe"
if exist "C:\Program Files (x86)\Git\bin\bash.exe" set "GITBASH=C:\Program Files (x86)\Git\bin\bash.exe"

if "%GITBASH%"=="" (
    echo [ERROR] Git for Windows not found.
    echo.
    echo Please install Git for Windows from:
    echo   https://git-scm.com/download/win
    echo.
    pause
    exit /b 1
)

echo Found Git Bash: %GITBASH%
echo.

:: Run install.sh via Git Bash
"%GITBASH%" --login -c "cd '%~dp0' && bash install.sh"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Installation failed. See errors above.
    pause
    exit /b 1
)

echo.
echo Installation complete! Open Git Bash to start using Theos.
pause
