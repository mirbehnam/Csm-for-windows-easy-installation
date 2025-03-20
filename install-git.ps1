[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Configuration
$config = @{
    GitInstallerUrl = 'https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe'
    GitInstaller    = Join-Path $PWD 'Git-2.42.0-64-bit.exe'
    LocalGitPath    = Join-Path $PWD 'Git'
    RepoUrl         = 'https://github.com/SesameAILabs/csm.git'
    CloneDir        = Join-Path $PWD 'csm'
}

function Test-GitInstallation {
    try {
        $null = Get-Command git -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

try {
    Write-Host "Checking for Git installation..." -ForegroundColor Cyan
    
    if (-not (Test-GitInstallation)) {
        Write-Host "Downloading Git installer..." -ForegroundColor Yellow
        
        if (-not (Test-Path $config.GitInstaller)) {
            # Use BITS for faster download with progress
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $config.GitInstallerUrl -Destination $config.GitInstaller -DisplayName "Git Installer" -Description "Downloading Git installer..."
        }

        # Verify download
        if (-not (Test-Path $config.GitInstaller) -or (Get-Item $config.GitInstaller).Length -lt 1MB) {
            throw "Download failed or file is corrupted"
        }

        Write-Host "Installing Git silently..." -ForegroundColor Yellow
        $args = @(
            '/VERYSILENT',
            '/SUPPRESSMSGBOXES',
            '/NORESTART',
            '/NOCANCEL',
            "/DIR=`"$($config.LocalGitPath)`""
        )
        
        Start-Process -FilePath $config.GitInstaller -ArgumentList $args -Wait
        
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + 
                    [System.Environment]::GetEnvironmentVariable("Path", "User")
        
        if (-not (Test-GitInstallation)) {
            throw "Git installation failed verification"
        }
        Write-Host "Git installed successfully" -ForegroundColor Green
    }

    Write-Host "Preparing to clone repository..." -ForegroundColor Cyan
    # With this:
    if (Test-Path $config.CloneDir) {
        Write-Host "Repository directory already exists. Updating instead of cloning..." -ForegroundColor Yellow
        Set-Location $config.CloneDir
        git pull
        Set-Location $PWD
    } else {
        Write-Host "Cloning repository..." -ForegroundColor Yellow
        git clone $config.RepoUrl $config.CloneDir
    }

    Write-Host "`nInstallation and clone completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "Script encountered an error." -ForegroundColor Red
}
finally {
    Write-Host "`n"  # Just add a newline for spacing
}
