<#
.SYNOPSIS
    WP17-R2 Android leg: cross-compile ncnn and the shared OCR CLI for
    android-23 with the NDK.

.DESCRIPTION
    Builds two ABIs:
      x86_64    - what the API 23 emulator can actually execute (the real
                  runtime validation happens here)
      arm64-v8a - the ABI a real phone uses.  Producing the binary proves the
                  same source builds against minSdk 23 for arm64; running it
                  needs an arm64 device or an arm64 host emulator, so if none is
                  available the report says "built, not run".

    Tesseract is not built here; docs/WP17_OCR_EVALUATION.md records its
    unverified Android status.

.EXAMPLE
    powershell -File core/build_android.ps1
#>
param(
    [string]$Assets = "$env:LOCALAPPDATA\wp17r2-assets",
    [string]$Ndk = "D:\Dev_SDKs\android-ndk-r27b",
    [string[]]$Abis = @("x86_64", "arm64-v8a"),
    [int]$Api = 23
)

$ErrorActionPreference = "Stop"
$core = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolchain = Join-Path $Ndk "build\cmake\android.toolchain.cmake"
if (-not (Test-Path $toolchain)) { throw "NDK toolchain not found: $toolchain" }

$ninjaExe = (Get-Command ninja -ErrorAction SilentlyContinue).Source
if (-not $ninjaExe) {
    $cand = Get-ChildItem "D:\Dev_Tools" -Recurse -Depth 3 -Filter "ninja.exe" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cand) { $ninjaExe = $cand.FullName; $env:PATH = "$($cand.DirectoryName);$env:PATH" }
}
if (-not $ninjaExe) { throw "ninja not found" }
Write-Host "ninja: $ninjaExe"

# Forward slashes: the NDK toolchain greps these values, and backslashes inside
# -D arguments reach cmake as escapes.
$fwd = { param($p) $p -replace '\\', '/' }
$tcArg = "-DCMAKE_TOOLCHAIN_FILE=$(& $fwd $toolchain)"
$mkArg = "-DCMAKE_MAKE_PROGRAM=$(& $fwd $ninjaExe)"
$assetsFwd = & $fwd $Assets
$coreFwd = & $fwd $core

foreach ($abi in $Abis) {
    Write-Host "==== $abi (android-$Api) ====" -ForegroundColor Cyan

    $ncnnBuild = "$assetsFwd/ncnn-android-$abi"
    $ncnnArgs = @(
        "-S", "$assetsFwd/ncnn-src", "-B", $ncnnBuild, "-G", "Ninja",
        $tcArg, "-DANDROID_ABI=$abi", "-DANDROID_PLATFORM=android-$Api",
        "-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=Release", $mkArg,
        "-DNCNN_VULKAN=OFF", "-DNCNN_BUILD_EXAMPLES=OFF", "-DNCNN_BUILD_TOOLS=OFF",
        "-DNCNN_BUILD_BENCHMARK=OFF", "-DNCNN_BUILD_TESTS=OFF", "-DNCNN_SHARED_LIB=OFF",
        "-DNCNN_PIXEL=ON"
    )
    # The API 23 x86_64 emulator exposes SSE4.2 but no AVX/FMA/F16C.
    # ncnn enables these optimizations by default and otherwise traps with SIGILL.
    if ($abi -eq "x86_64") {
        $ncnnArgs += @(
            "-DNCNN_AVX=OFF", "-DNCNN_AVX2=OFF", "-DNCNN_AVX512=OFF",
            "-DNCNN_FMA=OFF", "-DNCNN_F16C=OFF"
        )
    }
    & cmake @ncnnArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ncnn configure failed for $abi" }
    & cmake --build $ncnnBuild --target install | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "ncnn build failed for $abi" }
    Write-Host "ncnn installed: $ncnnBuild/install"

    $cliBuild = "$assetsFwd/build-android-$abi"
    $cliArgs = @(
        "-S", $coreFwd, "-B", $cliBuild, "-G", "Ninja",
        $tcArg, "-DANDROID_ABI=$abi", "-DANDROID_PLATFORM=android-$Api",
        "-DANDROID_STL=c++_static", "-DCMAKE_BUILD_TYPE=Release", $mkArg,
        "-Dncnn_DIR=$ncnnBuild/install/lib/cmake/ncnn",
        "-DWP17R2_THIRD_PARTY=$assetsFwd/third_party",
        "-DWP17R2_WITH_TESSERACT=OFF"
    )
    & cmake @cliArgs | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "cli configure failed for $abi" }
    & cmake --build $cliBuild | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "cli build failed for $abi" }

    $exe = Get-ChildItem -Recurse $cliBuild -Filter "wp17r2_ocr" | Select-Object -First 1
    Write-Host ("cli: {0}  ({1:N0} KiB)" -f $exe.FullName, ($exe.Length / 1KB)) -ForegroundColor Green
}
