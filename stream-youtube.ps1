param(
    [Parameter(Mandatory=$true)]
    [string]$YoutubeUrl
)

# Color definitions
$colors = @{
    Header = "Cyan"
    Success = "Green"
    Warning = "Yellow"
    Error = "Red"
    Info = "Blue"
    Highlight = "Magenta"
}

# yt-dlp path
$ytdlpPath = "C:\Users\user\AppData\Local\Microsoft\WinGet\Packages\yt-dlp.yt-dlp_Microsoft.Winget.Source_8wekyb3d8bbwe\yt-dlp.exe"

# VLC path
$vlcPath = "C:\Program Files (x86)\VideoLAN\VLC\vlc.exe"

# Base directory for saving video details
$baseDir = "C:\Users\user\AppData\Local\Temp\New folder"
$logFile = Join-Path $baseDir "video_cache.log"

# Check if yt-dlp is available
if (-not (Test-Path $ytdlpPath)) {
    Write-Host "[X] ERROR: yt-dlp is not found at: $ytdlpPath" -ForegroundColor $colors.Error
    exit 1
}

# Check if VLC is available
if (-not (Test-Path $vlcPath)) {
    Write-Host "[X] ERROR: vlc.exe not found at: $vlcPath" -ForegroundColor $colors.Error
    exit 1
}

# Ensure base directory exists
if (-not (Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
}

Write-Host "`n[*] Checking cache for previously processed video..." -ForegroundColor $colors.Header

# Check if video was previously processed
$cached = $false
$videoDir = $null
$subtitleFile = $null

if (Test-Path $logFile) {
    $logContent = Get-Content $logFile -Raw
    $logEntries = $logContent | ConvertFrom-Json
    
    # Handle both single object and array
    if ($logEntries -isnot [Array]) {
        $logEntries = @($logEntries)
    }
    
    $existingEntry = $logEntries | Where-Object { $_.YoutubeUrl -eq $YoutubeUrl }
    
    if ($existingEntry) {
        $videoDir = $existingEntry.VideoDir
        
        # Check if directory still exists
        if (Test-Path $videoDir) {
            Write-Host "[+] Found cached video directory!" -ForegroundColor $colors.Success
            Write-Host "    Directory: $videoDir" -ForegroundColor $colors.Info
            
            # Check for subtitle file
            $subtitleFiles = Get-ChildItem -Path $videoDir -Filter "subtitle*.srt" -ErrorAction SilentlyContinue
            if ($subtitleFiles) {
                $subtitleFile = $subtitleFiles[0].FullName
                Write-Host "[+] Subtitle file found: $(Split-Path $subtitleFile -Leaf)" -ForegroundColor $colors.Success
            }
            
            $cached = $true
        } else {
            Write-Host "[!] Cached directory missing, will create new one." -ForegroundColor $colors.Warning
        }
    }
}

# If not cached, create directory and download subtitles
if (-not $cached) {
    Write-Host "`n[*] Video not in cache. Setting up..." -ForegroundColor $colors.Header
    
    # Get video title for directory name
    $videoTitleOutput = & $ytdlpPath --get-title $YoutubeUrl 2>$null
    
    # Handle array output - take first element and convert to string
    if ($videoTitleOutput -is [Array]) {
        $videoTitle = [string]$videoTitleOutput[0]
    } else {
        $videoTitle = [string]$videoTitleOutput
    }
    
    # Check if title is valid
    if ([string]::IsNullOrWhiteSpace($videoTitle)) {
        Write-Host "[X] ERROR: Could not fetch video title. Check the YouTube URL." -ForegroundColor $colors.Error
        exit 1
    }
    
    # Remove invalid characters
    $videoTitle = $videoTitle.Trim() -replace '[\\/:*?"<>|]', '_'
    
    # Create directory for this video
    $videoDir = Join-Path $baseDir $videoTitle
    if (-not (Test-Path $videoDir)) {
        New-Item -ItemType Directory -Path $videoDir -Force | Out-Null
    }
    
    Write-Host "[+] Video directory created: $(Split-Path $videoDir -Leaf)" -ForegroundColor $colors.Success
    
    # Download subtitles
    Write-Host "`n[*] Downloading subtitles..." -ForegroundColor $colors.Header
    
    # Change to video directory for subtitle download
    Push-Location $videoDir
    
    # Try to download auto-generated subtitles with embed-chapters
    & $ytdlpPath --skip-download --write-auto-subs --embed-chapters --sub-format "srt/vtt/best" --convert-subs srt -o "subtitle" $YoutubeUrl 2>$null
    
    # Check for downloaded subtitle files
    $subtitleFiles = Get-ChildItem -Filter "subtitle*.srt" -ErrorAction SilentlyContinue
    if ($subtitleFiles) {
        $subtitleFile = $subtitleFiles[0].FullName
        Write-Host "[+] Subtitles downloaded: $(Split-Path $subtitleFile -Leaf)" -ForegroundColor $colors.Success
    } else {
        Write-Host "[!] No subtitles available or download failed." -ForegroundColor $colors.Warning
    }
    
    # Return to original directory
    Pop-Location
    
    # Update log file
    Write-Host "`n[*] Updating cache log..." -ForegroundColor $colors.Header
    
    $logEntries = @()
    if (Test-Path $logFile) {
        $existingContent = Get-Content $logFile -Raw | ConvertFrom-Json
        if ($existingContent -is [Array]) {
            $logEntries = [System.Collections.ArrayList]@($existingContent)
        } else {
            $logEntries = [System.Collections.ArrayList]@($existingContent)
        }
    } else {
        $logEntries = [System.Collections.ArrayList]@()
    }
    
    # Add new entry
    $newEntry = [PSCustomObject]@{
        YoutubeUrl = $YoutubeUrl
        VideoDir = $videoDir
        CachedOn = (Get-Date).ToString()
    }
    
    $logEntries.Add($newEntry) | Out-Null
    $logEntries | ConvertTo-Json | Out-File -FilePath $logFile -Encoding UTF8
    
    Write-Host "[+] Cache log updated successfully!" -ForegroundColor $colors.Success
}

# ALWAYS fetch fresh URLs for optimal streaming performance
Write-Host "`n[*] Fetching fresh stream URLs for optimal performance..." -ForegroundColor $colors.Header

# Select the absolute best combined format available (video+audio together)
# This prioritizes combined streams for better performance over separate video+audio
# Will select highest resolution available (4K, 2K, 1080p, 720p, etc.)
$videoUrl = & $ytdlpPath --get-url -f "best" $YoutubeUrl 2>$null | Select-Object -First 1

# Check if we got a combined format or separate streams
$allUrls = & $ytdlpPath --get-url -f "best" $YoutubeUrl 2>$null

if ($allUrls -is [Array] -and $allUrls.Count -gt 1) {
    # Separate video and audio streams
    $audioUrl = $allUrls[1]
    $useSeparateAudio = $true
} else {
    # Combined stream (best for performance)
    $audioUrl = $null
    $useSeparateAudio = $false
}

if (-not $videoUrl) {
    Write-Host "[X] ERROR: Failed to extract URLs from YouTube video." -ForegroundColor $colors.Error
    exit 1
}

if ($useSeparateAudio) {
    Write-Host "[+] Video URL extracted: $($videoUrl.Substring(0, 60))..." -ForegroundColor $colors.Success
    Write-Host "[+] Audio URL extracted: $($audioUrl.Substring(0, 60))..." -ForegroundColor $colors.Success
} else {
    Write-Host "[+] Combined stream URL extracted: $($videoUrl.Substring(0, 60))..." -ForegroundColor $colors.Success
    Write-Host "[*] Using single combined stream for optimal performance" -ForegroundColor $colors.Info
}

# Build VLC command
Write-Host "`n[*] Launching VLC Media Player..." -ForegroundColor $colors.Highlight

$vlcArgs = @(
    $videoUrl
)

# Add audio slave if separate
if ($useSeparateAudio -and $audioUrl) {
    $vlcArgs += "--input-slave=$audioUrl"
}

# Enable subtitle auto-detection
$vlcArgs += "--sub-autodetect-file"

# Add subtitle if available
if ($subtitleFile) {
    $vlcArgs += "--sub-file=`"$subtitleFile`""
    $vlcArgs += "--sub-track=0"
}

# Launch VLC
Start-Process -FilePath $vlcPath -ArgumentList $vlcArgs -NoNewWindow

$separator = "=" * 65
Write-Host "`n$separator" -ForegroundColor $colors.Highlight
Write-Host "[+] VLC launched successfully with fresh URLs!" -ForegroundColor $colors.Success
Write-Host "[*] Cache: $(Split-Path $videoDir -Leaf)" -ForegroundColor $colors.Info
Write-Host "$separator`n" -ForegroundColor $colors.Highlight

# Ask user if there's an error
Write-Host "`n[?] Did VLC show an error? (Y/N)" -ForegroundColor Yellow
Write-Host "    Press Y to clear cache and retry" -ForegroundColor DarkGray
Write-Host "    Press any other key to exit" -ForegroundColor DarkGray
Write-Host ""

$response = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

if ($response.Character -eq 'y' -or $response.Character -eq 'Y') {
    Write-Host "`n[!] Clearing cache..." -ForegroundColor $colors.Warning
    
    # Kill VLC if still running
    Get-Process -Name "vlc" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    
    # Delete entire video directory
    if (Test-Path $videoDir) {
        Remove-Item $videoDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "[+] Deleted video directory" -ForegroundColor $colors.Success
    }
    
    # Remove from cache log
    if (Test-Path $logFile) {
        try {
            $logContent = Get-Content $logFile -Raw -ErrorAction SilentlyContinue
            if ($logContent) {
                $logEntries = $logContent | ConvertFrom-Json
                
                if ($logEntries -isnot [Array]) {
                    $logEntries = @($logEntries)
                }
                
                $filteredEntries = [System.Collections.ArrayList]@($logEntries | Where-Object { $_.YoutubeUrl -ne $YoutubeUrl })
                
                if ($filteredEntries.Count -gt 0) {
                    $filteredEntries | ConvertTo-Json | Out-File -FilePath $logFile -Encoding UTF8
                } else {
                    Remove-Item $logFile -Force -ErrorAction SilentlyContinue
                }
                Write-Host "[+] Updated cache log" -ForegroundColor $colors.Success
            }
        } catch {
            Write-Host "[!] Could not update cache log" -ForegroundColor DarkGray
        }
    }
    
    Write-Host "`n[***] RESTARTING WITH FRESH SETUP [***]" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor DarkCyan
    
    Start-Sleep -Seconds 1
    
    # Re-run the script
    & $PSCommandPath $YoutubeUrl
} else {
    Write-Host "`n[*] Exiting. Enjoy your video!" -ForegroundColor $colors.Success
}
