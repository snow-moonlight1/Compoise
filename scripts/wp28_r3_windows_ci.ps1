[CmdletBinding()]
param(
    [switch]$Run,
    [ValidateSet('Debug','Release','All')][string]$Configuration='All',
    [string]$Flutter='D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat',
    [string]$EvidenceDirectory='',
    [int]$ReportTimeoutMs=30000,
    [int]$ExitTimeoutMs=45000,
    [int]$GateTimeoutMs=15000
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$Run) { Write-Output 'Blocked: WP28-R3 native CI matrix requires -Run.'; exit 2 }
if ($env:OS -ne 'Windows_NT') { throw 'WP28-R3 native matrix requires Windows.' }
if ($ReportTimeoutMs -le 0 -or $ExitTimeoutMs -le 0 -or $GateTimeoutMs -le 0) { throw 'Timeouts must be positive.' }
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $workspace
if (!(Test-Path -LiteralPath $Flutter)) {
    $resolved=Get-Command $Flutter -ErrorAction SilentlyContinue
    if ($resolved) { $Flutter=$resolved.Source }
}
if (!(Test-Path -LiteralPath $Flutter)) { throw "Flutter SDK not found: $Flutter" }
if (!$EvidenceDirectory) { $EvidenceDirectory = Join-Path $workspace ('build/wp28-r3/' + [guid]::NewGuid().ToString()) }
$evidence=[IO.Path]::GetFullPath($EvidenceDirectory)
New-Item -ItemType Directory -Force -Path $evidence | Out-Null
$python=(Get-Command python).Source
$probe=Join-Path $PSScriptRoot 'wp28_r3_desktop_probe.ps1'
$diagnostic=Join-Path $PSScriptRoot 'wp28_r2_build_diagnostic.ps1'
$harness=Join-Path $PSScriptRoot 'wp28_u2_windows_harness.ps1'
$gates=Join-Path $PSScriptRoot 'wp28_r2_windows_gates.ps1'
$reportPy=Join-Path $PSScriptRoot 'wp28_r3_report.py'
$validator=Join-Path $PSScriptRoot 'release_candidate.py'
$output=Join-Path $evidence 'ci-report.json'
function Save-Failure([string]$Message) {
    $Message | Set-Content -LiteralPath (Join-Path $evidence 'orchestrator-error.txt') -Encoding utf8
}
& $python $reportPy require-fresh --evidence $evidence
if ($LASTEXITCODE -ne 0) { throw 'Evidence directory is not fresh; refusing to reuse an old report.' }
if (Test-Path -LiteralPath $output) {
    $placeholder=Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    $placeholder.status='running'
    $placeholder | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $output -Encoding utf8
}
$revision=(& git rev-parse HEAD).Trim()
$trace=(& $python $validator source --directory $evidence --platform Windows --tag v1.0.0+1 --commit $revision) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot trace diagnostic source.' }
$trace | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $evidence 'source.json') -Encoding utf8
Write-Output "Source fingerprint written; checking pinned Flutter."
$toolchain=(& $Flutter --version --machine | Out-String) | ConvertFrom-Json
$pin=Get-Content -LiteralPath (Join-Path $workspace 'toolchain.json') -Raw | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $toolchain.frameworkRevision -ne $pin.verified.revision -or
    $toolchain.engineRevision -ne $pin.verified.engineRevision -or $toolchain.dartSdkVersion -ne $pin.verified.dartVersion) {
    throw 'Pinned Flutter/Dart required.'
}
Write-Output 'Running pub get --enforce-lockfile.'
& $Flutter pub get --enforce-lockfile
if ($LASTEXITCODE -ne 0) { throw 'pub get --enforce-lockfile failed.' }
try {
    Write-Output 'Probing interactive desktop.'
    & $probe -Run -EvidenceDirectory $evidence
    if ($LASTEXITCODE -ne 0) { throw "Desktop probe failed (exit $LASTEXITCODE)." }
    Write-Output 'Running compile-gate negatives.'
    & $gates -Run -Kind Build -Flutter $Flutter -EvidenceDirectory $evidence -TimeoutMs $GateTimeoutMs
    if ($LASTEXITCODE -ne 0) { throw "Build gates failed (exit $LASTEXITCODE)." }
    $configs=@($Configuration)
    if ($Configuration -eq 'All') { $configs=@('Debug','Release') }
    foreach ($config in $configs) {
        Write-Output "Starting $config diagnostic matrix."
        $cfgDir=Join-Path $evidence $config
        New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
        & $diagnostic -Run -Configuration $config -Flutter $Flutter -EvidenceDirectory $cfgDir
        if ($LASTEXITCODE -ne 0) { throw "Diagnostic $config failed (exit $LASTEXITCODE)." }
        $proof=Join-Path $cfgDir "diagnostic-$config.json"
        $matrixDir=Join-Path $cfgDir 'matrix'
        New-Item -ItemType Directory -Force -Path $matrixDir | Out-Null
        Write-Output "Starting $config harness reportTimeoutMs=$ReportTimeoutMs exitTimeoutMs=$ExitTimeoutMs"
        $harnessArgs=@{
            Run=$true
            Mode='Core'
            Configuration=$config
            EvidenceDirectory=$matrixDir
            DiagnosticProof=$proof
            ReportTimeoutMs=$ReportTimeoutMs
            ExitTimeoutMs=$ExitTimeoutMs
        }
        & $harness @harnessArgs
        if ($LASTEXITCODE -ne 0) { throw "Matrix $config failed (exit $LASTEXITCODE)." }
        $harnessReport=Get-ChildItem -LiteralPath $matrixDir -Recurse -Filter harness.json | Select-Object -First 1
        if (!$harnessReport) { throw "Missing harness.json for $config." }
        & $gates -Run -Kind Runtime -Flutter $Flutter -EvidenceDirectory $cfgDir -MatrixReport $harnessReport.FullName -TimeoutMs $GateTimeoutMs
        if ($LASTEXITCODE -ne 0) { throw "Runtime gates $config failed (exit $LASTEXITCODE)." }
    }
} catch {
    Save-Failure $_.Exception.Message
}
& $python $reportPy assemble --evidence $evidence --commit $revision --configuration $Configuration --output $output
exit $LASTEXITCODE
