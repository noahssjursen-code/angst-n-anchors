param(
    [string]$GodotPath = "",
    [string]$Preset = "Windows Desktop",
    [string]$Output = "build/AngstNAnchors.exe"
)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
$outPath = Join-Path $root $Output
$outDir = Split-Path $outPath -Parent

if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

$godotExe = $GodotPath
if (-not $godotExe -or -not (Test-Path $godotExe)) {
    foreach ($candidate in @(
        "godot",
        "godot4",
        "$env:LOCALAPPDATA\Programs\Godot\Godot_v4.6.1-stable_win64.exe",
        "$env:USERPROFILE\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
    )) {
        if ($candidate -match "[/\\]" -or $candidate -match "\.exe$") {
            if (Test-Path $candidate) {
                $godotExe = (Resolve-Path $candidate).Path
                break
            }
        } else {
            $found = Get-Command $candidate -ErrorAction SilentlyContinue
            if ($found) {
                $godotExe = $found.Source
                break
            }
        }
    }
}

if (-not $godotExe -or -not (Test-Path $godotExe)) {
    Write-Error "Godot 4.6.1 not found. Pass -GodotPath to godot.exe"
}

Write-Host "Exporting '$Preset' with $godotExe" -ForegroundColor Cyan
Write-Host "Output: $outPath" -ForegroundColor Cyan

& $godotExe --headless --path $root --export-release $Preset $outPath
if ($LASTEXITCODE -ne 0) {
    throw "Godot export failed with exit code $LASTEXITCODE"
}

$sizeMb = [math]::Round((Get-Item $outPath).Length / 1MB, 1)
Write-Host "Done: $outPath ($sizeMb MB)" -ForegroundColor Green

$zipPath = Join-Path $outDir "AngstNAnchors-win64.zip"
if (Test-Path $zipPath) {
    Remove-Item $zipPath -Force
}
Compress-Archive -Path $outPath -DestinationPath $zipPath -Force
Write-Host "Zip:  $zipPath" -ForegroundColor Green
