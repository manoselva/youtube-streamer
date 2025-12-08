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
$videoUrl = $null
$audioUrl = $null
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
        
        # Check if directory and urls.txt still exist
        $urlsFile = Join-Path $videoDir "urls.txt"
        if ((Test-Path $videoDir) -and (Test-Path $urlsFile)) {
            Write-Host "[+] Found cached video! Loading from cache..." -ForegroundColor $colors.Success
            Write-Host "    Directory: $videoDir" -ForegroundColor $colors.Info
            
            # Read URLs from file line by line
            $urlLines = Get-Content $urlsFile
            $videoUrlLine = $null
            $audioUrlLine = $null
            
            for ($i = 0; $i -lt $urlLines.Length; $i++) {
                if ($urlLines[$i] -eq "Video URL:" -and $i + 1 -lt $urlLines.Length) {
                    $videoUrlLine = $urlLines[$i + 1].Trim()
                }
                if ($urlLines[$i] -eq "Audio URL:" -and $i + 1 -lt $urlLines.Length) {
                    $audioUrlLine = $urlLines[$i + 1].Trim()
                }
            }
            
            if ($videoUrlLine -and $audioUrlLine -and $videoUrlLine.Length -gt 0 -and $audioUrlLine.Length -gt 0) {
                $videoUrl = $videoUrlLine
                $audioUrl = $audioUrlLine
                
                # Check for subtitle file
                $subtitleFiles = Get-ChildItem -Path $videoDir -Filter "subtitle*.srt" -ErrorAction SilentlyContinue
                if ($subtitleFiles) {
                    $subtitleFile = $subtitleFiles[0].FullName
                    Write-Host "[+] Subtitle file found: $(Split-Path $subtitleFile -Leaf)" -ForegroundColor $colors.Success
                }
                
                $cached = $true
                Write-Host "`n[*] Using cached URLs:" -ForegroundColor $colors.Highlight
                Write-Host "    Video: $($videoUrl.Substring(0, [Math]::Min(60, $videoUrl.Length)))..." -ForegroundColor $colors.Info
                Write-Host "    Audio: $($audioUrl.Substring(0, [Math]::Min(60, $audioUrl.Length)))..." -ForegroundColor $colors.Info
            } else {
                Write-Host "[!] Failed to parse cached URLs, will fetch new ones." -ForegroundColor $colors.Warning
            }
        } else {
            Write-Host "[!] Cached directory or files missing, will fetch new data." -ForegroundColor $colors.Warning
        }
    }
}

# If not cached, fetch new URLs
if (-not $cached) {
    Write-Host "`n[*] Video not in cache. Fetching video information..." -ForegroundColor $colors.Header
    
    # Get video title for directory name
    $videoTitle = & $ytdlpPath --get-title $YoutubeUrl 2>$null
    $videoTitle = $videoTitle -replace '[\\/:*?"<>|]', '_'
    
    # Create directory for this video
    $videoDir = Join-Path $baseDir $videoTitle
    if (-not (Test-Path $videoDir)) {
        New-Item -ItemType Directory -Path $videoDir -Force | Out-Null
    }
    
    Write-Host "[+] Video directory created: $(Split-Path $videoDir -Leaf)" -ForegroundColor $colors.Success
    
    Write-Host "`n[*] Fetching available formats..." -ForegroundColor $colors.Header
    
    # Get all available formats
    $formatsOutput = & $ytdlpPath -F $YoutubeUrl 2>$null
    
    Write-Host "`n[*] Analyzing formats and selecting best quality..." -ForegroundColor $colors.Header
    
    # Get video URL (best video+audio combined format, or best video only)
    $videoUrl = & $ytdlpPath --get-url -f "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo[ext=webm]+bestaudio[ext=webm]/bestvideo+bestaudio/best" $YoutubeUrl 2>$null | Select-Object -First 1
    
    # Get audio URL (best audio quality)
    $audioUrl = & $ytdlpPath --get-url -f "bestaudio[ext=m4a]/bestaudio[ext=webm]/bestaudio" $YoutubeUrl 2>$null | Select-Object -Last 1
    
    if (-not $videoUrl -or -not $audioUrl) {
        Write-Host "[X] ERROR: Failed to extract URLs from YouTube video." -ForegroundColor $colors.Error
        exit 1
    }
    
    Write-Host "[+] Video URL extracted: $($videoUrl.Substring(0, 60))..." -ForegroundColor $colors.Success
    Write-Host "[+] Audio URL extracted: $($audioUrl.Substring(0, 60))..." -ForegroundColor $colors.Success
    
    # Save URLs to file
    $urlsFile = Join-Path $videoDir "urls.txt"
    @"
Video URL:
$videoUrl

Audio URL:
$audioUrl

YouTube URL:
$YoutubeUrl

Generated on: $(Get-Date)
"@ | Out-File -FilePath $urlsFile -Encoding UTF8
    
    Write-Host "[+] URLs saved to: urls.txt" -ForegroundColor $colors.Success
    
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

# Build VLC command
Write-Host "`n[*] Launching VLC Media Player..." -ForegroundColor $colors.Highlight

$vlcArgs = @(
    $videoUrl
    "--input-slave=$audioUrl"
    "--sub-autodetect-file"
)

# Add subtitle if available
if ($subtitleFile) {
    $vlcArgs += "--sub-file=`"$subtitleFile`""
    $vlcArgs += "--sub-track=0"
}

# Launch VLC
Write-Host "[*] Launching VLC Media Player..." -ForegroundColor $colors.Highlight

Start-Process -FilePath $vlcPath -ArgumentList $vlcArgs -NoNewWindow

$separator = "=" * 65
Write-Host "`n$separator" -ForegroundColor $colors.Highlight
Write-Host "[+] VLC launched successfully!" -ForegroundColor $colors.Success
Write-Host "[*] Cache: $(Split-Path $videoDir -Leaf)" -ForegroundColor $colors.Info
Write-Host "$separator`n" -ForegroundColor $colors.Highlight

# Ask user if there's an error
Write-Host "`n[?] Did VLC show an error? (Y/N)" -ForegroundColor Yellow
Write-Host "    Press Y to clear cache and fetch fresh URLs" -ForegroundColor DarkGray
Write-Host "    Press any other key to exit" -ForegroundColor DarkGray
Write-Host ""

$response = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

if ($response.Character -eq 'y' -or $response.Character -eq 'Y') {
    Write-Host "`n[!] Clearing expired cache..." -ForegroundColor $colors.Warning
    
    # Kill VLC if still running
    Get-Process -Name "vlc" -ErrorAction SilentlyContinue | Stop-Process -Force
    Start-Sleep -Seconds 1
    
    # Delete cached files for this video
    if (Test-Path $videoDir) {
        $urlsFile = Join-Path $videoDir "urls.txt"
        if (Test-Path $urlsFile) {
            Remove-Item $urlsFile -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Deleted expired URLs" -ForegroundColor $colors.Success
        }
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
    
    Write-Host "`n[***] RESTARTING WITH FRESH URLS [***]" -ForegroundColor Cyan
    Write-Host "================================================================`n" -ForegroundColor DarkCyan
    
    Start-Sleep -Seconds 1
    
    # Re-run the script
    & $PSCommandPath $YoutubeUrl
} else {
    Write-Host "`n[*] Exiting. Enjoy your video!" -ForegroundColor $colors.Success
}
