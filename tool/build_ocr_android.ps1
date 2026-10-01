<#
.SYNOPSIS
    Build the WP17 OCR shared library for the Android ABIs with the pinned NDK
    and record the ELF facts (API level, NEEDED libraries, architecture).

.DESCRIPTION
    This is the native-input check that runs without a full APK build. The
    shipped APK is still produced by `flutter build apk` with the
    wp17OcrNcnnRoot / wp17OcrStbDir Gradle properties or local.properties keys.

.EXAMPLE
    powershell -File tool/build_ocr_android.ps1
#>
param(
    [string]$Ndk = 'D:\Dev_SDKs\android-ndk-r27b',
    [string]$Assets = $(if ($env:WP17R2_ASSETS) { $env:WP17R2_ASSETS } else { Join-Path $env:LOCALAPPDATA 'wp17r2-assets' }),
    [string[]]$Abi = @('x86_64', 'arm64-v8a'),
    [int]$Api = 23,
    [string]$Out
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$toolchain = Join-Path $Ndk 'build/cmake/android.toolchain.cmake'
if (-not (Test-Path -LiteralPath $toolchain)) { throw "NDK toolchain not found: $toolchain" }

$ninja = (Get-Command ninja -ErrorAction SilentlyContinue).Source
if (-not $ninja) {
    $ninja = (Get-ChildItem 'D:\Dev_Tools' -Recurse -Depth 3 -Filter 'ninja.exe' -ErrorAction SilentlyContinue |
        Select-Object -First 1).FullName
    if ($ninja) { $env:PATH = "$(Split-Path -Parent $ninja);$env:PATH" }
}
if (-not $ninja) { throw 'ninja was not found' }

if (-not $Out) { $Out = Join-Path $Assets 'wp17i4-android' }
$fwd = { param($p) $p -replace '\\', '/' }
$readelf = Join-Path $Ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe'
if (-not (Test-Path -LiteralPath $readelf)) { throw "llvm-readelf not found: $readelf" }

foreach ($abiName in $Abi) {
    Write-Host "==== $abiName (android-$Api) ====" -ForegroundColor Cyan
    $build = Join-Path $Out $abiName
    $args = @(
        '-S', $repo, '-B', $build, '-G', 'Ninja',
        "-DCMAKE_TOOLCHAIN_FILE=$(& $fwd $toolchain)",
        "-DANDROID_ABI=$abiName", "-DANDROID_PLATFORM=android-$Api", '-DANDROID_STL=c++_static',
        '-DCMAKE_BUILD_TYPE=Release',
        "-DWP17_NCNN_ROOT=$(& $fwd $Assets)",
        "-DWP17_STB_DIR=$(& $fwd (Join-Path $Assets 'third_party'))",
        '-DWP17_OCR_BUILD_SMOKE=ON'
    )
    & cmake @args | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "configure failed for $abiName" }
    & cmake --build $build | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "build failed for $abiName" }

    $lib = Join-Path $build 'libmatrixflow_ocr.so'
    if (-not (Test-Path -LiteralPath $lib)) { throw "missing $lib" }
    Write-Host ("library : {0} ({1:N0} bytes)" -f $lib, (Get-Item $lib).Length)
    & $readelf -d $lib | Select-String -Pattern 'NEEDED|SONAME'
    & $readelf -n $lib | Select-String -Pattern 'Android|NDK'
}
