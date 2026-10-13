param([string]$ServerRepository = (Join-Path $PSScriptRoot '../../angst-n-anchors-mp'))
$ErrorActionPreference = 'Stop'
$gameRoot = Split-Path $PSScriptRoot -Parent
$serverRoot = (Resolve-Path -LiteralPath $ServerRepository).Path
$gameCatalog = Join-Path $gameRoot 'resources/data/vessels/gameplay_catalog.json'
$serverCatalog = Join-Path $serverRoot 'internal/gameplay/catalog.json'
if ((Get-FileHash -LiteralPath $gameCatalog).Hash -ne (Get-FileHash -LiteralPath $serverCatalog).Hash) {
    throw 'Game and authority catalogs differ. Export and sync the catalog before building.'
}
$gameEngines = Join-Path $gameRoot 'resources/data/vessels/engine_presets.json'
$serverEngines = Join-Path $serverRoot 'internal/gameplay/engine_presets.json'
if ((Get-FileHash -LiteralPath $gameEngines).Hash -ne (Get-FileHash -LiteralPath $serverEngines).Hash) {
    throw 'Game and authority engine presets differ. Sync the authored engine presets before building.'
}
$outDir = Join-Path $gameRoot '.godot/tools'
New-Item -ItemType Directory -Path $outDir -Force | Out-Null
Push-Location $serverRoot
try {
    & go build '-ldflags=-H=windowsgui' -o (Join-Path $outDir 'gameplaylab.exe') ./cmd/gameplaylab
    if ($LASTEXITCODE -ne 0) { throw 'Authority lab build failed.' }
    & go run ./cmd/gameplaylab -export-fixtures (Join-Path $gameRoot 'resources/data/showcases/authority_builds.json')
    if ($LASTEXITCODE -ne 0) { throw 'Construction fixture export failed.' }
} finally { Pop-Location }
Write-Output 'Ready: F6 scenes/showcases/gameplay_data_lab.tscn'
