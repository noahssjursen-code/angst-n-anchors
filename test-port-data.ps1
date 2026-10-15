param(
    [ValidateSet('Simulation', 'Rules', 'All')]
    [string]$Suite = 'Simulation',
    [string]$GodotPath = $env:GODOT_BIN,
    [string]$OutputDirectory = '',
    [ValidateRange(10, 3600)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
$projectPath = $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $godotCommand = Get-Command godot, godot4 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($godotCommand) { $GodotPath = $godotCommand.Source }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $packageRoots = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'),
        (Join-Path $env:USERPROFILE 'AppData\Local\Microsoft\WinGet\Packages')
    ) | Select-Object -Unique
    $packages = foreach ($packageRoot in $packageRoots) {
        if (Test-Path -LiteralPath $packageRoot -PathType Container) {
            Get-ChildItem -LiteralPath $packageRoot -Directory -Filter 'GodotEngine.GodotEngine_*'
        }
    }
    if ($packages) {
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
$GodotPath = (Resolve-Path -LiteralPath $GodotPath).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectPath '.codex\port-data-runs'
}
$runName = '{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutputDirectory)) $runName
New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null

$cases = @()
if ($Suite -in @('Rules', 'All')) {
    $cases += @(
        @{ Name = 'data'; Marker = 'CUSTOM PORT DATA PASS' },
        @{ Name = 'berths'; Marker = 'CUSTOM PORT BERTHS PASS' },
        @{ Name = 'catch_data'; Marker = 'CUSTOM PORT CATCH DATA PASS' },
        @{ Name = 'physical_import'; Marker = 'CUSTOM PORT PHYSICAL IMPORT PASS' },
        @{ Name = 'transform'; Marker = 'CUSTOM PORT TRANSFORM PASS' },
        @{ Name = 'repository'; Marker = 'CUSTOM PORT REPOSITORY PASS' },
        @{ Name = 'collection'; Marker = 'CUSTOM PORT COLLECTION PASS' },
        @{ Name = 'naming'; Marker = 'CUSTOM PORT NAMING PASS' }
    )
}
if ($Suite -in @('Simulation', 'All')) {
    $cases += @{ Name = 'simulation'; Marker = 'CUSTOM PORT SIMULATION PASS' }
}

# Every run has fresh evidence and a separate Godot user profile. Do not reuse a
# captain profile or overwrite older checkpoints when a fixture changes.
$results = [Collections.Generic.List[object]]::new()
$previousAppData = $env:APPDATA
$startedUtc = [DateTime]::UtcNow.ToString('o')
$runError = ''
Write-Output "Port data $Suite checks. Evidence: $runDirectory"
try {
    foreach ($case in $cases) {
        $caseDirectory = Join-Path $runDirectory $case.Name
        $profileDirectory = Join-Path $caseDirectory 'profile'
        New-Item -ItemType Directory -Path $profileDirectory -Force | Out-Null
        $env:APPDATA = $profileDirectory
        $stdout = Join-Path $caseDirectory 'stdout.log'
        $stderr = Join-Path $caseDirectory 'stderr.log'
        $arguments = @('--headless', '--path', $projectPath,
            "res://tests/custom_port_$($case.Name)_test.tscn", '--', '--shipyard-playtest')
        if ($case.Name -eq 'simulation') {
            $arguments += '--port-simulation-output=' + (Join-Path $caseDirectory 'session')
        }
        # Start-Process joins ArgumentList into a Windows command line. All
        # arguments here are literal paths/flags; quote spaces without a shell.
        $quotedArguments = foreach ($argument in $arguments) {
            if ($argument.Contains('"')) { throw 'A test argument contains an invalid quote.' }
            '"' + $argument + '"'
        }
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $testProcess = $null
        $timedOut = $false
        try {
            $testProcess = Start-Process -FilePath $GodotPath -ArgumentList $quotedArguments -WindowStyle Hidden `
                -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
            while (-not $testProcess.WaitForExit(1000)) {
                if ($timer.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                    $timedOut = $true
                    # This is solely the child launched above, never another
                    # editor, game client or Godot process found by name.
                    $testProcess.Kill()
                    $testProcess.WaitForExit()
                    break
                }
            }
            $testProcess.Refresh()
            $exitCode = $testProcess.ExitCode
        } finally {
            if ($null -ne $testProcess) {
                if (-not $testProcess.HasExited) { $testProcess.Kill(); $testProcess.WaitForExit() }
                $testProcess.Dispose()
            }
            $timer.Stop()
        }
        $output = (Get-Content -LiteralPath $stdout -Raw) + "`n" + (Get-Content -LiteralPath $stderr -Raw)
        $marker = ($output -split '\r?\n' | Where-Object { $_.Contains($case.Marker) } | Select-Object -Last 1)
        $errors = @($output -split '\r?\n' | Where-Object { $_ -match '^\s*(SCRIPT ERROR|ERROR):' })
        $passed = -not $timedOut -and $exitCode -eq 0 -and $null -ne $marker -and $errors.Count -eq 0
        $results.Add([ordered]@{
            name = $case.Name; passed = $passed; exit_code = $exitCode; timed_out = $timedOut
            duration_seconds = [Math]::Round($timer.Elapsed.TotalSeconds, 3)
            completion = $marker; errors = $errors; directory = $caseDirectory
        })
        Write-Output ('{0}: {1} ({2:N1}s)' -f $case.Name, $(if ($passed) { 'PASS' } else { 'FAIL' }), $timer.Elapsed.TotalSeconds)
        if (-not $passed) { break }
    }
} catch {
    $runError = $_.Exception.Message
} finally {
    $env:APPDATA = $previousAppData
    $complete = $results.Count -eq $cases.Count -and $runError -eq '' -and @($results | Where-Object { -not $_.passed }).Count -eq 0
    $summary = [ordered]@{
        schema_version = 1; suite = $Suite; passed = $complete
        started_utc = $startedUtc; finished_utc = [DateTime]::UtcNow.ToString('o')
        project_path = $projectPath; godot_path = $GodotPath
        planned_cases = @($cases | ForEach-Object { $_.Name }); results = @($results.ToArray()); error = $runError
    }
    $summary | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runDirectory 'summary.json') -Encoding UTF8
}
if (-not $complete) { throw "Port data checks failed. $runError See $runDirectory\summary.json and the per-case logs." }
Write-Output "All requested port data checks passed. Report: $runDirectory\summary.json"
