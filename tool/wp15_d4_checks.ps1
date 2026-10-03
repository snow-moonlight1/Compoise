param(
    [ValidateSet('baseline','targeted','analyze','full','build')]
    [string]$Stage = 'targeted',
    [string]$Flutter = 'D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat'
)
$ErrorActionPreference = 'Stop'
$taskWorkspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $taskWorkspace
$taskRoot = Join-Path $taskWorkspace 'build/wp15-d4'
New-Item -ItemType Directory -Path $taskRoot,(Join-Path $taskRoot '.pub-cache'),(Join-Path $taskRoot 'tmp') -Force | Out-Null
$env:PUB_CACHE = Join-Path $taskRoot '.pub-cache'
$env:TEMP = Join-Path $taskRoot 'tmp'
$env:TMP = $env:TEMP
$taskPin = Get-Content toolchain.json -Raw | ConvertFrom-Json
$taskVersion = (& $Flutter --version --machine | Out-String) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $taskVersion.frameworkRevision -ne $taskPin.verified.revision -or $taskVersion.dartSdkVersion -ne $taskPin.verified.dartVersion -or $taskVersion.engineRevision -ne $taskPin.verified.engineRevision) { throw 'Pinned SDK mismatch.' }
$taskLog = Join-Path $taskRoot "$Stage.log"
$taskArgs = switch ($Stage) {
    'baseline' { @('test','--no-pub','--concurrency=1','--reporter','expanded','test/wp15_d4_accessibility_test.dart') }
    'targeted' { @('test','--no-pub','--concurrency=1','--reporter','expanded') + @(Get-ChildItem test/wp15_d4_*_test.dart,test/wp15_c1_*_test.dart,test/wp15_c2_*_test.dart,test/wp15_d1_*_test.dart,test/wp15_d2_*_test.dart,test/wp15_d3_*_test.dart | ForEach-Object { $_.FullName }) }
    'analyze' { @('analyze','--no-pub') }
    'full' { @('test','--no-pub','--concurrency=1','--reporter','expanded') }
    'build' { @('build','windows','--debug','--no-pub','-t','lib/main.dart') }
}
$taskPriorPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue' # PS5 reports native stderr as ErrorRecord.
& $Flutter @taskArgs > $taskLog 2>&1
$taskExit = $LASTEXITCODE
$ErrorActionPreference = $taskPriorPreference
@{ stage=$Stage; command="$Flutter $($taskArgs -join ' ')"; exitCode=$taskExit; revision=(& git rev-parse HEAD); dirty=[bool](& git status --porcelain); log=$taskLog } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $taskRoot "$Stage-result.json") -Encoding utf8
Get-Content -LiteralPath $taskLog -Tail 18
Write-Output "WP15_D4_${Stage}_EXIT=$taskExit"
exit $taskExit
