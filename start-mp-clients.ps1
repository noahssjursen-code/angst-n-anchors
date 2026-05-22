param(
    [int]$Count = 2,
    [string]$GodotPath = "godot"
)

# Robustly find Godot executable
$godotExe = ""

# 1. Check if provided path is valid
if ($GodotPath -and (Test-Path $GodotPath)) {
    $godotExe = (Resolve-Path $GodotPath).Path
}

# 2. Check if godot is on the PATH
if (-not $godotExe) {
    foreach ($cmd in @("godot", "godot4", "godot.exe")) {
        $found = Get-Command $cmd -ErrorAction SilentlyContinue
        if ($found) {
            $godotExe = $found.Source
            break
        }
    }
}

# 3. Search standard Windows installation and download locations
if (-not $godotExe) {
    $searchPaths = @(
        "$env:LOCALAPPDATA\Programs\Godot",
        "$env:USERPROFILE\Downloads",
        "$env:ProgramFiles\Godot",
        "$env:USERPROFILE\scoop\apps\godot\current",
        "C:\Tools\Godot"
    )
    foreach ($p in $searchPaths) {
        if (Test-Path $p) {
            $files = Get-ChildItem -Path $p -Filter "*godot*.exe" -File -Recurse -ErrorAction SilentlyContinue | 
                     Where-Object { $_.Name -notmatch "console" } |
                     Sort-Object LastWriteTime -Descending
            if ($files -and $files.Count -gt 0) {
                $godotExe = $files[0].FullName
                break
            }
        }
    }
}

if (-not $godotExe) {
    Write-Warning "Could not find a Godot executable on PATH or standard locations."
    Write-Host "Please install Godot, add it to your system PATH, or run this script passing the path to godot.exe:" -ForegroundColor Cyan
    Write-Host "Example: .\start-mp-clients.ps1 -Count 2 -GodotPath C:\Path\To\godot.exe" -ForegroundColor Yellow
    exit 1
}

Write-Host "Using Godot Executable: $godotExe" -ForegroundColor Green
Write-Host "Launching $Count client instances side-by-side..." -ForegroundColor Cyan

# Screen / Positioning setup
# Standard safe sizes for modern screens: 960x540 (half 1080p width)
$width = 960
$height = 540
$yOffset = 150
$xSpacing = 980
$startX = 100

for ($i = 0; $i -lt $Count; $i++) {
    $posX = $startX + ($i * $xSpacing)
    $args = @(
        "--path", "$PSScriptRoot",
        "--windowed",
        "--display/window/size/mode=0",
        "--display/window/size/viewport_width=$width",
        "--display/window/size/viewport_height=$height",
        "--position", "${posX},${yOffset}"
    )
    
    Write-Host "Starting instance $($i + 1) at position ($posX, $yOffset)..." -ForegroundColor DarkCyan
    
    # Launch in background without blocking PowerShell
    Start-Process -FilePath $godotExe -ArgumentList $args -NoNewWindow
}

Write-Host "All instances launched! Happy testing." -ForegroundColor Green
