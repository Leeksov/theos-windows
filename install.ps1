# Theos for Windows - PowerShell Installer
# Downloads everything from GitHub. Installs to %USERPROFILE%\.theos
# Run: powershell -ExecutionPolicy Bypass -File install.ps1
# Or:  iwr bit.ly/theos-win -OutFile i.ps1; .\i.ps1

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "  Theos for Windows - Installer" -ForegroundColor Cyan
Write-Host ""

# ── Find or install Git ──
$gitBash = @(
    "$env:ProgramFiles\Git\bin\bash.exe",
    "${env:ProgramFiles(x86)}\Git\bin\bash.exe",
    "$env:LOCALAPPDATA\Programs\Git\bin\bash.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if (-not $gitBash) {
    Write-Host "[!] Git not found. Installing..." -ForegroundColor Yellow
    $installer = "$env:TEMP\GitInstall.exe"
    try {
        $releases = Invoke-RestMethod "https://api.github.com/repos/git-for-windows/git/releases/latest"
        $url = ($releases.assets | Where-Object { $_.name -match "64-bit\.exe$" } | Select-Object -First 1).browser_download_url
        Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
        Start-Process -FilePath $installer -ArgumentList "/VERYSILENT","/NORESTART" -Wait
        Remove-Item $installer -ErrorAction SilentlyContinue
    } catch {
        Write-Host "[ERROR] Install Git manually: https://git-scm.com/download/win" -ForegroundColor Red
        Read-Host "Press Enter"; exit 1
    }
    $gitBash = "$env:ProgramFiles\Git\bin\bash.exe"
    if (-not (Test-Path $gitBash)) {
        Write-Host "[ERROR] Git install failed." -ForegroundColor Red
        Read-Host "Press Enter"; exit 1
    }
}

Write-Host "[OK] Git Bash: $gitBash" -ForegroundColor Green
Write-Host ""
Write-Host "Downloading and running installer..." -ForegroundColor Gray
Write-Host ""

& $gitBash --login -c "curl -fsSL https://raw.githubusercontent.com/Leeksov/theos-windows/master/install.sh | bash"

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "  Installation complete!" -ForegroundColor Green
    Write-Host "  Open Git Bash to use Theos." -ForegroundColor White
} else {
    Write-Host "[ERROR] Installation failed." -ForegroundColor Red
}
Write-Host ""
Read-Host "Press Enter to exit"
