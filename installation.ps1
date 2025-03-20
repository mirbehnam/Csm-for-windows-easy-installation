[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

function Use-Python310 {
    # Get all python.exe in PATH
    $pythonPaths = Get-Command python -All -ErrorAction SilentlyContinue | 
                  Where-Object { $_.Source -notlike "*WindowsApps*" } | 
                  Select-Object -ExpandProperty Source

    foreach ($pythonPath in $pythonPaths) {
        $versionOutput = & $pythonPath -c "import sys; print(sys.version.split()[0])" 2>$null
        if ($versionOutput -match "^3\.10\.\d+$") {
            Write-Host "Using Python $versionOutput at: $pythonPath" -ForegroundColor Green
            $pythonDir = Split-Path -Parent $pythonPath
            $env:Path = "$pythonDir;$pythonDir\Scripts;" + $env:Path
            return $true
        }
    }
    Write-Host "Python 3.10.x not found in PATH" -ForegroundColor Red
    return $false
}

try {
    # Verify Python 3.10.0 is available
    if (-not (Use-Python310)) {
        throw "Python 3.10.0 is required but not found in PATH"
    }

    # Change to root directory and verify we're in the right place
    Set-Location -Path $PSScriptRoot -ErrorAction Stop
    Write-Host "Current directory: $((Get-Location).Path)" -ForegroundColor Cyan

    # Create and activate virtual environment in the csm directory
    Set-Location -Path ".\csm" -ErrorAction Stop
    Write-Host "Changed directory to: $((Get-Location).Path)" -ForegroundColor Cyan

    # Create and activate virtual environment
    Write-Host "Creating virtual environment..." -ForegroundColor Yellow
    python -m venv .venv

    # Activate virtual environment
    Write-Host "Activating virtual environment..." -ForegroundColor Yellow
    . .\.venv\Scripts\Activate.ps1

    pip install gradio
    # Check for NVIDIA GPU
    Write-Host "Checking for NVIDIA GPU..." -ForegroundColor Cyan
    $gpuInfo = Get-WmiObject Win32_VideoController | Where-Object { $_.Name -like '*NVIDIA*' }
    
    # Flag to determine if we need to use CPU config
    $useCPUConfig = $false
    
    if ($gpuInfo) {
        Write-Host "NVIDIA GPU detected: $($gpuInfo.Name)" -ForegroundColor Green
        
        # Check GPU VRAM using NVIDIA-SMI
        try {
            $nvidiaSmi = & 'nvidia-smi' '--query-gpu=memory.total' '--format=csv,noheader,nounits' 2>$null
            if ($nvidiaSmi) {
                $vramMB = [int]($nvidiaSmi.Trim())
                $vramGB = [math]::Round($vramMB / 1024, 2)
                Write-Host "GPU VRAM: $vramGB GB" -ForegroundColor Cyan
                
                # Check if VRAM is 8GB or more
                if ($vramGB -ge 8) {
                    Write-Host "GPU has 8GB or more VRAM. Installing GPU-compatible packages..." -ForegroundColor Green
                    $useCPUConfig = $false
                } else {
                    Write-Host "GPU has less than 8GB VRAM ($vramGB GB). Using CPU configuration." -ForegroundColor Yellow
                    $useCPUConfig = $true
                }
            } else {
            Write-Host "`n========================================" -ForegroundColor Yellow
            Write-Host "⚠️ Could not detect VRAM using nvidia-smi" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "`nGPU Information:" -ForegroundColor Cyan
            Write-Host "Model: $($gpuInfo.Name)" -ForegroundColor White
            Write-Host "Driver Version: $($gpuInfo.DriverVersion)" -ForegroundColor White
            
            Write-Host "`nPlease choose installation type:" -ForegroundColor Magenta
            Write-Host "1) GPU Version (Choose if you have 8GB+ VRAM)" -ForegroundColor Green
            Write-Host "   - Faster processing" -ForegroundColor Gray
            Write-Host "   - Requires 8GB+ VRAM" -ForegroundColor Gray
            Write-Host "   - CUDA acceleration" -ForegroundColor Gray
            
            Write-Host "`n2) CPU Version (Choose if unsure)" -ForegroundColor Yellow
            Write-Host "   - Works on any system" -ForegroundColor Gray
            Write-Host "   - Slower processing" -ForegroundColor Gray
            Write-Host "   - No special requirements" -ForegroundColor Gray
            
            Write-Host "`nEnter your choice (1 or 2):" -ForegroundColor Cyan
            $choice = Read-Host
            
            if ($choice -eq "1") {
                Write-Host "`nSelected: GPU Version" -ForegroundColor Green
                $useCPUConfig = $false
            } else {
                Write-Host "`nSelected: CPU Version" -ForegroundColor Yellow
                $useCPUConfig = $true
            }            }
        } catch {
            Write-Host "`n========================================" -ForegroundColor Yellow
            Write-Host "⚠️ Could not detect VRAM using nvidia-smi" -ForegroundColor Yellow
            Write-Host "========================================" -ForegroundColor Yellow
            Write-Host "`nGPU Information:" -ForegroundColor Cyan
            Write-Host "Model: $($gpuInfo.Name)" -ForegroundColor White
            Write-Host "Driver Version: $($gpuInfo.DriverVersion)" -ForegroundColor White
            
            Write-Host "`nPlease choose installation type:" -ForegroundColor Magenta
            Write-Host "1) GPU Version (Choose if you have 8GB+ VRAM)" -ForegroundColor Green
            Write-Host "   - Faster processing" -ForegroundColor Gray
            Write-Host "   - Requires 8GB+ VRAM" -ForegroundColor Gray
            Write-Host "   - CUDA acceleration" -ForegroundColor Gray
            
            Write-Host "`n2) CPU Version (Choose if unsure)" -ForegroundColor Yellow
            Write-Host "   - Works on any system" -ForegroundColor Gray
            Write-Host "   - Slower processing" -ForegroundColor Gray
            Write-Host "   - No special requirements" -ForegroundColor Gray
            
            Write-Host "`nEnter your choice (1 or 2):" -ForegroundColor Cyan
            $choice = Read-Host
            
            if ($choice -eq "1") {
                Write-Host "`nSelected: GPU Version" -ForegroundColor Green
                $useCPUConfig = $false
            } else {
                Write-Host "`nSelected: CPU Version" -ForegroundColor Yellow
                $useCPUConfig = $true
            }
        }
    } else {
        Write-Host "No NVIDIA GPU detected. Using CPU configuration." -ForegroundColor Yellow
        $useCPUConfig = $true
    }
    # Upgrade pip and install base packages
    python -m pip install --upgrade pip

    # If CPU config is needed, run the CPU installation
    if ($useCPUConfig) {
        Write-Host "Use CPU." -ForegroundColor Green
        pip uninstall -y torch torchvision torchaudio bitsandbytes-windows
        pip install triton-windows
        pip install bitsandbytes
        pip install torch==2.6.0
        pip install torchaudio==2.6.0
        pip install tokenizers==0.21.0
        pip install transformers==4.49.0
        pip install huggingface_hub==0.28.1
        pip install moshi==0.2.2
        pip install torchtune==0.4.0
        pip install torchao==0.9.0
        pip install "silentcipher @ git+https://github.com/SesameAILabs/silentcipher@master"
    }else{
        Write-Host "Installing GPU-compatible packages for CUDA 12.4..." -ForegroundColor Yellow
        pip uninstall -y torch torchvision torchaudio bitsandbytes-windows
        pip install triton-windows
        pip install --extra-index-url https://download.pytorch.org/whl/cu118 torch==2.6.0+cu118
        pip install --extra-index-url https://download.pytorch.org/whl/cu118 torchvision==0.21.0+cu118 torchaudio==2.6.0+cu118
        pip install bitsandbytes --find-links https://github.com/jllllll/bitsandbytes-windows-webui/releases/download/wheels/bitsandbytes-0.41.1-py3-none-win_amd64.whl
        pip install torchaudio==2.6.0
        pip install tokenizers==0.21.0
        pip install transformers==4.49.0
        pip install huggingface_hub==0.28.1
        pip install moshi==0.2.2
        pip install torchtune==0.4.0
        pip install torchao==0.9.0
        pip install "silentcipher @ git+https://github.com/SesameAILabs/silentcipher@master"
    }
    
    # Remove the model download part since it's now in a separate script
    Write-Host "`nAll tasks completed successfully!" -ForegroundColor Green
}
catch {
    Write-Host "`nError: $_" -ForegroundColor Red
    Write-Host "Installation encountered errors. Please check the output above." -ForegroundColor Red
}
finally {
    Write-Host "`n" # Just add a newline for spacing
}