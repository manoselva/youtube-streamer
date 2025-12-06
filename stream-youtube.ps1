param(
    [Parameter(Mandatory=$true)]
    [string]$YoutubeUrl
)

# yt-dlp path
$ytdlpPath = "C:\Users\user\AppData\Local\Microsoft\WinGet\Packages\yt-dlp.yt-dlp_Microsoft.Winget.Source_8wekyb3d8bbwe\yt-dlp.exe"

# Base directory for saving video details
$baseDir = "C:\Users\user\AppData\Local\Temp\New folder"
$logFile = Join-Path $baseDir "video_cache.log"

# Check if yt-dlp is available
if (-not (Test-Path $ytdlpPath)) {
    Write-Error "yt-dlp is not found at: $ytdlpPath"
    exit 1
}

# Check if VLC is in current directory
if (-not (Test-Path ".\vlc.exe")) {
    Write-Error "vlc.exe not found in current directory."
    exit 1
}

# Ensure base directory exists
if (-not (Test-Path $baseDir)) {
    New-Item -ItemType Directory -Path $baseDir -Force | Out-Null
}

Write-Host "Checking cache for previously processed video..." -ForegroundColor Cyan

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
            Write-Host "Found cached video! Loading from: $videoDir" -ForegroundColor Green
            
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
                    Write-Host "Subtitle file found: $subtitleFile" -ForegroundColor Green
                }
                
                $cached = $true
                Write-Host "Using cached URLs:" -ForegroundColor Green
                Write-Host "Video URL: $($videoUrl.Substring(0, [Math]::Min(60, $videoUrl.Length)))..." -ForegroundColor Green
                Write-Host "Audio URL: $($audioUrl.Substring(0, [Math]::Min(60, $audioUrl.Length)))..." -ForegroundColor Green
            } else {
                Write-Host "Failed to parse cached URLs, will fetch new ones." -ForegroundColor Yellow
            }
        } else {
            Write-Host "Cached directory or files missing, will fetch new data." -ForegroundColor Yellow
        }
    }
}

# If not cached, fetch new URLs
if (-not $cached) {
    Write-Host "Video not in cache. Fetching video title..." -ForegroundColor Cyan
    
    # Get video title for directory name
    $videoTitle = & $ytdlpPath --get-title $YoutubeUrl 2>$null
    $videoTitle = $videoTitle -replace '[\\/:*?"<>|]', '_'  # Remove invalid characters
    
    # Create directory for this video
    $videoDir = Join-Path $baseDir $videoTitle
    if (-not (Test-Path $videoDir)) {
        New-Item -ItemType Directory -Path $videoDir -Force | Out-Null
    }
    
    Write-Host "Video directory: $videoDir" -ForegroundColor Green
    
    Write-Host "`nFetching available formats..." -ForegroundColor Cyan
    
    # Get all available formats
    $formats = & $ytdlpPath -F $YoutubeUrl 2>$null
    
    Write-Host "`nFetching video and audio URLs..." -ForegroundColor Cyan
    
    # Get video URL (best quality available)
    $videoUrl = & $ytdlpPath --get-url -f "bestvideo" $YoutubeUrl 2>$null | Select-Object -First 1
    
    # Get audio URL (best audio quality)
    $audioUrl = & $ytdlpPath --get-url -f "bestaudio" $YoutubeUrl 2>$null | Select-Object -Last 1
    
    if (-not $videoUrl -or -not $audioUrl) {
        Write-Error "Failed to extract URLs from YouTube video."
        exit 1
    }
    
    Write-Host "Video URL extracted: $($videoUrl.Substring(0, 60))..." -ForegroundColor Green
    Write-Host "Audio URL extracted: $($audioUrl.Substring(0, 60))..." -ForegroundColor Green
    
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
    
    Write-Host "URLs saved to: $urlsFile" -ForegroundColor Green
    
    # Download subtitles
    Write-Host "`nDownloading subtitles..." -ForegroundColor Cyan
    
    # Change to video directory for subtitle download
    Push-Location $videoDir
    
    # Try to download auto-generated subtitles with embed-chapters
    & $ytdlpPath --skip-download --write-auto-subs --embed-chapters --sub-format "srt/vtt/best" --convert-subs srt -o "subtitle" $YoutubeUrl 2>$null
    
    # Check for downloaded subtitle files
    $subtitleFiles = Get-ChildItem -Filter "subtitle*.srt" -ErrorAction SilentlyContinue
    if ($subtitleFiles) {
        $subtitleFile = $subtitleFiles[0].FullName
        Write-Host "Subtitles downloaded: $subtitleFile" -ForegroundColor Green
    } else {
        Write-Host "No subtitles available or download failed." -ForegroundColor Yellow
    }
    
    # Return to original directory
    Pop-Location
    
    # Update log file
    Write-Host "`nUpdating cache log..." -ForegroundColor Cyan
    
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
    
    Write-Host "Cache log updated." -ForegroundColor Green
}

# Build VLC command
Write-Host "`nLaunching VLC..." -ForegroundColor Cyan

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
Start-Process -FilePath ".\vlc.exe" -ArgumentList $vlcArgs -NoNewWindow

Write-Host "`nVLC launched successfully!" -ForegroundColor Green
Write-Host "The video should start playing with audio and subtitles (if available)." -ForegroundColor Green
Write-Host "`nVideo details saved in: $videoDir" -ForegroundColor Cyan
