[CmdletBinding()]
param(
    [switch]$Run,
    [ValidateSet('Debug','Release')][string]$Configuration='Debug',
    [string]$Flutter='D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat',
    [string]$EvidenceDirectory=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$Run) { Write-Output 'Blocked: R2 diagnostic build requires -Run.'; exit 2 }
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $workspace
if (!$EvidenceDirectory) { $EvidenceDirectory = Join-Path $workspace 'build/wp28-r2' }
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$proof=Join-Path $evidence "diagnostic-$Configuration.json"
if (Test-Path -LiteralPath $proof) { Remove-Item -LiteralPath $proof }
$validator=Join-Path $workspace 'scripts/release_candidate.py'
$revision=(& git rev-parse HEAD).Trim()
$trace=(& python $validator source --directory $evidence --platform Windows --tag v1.0.0+1 --commit $revision) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot trace diagnostic source.' }
$toolchain=(& $Flutter --version --machine | Out-String) | ConvertFrom-Json
$pin=Get-Content toolchain.json -Raw | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $toolchain.frameworkRevision -ne $pin.verified.revision -or
    $toolchain.engineRevision -ne $pin.verified.engineRevision -or $toolchain.dartSdkVersion -ne $pin.verified.dartVersion) { throw 'Pinned Flutter/Dart required.' }
$priorU2=$env:WP28_U2_HARNESS_BUILD; $priorD3=$env:WP15_D3_DEVICE_BUILD
try {
    $cache=Join-Path $workspace 'build/windows/x64/CMakeCache.txt'
    if (Test-Path -LiteralPath $cache) {
        $prefix=[regex]::Match((Get-Content -LiteralPath $cache -Raw),'(?m)^CMAKE_INSTALL_PREFIX:PATH=(.+)$').Groups[1].Value.Trim()
        if (!$prefix.StartsWith('$<TARGET_FILE_DIR:') -and !$prefix.StartsWith(($workspace.Replace('\','/') + '/build/windows/'))) {
            Move-Item -LiteralPath $cache -Destination (Join-Path $evidence "rejected-install-prefix-$([guid]::NewGuid()).txt")
        }
    }
    $env:WP28_U2_HARNESS_BUILD='1'; $env:WP15_D3_DEVICE_BUILD=$null
    $log=Join-Path $evidence "diagnostic-$Configuration-build.log"
    $prevEA=$ErrorActionPreference
    $ErrorActionPreference='Continue'
    & $Flutter build windows "--$($Configuration.ToLowerInvariant())" --no-pub --dart-define=WP28_U2_HARNESS=true -t lib/main.dart *> $log
    $code=$LASTEXITCODE
    $ErrorActionPreference=$prevEA
    if ($code -ne 0) { throw "Diagnostic build failed (exit $code): $log" }
    $after=(& python $validator source --directory $evidence --platform Windows --tag v1.0.0+1 --commit $revision) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or (& git rev-parse HEAD).Trim() -ne $revision -or $after.diffSha256 -ne $trace.diffSha256) { throw 'Source changed during diagnostic build.' }
    $bundle=Join-Path $workspace "build/windows/x64/runner/$Configuration"
    $bundleRoot=[IO.Path]::GetFullPath($bundle).TrimEnd('\') + '\'
    $files=@(Get-ChildItem -LiteralPath $bundle -File -Recurse | ForEach-Object {
        $rel=[IO.Path]::GetFullPath($_.FullName)
        if ($rel.StartsWith($bundleRoot, [StringComparison]::OrdinalIgnoreCase)) { $rel=$rel.Substring($bundleRoot.Length) }
        @{path=$rel.Replace('\','/'); bytes=$_.Length; sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}
    } | Sort-Object { $_.path })
    @{schema=1;normalCandidate=$false;configuration=$Configuration;commit=$revision;source=$trace;toolchain=$toolchain;
      nativeGate='WP28_U2_HARNESS';dartGate='WP28_U2_HARNESS=true';target='lib/main.dart';buildExitCode=$code;
      executableSHA256=(Get-FileHash -LiteralPath (Join-Path $bundle 'compoise.exe')).Hash;files=$files;log=$log} |
      ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $proof -Encoding utf8
    Write-Output "Diagnostic proof: $proof; exit=$code"
} finally {
    $env:WP28_U2_HARNESS_BUILD=$priorU2; $env:WP15_D3_DEVICE_BUILD=$priorD3
}
