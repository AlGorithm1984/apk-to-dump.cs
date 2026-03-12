param (
    [Parameter(Mandatory=$true)]
    [string]$ApkPath
)

# --- Ensure we have Microsoft.VisualBasic mapped for Safe Deletion ---
Add-Type -AssemblyName Microsoft.VisualBasic
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Helper function for safe deletion
function Remove-Safe {
    param([string]$Path)
    if (Test-Path $Path) {
        $item = Get-Item $Path
        if ($item.PSIsContainer) {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        } else {
            [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
        }
    }
}

# --- Configuration & Paths ---
$BaseDir = Split-Path -Parent $PSScriptRoot
$ToolsDir = Join-Path $BaseDir "core\tools"
$WorkspaceDir = Join-Path $BaseDir "workspace"
$TempExtracted = Join-Path $WorkspaceDir ([guid]::NewGuid().ToString())
$OutputDir = Join-Path $BaseDir "output"

# Create required directories
@($ToolsDir, $WorkspaceDir, $OutputDir) | ForEach-Object {
    if (-not (Test-Path $_)) { New-Item -ItemType Directory -Path $_ -Force | Out-Null }
}

# --- Tool Validation & Auto-Download ---
$AaptPath = Join-Path $ToolsDir "aapt.exe"
$DumperPath = Join-Path $ToolsDir "Il2CppDumper.exe"

if (-not (Test-Path $AaptPath)) {
    Write-Host "[*] aapt.exe is missing. Downloading Android Build Tools (~50MB) for versioning..." -ForegroundColor Yellow
    $aaptZip = Join-Path $ToolsDir "build-tools.zip"
    $aaptTemp = Join-Path $ToolsDir "temp_aapt"
    
    try {
        Invoke-WebRequest -Uri "https://dl.google.com/android/repository/build-tools_r33.0.1-windows.zip" -OutFile $aaptZip -UseBasicParsing
        Write-Host "[*] Extracting aapt.exe..." -ForegroundColor Yellow
        New-Item -ItemType Directory -Path $aaptTemp -Force | Out-Null
        Expand-Archive -Path $aaptZip -DestinationPath $aaptTemp -Force
        
        $aaptFile = Get-ChildItem -Path $aaptTemp -Filter "aapt.exe" -Recurse | Select-Object -First 1
        $pthreadFile = Get-ChildItem -Path $aaptTemp -Filter "libwinpthread-1.dll" -Recurse | Select-Object -First 1
        
        if ($aaptFile) {
            Copy-Item $aaptFile.FullName -Destination $ToolsDir -Force
        }
        if ($pthreadFile) {
            Copy-Item $pthreadFile.FullName -Destination $ToolsDir -Force
        }
    } catch {
        Write-Host "[-] Failed to download or extract aapt.exe: $_" -ForegroundColor Red
    } finally {
        Remove-Safe $aaptTemp
        Remove-Safe $aaptZip
    }
    
    if (Test-Path $AaptPath) {
        Write-Host "[+] aapt.exe configured successfully." -ForegroundColor Green
    } else {
        Write-Host "[-] aapt.exe installation failed. The script cannot automatically determine the APK version." -ForegroundColor Red
        # We don't exit here. We can still try to dump without version number.
    }
}

if (-not (Test-Path $DumperPath)) {
    Write-Host "[*] Il2CppDumper.exe is missing. Downloading latest release from GitHub..." -ForegroundColor Yellow
    
    try {
        # Get latest release from GitHub API
        $releaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/Perfare/Il2CppDumper/releases/latest"
        $downloadUrl = ($releaseInfo.assets | Where-Object { $_.name -match "win-v" } | Select-Object -First 1).browser_download_url
        
        if ($downloadUrl) {
            $dumperZip = Join-Path $ToolsDir "Il2CppDumper.zip"
            Invoke-WebRequest -Uri $downloadUrl -OutFile $dumperZip
            
            Write-Host "[*] Extracting Il2CppDumper..." -ForegroundColor Yellow
            $dumperTemp = Join-Path $ToolsDir "temp_dumper"
            New-Item -ItemType Directory -Path $dumperTemp -Force | Out-Null
            Expand-Archive -Path $dumperZip -DestinationPath $dumperTemp -Force
            
            # Move all contents to Tools
            Get-ChildItem -Path $dumperTemp | Move-Item -Destination $ToolsDir -Force
            
            Remove-Safe $dumperTemp
            Remove-Safe $dumperZip

            # Ensure the tool doesn't wait for 'Any Key' when running automated
            $configPath = Join-Path $ToolsDir "config.json"
            if (Test-Path $configPath) {
                (Get-Content $configPath) -replace '"RequireAnyKey": true', '"RequireAnyKey": false' | Set-Content $configPath
            }
        } else {
            Write-Host "[-] Could not finding Windows release URL for Il2CppDumper." -ForegroundColor Red
        }
    } catch {
        Write-Host "[-] Failed to download Il2CppDumper: $_" -ForegroundColor Red
    }
    
    if (Test-Path $DumperPath) {
        Write-Host "[+] Il2CppDumper configured successfully." -ForegroundColor Green
    } else {
        Write-Host "[-] Critical: Il2CppDumper installation failed." -ForegroundColor Red
        exit
    }
}

# --- Extract Version Info ---
$versionName = "UnknownVersion"
if (Test-Path $AaptPath) {
    Write-Host "[*] Analyzing APK Version..." -ForegroundColor White
    $aaptOutput = (& $AaptPath dump badging $ApkPath) -join "`n"
    if ($aaptOutput -match "versionName='([^']+)'") {
        $versionName = $matches[1]
        Write-Host "[+] Found Game Version: $versionName" -ForegroundColor Green
    } else {
        Write-Host "[-] Could not determine game version (using 'UnknownVersion')." -ForegroundColor Yellow
    }
} else {
    Write-Host "[-] Skipping version checking because aapt.exe is not available." -ForegroundColor Yellow
}

# --- Cleanup previous temp extractions if any ---
if (Test-Path $TempExtracted) {
    Remove-Safe $TempExtracted
}

# --- Extract APK (as ZIP) ---
Write-Host "[*] Unzipping APK to workspace..." -ForegroundColor Yellow
try {
    # .NET extraction logic that supports duplicate entries (by overwriting)
    $zip = [System.IO.Compression.ZipFile]::OpenRead($ApkPath)
    foreach ($entry in $zip.Entries) {
        # Avoid PathTooLongExceptions and handle duplicate entry bugs gracefully
        $destPath = Join-Path $TempExtracted $entry.FullName
        $destDir = Split-Path $destPath -Parent
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        
        if ($entry.Name -ne "") {
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destPath, $true)
        }
    }
} catch {
    Write-Host "[-] Error extracting APK. Is it a valid ZIP or packaged differently? $_" -ForegroundColor Red
    exit
} finally {
    if ($zip) { $zip.Dispose() }
}

# --- Locate Target Files ---
Write-Host "[*] Searching for libil2cpp.so and global-metadata.dat..." -ForegroundColor Yellow
$lib = Get-ChildItem -Path $TempExtracted -Filter "libil2cpp.so" -Recurse | Select-Object -First 1
$metadata = Get-ChildItem -Path $TempExtracted -Filter "global-metadata.dat" -Recurse | Select-Object -First 1

if (-not $lib -or -not $metadata) {
    Write-Host "[-] Critical files (libil2cpp.so or global-metadata.dat) missing from APK. This might not be an Il2Cpp game or uses a split-APK format." -ForegroundColor Red
    exit
}

Write-Host "[+] Found libil2cpp.so at $($lib.FullName)" -ForegroundColor Gray
Write-Host "[+] Found global-metadata.dat at $($metadata.FullName)" -ForegroundColor Gray

# --- Run Il2CppDumper ---
Write-Host "[*] Running Il2CppDumper..." -ForegroundColor Yellow
$dumpArgs = @(
    $lib.FullName,
    $metadata.FullName,
    $OutputDir
)
Write-Output "`n" | & $DumperPath $dumpArgs | Out-Null

# Wait for dump.cs explicitly
$dumpCsFile = Join-Path $OutputDir "dump.cs"
$timeout = 0
while (-not (Test-Path $dumpCsFile) -and $timeout -lt 60) {
    Start-Sleep -Seconds 1
    $timeout++
}

# --- Run Dump Cleaner (C# compilation & execution) ---
if (Test-Path $dumpCsFile) {
    Write-Host "[*] Compiling high-speed C# Dump Cleaner..." -ForegroundColor Yellow
    $cleanerSource = Join-Path $ToolsDir "DumpCleaner.cs"
    $cleanerExe = Join-Path $ToolsDir "DumpCleaner.exe"
    $renamedCs = Join-Path $OutputDir "${versionName}_dump.cs"
    
    # Locate Windows built-in C# compiler (usually packaged with .NET framework)
    $cscPath = Join-Path $env:windir "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
    if (-not (Test-Path $cscPath)) {
        # Fallback to 32-bit if 64-bit somehow doesn't exist
        $cscPath = Join-Path $env:windir "Microsoft.NET\Framework\v4.0.30319\csc.exe"
    }
    
    # Rename the original dump first
    if (Test-Path $renamedCs) { Remove-Safe $renamedCs }
    Rename-Item -Path $dumpCsFile -NewName "${versionName}_dump.cs" -Force

    if ((Test-Path $cleanerSource) -and (Test-Path $cscPath)) {
        if (-not (Test-Path $cleanerExe)) {
            # Compile DumpCleaner.cs on the fly
             & $cscPath "-out:$cleanerExe" $cleanerSource | Out-Null
        }
        
        Write-Host "[*] Cleaning dump.cs to remove framework noise..." -ForegroundColor Yellow
        $cleanedCs = Join-Path $OutputDir "${versionName}_cleaned_dump.cs"
        if (Test-Path $cleanedCs) { Remove-Safe $cleanedCs }
        
        # Execute the compiled C# cleaner on the renamed original file
        & $cleanerExe $renamedCs $cleanedCs | Out-Null
    } else {
        Write-Host "[-] Could not find DumpCleaner.cs or csc.exe. Skipping cleanup phase." -ForegroundColor Yellow
    }
    
    Write-Host "[*] Cleaning up residual Il2CppDumper artifacts..." -ForegroundColor Yellow
    Get-ChildItem -Path $OutputDir | Where-Object { $_.Name -notmatch "_dump\.cs$" } | ForEach-Object { Remove-Safe $_.FullName }

    Write-Host ""
    
    # User-friendly green success screen
    $spaces = " " * 80
    Write-Host ""
    Write-Host $spaces -BackgroundColor DarkGreen
    Write-Host "    SUCCESS! APK Dump and Cleanup Complete!             " -BackgroundColor DarkGreen -ForegroundColor White
    Write-Host $spaces -BackgroundColor DarkGreen
    Write-Host "    Raw Dump File:                                      " -BackgroundColor DarkGreen -ForegroundColor White
    Write-Host "    $renamedCs " -BackgroundColor DarkGreen -ForegroundColor Yellow
    Write-Host "    Cleaned Dump File:                                  " -BackgroundColor DarkGreen -ForegroundColor White
    if (Test-Path $cleanedCs) {
        Write-Host "    $cleanedCs " -BackgroundColor DarkGreen -ForegroundColor Yellow
    } else {
        Write-Host "    (Cleaned version skipped or failed)                 " -BackgroundColor DarkGreen -ForegroundColor Gray
    }
    Write-Host $spaces -BackgroundColor DarkGreen
    Write-Host ""
} else {
    Write-Host "[-] Dumping failed. dump.cs was not found in the output directory." -ForegroundColor Red
}

# --- Final Cleanup ---
Write-Host "[*] Cleaning up workspace..." -ForegroundColor Yellow
Remove-Safe $TempExtracted

Write-Host "[*] All tasks complete." -ForegroundColor Green
