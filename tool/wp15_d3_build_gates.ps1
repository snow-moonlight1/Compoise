param([switch]$Run, [string]$Flutter='D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat')
$ErrorActionPreference='Stop'
if(-not $Run) { Write-Error 'D3 build-gate acceptance requires -Run (blocked 2).' -ErrorAction Continue; exit 2 }
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace
$logs=Join-Path $workspace 'build/wp15-d3/build-gates'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$runLock=[IO.File]::Open((Join-Path $workspace 'build/wp15-d3/windows-run.lock'),'OpenOrCreate','ReadWrite','None')
$priorD3=$env:WP15_D3_DEVICE_BUILD; $priorU2=$env:WP28_U2_HARNESS_BUILD
$results=@()
$exitCode=1
try {
    $version=(& $Flutter --version --machine | Out-String) | ConvertFrom-Json
    if($LASTEXITCODE -ne 0 -or $version.frameworkVersion -ne '3.32.8') { throw 'Flutter 3.32.8 required.' }
    foreach($case in @('native_only','dart_only','combined_u2')) {
        $env:WP15_D3_DEVICE_BUILD=$null; $env:WP28_U2_HARNESS_BUILD=$null
        $arguments=@('build','windows','--debug','--no-pub','-t','test/wp15_d3_device_test.dart')
        switch($case) {
            'native_only' { $env:WP15_D3_DEVICE_BUILD='1'; $expected='WP15_D3_DEVICE_BUILD=1 requires WP15_D3_DEVICE=true' }
            'dart_only' { $arguments+='--dart-define=WP15_D3_DEVICE=true'; $expected='WP15_D3_DEVICE=true requires WP15_D3_DEVICE_BUILD=1' }
            'combined_u2' { $env:WP15_D3_DEVICE_BUILD='1'; $env:WP28_U2_HARNESS_BUILD='1'; $arguments+=@('--dart-define=WP15_D3_DEVICE=true','--dart-define=WP28_U2_HARNESS=true'); $expected='D3 and U2 harness builds cannot be combined' }
        }
        $log=Join-Path $logs "$case.log"
        & $Flutter @arguments *> $log
        $code=$LASTEXITCODE
        if($code -eq 0 -or -not (Get-Content -LiteralPath $log -Raw).Contains($expected)) { throw "Build gate $case did not reject for its expected reason (exit $code)." }
        $results+=@{case=$case;exitCode=$code;expected=$expected;log=$log}
        Write-Output "WP15_D3_BUILD_GATE $case expected rejection exit=$code"
    }
    $exitCode=0
} finally {
    $env:WP15_D3_DEVICE_BUILD=$priorD3; $env:WP28_U2_HARNESS_BUILD=$priorU2
    @{exitCode=$exitCode;cases=$results} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $logs 'result.json') -Encoding utf8
    $runLock.Dispose()
}
exit $exitCode
