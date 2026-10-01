<#
.SYNOPSIS
    Build the reviewed WP17 OCR native library and smoke caller for Windows.

.DESCRIPTION
    Same ncnn commit, same source file, same compiler flags as the Android and
    Linux legs. Use this when you want the library plus its measurements without
    a full `flutter build windows`; the Flutter build itself uses the same
    wp17_ocr subdirectory through windows/CMakeLists.txt.

.EXAMPLE
    powershell -File tool/build_ocr_windows.ps1
#>
param(
    [string]$Assets = $(if ($env:WP17R2_ASSETS) { $env:WP17R2_ASSETS } else { Join-Path $env:LOCALAPPDATA 'wp17r2-assets' }),
    [string]$Out = $(Join-Path $env:TEMP 'wp17i4-native-win'),
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$ncnnDir = Join-Path $Assets 'ncnn-build-win\install\lib\cmake\ncnn'
$stbDir = Join-Path $Assets 'third_party'
if (-not (Test-Path -LiteralPath $ncnnDir)) { throw "ncnn install tree not found: $ncnnDir" }
if (-not (Test-Path -LiteralPath (Join-Path $stbDir 'stb_image.h'))) { throw "stb_image.h not found in $stbDir" }

Write-Host "ncnn   : $ncnnDir"
Write-Host "stb    : $stbDir"
Write-Host "config : $Configuration"

& cmake -S (Join-Path $repo 'native\ocr') -B $Out -DCMAKE_BUILD_TYPE=$Configuration `
    -Dncnn_DIR="$ncnnDir" -DWP17_STB_DIR="$stbDir" -DWP17_OCR_BUILD_SMOKE=ON
if ($LASTEXITCODE -ne 0) { throw 'configure failed' }
& cmake --build $Out --config $Configuration
if ($LASTEXITCODE -ne 0) { throw 'build failed' }

$dll = Get-ChildItem $Out -Recurse -Filter 'matrixflow_ocr.dll' | Select-Object -First 1
$smoke = Get-ChildItem $Out -Recurse -Filter 'matrixflow_ocr_smoke.exe' | Select-Object -First 1
if (-not $dll) { throw 'matrixflow_ocr.dll was not produced' }
Write-Host ("library: {0} ({1:N0} bytes, sha256 {2})" -f $dll.FullName, $dll.Length, (Get-FileHash $dll.FullName -Algorithm SHA256).Hash)
if ($smoke) { Write-Host ("smoke  : {0}" -f $smoke.FullName) }
