[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

try {
    Write-Host "Starting model download process..." -ForegroundColor Cyan
    
    # Ensure we're in the correct directory
    Set-Location -Path $PSScriptRoot -ErrorAction Stop
    
    # Run the Python script
    Write-Host "Running download_models.py..." -ForegroundColor Yellow
    . .\csm\.venv\Scripts\Activate.ps1
    python download_models.py
    
    if ($LASTEXITCODE -ne 0) {
        throw "Model download failed with exit code $LASTEXITCODE"
    }
    
    Write-Host "Model download completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "Model download failed." -ForegroundColor Red
    throw
}
