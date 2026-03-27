# Theos for Windows - PowerShell Installer
# Run: powershell -ExecutionPolicy Bypass -File install.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  Theos for Windows - Installer" -ForegroundColor Cyan
Write-Host "  ==============================" -ForegroundColor Cyan
Write-Host ""

# Check for Git
$gitBash = $null
$gitPaths = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe"
)
foreach ($p in $gitPaths) {
    if (Test-Path $p) { $gitBash = $p; break }
}

if (-not $gitBash) {
    Write-Host "[!] Git for Windows not found. Installing..." -ForegroundColor Yellow
    Write-Host "    Downloading Git for Windows..." -ForegroundColor Gray

    $gitInstaller = "$env:TEMP\GitInstaller.exe"
    $gitUrl = "https://github.com/git-for-windows/git/releases/latest/download/Git-2.47.1-64-bit.exe"

    try {
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
        Write-Host "    Running Git installer (please complete the wizard)..." -ForegroundColor Gray
        Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART" -Wait
        Remove-Item $gitInstaller -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[ERROR] Could not download Git. Please install manually:" -ForegroundColor Red
        Write-Host "  https://git-scm.com/download/win" -ForegroundColor White
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Re-check
    foreach ($p in $gitPaths) {
        if (Test-Path $p) { $gitBash = $p; break }
    }
    if (-not $gitBash) {
        Write-Host "[ERROR] Git still not found after install. Restart and try again." -ForegroundColor Red
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host "[OK] Git Bash: $gitBash" -ForegroundColor Green

# Check for Python
$python = $null
foreach ($p in @("python3", "python")) {
    try { $python = (Get-Command $p -ErrorAction Stop).Source; break } catch {}
}
if (-not $python) {
    $pyPaths = Get-ChildItem "$env:LOCALAPPDATA\Programs\Python" -Filter "python.exe" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pyPaths) { $python = $pyPaths.FullName }
}

if ($python) {
    Write-Host "[OK] Python: $python" -ForegroundColor Green
    # Install zstandard
    & $python -m pip install zstandard -q 2>$null
} else {
    Write-Host "[!] Python not found. MSYS2 make download may fail." -ForegroundColor Yellow
    Write-Host "    Install from: https://python.org" -ForegroundColor Gray
}

# Download install.sh if not present
$scriptDir = $PSScriptRoot
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }

$installSh = Join-Path $scriptDir "install.sh"
if (-not (Test-Path $installSh)) {
    Write-Host "Downloading install.sh..." -ForegroundColor Gray
    Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Leeksov/theos-windows/master/install.sh" -OutFile $installSh -UseBasicParsing
}

Write-Host ""
Write-Host "Starting installation via Git Bash..." -ForegroundColor Cyan
Write-Host ""

# Run install.sh in Git Bash
$installShUnix = $installSh -replace '\\','/' -replace '^([A-Z]):','/`$1'.ToLower()
& $gitBash --login -c "bash '$installShUnix'"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "============================================" -ForegroundColor Green
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host "============================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Open Git Bash and run: `$THEOS/bin/nic.pl" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "[ERROR] Installation failed." -ForegroundColor Red
}

Read-Host "Press Enter to exit"
