param(
    [string]$GodotPath = $env:GODOT_BIN,
    [int]$TimeoutSeconds = 30
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $command = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $command) {
        $GodotPath = $command.Source
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath)) {
    $localGodot = "C:\Users\noahs\Downloads\Godot_v4.6.1-stable_win64.exe\Godot_v4.6.1-stable_win64.exe"
    if (Test-Path $localGodot) {
        $GodotPath = $localGodot
    }
}
if ([string]::IsNullOrWhiteSpace($GodotPath) -or -not (Test-Path $GodotPath)) {
    throw "Godot executable not found. Pass -GodotPath or set GODOT_BIN."
}

$stdout = Join-Path $env:TEMP "captain_vessel_hard_stdout_$PID.log"
$stderr = Join-Path $env:TEMP "captain_vessel_hard_stderr_$PID.log"
$arguments = @(
    "--headless",
    "--path", $projectRoot,
    "--quit-after", "20",
    "res://tests/captain_vessel_hard_persistence_test.tscn"
)

try {
    $process = Start-Process `
        -FilePath $GodotPath `
        -ArgumentList $arguments `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr `
        -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        throw "HARD persistence test timed out after $TimeoutSeconds seconds."
    }
    $output = ""
    if (Test-Path $stdout) { $output += Get-Content $stdout -Raw }
    if (Test-Path $stderr) { $output += Get-Content $stderr -Raw }
    Write-Output $output
    $success = "Captain/vessel HARD persistence test: all checks passed"
    if (-not $output.Contains($success)) {
        throw "HARD persistence test failed; success sentinel was not emitted."
    }
}
finally {
    Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue
}
