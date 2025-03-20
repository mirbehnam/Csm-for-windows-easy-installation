[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# Get the directory where this script is located
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$scripts = @(
    @{Name = "Git Installation"; Path = Join-Path $scriptDir "install-git.ps1"},
    @{Name = "Dependencies Installation"; Path = Join-Path $scriptDir "install-dependencies.ps1"},
    @{Name = "Project Setup"; Path = Join-Path $scriptDir "installation.ps1"},
    @{Name = "Model Download"; Path = Join-Path $scriptDir "download-models.ps1"}
)

try {
    # Set execution policy
    Write-Host "Setting execution policy..." -ForegroundColor Cyan
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force

    # Run each script in sequence
    foreach ($script in $scripts) {
        Write-Host "`n=== Starting $($script.Name) ===" -ForegroundColor Green
        
        if (-not (Test-Path $script.Path)) {
            throw "Script not found: $($script.Path)"
        }

        & $script.Path
        
        if ($LASTEXITCODE -ne 0) {
            throw "Script failed: $($script.Path)"
        }
        
        Write-Host "=== Completed $($script.Name) ===" -ForegroundColor Green
    }

    Write-Host "`nAll installation steps completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "Installation process failed." -ForegroundColor Red
}
finally {
    # Only show press key prompt if running the script directly (not from setup.bat)
    if ($MyInvocation.InvocationName -eq $MyInvocation.MyCommand.Path) {
        Write-Host "`nPress any key to exit..."
        $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    }
}
