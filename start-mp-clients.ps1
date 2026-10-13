param(
    [ValidateRange(1, 8)][int]$Count = 2,
    [string]$GodotPath = "godot",
    [switch]$ManualLogin,
    [switch]$Headless
)

$ErrorActionPreference = 'Stop'
$baseUrl = 'http://127.0.0.1:8080'

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
if (-not $ManualLogin) {
    try {
        $null = Invoke-RestMethod "$baseUrl/readyz" -TimeoutSec 5
        $worldOptions = Invoke-RestMethod "$baseUrl/v1/world-options" -TimeoutSec 5
    } catch {
        throw 'Local multiplayer server is not ready at localhost:8080. Start the Docker server, then run this launcher again.'
    }
    # Reuse these development accounts across launches. Never put passwords or
    # access tokens in the repository, command line, or console output.
    $testFolder = Join-Path $env:LOCALAPPDATA 'Angst-n-Anchors\mp-launcher'
    $null = New-Item -ItemType Directory -Path $testFolder -Force
    $identityPath = Join-Path $testFolder 'test-identity.json'
    if (Test-Path -LiteralPath $identityPath) {
        $testIdentity = Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
    } else {
        $testIdentity = @{ namespace = [guid]::NewGuid().ToString('N'); password = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N') }
        [IO.File]::WriteAllText($identityPath, ($testIdentity | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    }
    if (-not $testIdentity.namespace -or -not $testIdentity.password) { throw 'Invalid local test identity file.' }
}
$logFolder = Join-Path $env:LOCALAPPDATA 'Angst-n-Anchors\mp-launcher\logs'
$null = New-Item -ItemType Directory -Path $logFolder -Force
$runId = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
Write-Host "Launching $Count isolated clients on localhost..." -ForegroundColor Cyan

# Screen / Positioning setup
# Standard safe sizes for modern screens: 960x540 (half 1080p width)
$width = 960
$height = 540
$yOffset = 150
$xSpacing = 980
$startX = 100

for ($i = 0; $i -lt $Count; $i++) {
    $handoff = $null
    if (-not $ManualLogin) {
        $email = "launcher-$($testIdentity.namespace)-$($i + 1)@localhost.test"
        $body = @{ email = $email; password = $testIdentity.password } | ConvertTo-Json -Compress
        try {
            $auth = Invoke-RestMethod "$baseUrl/v2/accounts/login" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 15
        } catch {
            if ([int]$_.Exception.Response.StatusCode -ne 401) { throw "Test account $($i + 1) login failed. Check the localhost server." }
            try {
                $auth = Invoke-RestMethod "$baseUrl/v2/accounts/register" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 15
            } catch { throw "Could not create localhost test account $($i + 1). Check the server log." }
        }
        if (-not $auth.access_token -or -not $auth.account.id) { throw 'Server returned an incomplete account session.' }
        $handoff = @{ base_url = $baseUrl; account = $auth.account; access_token = $auth.access_token; captain_name = "MP Test Captain $($i + 1)"; world_options = $worldOptions } | ConvertTo-Json -Depth 12 -Compress
    }
    $posX = $startX + ($i * $xSpacing)
    $logPath = Join-Path $logFolder "$runId-client-$($i + 1).log"
    $clientArgs = @(
        "--path", "$PSScriptRoot",
        "--windowed",
        "--resolution", "${width}x${height}",
        "--position", "${posX},${yOffset}",
        "--log-file", $logPath
    )
    if ($Headless) { $clientArgs += '--headless' }
    $clientArgs += @('--', "--mp-client-slot=client-$($i + 1)", '--mp-test-window')
    if (-not $ManualLogin) { $clientArgs += '--mp-auto-join' }
    
    Write-Host "Starting instance $($i + 1) at position ($posX, $yOffset) with isolated account storage..." -ForegroundColor DarkCyan
    
    # Explicitly quote paths (the project path may contain spaces). Environment
    # handoff is unique to each child, so the two accounts never race or mix.
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $godotExe
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.Arguments = ($clientArgs | ForEach-Object { '"' + $_ + '"' }) -join ' '
    if ($handoff) { $startInfo.EnvironmentVariables['ANGST_MP_TEST_SESSION'] = $handoff }
    else { $startInfo.EnvironmentVariables.Remove('ANGST_MP_TEST_SESSION') }
    $process = [Diagnostics.Process]::Start($startInfo)
    [pscustomobject]@{ Client = $i + 1; ProcessId = $process.Id; Log = $logPath }
}

Write-Host 'Clients launched. Default: automatic login and join. Use -ManualLogin for the old menu flow.' -ForegroundColor Green
