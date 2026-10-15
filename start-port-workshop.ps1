param(
    [string]$GodotPath = '',
    [string]$PortFile = '',
    [switch]$Capture,
    [switch]$Empty,
    [switch]$Fishing,
    [switch]$Starter,
    [switch]$Travel,
    [string[]]$TravelPortFiles = @()
)

$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
if ($Starter -and ($Fishing -or $Empty -or $Travel -or $PortFile)) {
    throw 'Starter opens the finished first fishing port. Use it separately from other examples.'
}
if ($Fishing -and ($Empty -or $Travel -or $PortFile)) {
    throw 'Fishing opens the compact fishing example. Use it separately from Empty, Travel or PortFile.'
}
if ($Travel -and ($Empty -or $PortFile)) {
    throw 'Use -TravelPortFiles with -Travel. Use -PortFile or -Empty for the editable workshop.'
}
if ($TravelPortFiles.Count -gt 0 -and -not $Travel) {
    throw 'TravelPortFiles requires -Travel. Imported travel documents are read-only.'
}
$resolvedTravelFiles = foreach ($travelFile in $TravelPortFiles) {
    if ([string]::IsNullOrWhiteSpace($travelFile)) { throw 'TravelPortFiles must contain saved port JSON paths.' }
    $resolvedTravelFile = (Resolve-Path -LiteralPath $travelFile -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $resolvedTravelFile -PathType Leaf)) { throw 'Every TravelPortFiles entry must be a saved port JSON file.' }
    $resolvedTravelFile
}
if ($PortFile) {
    if ($Empty) { throw 'Use either -Empty or -PortFile, not both.' }
    $PortFile = (Resolve-Path -LiteralPath $PortFile -ErrorAction Stop).Path
    if (-not (Test-Path -LiteralPath $PortFile -PathType Leaf)) { throw 'PortFile must be a saved port JSON file.' }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($godotCommand) {
        $GodotPath = $godotCommand.Source
    } else {
        $packageRoots = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
            (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\WinGet\Packages')
        ) | Select-Object -Unique
        $packages = foreach ($packageRoot in $packageRoots) {
            if (Test-Path -LiteralPath $packageRoot -PathType Container) {
                Get-ChildItem -LiteralPath $packageRoot -Directory -Filter 'GodotEngine.GodotEngine_*'
            }
        }
        $package = $packages | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($package) {
            $executable = Get-ChildItem -LiteralPath $package.FullName -File -Filter '*win64_console.exe' |
                Select-Object -First 1
            if ($executable) { $GodotPath = $executable.FullName }
        }
    }
}
if (-not $GodotPath -or -not (Test-Path -LiteralPath $GodotPath -PathType Leaf)) {
    throw 'Godot was not found. Supply -GodotPath pointing to your Godot executable.'
}

# A separate profile prevents workshop settings or test saves touching a captain.
$profilePath = Join-Path $env:LOCALAPPDATA 'AngstPortWorkshop'
New-Item -ItemType Directory -Path $profilePath -Force | Out-Null
$previousAppData = $env:APPDATA
$env:APPDATA = $profilePath
try {
    $scene = if ($Travel) { 'res://scenes/showcases/custom_port_streaming_showcase.tscn' } elseif ($Starter) { 'res://scenes/showcases/custom_port_starter_showcase.tscn' } elseif ($Fishing) { 'res://scenes/showcases/custom_port_fishing_showcase.tscn' } else { 'res://scenes/showcases/custom_port_showcase.tscn' }
    $arguments = @('--path', $projectPath, '--windowed', '--resolution', '1440x900',
        '--log-file', (Join-Path $profilePath 'port-workshop.log'),
        $scene, '--', '--shipyard-playtest')
    if ($Capture) { $arguments += $(if ($Travel) { '--verify-streaming' } else { '--capture-custom-port' }) }
    if ($Empty) { $arguments += '--empty-custom-port' }
    if ($PortFile) { $arguments += "--port-document=$PortFile" }
    foreach ($travelFile in $resolvedTravelFiles) { $arguments += "--travel-port-document=$travelFile" }
    & $GodotPath @arguments
    if ($LASTEXITCODE -ne 0) { throw "Port workshop exited with code $LASTEXITCODE. See $profilePath\port-workshop.log" }
} finally {
    $env:APPDATA = $previousAppData
}
