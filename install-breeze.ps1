#Requires -Version 5.1
<#
.SYNOPSIS
  Optional: adds the Breeze ASR 25 speech model to an installed Hex and selects it.

.DESCRIPTION
  Breeze ASR 25 (MediaTek Research, Apache-2.0) is a Whisper large-v2 fine-tune for
  Taiwanese Mandarin with Mandarin-English code-switching. It writes Traditional
  Chinese itself. Hex does not list it, so it is added with `hex model import`.

  The script
    1. downloads the Q8_0 GGUF (1.67 GB) from a pinned revision of
       handy-computer/Breeze-ASR-25-gguf on Hugging Face (resumable),
    2. checks its size and SHA-256 against the values pinned below,
    3. runs `hex model import` and `hex model use`,
    4. deletes the download (Hex keeps its own copy).
  Nothing is downloaded when Hex already has the model.

  Breeze writes no punctuation. Keeping the s2twp step from install-windows.ps1
  is harmless: it leaves Traditional text as it is.

.PARAMETER Path
  Use this already downloaded GGUF file instead of downloading. It must match the
  pinned SHA-256. The file is not deleted.

.PARAMETER NoSelect
  Import the model but leave the selected model as it is.

.PARAMETER KeepDownload
  Do not delete the downloaded file afterwards.
#>
[CmdletBinding()]
param(
    [string]$Path,
    [switch]$NoSelect,
    [switch]$KeepDownload
)

$ErrorActionPreference = 'Stop'

# Pinned on 2026-11-24. A new upload in the Hugging Face repository does not change
# what this script installs; update all four values together after reviewing it.
$Revision    = 'c827f209c3fcb4956f49f9935ae04a0d88b7fae9'
$FileName    = 'Breeze-ASR-25-Q8_0.gguf'
$ModelBytes  = 1667964224
$ModelSha256 = '1650c163cd1623d13b585368ffd87d7e669c5ff23014511e0fa91bb4ce994756'
$ModelUrl    = "https://huggingface.co/handy-computer/Breeze-ASR-25-gguf/resolve/$Revision/$FileName"
$ModelId     = 'custom-' + $ModelSha256.Substring(0, 16)
$ModelName   = 'Breeze ASR 25'

function Write-Step { param([string]$Message) Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Ok   { param([string]$Message) Write-Host "    $Message" -ForegroundColor Green }

# Runs hex.com and returns its output as one string; the exit code is in $script:HexExit.
# Windows PowerShell 5.1 turns native stderr into errors under 'Stop', hence 'Continue'.
function Invoke-Hex {
    $ErrorActionPreference = 'Continue'
    $output = (& $script:Hex @args 2>&1 | ForEach-Object { "$_" }) -join "`n"
    $script:HexExit = $LASTEXITCODE
    $output
}

function Test-ModelInstalled {
    $list = Invoke-Hex model list
    foreach ($line in $list -split "`n") {
        if ($line -match [regex]::Escape($ModelId) -and $line -notmatch 'not installed') { return $true }
    }
    $false
}

$script:Hex = Join-Path $env:APPDATA 'hex\bin\hex.com'
if (-not (Test-Path $script:Hex)) {
    throw "Hex is not installed ($script:Hex not found). Run install-windows.ps1 first."
}

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

Write-Step "Checking for $ModelName"
if (Test-ModelInstalled) {
    Write-Ok "already in Hex ($ModelId); nothing to download"
} else {
    $downloaded = $false
    if ($Path) {
        $file = (Resolve-Path -LiteralPath $Path).Path
    } else {
        $dir = Join-Path $env:TEMP 'hex-zh-hant'
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $file = Join-Path $dir $FileName

        $have = 0
        if (Test-Path $file) { $have = (Get-Item $file).Length }
        if ($have -gt $ModelBytes) { Remove-Item $file -Force; $have = 0 }

        if ($have -lt $ModelBytes) {
            # The download and the copy Hex makes on import both have to fit.
            $drive = (Get-Item $env:LOCALAPPDATA).PSDrive
            $need = (2 * $ModelBytes) - $have + 200MB
            if ($drive.Free -lt $need) {
                throw ("Not enough free space on {0}: {1:N1} GB needed, {2:N1} GB free." -f $drive.Name, ($need / 1GB), ($drive.Free / 1GB))
            }

            Write-Step ("Downloading $FileName ({0:N2} GB)" -f ($ModelBytes / 1GB))
            $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
            if (-not (Test-Path $curl)) { throw 'curl.exe was not found in System32 (Windows 10 1803 or later has it).' }
            for ($attempt = 1; $attempt -le 5; $attempt++) {
                # -C - resumes a partial file, so an interrupted run continues where it stopped.
                & $curl --location --fail --continue-at - --retry 3 --retry-delay 5 --connect-timeout 30 --output $file $ModelUrl
                if ($LASTEXITCODE -eq 0) { break }
                if ($attempt -eq 5) { throw "The download failed (curl exit code $LASTEXITCODE). Run the script again to resume." }
                Write-Host "    attempt $attempt failed (curl exit code $LASTEXITCODE); retrying" -ForegroundColor Yellow
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
    if ($length -eq $ModelBytes) { $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() }
    if ($hash -ne $ModelSha256) {
        if ($downloaded) { Remove-Item -LiteralPath $file -Force }
        $what = if ($hash) { "SHA-256 $hash" } else { "$length bytes" }
        $tail = if ($downloaded) { ' The download was deleted; run the script again.' } else { '' }
        throw "$file is not the pinned $FileName ($what; expected $ModelBytes bytes, SHA-256 $ModelSha256).$tail"
    }
    Write-Ok 'matches the pinned file'

    Write-Step 'Importing into Hex'
    $imported = Invoke-Hex model import $file --name $ModelName
    Write-Ok $imported
    if ($script:HexExit -ne 0 -or -not (Test-ModelInstalled)) {
        throw "hex model import did not add $ModelId (exit code $script:HexExit)."
    }

    if ($downloaded -and -not $KeepDownload) {
        Remove-Item -LiteralPath $file -Force
        Write-Ok 'download deleted (Hex has its own copy)'
    }
}

if (-not $NoSelect) {
    Write-Step "Selecting $ModelName"
    $used = Invoke-Hex model use $ModelId
    Write-Ok $used
    if ($script:HexExit -ne 0) { throw "hex model use $ModelId failed (exit code $script:HexExit)." }
}

Write-Step 'Result'
Write-Host (Invoke-Hex model status)
Write-Host ''
Write-Host "Done. To go back: hex model use qwen3_asr06_b    To remove: hex model remove $ModelId"
