@echo off
:: Theos for Windows - One-Click Installer
:: Downloads install.sh from GitHub and runs it via Git Bash
:: Installs everything to %USERPROFILE%\.theos

setlocal

echo.
echo   Theos for Windows - Installer
echo   ==============================
echo.

:: Find Git Bash
set "GITBASH="
for %%d in (
    "C:\Program Files\Git\bin\bash.exe"
    "C:\Program Files (x86)\Git\bin\bash.exe"
    "%LOCALAPPDATA%\Programs\Git\bin\bash.exe"
) do if exist %%d set "GITBASH=%%~d"

if "%GITBASH%"=="" (
    echo [!] Git for Windows not found. Downloading...
    echo.
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/latest/download/Git-2.47.1-64-bit.exe' -OutFile '%TEMP%\GitInstall.exe' -UseBasicParsing"
    if exist "%TEMP%\GitInstall.exe" (
        echo Installing Git for Windows...
        "%TEMP%\GitInstall.exe" /VERYSILENT /NORESTART
        del "%TEMP%\GitInstall.exe"
        if exist "C:\Program Files\Git\bin\bash.exe" set "GITBASH=C:\Program Files\Git\bin\bash.exe"
    )
)

if "%GITBASH%"=="" (
    echo [ERROR] Git for Windows is required.
    echo   Install from: https://git-scm.com/download/win
    echo   Then run this again.
    pause
    exit /b 1
)

echo [OK] Git Bash: %GITBASH%
echo.
echo Downloading installer from GitHub and running...
echo.

"%GITBASH%" --login -c "curl -fsSL https://raw.githubusercontent.com/Leeksov/theos-windows/master/install.sh | bash"

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [ERROR] Installation failed. See errors above.
    pause
    exit /b 1
)

echo.
echo Done! Open Git Bash to use Theos.
pause
