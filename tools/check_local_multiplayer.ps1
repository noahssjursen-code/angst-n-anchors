param(
    [Parameter(Mandatory=$true)][string]$Godot,
    [string]$ServerRepository = (Join-Path $PSScriptRoot '../../angst-n-anchors-mp'),
    [switch]$CheckPersistence
)

$ErrorActionPreference = 'Stop'
$gameRoot = Split-Path $PSScriptRoot -Parent
$serverRoot = (Resolve-Path -LiteralPath $ServerRepository).Path
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) { throw 'Supply the Godot console executable path.' }
foreach ($pair in @(
    @('resources/data/vessels/gameplay_catalog.json', 'internal/gameplay/catalog.json'),
    @('resources/data/vessels/engine_presets.json', 'internal/gameplay/engine_presets.json')
)) {
    if ((Get-FileHash -LiteralPath (Join-Path $gameRoot $pair[0])).Hash -ne
        (Get-FileHash -LiteralPath (Join-Path $serverRoot $pair[1])).Hash) {
        throw "Game and server definitions differ: $($pair[0]). Sync authored definitions first."
    }
}
Push-Location $serverRoot
try {
    & go test ./...
    if ($LASTEXITCODE -ne 0) { throw 'Server tests failed.' }
    & docker compose -p angst-anchors-dev -f docker-compose.yml -f docker-compose.dev.yml up --build -d --wait
    if ($LASTEXITCODE -ne 0) { throw 'Local multiplayer Docker startup failed.' }
    if ($CheckPersistence) { & ./tests/persistence_integration.ps1 }
} finally { Pop-Location }
Push-Location $gameRoot
try {
    & $Godot --headless --editor --path $gameRoot --quit -- --shipyard-playtest
    if ($LASTEXITCODE -ne 0) { throw 'Godot import failed.' }
    foreach ($test in @('vessel_blueprint_replication_test', 'harbour_blueprint_deployment_test', 'authority_vessel_assembly_test', 'mp_blueprint_flow_test')) {
        & $Godot --headless --path $gameRoot "res://tests/$test.tscn" -- --shipyard-playtest
        if ($LASTEXITCODE -ne 0) { throw "Godot test failed: $test" }
    }
} finally { Pop-Location }
Write-Output 'Local multiplayer blueprint checks passed. Docker remains running on localhost:8080 / UDP 7777.'
