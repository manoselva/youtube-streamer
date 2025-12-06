param(
    [Parameter(Mandatory=$true)]
    [string]$YoutubeUrl
)

# yt-dlp path
$ytdlpPath = "C:\Users\user\AppData\Local\Microsoft\WinGet\Packages\yt-dlp.yt-dlp_Microsoft.Winget.Source_8wekyb3d8bbwe\yt-dlp.exe"

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

Write-Host "Fetching video and audio URLs..." -ForegroundColor Cyan

# Get video URL (best video quality with webm/mp4)
$videoUrl = & $ytdlpPath --get-url -f "bestvideo[ext=webm]/bestvideo[ext=mp4]/bestvideo" $YoutubeUrl 2>$null | Select-Object -First 1

# Get audio URL (best audio quality)
$audioUrl = & $ytdlpPath --get-url -f "bestaudio[ext=webm]/bestaudio[ext=m4a]/bestaudio" $YoutubeUrl 2>$null | Select-Object -Last 1

if (-not $videoUrl -or -not $audioUrl) {
    Write-Error "Failed to extract URLs from YouTube video."
    exit 1
}

Write-Host "Video URL extracted: $($videoUrl.Substring(0, 60))..." -ForegroundColor Green
Write-Host "Audio URL extracted: $($audioUrl.Substring(0, 60))..." -ForegroundColor Green

# Download subtitles
Write-Host "`nDownloading subtitles..." -ForegroundColor Cyan
$subtitleFile = $null

# Try to download auto-generated subtitles
& $ytdlpPath --skip-download --write-auto-subs --sub-format "srt/vtt/best" --convert-subs srt -o "subtitle" $YoutubeUrl 2>$null

# Check for downloaded subtitle files
$subtitleFiles = Get-ChildItem -Filter "subtitle*.srt" -ErrorAction SilentlyContinue
if ($subtitleFiles) {
    $subtitleFile = $subtitleFiles[0].FullName
    Write-Host "Subtitles downloaded: $subtitleFile" -ForegroundColor Green
} else {
    Write-Host "No subtitles available or download failed." -ForegroundColor Yellow
}

# Build VLC command
Write-Host "`nLaunching VLC..." -ForegroundColor Cyan

$vlcArgs = @(
    $videoUrl
    "--input-slave=$audioUrl"
)

# Add subtitle if available
if ($subtitleFile) {
    $vlcArgs += "--sub-file=$subtitleFile"
}

# Launch VLC
Start-Process -FilePath ".\vlc.exe" -ArgumentList $vlcArgs -NoNewWindow

Write-Host "`nVLC launched successfully!" -ForegroundColor Green
Write-Host "The video should start playing with audio and subtitles (if available)." -ForegroundColor Green

# Optional: Clean up subtitle files after VLC closes
Write-Host "`nPress any key to clean up subtitle files..." -ForegroundColor Yellow
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

if ($subtitleFile -and (Test-Path $subtitleFile)) {
    Remove-Item "subtitle*.*" -Force
    Write-Host "Subtitle files cleaned up." -ForegroundColor Green
}
