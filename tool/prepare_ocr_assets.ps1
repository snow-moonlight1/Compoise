# WP17-I4 OCR dependency and model preparation.
#
# Deterministic, restartable preparation of everything the optional OCR
# component needs, kept outside the repository:
#
#   <AssetRoot>/third_party/stb_image.h          (public domain / MIT)
#   <AssetRoot>/ncnn/ppocrv5_dict.txt            (Apache-2.0, PaddleOCR)
#   <AssetRoot>/ncnn/<four PP-OCRv5 ncnn files>  (source selectable, see -ModelSource)
#   <AssetRoot>/ncnn-src                         (ncnn, BSD-3-Clause, pinned commit)
#   <AssetRoot>/ncnn-build-win, ncnn-android-*   (ncnn install trees, optional)
#   <AssetRoot>/deploy/ncnn                      (deployment layout, optional)
#
# Guarantees:
#   * every downloaded blob is checked against a pinned SHA-256 before use;
#   * a hash mismatch stops the run instead of replacing the cached file;
#   * -Offline never opens the network and only reuses verified cache entries;
#   * -Check only reads and verifies; it writes nothing;
#   * no model, DLL, SO, APK or log is ever written inside the repository.
#
# Exit codes: 0 ok, 2 usage, 3 verification failure, 4 network/offline failure,
#             5 missing tool (git/cmake/flutter/python).
[CmdletBinding()]
param(
    [string]$AssetRoot = $(if ($env:WP17R2_ASSETS) { $env:WP17R2_ASSETS } else { Join-Path $env:LOCALAPPDATA 'wp17r2-assets' }),
    [ValidateSet('nihui', 'official')][string]$ModelSource = 'nihui',
    [ValidateSet('host', 'none')][string]$Ncnn = 'host',
    [string[]]$Abi = @('x86_64', 'arm64-v8a'),
    [string]$DeployRoot,
    [string]$Python,
    [switch]$SkipNcnnSource,
    [switch]$Offline,
    [switch]$Check,
    [switch]$Force,
    [switch]$CleanWork
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$exitOk = 0; $exitUsage = 2; $exitVerify = 3; $exitNetwork = 4; $exitTool = 5

function Write-Step([string]$Message) { Write-Host "==> $Message" -ForegroundColor Cyan }
function Write-Note([string]$Message) { Write-Host "    $Message" }
function Fail([int]$Code, [string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit $Code }

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Get-FileRecord([string]$Path) {
    $item = Get-Item -LiteralPath $Path
    return [ordered]@{ bytes = $item.Length; sha256 = (Get-Sha256 $Path) }
}

# --- third-party sources -----------------------------------------------------
# The dictionary is the PaddleOCR PP-OCRv5 character dictionary; the repository
# tree is Apache-2.0. stb_image.h is public domain (upstream also offers MIT or
# Unlicense). The converted ncnn weights have two possible sources:
#   nihui    - nihui/ncnn-android-ppocrv5 assets; no licence file exists for the
#              repository or the weights (HTTP 404 on /license), so this source
#              is usable for validation only and must not be redistributed.
#   official - conversion from PaddlePaddle/PP-OCRv5_mobile_* (Hugging Face
#              model card declares apache-2.0) with the pinned toolchain in
#              native/ocr/tools/convert_models.py.
$Sources = @{
    dict = @{
        url = 'https://raw.githubusercontent.com/PaddlePaddle/PaddleOCR/main/ppocr/utils/dict/ppocrv5_dict.txt'
        rel = 'ncnn/ppocrv5_dict.txt'
        sha256 = 'd1979e9f794c464c0d2e0b70a7fe14dd978e9dc644c0e71f14158cdf8342af1b'
        licence = 'Apache-2.0 (PaddleOCR)'
    }
    stb = @{
        url = 'https://raw.githubusercontent.com/nothings/stb/master/stb_image.h'
        rel = 'third_party/stb_image.h'
        sha256 = '594c2fe35d49488b4382dbfaec8f98366defca819d916ac95becf3e75f4200b3'
        licence = 'public domain / MIT (nothings/stb)'
    }
}

$NihuiModels = [ordered]@{
    'PP_OCRv5_mobile_det.ncnn.param' = '358f459680ae0e7a73e477469e529ce116f68c629019ec7a0b6457d2d9117934'
    'PP_OCRv5_mobile_det.ncnn.bin'   = '857a96bc963725105b78a178dfcc3c0c3db1a7b9eef32244367b2cb105ccf60b'
    'PP_OCRv5_mobile_rec.ncnn.param' = 'f52a6586ac3338d8c350db0c9f3c55ff2ecd3763327f9bc7f0efc091f8a63e74'
    'PP_OCRv5_mobile_rec.ncnn.bin'   = '49d9907a55ba20fa6637f9f788f66ab00793bc8ce57a733a09dbe86b9a2e3db0'
}
$NihuiBase = 'https://raw.githubusercontent.com/nihui/ncnn-android-ppocrv5/master/app/src/main/assets/'
$RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$NcnnPinFile = Join-Path $RepoRoot 'third_party\ncnn_pin.txt'
$OfficialLock = Join-Path $RepoRoot 'native\ocr\tools\models.lock.json'

$RequiredModelFiles = @(
    'ppocrv5_dict.txt',
    'PP_OCRv5_mobile_det.ncnn.param',
    'PP_OCRv5_mobile_det.ncnn.bin',
    'PP_OCRv5_mobile_rec.ncnn.param',
    'PP_OCRv5_mobile_rec.ncnn.bin'
)
$RequiredSymbols = @('mf_ocr_create', 'mf_ocr_run_file', 'mf_ocr_destroy', 'mf_ocr_free')

$script:records = [ordered]@{}

function Add-Record([string]$Key, [string]$Path, [string]$Licence, [string]$Source, [string]$Note) {
    $record = Get-FileRecord $Path
    $script:records[$Key] = [ordered]@{
        path = $Path
        bytes = $record.bytes
        sha256 = $record.sha256
        licence = $Licence
        source = $Source
        note = $Note
    }
}

function Get-Cached([string]$RelPath, [string]$Expected, [string]$Url, [string]$Licence, [string]$Key, [string]$Note = '') {
    $dest = Join-Path $AssetRoot $RelPath
    $dir = Split-Path -Parent $dest
    if (-not $Check -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

    $present = Test-Path -LiteralPath $dest
    if ($present) {
        $digest = Get-Sha256 $dest
        if ($digest -eq $Expected) {
            Write-Note "cache hit  $RelPath"
            Add-Record $Key $dest $Licence $Url $Note
            return $dest
        }
        if ($Check) { Fail $exitVerify "cached $RelPath has sha256 $digest, expected $Expected" }
        Fail $exitVerify "$RelPath has sha256 $digest but $Expected is pinned; remove the file deliberately if upstream really changed (refusing to overwrite a mismatching cache entry)"
    }

    if ($Check) { Fail $exitVerify "missing $RelPath (checked $AssetRoot)" }
    if ($Offline) { Fail $exitNetwork "offline: $RelPath is not cached" }

    Write-Note "fetch     $RelPath"
    $tmp = "$dest.part"
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    try {
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $tmp -UseBasicParsing -TimeoutSec 300
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
        Fail $exitNetwork "download failed for $Url : $($_.Exception.Message)"
    }
    $digest = Get-Sha256 $tmp
    if ($digest -ne $Expected) {
        Remove-Item -LiteralPath $tmp -Force
        Fail $exitVerify "downloaded $RelPath has sha256 $digest, expected $Expected (upstream changed; nothing was installed)"
    }
    Move-Item -LiteralPath $tmp -Destination $dest -Force
    Add-Record $Key $dest $Licence $Url $Note
    return $dest
}

# --- argument validation -----------------------------------------------------
if ($Check -and $CleanWork) { Fail $exitUsage '-Check cannot be combined with -CleanWork' }
if (-not (Test-Path -LiteralPath $AssetRoot)) {
    if ($Check) { Fail $exitVerify "asset root does not exist: $AssetRoot" }
    New-Item -ItemType Directory -Force -Path $AssetRoot | Out-Null
}
$AssetRoot = (Resolve-Path -LiteralPath $AssetRoot).Path
if (-not $DeployRoot) { $DeployRoot = Join-Path $AssetRoot 'deploy' }
$WorkRoot = Join-Path $AssetRoot 'wp17i4-work'

if ($CleanWork) {
    if (-not (Test-Path -LiteralPath $WorkRoot)) { Write-Note 'work directory already absent'; exit $exitOk }
    $resolved = (Resolve-Path -LiteralPath $WorkRoot).Path
    $workItem = Get-Item -LiteralPath $resolved
    if (-not [string]::Equals((Split-Path -Parent $resolved), $AssetRoot, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path -Leaf $resolved) -ne 'wp17i4-work' -or
        ($workItem.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        Fail $exitUsage "refusing to delete $resolved"
    }
    Remove-Item -LiteralPath $resolved -Recurse -Force
    Write-Note "removed $resolved"
    exit $exitOk
}

Write-Step "WP17-I4 OCR dependency preparation"
Write-Note "asset root : $AssetRoot"
Write-Note "model      : $ModelSource"
Write-Note "ncnn       : $Ncnn"
Write-Note "offline    : $($Offline.IsPresent)"
Write-Note "check only : $($Check.IsPresent)"

$tools = [ordered]@{}
foreach ($tool in 'git', 'cmake', 'flutter', 'python') {
    $command = Get-Command $tool -ErrorAction SilentlyContinue
    $tools[$tool] = if ($command) { $command.Source } else { $null }
}
if (-not $tools['git']) { Fail $exitTool 'git is required to pin the ncnn source tree' }

# --- fixed first-party-of-record inputs --------------------------------------
Write-Step 'PaddleOCR dictionary and stb_image.h'
Get-Cached $Sources.dict.rel $Sources.dict.sha256 $Sources.dict.url $Sources.dict.licence 'ppocrv5_dict' | Out-Null
Get-Cached $Sources.stb.rel $Sources.stb.sha256 $Sources.stb.url $Sources.stb.licence 'stb_image' | Out-Null

# --- ncnn source tree --------------------------------------------------------
$ncnnPin = (Get-Content -LiteralPath $NcnnPinFile -Raw).Trim()
$ncnnSrc = Join-Path $AssetRoot 'ncnn-src'
if (-not $SkipNcnnSource) {
    Write-Step 'ncnn source tree (BSD-3-Clause)'
    if (-not (Test-Path -LiteralPath (Join-Path $ncnnSrc '.git'))) {
        if ($Check) { Fail $exitVerify "missing ncnn source tree: $ncnnSrc" }
        if ($Offline) { Fail $exitNetwork "offline: ncnn source tree is not present at $ncnnSrc" }
        Write-Note "clone     $ncnnSrc"
        & git clone --quiet https://github.com/Tencent/ncnn.git $ncnnSrc
        if ($LASTEXITCODE -ne 0) { Fail $exitNetwork 'git clone of Tencent/ncnn failed' }
    }
    $head = (& git -C $ncnnSrc rev-parse HEAD).Trim()
    if ($head -ne $ncnnPin) {
        if ($Check) { Fail $exitVerify "ncnn source is at $head, pinned $ncnnPin" }
        if ($Offline) { Fail $exitNetwork "offline: ncnn source is at $head, pinned $ncnnPin" }
        Write-Note "checkout  $ncnnPin"
        & git -C $ncnnSrc fetch --quiet origin $ncnnPin
        if ($LASTEXITCODE -eq 0) {
            & git -C $ncnnSrc checkout --quiet $ncnnPin
            if ($LASTEXITCODE -ne 0) { Fail $exitVerify "could not check out $ncnnPin" }
            $head = (& git -C $ncnnSrc rev-parse HEAD).Trim()
        }
    }
    if ($head -ne $ncnnPin) { Fail $exitVerify "ncnn source is at $head, pinned $ncnnPin" }
    $ncnnLicence = Join-Path $ncnnSrc 'LICENSE.txt'
    if (Test-Path -LiteralPath $ncnnLicence) {
        Add-Record 'ncnn_source' $ncnnLicence 'BSD-3-Clause (Tencent/ncnn)' "https://github.com/Tencent/ncnn @ $ncnnPin" 'source tree, not redistributed'
        Write-Note "ncnn      $head"
    }
} else {
    Write-Step 'ncnn source tree (skipped)'
}

# --- OCR weights -------------------------------------------------------------
Write-Step "PP-OCRv5 mobile ncnn weights (source: $ModelSource)"
if ($ModelSource -eq 'official') {
    if (-not (Test-Path -LiteralPath $OfficialLock)) {
        Fail $exitVerify "official conversion lock is missing: $OfficialLock"
    }
    $lock = Get-Content -LiteralPath $OfficialLock -Raw | ConvertFrom-Json
    foreach ($name in @('PP_OCRv5_mobile_det.ncnn.param', 'PP_OCRv5_mobile_det.ncnn.bin',
                        'PP_OCRv5_mobile_rec.ncnn.param', 'PP_OCRv5_mobile_rec.ncnn.bin')) {
        $property = $lock.files.PSObject.Properties["ncnn-official/$name"]
        if (-not $property -or $property.Value.sha256 -notmatch '^[a-f0-9]{64}$') {
            Fail $exitVerify "models.lock.json has no pinned hash for ncnn-official/$name; complete and review the official conversion first"
        }
    }
    $converted = Join-Path $AssetRoot 'ncnn-official'
    $missingConverted = @($NihuiModels.Keys | Where-Object { -not (Test-Path -LiteralPath (Join-Path $converted $_)) })
    if ($missingConverted.Count -gt 0 -and -not $Check) {
        $pythonExe = if ($Python) { $Python } elseif ($env:WP17_CONVERT_PYTHON) { $env:WP17_CONVERT_PYTHON } else { $tools['python'] }
        if (-not $pythonExe) { Fail $exitTool 'python is required to run the pinned conversion' }
        $conversionArgs = @((Join-Path $RepoRoot 'native\ocr\tools\convert_models.py'), '--assets', $AssetRoot, '--python', $pythonExe)
        if ($Offline) { $conversionArgs += '--offline' }
        Write-Note "converting official weights with $pythonExe (paddle2onnx + pnnx)"
        & $pythonExe @conversionArgs
        if ($LASTEXITCODE -ne 0) { Fail $exitVerify 'model conversion failed; see the output above' }
    }
    # Verify the entire converted set before replacing any historical model.
    foreach ($name in @('PP_OCRv5_mobile_det.ncnn.param', 'PP_OCRv5_mobile_det.ncnn.bin',
                        'PP_OCRv5_mobile_rec.ncnn.param', 'PP_OCRv5_mobile_rec.ncnn.bin')) {
        $entry = $lock.files."ncnn-official/$name"
        $source = Join-Path $converted $name
        if (-not (Test-Path -LiteralPath $source)) { Fail $exitVerify "missing converted weight $source" }
        $digest = Get-Sha256 $source
        if ($digest -ne $entry.sha256) {
            Fail $exitVerify "$name has sha256 $digest, pinned $($entry.sha256)"
        }
    }
    foreach ($name in $NihuiModels.Keys) {
        $source = Join-Path $converted $name
        $dest = Join-Path (Join-Path $AssetRoot 'ncnn') $name
        if ($Check) {
            if (-not (Test-Path -LiteralPath $dest) -or (Get-Sha256 $dest) -ne (Get-Sha256 $source)) {
                Fail $exitVerify "official deployment does not match the converted weight: $dest"
            }
        } else {
            Copy-Item -LiteralPath $source -Destination $dest -Force
        }
        Add-Record "ncnn/$name" $dest 'apache-2.0 (PaddlePaddle/PP-OCRv5_mobile_*)' 'native/ocr/tools/convert_models.py' 'converted from the official Paddle inference model'
    }
} else {
    foreach ($name in $NihuiModels.Keys) {
        $url = $NihuiBase + $name
        Get-Cached "ncnn/$name" $NihuiModels[$name] $url 'no licence declared for the weights (repository /license is 404)' $url 'validation only: not cleared for redistribution' | Out-Null
    }
    Write-Note 'WARNING: the nihui weights have no declared redistribution licence.'
    Write-Note '         Use -ModelSource official once the pinned conversion is verified.'
}

# --- optional ncnn install trees --------------------------------------------
if ($Ncnn -eq 'host') {
    Write-Step 'ncnn host install tree'
    $hostBuild = Join-Path $AssetRoot 'ncnn-build-win'
    $hostInstall = Join-Path $hostBuild 'install'
    $hostCMake = Join-Path $hostInstall 'lib/cmake/ncnn/ncnnConfig.cmake'
    if ($Check) {
        if (-not (Test-Path -LiteralPath $hostCMake)) { Fail $exitVerify "missing ncnn install tree: $hostCMake" }
        Write-Note "cache hit  $hostCMake"
    } elseif ($Force -or -not (Test-Path -LiteralPath $hostCMake)) {
        if ($Offline) { Fail $exitNetwork "offline: ncnn host install tree is missing at $hostInstall" }
        Write-Note "build     $hostBuild (Release)"
        & cmake -S $ncnnSrc -B $hostBuild -DCMAKE_BUILD_TYPE=Release -DNCNN_VULKAN=OFF `
            -DNCNN_BUILD_TOOLS=OFF -DNCNN_BUILD_TESTS=OFF -DNCNN_BUILD_BENCHMARK=OFF `
            -DNCNN_BUILD_EXAMPLES=OFF -DNCNN_INSTALL_SDK=ON -DNCNN_SHARED_LIB=OFF -DNCNN_PIXEL=ON
        if ($LASTEXITCODE -ne 0) { Fail $exitVerify 'ncnn host configure failed' }
        & cmake --build $hostBuild --config Release --target install --parallel
        if ($LASTEXITCODE -ne 0) { Fail $exitVerify 'ncnn host build failed' }
    } else {
        Write-Note "cache hit  $hostCMake"
    }
}

# --- deployment layout -------------------------------------------------------
Write-Step "deployment layout under $DeployRoot"
$modelDir = Join-Path $DeployRoot 'ncnn'
if (-not $Check) { New-Item -ItemType Directory -Force -Path $modelDir | Out-Null }
foreach ($name in $RequiredModelFiles) {
    $source = Join-Path (Join-Path $AssetRoot 'ncnn') $name
    if (-not (Test-Path -LiteralPath $source)) { Fail $exitVerify "missing model file $source" }
    $target = Join-Path $modelDir $name
    if ($Check) {
        if (-not (Test-Path -LiteralPath $target)) { Fail $exitVerify "missing deployment file $target" }
        if ((Get-Sha256 $target) -ne (Get-Sha256 $source)) { Fail $exitVerify "deployment file differs from the verified source: $target" }
    } elseif ($Force -or -not (Test-Path -LiteralPath $target) -or (Get-Sha256 $target) -ne (Get-Sha256 $source)) {
        Copy-Item -LiteralPath $source -Destination $target -Force
    }
}
Write-Note "models    $modelDir"

# --- verification ------------------------------------------------------------
Write-Step 'verification'
$deployed = [ordered]@{}
foreach ($name in $RequiredModelFiles) {
    $target = Join-Path $modelDir $name
    if (-not (Test-Path -LiteralPath $target)) { Fail $exitVerify "deployment is missing $name" }
    if ((Get-Item -LiteralPath $target).Length -le 0) { Fail $exitVerify "$name is empty" }
    $deployed[$name] = Get-FileRecord $target
}
$dictLines = (Get-Content -LiteralPath (Join-Path $modelDir 'ppocrv5_dict.txt')).Count
if ($dictLines -lt 1000) { Fail $exitVerify "dictionary has only $dictLines lines" }
Write-Note "dictionary lines: $dictLines"

$nativeLib = $null
foreach ($candidate in @(
        (Join-Path $AssetRoot 'ncnn-build-win/install/bin/ncnn.dll'),
        (Join-Path $AssetRoot 'windows/matrixflow_ocr.dll'))) {
    if (Test-Path -LiteralPath $candidate) { $nativeLib = $candidate; break }
}
if ($nativeLib) {
    $bytes = [System.IO.File]::ReadAllBytes($nativeLib)
    $text = [System.Text.Encoding]::ASCII.GetString($bytes)
    foreach ($symbol in $RequiredSymbols) {
        if (-not $text.Contains($symbol)) { Fail $exitVerify "$nativeLib does not export $symbol" }
    }
    Add-Record 'windows/matrixflow_ocr.dll' $nativeLib 'project code' 'flutter build windows with WP17_OCR_NCNN_DIR/WP17_OCR_STB_DIR' 'optional component'
    Write-Note "native    $nativeLib exports all four ABI symbols"
} else {
    Write-Note 'native    no matrixflow_ocr.dll found next to the asset root; build it with'
    Write-Note '          WP17_OCR_NCNN_DIR / WP17_OCR_STB_DIR set before flutter build windows'
}

$reportPath = Join-Path $DeployRoot 'deployed.json'
if (-not $Check) {
    $report = [ordered]@{
        schema = 1
        generatedBy = 'tool/prepare_ocr_assets.ps1'
        assetRoot = $AssetRoot
        deployRoot = $DeployRoot
        modelSource = $ModelSource
        ncnnCommit = $ncnnPin
        models = $deployed
        records = $script:records
    }
    $json = $report | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath $reportPath -Value $json -Encoding UTF8
    Write-Note "report    $reportPath"
}

Write-Step 'result'
Write-Note "models deployed : $($deployed.Count) files under $modelDir"
Write-Note "WP17_OCR_ASSETS : $DeployRoot"
if ($Check) { Write-Note 'check-only run: nothing was written' }
exit $exitOk
