# Runs every check from the game/ directory (adapted from Cubika scripts/check.ps1).
# One Rojo project per game: <name>.project.json (in game/ so sourcemap paths stay relative) -> build/<name>.rbxl
# Game code lives in src/<name>/, shared code in src/core/. Type analysis per game covers src/core + src/<name>
# (other games' folders are not in that game's sourcemap). Lint/format cover all of src and tests.
# Tests: every tests/**/*.spec.luau (tests/core for core, tests/<name> per game). See docs/33.
# Each step is reported PASS/FAIL; all steps run even after a failure. Exit 1 if any step failed.
#
# First run on a new machine: tools/bin and tools/globalTypes.d.luau are git-ignored.
# Copy them from the Cubika project (C:\Users\NullMa\UnityProjects\Cubika\Roblox\tools) or `rokit install`.

$ErrorActionPreference = 'Continue'
$GameDir = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $GameDir
$env:PATH = (Join-Path $GameDir 'tools\bin') + ';' + $env:PATH

$results = New-Object System.Collections.ArrayList

function Add-Result([string]$Name, [string]$Status) {
    [void]$results.Add([pscustomobject]@{ Name = $Name; Status = $Status })
}

function Invoke-Step([string]$Name, [scriptblock]$Action) {
    Write-Host ''
    Write-Host "=== $Name ===" -ForegroundColor Cyan
    $global:LASTEXITCODE = 0
    try {
        & $Action
        $code = $LASTEXITCODE
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        $code = 1
    }
    if ($code -eq 0) { $status = 'PASS' } else { $status = "FAIL (exit $code)" }
    Add-Result $Name $status
    Write-Host "--> $Name : $status"
}

$places = @(Get-ChildItem -Path '.' -Filter '*.project.json' -File)

foreach ($place in $places) {
    # $placeName, not $name: PowerShell names are case-insensitive and Invoke-Step's $Name would shadow it
    $placeName = $place.Name -replace '\.project\.json$', ''
    $proj = $place.Name

    # a. sourcemap per place (luau-lsp resolves DataModel paths from it)
    Invoke-Step "a. sourcemap $placeName" {
        rojo sourcemap $proj -o sourcemap.json
    }
    # b. type analysis of the code that place uses
    $srcDirs = @(@('src/core', ('src/' + $placeName)) | Where-Object { Test-Path -LiteralPath $_ })
    Invoke-Step "b. luau-lsp $placeName" {
        luau-lsp analyze --sourcemap=sourcemap.json --definitions=tools/globalTypes.d.luau --no-strict-dm-types --base-luaurc=.luaurc --ignore=vendor/** $srcDirs
    }
    # f. build
    Invoke-Step "f. rojo build $placeName" {
        if (-not (Test-Path -LiteralPath 'build')) { New-Item -ItemType Directory -Path 'build' | Out-Null }
        rojo build $proj -o ("build/" + $placeName + ".rbxl")
    }
}

Invoke-Step 'c. selene src' { selene src }

$fmtDirs = @(@('src', 'tests') | Where-Object { Test-Path -LiteralPath $_ })
Invoke-Step 'd. stylua --check' { stylua --check $fmtDirs }

$specs = @(Get-ChildItem -Path 'tests' -Filter '*.spec.luau' -File -Recurse -ErrorAction SilentlyContinue | Sort-Object FullName)
if ($specs.Count -eq 0) { Add-Result 'e. lune tests' 'SKIP (no tests/**/*.spec.luau)' }
foreach ($spec in $specs) {
    $specPath = $spec.FullName.Substring($GameDir.Length + 1) -replace '\\', '/'
    Invoke-Step "e. lune run $specPath" { lune run $specPath }
}

Write-Host ''
Write-Host '=== Summary ===' -ForegroundColor Cyan
$results | ForEach-Object { '{0,-48} {1}' -f $_.Name, $_.Status }

$failed = @($results | Where-Object { $_.Status -like 'FAIL*' }).Count
if ($failed -gt 0) {
    Write-Host "$failed step(s) failed." -ForegroundColor Red
    exit 1
}
Write-Host 'All checks passed.' -ForegroundColor Green
exit 0
