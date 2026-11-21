#Requires -Version 5.1
<#
.SYNOPSIS
  Installs Hex and makes its dictation output Traditional Chinese (Taiwan).

.DESCRIPTION
  What this script changes:
    1. Installs Hex from https://anoma.ly/hex/install-windows.ps1 when hex.com is missing.
       That installer verifies the download's size, SHA-256 and Authenticode signature.
    2. Creates ~/.config/hex and drops the OpenCC s2tw / s2twp transformers into it
       (downloads them from this repository when the transformer folder is not beside
       this script, so the one-liner below works on its own).
    3. Adds the s2twp step to "Every dictation" in %APPDATA%\hex\settings.json.
       Hex is quit first: it rewrites settings.json on exit, so edits made while it
       runs are lost.
    4. Sets the interface language to zh-Hant and an IME-safe dictation shortcut
       (Ctrl+Space is the Chinese IME toggle on Windows, so Hex's default collides).

  Hex has no built-in simplified-to-traditional conversion for transcripts, and
  none of its speech models reliably picks the script. This script installs the
  officially supported workaround: a personal transformation in hex.config.ts.
  See https://github.com/anomalyco/hex/issues/829 and /issues/1835.

.PARAMETER Hotkey
  Dictation shortcut in Hex's text form: `control+option+space`, `f5`,
  `right-command`, `caps-lock`. Default: control+option+space

.PARAMETER SkipHotkey
  Leave the dictation shortcut exactly as it is.

.PARAMETER ConfigureOnly
  Do not install Hex and do not open it; only write the config and patch settings.
  Requires Hex to be installed already.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -Command "iwr https://raw.githubusercontent.com/mathruffian-dot/hex-zh-hant/main/install-windows.ps1 -OutFile i.ps1; ./i.ps1"

.EXAMPLE
  ./install-windows.ps1 -SkipHotkey
#>
[CmdletBinding()]
param(
    [string]$Hotkey = 'control+option+space',
    [switch]$SkipHotkey,
    [switch]$ConfigureOnly
)

$ErrorActionPreference = 'Stop'

$RepoOwner = 'mathruffian-dot'
$RepoName  = 'hex-zh-hant'
$RawBase   = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/main/transformer"

$TransformerFiles = @(
    'hex.config.ts',
    'hex-s2tw.ts',
    'hex-data-st.ts',
    'hex-data-tw.ts'
)

$SupportDir  = Join-Path $env:APPDATA 'hex'
$HexExe      = Join-Path $SupportDir 'versions'
$Hex         = Join-Path $SupportDir 'bin\hex.com'
$SettingsPath = Join-Path $SupportDir 'settings.json'
$ConfigDir   = Join-Path $env:USERPROFILE '.config\hex'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Warn2 { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

function Invoke-Hex {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & $Hex @Arguments 2>&1
}

# `hex start` goes through hex.com, the console shim that waits for hex.exe to
# exit, so calling it from a script blocks until the app is closed. Launch the
# executable directly and poll the control pipe instead.
function Get-HexExe {
    $pointer = Join-Path $SupportDir 'current-version'
    if (Test-Path $pointer) {
        $version = (Get-Content $pointer -Raw).Trim()
        $candidate = Join-Path $SupportDir "versions\$version\hex.exe"
        if (Test-Path $candidate) { return $candidate }
    }
    Get-ChildItem (Join-Path $SupportDir 'versions') -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName 'hex.exe' } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1
}

function Start-Hex {
    if (Get-Process hex -ErrorAction SilentlyContinue) { return }
    $exe = Get-HexExe
    if (-not $exe) { throw 'hex.exe was not found under %APPDATA%\hex\versions.' }
    Start-Process $exe -ArgumentList 'app' | Out-Null
    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Milliseconds 500
        & $Hex status *> $null
        if ($LASTEXITCODE -eq 0) { return }
    }
    Write-Warn2 "Hex did not answer within 20 s; carrying on."
}

# ---------------------------------------------------------------------------
# 1. Hex itself
# ---------------------------------------------------------------------------
if (-not (Test-Path $Hex)) {
    if ($ConfigureOnly) {
        throw "Hex is not installed: $Hex is missing and -ConfigureOnly was given."
    }
    Write-Step 'Installing Hex'
    $installer = Join-Path $env:TEMP ("hex-install-{0}.ps1" -f [guid]::NewGuid().ToString('N'))
    Invoke-WebRequest 'https://anoma.ly/hex/install-windows.ps1' -OutFile $installer -UseBasicParsing
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer
        if ($LASTEXITCODE -ne 0) { throw "Hex's installer exited with $LASTEXITCODE" }
    } finally {
        Remove-Item $installer -Force -ErrorAction SilentlyContinue
    }
    if (-not (Test-Path $Hex)) { throw "Hex's installer finished but $Hex is missing." }
    Write-Ok "installed $Hex"
}

# ---------------------------------------------------------------------------
# 2. Let Hex write its own settings, then close it before we patch them
# ---------------------------------------------------------------------------
Write-Step 'Starting and quitting Hex so settings.json is complete'
if (-not $ConfigureOnly) {
    Start-Hex
    Start-Sleep -Seconds 3
}
Invoke-Hex quit | Out-Null
Start-Sleep -Seconds 2
if (Get-Process hex -ErrorAction SilentlyContinue) {
    Stop-Process -Name hex -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}
if (-not (Test-Path $SettingsPath)) {
    throw "$SettingsPath is missing. Run Hex once by hand, then run this script again."
}

# ---------------------------------------------------------------------------
# 3. The transformer workspace
# ---------------------------------------------------------------------------
Write-Step "Installing the OpenCC transformer into $ConfigDir"
New-Item -ItemType Directory -Force -Path $ConfigDir | Out-Null
Invoke-Hex commands init | Out-Null

$localTransformer = Join-Path $PSScriptRoot 'transformer'
foreach ($name in $TransformerFiles) {
    $target = Join-Path $ConfigDir $name
    $source = Join-Path $localTransformer $name
    if (Test-Path $source) {
        Copy-Item $source $target -Force
    } else {
        Invoke-WebRequest "$RawBase/$name" -OutFile $target -UseBasicParsing
    }
}

$check = Invoke-Hex commands check
Write-Ok ($check -join ' ')
if (($check -join "`n") -notmatch 'transformations') {
    throw "hex commands check did not report any transformations: $($check -join ' ')"
}

# ---------------------------------------------------------------------------
# 4. settings.json: add the step (Hex is closed, so this sticks)
# ---------------------------------------------------------------------------
Write-Step 'Adding the s2twp step to Every dictation'
$backup = "$SettingsPath.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
Copy-Item $SettingsPath $backup -Force
Write-Ok "settings backed up to $backup"

$settings = [IO.File]::ReadAllText($SettingsPath, [Text.Encoding]::UTF8) | ConvertFrom-Json
$mode = $settings.dictation_processing.default_mode
$steps = @($mode.transformations | Where-Object { $_ })
if ($steps -notcontains 's2twp') { $steps += 's2twp' }
$mode.transformations = @($steps)
$encoded = $settings | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($SettingsPath, $encoded, (New-Object Text.UTF8Encoding($false)))
Write-Ok ("steps: " + ($steps -join ', '))

# ---------------------------------------------------------------------------
# 5. Start Hex and set what the CLI can set
# ---------------------------------------------------------------------------
if (-not $ConfigureOnly) {
    Write-Step 'Starting Hex'
    Start-Hex
    Start-Sleep -Seconds 2

    Write-Step 'Interface language -> zh-Hant'
    Invoke-Hex settings set ui_language zh-Hant | Out-Null

    if (-not $SkipHotkey -and $Hotkey) {
        Write-Step "Dictation shortcut -> $Hotkey"
        Invoke-Hex settings set dictation_hotkey $Hotkey | Out-Null
    }
}

# ---------------------------------------------------------------------------
# 6. Report
# ---------------------------------------------------------------------------
Write-Step 'Result'
Invoke-Hex settings get ui_language
Invoke-Hex settings get dictation_hotkey
Invoke-Hex settings get dictation_processing.default_mode

Write-Host ''
Write-Host 'Done. Speak one sentence somewhere, then:'
Write-Host '  hex history --raw --limit 1     # raw_text is simplified, final_text must be traditional'
Write-Host 'If the Output pane still shows no step, run: hex restart'

