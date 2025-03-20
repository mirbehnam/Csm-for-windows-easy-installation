[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Configuration
$config = @{
    PythonUrl     = 'https://www.python.org/ftp/python/3.10.0/python-3.10.0-amd64.exe'
    PythonInstaller = Join-Path $PWD 'python-3.10.0-amd64.exe'
    FFmpegUrl     = 'https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip'
    FFmpegZip     = Join-Path $PWD 'ffmpeg.zip'
    FFmpegDir     = Join-Path $PWD 'ffmpeg'
    RequiredPythonVersion = '3.10.0'
}

function Test-ValidPythonInstallation {
    try {
        # Get all python.exe in PATH
        $pythonPaths = Get-Command python -All -ErrorAction SilentlyContinue | 
                      Where-Object { $_.Source -notlike "*WindowsApps*" } | 
                      Select-Object -ExpandProperty Source

        foreach ($pythonPath in $pythonPaths) {
            $versionOutput = & $pythonPath -c "import sys; print(sys.version.split()[0])" 2>$null
            if ($versionOutput -match "^3\.10\.\d+$") {
                Write-Host "Found Python $versionOutput at: $pythonPath" -ForegroundColor Green
                $pythonDir = Split-Path -Parent $pythonPath
                $env:Path = "$pythonDir;$pythonDir\Scripts;" + $env:Path
                return $true
            }
        }
        Write-Host "Python 3.10.x not found in PATH" -ForegroundColor Yellow
        return $false
    }
    catch {
        Write-Host "Error checking Python installation: $_" -ForegroundColor Yellow
        return $false
    }
}

function Test-ProgramInstallation {
    param($ProgramName)
    try {
        $null = Get-Command $ProgramName -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Install-FFmpeg {
    if (-not (Test-Path $config.FFmpegZip)) {
        Write-Host "Downloading FFmpeg..." -ForegroundColor Yellow
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $config.FFmpegUrl -Destination $config.FFmpegZip
    }

    if (-not (Test-Path $config.FFmpegDir)) {
        Write-Host "Extracting FFmpeg..." -ForegroundColor Yellow
        Expand-Archive -Path $config.FFmpegZip -DestinationPath $config.FFmpegDir -Force
        
        # Move files from nested directory to FFmpegDir
        $nestedDir = Get-ChildItem $config.FFmpegDir -Directory | Select-Object -First 1
        Move-Item "$($nestedDir.FullName)\bin\*" $config.FFmpegDir -Force
        Remove-Item $nestedDir.FullName -Recurse -Force
    }

    # Add to PATH
    $env:Path = "$($config.FFmpegDir);$env:Path"
    [Environment]::SetEnvironmentVariable(
        "Path",
        [Environment]::GetEnvironmentVariable("Path", "Machine") + ";$($config.FFmpegDir)",
        "Machine"
    )
}

try {
    # Install Python if not present or not the correct version
    if (-not (Test-ValidPythonInstallation)) {
        Write-Host "Downloading Python $($config.RequiredPythonVersion)..." -ForegroundColor Yellow
        if (-not (Test-Path $config.PythonInstaller)) {
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $config.PythonUrl -Destination $config.PythonInstaller
        }

        Write-Host "Installing Python silently..." -ForegroundColor Yellow
        $pythonArgs = @(
            '/quiet'
            'InstallAllUsers=1'
            'PrependPath=1'
            'Include_test=0'
            'Include_pip=1'
        )
        Start-Process -FilePath $config.PythonInstaller -ArgumentList $pythonArgs -Wait -NoNewWindow

        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
    }

    # Install FFmpeg if not present
    if (-not (Test-ProgramInstallation "ffmpeg")) {
        Install-FFmpeg
    }

    # Verify installations
    $python = Test-ValidPythonInstallation
    $ffmpeg = Test-ProgramInstallation "ffmpeg"

    if (-not ($python -and $ffmpeg)) {
        throw "Installation verification failed"
    }

    Write-Host "`nAll dependencies installed successfully!" -ForegroundColor Green
    
    # Display versions
    Write-Host "`nInstalled versions:" -ForegroundColor Cyan
    python --version
    ffmpeg -version | Select-Object -First 1
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "Script encountered an error." -ForegroundColor Red
}
finally {
    Write-Host "`n"  # Just add a newline for spacing
}