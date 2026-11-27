#Requires -Version 5.1
<#
.SYNOPSIS
  Optional: picks a speech model that suits this computer, installs it in Hex and
  selects it.

.DESCRIPTION
  -Model auto (the default) looks at the computer. With at least 12 GB of system
  memory and a graphics card with at least 3 GB of its own memory, which Hex can
  use, it picks Qwen3-ASR 1.7B. Otherwise (integrated graphics only, a small card,
  or less memory) it picks Qwen3-ASR 0.6B: measured through Hex, 1.7B was about
  8 times slower on an i5-11400H processor than on an RTX 3050 Ti, and about 75 %
  slower than 0.6B on Radeon 760M integrated graphics.
  Run with -WhatIf to see the choice and the reasons without installing anything.

  The models:
    qwen-0.6b  Qwen3-ASR 0.6B   850 MB  built into Hex; Hex downloads and checks it
    qwen-1.7b  Qwen3-ASR 1.7B   2.2 GB  more accurate; best with a graphics card
    breeze     Breeze ASR 25    1.7 GB  Taiwanese Mandarin, writes Traditional
                                        Chinese itself, but no punctuation
  The Qwen models write Simplified Chinese with punctuation; the s2twp step from
  install-windows.ps1 turns that into Traditional Chinese (Taiwan).

  qwen-1.7b and breeze are not in Hex's list. They are downloaded from a pinned
  revision of the handy-computer GGUF repositories on Hugging Face (resumable),
  checked against the size and SHA-256 pinned below, added with `hex model import`
  and the download is deleted (Hex keeps its own copy). Nothing is downloaded when
  Hex already has the model.

.PARAMETER Model
  auto (default), qwen-0.6b, qwen-1.7b or breeze.

.PARAMETER Path
  Use this already downloaded GGUF file instead of downloading (qwen-1.7b and
  breeze). It must match the pinned SHA-256. The file is not deleted.

.PARAMETER NoSelect
  Install the model but leave the selected model as it is (qwen-1.7b and breeze;
  Hex always switches to a built-in model it installs).

.PARAMETER KeepDownload
  Do not delete the downloaded file afterwards.

.PARAMETER WhatIf
  Only print what this computer has and which model would be installed.
#>
[CmdletBinding()]
param(
    [ValidateSet('auto', 'qwen-0.6b', 'qwen-1.7b', 'breeze')]
    [string]$Model = 'auto',
    [string]$Path,
    [switch]$NoSelect,
    [switch]$KeepDownload,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# Pinned on 2026-11-28. A new upload in a Hugging Face repository does not change
# what this script installs; update a model's values together after reviewing it.
$Models = @{
    'qwen-0.6b' = @{
        Name = 'Qwen3-ASR 0.6B'; Id = 'qwen3_asr06_b'; BuiltIn = $true
    }
    'qwen-1.7b' = @{
        Name     = 'Qwen3-ASR 1.7B'
        Repo     = 'handy-computer/Qwen3-ASR-1.7B-gguf'
        Revision = '0e0a596e3959c3f3f2ab7d443a5b6f0f4a4bba6f'
        File     = 'Qwen3-ASR-1.7B-Q8_0.gguf'
        Bytes    = 2185030624
        Sha256   = '9a0d81792dfea2d5f278b8a63deb3ea6e02139ce42c2301f32ea19c4f77526b7'
        BuiltIn  = $false
    }
    'breeze' = @{
        Name     = 'Breeze ASR 25'
        Repo     = 'handy-computer/Breeze-ASR-25-gguf'
        Revision = 'c827f209c3fcb4956f49f9935ae04a0d88b7fae9'
        File     = 'Breeze-ASR-25-Q8_0.gguf'
        Bytes    = 1667964224
        Sha256   = '1650c163cd1623d13b585368ffd87d7e669c5ff23014511e0fa91bb4ce994756'
        BuiltIn  = $false
    }
}
foreach ($m in $Models.Values) {
    if (-not $m.BuiltIn) { $m.Id = 'custom-' + $m.Sha256.Substring(0, 16) }
}

# Thresholds for -Model auto.
$MinGpuBytes = 3GB    # Qwen3-ASR 1.7B Q8_0 is 2.2 GB and has to fit in the card's own memory
$MinRamBytes = 12GB   # a "16 GB" computer reports a little less than 16 GB

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }
function Write-Note { param([string]$Message) Write-Host "    $Message" -ForegroundColor Yellow }

# Runs hex.com and returns its output as one string; the exit code is in $script:HexExit.
# Windows PowerShell 5.1 turns native stderr into errors under 'Stop', hence 'Continue'.
function Invoke-Hex {
    $ErrorActionPreference = 'Continue'
    $output = (& $script:Hex @args 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $script:HexExit = $LASTEXITCODE
    $output
}

# `hex model status <id>` prints "installed<TAB>verified<TAB>..." for an installed model.
function Test-ModelInstalled {
    param([string]$Id)
    $status = Invoke-Hex model status $Id
    $script:HexExit -eq 0 -and $status -match '^installed\t'
}

# A registry value that is a number on some drivers and a byte array on others.
function ConvertTo-Bytes {
    param($Value)
    if ($null -eq $Value) { return [int64]0 }
    if ($Value -is [byte[]]) {
        $buffer = New-Object byte[] 8
        [Array]::Copy($Value, $buffer, [Math]::Min(8, $Value.Length))
        return [BitConverter]::ToInt64($buffer, 0)
    }
    [int64]$Value
}

# Each display adapter with the memory it has to itself. Win32_VideoController's
# AdapterRAM stops at 4 GB, so the driver's registry values are read instead.
# Integrated graphics report little or nothing here: they borrow system memory.
function Get-GraphicsCards {
    $class = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $class -ErrorAction SilentlyContinue |
        Where-Object { $_.PSChildName -match '^\d{4}$' } |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
            if (-not $p.DriverDesc) { return }
            $bytes = ConvertTo-Bytes $p.'HardwareInformation.qwMemorySize'
            if ($bytes -le 0) { $bytes = ConvertTo-Bytes $p.'HardwareInformation.MemorySize' }
            [pscustomobject]@{ Name = [string]$p.DriverDesc; Bytes = $bytes }
        }
}

function Select-Model {
    $ram = [int64](Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory
    Write-Ok ("system memory: {0:N1} GB" -f ($ram / 1GB))
    Write-Ok "processor: $env:PROCESSOR_ARCHITECTURE"

    # The compute devices Hex itself can run a model on, e.g. "1<TAB>vulkan<TAB>3962 MB<TAB>NVIDIA ...".
    $devices = Invoke-Hex model devices

    $best = $null
    foreach ($card in @(Get-GraphicsCards)) {
        $hexCanUse = [bool]($devices -split "`n" | Where-Object { $_ -match "`tvulkan`t" -and $_.Contains($card.Name) })
        $usable = $hexCanUse -and $card.Bytes -ge $MinGpuBytes
        $label = if ($usable) { 'usable' } elseif (-not $hexCanUse) { 'Hex cannot use it' } else { 'too little memory of its own' }
        Write-Ok ("graphics: {0}, {1:N1} GB of its own ({2})" -f $card.Name, ($card.Bytes / 1GB), $label)
        if ($usable -and (-not $best -or $card.Bytes -gt $best.Bytes)) { $best = $card }
    }

    if ($ram -lt $MinRamBytes) {
        return @{ Key = 'qwen-0.6b'; Why = ('less than {0} GB of system memory' -f ($MinRamBytes / 1GB)) }
    }
    if ($best) {
        return @{ Key = 'qwen-1.7b'; Why = "$($best.Name) and enough memory" }
    }
    $why = 'no graphics card with {0} GB of its own memory that Hex can use' -f ($MinGpuBytes / 1GB)
    @{ Key = 'qwen-0.6b'; Why = $why }
}

$script:Hex = Join-Path $env:APPDATA 'hex\bin\hex.com'
if (-not (Test-Path $script:Hex)) {
    throw "Hex is not installed ($script:Hex not found). Run install-windows.ps1 first."
}

if ($Model -eq 'auto') {
    Write-Step 'Looking at this computer'
    $pick = Select-Model
    $Model = $pick.Key
    Write-Ok "choice: $($Models[$Model].Name) ($($pick.Why))"
}
$m = $Models[$Model]

if ($WhatIf) {
    $state = if (Test-ModelInstalled $m.Id) { 'already in Hex' } else { 'not in Hex yet' }
    Write-Host ''
    Write-Host "Would install and select $($m.Name) ($($m.Id), $state). Nothing was changed."
    exit 0
}

if ($Path -and $m.BuiltIn) { throw "-Path is for qwen-1.7b and breeze; Hex downloads $($m.Name) itself." }

# The Claude desktop app is a packaged app: what it writes under %LOCALAPPDATA%
# lands in its private storage, where a Hex opened from the Start menu cannot see it.
$packages = Join-Path $env:LOCALAPPDATA 'Packages'
$probe = Join-Path $env:LOCALAPPDATA ("hex-sandbox-probe-{0}.tmp" -f [guid]::NewGuid().ToString('N'))
Set-Content -Path $probe -Value 'probe'
$redirected = @(Get-ChildItem $packages -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName ("LocalCache\Local\" + (Split-Path $probe -Leaf))) })
Remove-Item $probe -Force
if ($redirected.Count -gt 0) {
    throw 'This window runs inside the Claude app. Open PowerShell from the Start menu and run the script there.'
}

Write-Step "Checking for $($m.Name)"
if (Test-ModelInstalled $m.Id) {
    Write-Ok "already in Hex ($($m.Id)); nothing to download"
} elseif ($m.BuiltIn) {
    Write-Step "Hex is downloading $($m.Name)"
    $installed = Invoke-Hex model install $m.Id
    Write-Ok $installed
    if ($script:HexExit -ne 0 -or -not (Test-ModelInstalled $m.Id)) {
        throw "hex model install $($m.Id) did not finish (exit code $script:HexExit). If Hex is still downloading, wait and run the script again."
    }
} else {
    $downloaded = $false
    if ($Path) {
        $file = (Resolve-Path -LiteralPath $Path).Path
    } else {
        $dir = Join-Path $env:TEMP 'hex-zh-hant'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $file = Join-Path $dir $m.File

        $have = 0
        if (Test-Path $file) { $have = (Get-Item $file).Length }
        if ($have -gt $m.Bytes) { Remove-Item $file -Force; $have = 0 }

        if ($have -lt $m.Bytes) {
            # The download and the copy Hex makes on import both have to fit.
            $drive = (Get-Item $env:LOCALAPPDATA).PSDrive
            $need = (2 * $m.Bytes) - $have + 200MB
            if ($drive.Free -lt $need) {
                throw ("Not enough free space on {0}: {1:N1} GB needed, {2:N1} GB free." -f $drive.Name, ($need / 1GB), ($drive.Free / 1GB))
            }

            Write-Step ("Downloading $($m.File) ({0:N2} GB)" -f ($m.Bytes / 1GB))
            $url = "https://huggingface.co/$($m.Repo)/resolve/$($m.Revision)/$($m.File)"
            $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
            if (-not (Test-Path $curl)) { throw 'curl.exe was not found in System32 (Windows 10 1803 or later has it).' }
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                # --continue-at - resumes a partial file, so an interrupted run continues where it stopped.
                & $curl --location --fail --continue-at - --retry 3 --retry-delay 5 --connect-timeout 30 --output $file $url
                if ($LASTEXITCODE -eq 0) { break }
                if ($attempt -eq 5) { throw "The download failed (curl exit code $LASTEXITCODE). Run the script again to resume." }
                Write-Note "attempt $attempt failed (curl exit code $LASTEXITCODE); retrying"
                Start-Sleep -Seconds 10
            }
        } else {
            Write-Ok "using the finished download in $dir"
        }
        $downloaded = $true
    }

    Write-Step 'Verifying size and SHA-256'
    $length = (Get-Item -LiteralPath $file).Length
    $hash = $null
    if ($length -eq $m.Bytes) { $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() }
    if ($hash -ne $m.Sha256) {
        if ($downloaded) { Remove-Item -LiteralPath $file -Force }
        $what = if ($hash) { "SHA-256 $hash" } else { "$length bytes" }
        $tail = if ($downloaded) { ' The download was deleted; run the script again.' } else { '' }
        throw "$file is not the pinned $($m.File) ($what; expected $($m.Bytes) bytes, SHA-256 $($m.Sha256)).$tail"
    }
    Write-Ok 'matches the pinned file'

    Write-Step 'Importing into Hex'
    $imported = Invoke-Hex model import $file --name $m.Name
    Write-Ok $imported
    if ($script:HexExit -ne 0 -or -not (Test-ModelInstalled $m.Id)) {
        throw "hex model import did not add $($m.Id) (exit code $script:HexExit)."
    }

    if ($downloaded -and -not $KeepDownload) {
        Remove-Item -LiteralPath $file -Force
        Write-Ok 'download deleted (Hex has its own copy)'
    }
}

if (-not $NoSelect) {
    Write-Step "Selecting $($m.Name)"
    $used = Invoke-Hex model use $m.Id
    Write-Ok $used
    if ($script:HexExit -ne 0) { throw "hex model use $($m.Id) failed (exit code $script:HexExit)." }
}

Write-Step 'Result'
Write-Host (Invoke-Hex model status)
Write-Host ''
Write-Host "Done. Other models: hex model list    Switch: hex model use <id>    Remove an imported one: hex model remove <id>"
