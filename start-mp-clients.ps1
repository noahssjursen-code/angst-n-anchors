param(
	[string[]]$PlayerIds = @("player-a", "player-b"),
	[string]$GodotExe = "godot4",
	[string]$ProjectPath = $PSScriptRoot,
	[switch]$DryRun,
	[switch]$Wait
)

function Get-ConfiguredGodotExe {
	param([string]$ProjectRoot)

	$fromEnv = $env:AAN_GODOT_EXE
	if (-not [string]::IsNullOrWhiteSpace($fromEnv)) {
		return $fromEnv.Trim()
	}

	$localConfigPath = Join-Path $ProjectRoot "godot-exe.local.txt"
	if (Test-Path -LiteralPath $localConfigPath) {
		$line = (Get-Content -LiteralPath $localConfigPath -ErrorAction SilentlyContinue |
			Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
			Select-Object -First 1)
		if (-not [string]::IsNullOrWhiteSpace($line)) {
			return $line.Trim()
		}
	}

	return $null
}

function Resolve-GodotExe {
	param([string]$RequestedExe)

	# 1) Explicit path from -GodotExe
	if (Test-Path -LiteralPath $RequestedExe) {
		return (Resolve-Path -LiteralPath $RequestedExe).Path
	}

	# 2) Command on PATH (godot4, godot4.exe, godot, godot.exe, etc.)
	$fromPath = Get-Command -Name $RequestedExe -ErrorAction SilentlyContinue
	if ($fromPath -ne $null) {
		return $fromPath.Source
	}

	# 3) Common command names on PATH
	foreach ($name in @("godot4", "godot4.exe", "godot", "godot.exe")) {
		$cmd = Get-Command -Name $name -ErrorAction SilentlyContinue
		if ($cmd -ne $null) {
			return $cmd.Source
		}
	}

	# 4) Common Windows install locations
	$candidates = @(
		"$env:USERPROFILE\scoop\apps\godot\current\godot.exe",
		"$env:LOCALAPPDATA\Programs\Godot\Godot_v4.6-stable_win64.exe",
		"$env:LOCALAPPDATA\Programs\Godot\Godot.exe",
		"$env:ProgramFiles\Godot\Godot_v4.6-stable_win64.exe",
		"$env:ProgramFiles\Godot\Godot.exe",
		"$env:ProgramFiles(x86)\Godot\Godot.exe"
	)
	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}

	# 5) Last-resort quick scan in a few likely folders
	$scanRoots = @(
		"$env:LOCALAPPDATA\Programs",
		"$env:ProgramFiles",
		"$env:ProgramFiles(x86)",
		"$env:USERPROFILE\Downloads"
	)
	foreach ($root in $scanRoots) {
		if (-not (Test-Path -LiteralPath $root)) {
			continue
		}
		$matches = Get-ChildItem `
			-Path $root `
			-Recurse `
			-File `
			-Filter "Godot*.exe" `
			-ErrorAction SilentlyContinue
		if ($matches -ne $null) {
			$preferred = $matches |
				Where-Object { $_.Name -notlike "*_console.exe" } |
				Sort-Object LastWriteTime -Descending |
				Select-Object -First 1
			if ($preferred -ne $null) {
				return $preferred.FullName
			}
			$fallback = $matches |
				Sort-Object LastWriteTime -Descending |
				Select-Object -First 1
			if ($fallback -ne $null) {
				return $fallback.FullName
			}
		}
	}

	return $null
}

if ($PlayerIds.Count -eq 0) {
	throw "Provide at least one player ID via -PlayerIds."
}

if (-not (Test-Path -LiteralPath $ProjectPath)) {
	throw "Project path does not exist: $ProjectPath"
}

$configuredGodotExe = Get-ConfiguredGodotExe -ProjectRoot $ProjectPath
$effectiveGodotExe = $GodotExe
if ($GodotExe -eq "godot4" -and -not [string]::IsNullOrWhiteSpace($configuredGodotExe)) {
	$effectiveGodotExe = $configuredGodotExe
}

$resolvedGodotExe = Resolve-GodotExe -RequestedExe $effectiveGodotExe
if ([string]::IsNullOrWhiteSpace($resolvedGodotExe)) {
	throw (
		"Could not find Godot executable '$effectiveGodotExe'. " +
		"Set one of: (1) -GodotExe 'C:\path\Godot.exe', " +
		"(2) env var AAN_GODOT_EXE, " +
		"(3) file '$ProjectPath\godot-exe.local.txt' containing full exe path."
	)
}
Write-Host ("Using Godot executable: {0}" -f $resolvedGodotExe)

try {
	Unblock-File -LiteralPath $resolvedGodotExe -ErrorAction Stop
} catch {
	# Non-fatal: keep going even if there is no Zone.Identifier stream.
}

if ($DryRun) {
	Write-Host "Dry run only. No clients launched."
	return
}

$launched = @()

foreach ($playerId in $PlayerIds) {
	$id = $playerId.Trim()
	if ([string]::IsNullOrWhiteSpace($id)) {
		continue
	}

	$arguments = @(
		"--path", $ProjectPath,
		"-w",
		"--",
		"--force-windowed",
		"--player-id=$id"
	)

	try {
		$process = Start-Process `
			-FilePath $resolvedGodotExe `
			-ArgumentList $arguments `
			-PassThru `
			-ErrorAction Stop
		$launched += $process
		Write-Host ("Launched player '{0}' (PID {1})" -f $id, $process.Id)
	} catch {
		Write-Error ("Failed to launch player '{0}': {1}" -f $id, $_.Exception.Message)
	}
}

if ($launched.Count -eq 0) {
	throw "No clients were launched. Check -PlayerIds values."
}

if ($Wait) {
	Write-Host "Waiting for all launched clients to exit..."
	$launched | Wait-Process
}
