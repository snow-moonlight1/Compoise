[CmdletBinding()]
param(
    [switch]$Run,
    [ValidateSet('Build','Runtime')][string]$Kind='Runtime',
    [string]$Flutter='D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat',
    [string]$MatrixReport=''
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
if (!$Run) { Write-Output 'Blocked: R2 gate acceptance requires -Run.'; exit 2 }
$workspace=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
Set-Location -LiteralPath $workspace
$logs=Join-Path $workspace "build/wp28-r2/gates-$Kind-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $logs | Out-Null
$priorU2=$env:WP28_U2_HARNESS_BUILD
$priorD3=$env:WP15_D3_DEVICE_BUILD
$cases=[Collections.Generic.List[object]]::new()
$exitCode=1
$revision=(& git rev-parse HEAD).Trim()
$trace=(& python scripts/release_candidate.py source --directory $logs --platform Windows --tag v1.0.0+1 --commit $revision) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot trace gate source.' }
$diagnosticSource=$null
try {
    if ($Kind -eq 'Build') {
        $version=(& $Flutter --version --machine | Out-String) | ConvertFrom-Json
        $pin=Get-Content toolchain.json -Raw | ConvertFrom-Json
        if ($LASTEXITCODE -ne 0 -or $version.frameworkRevision -ne $pin.verified.revision -or
            $version.engineRevision -ne $pin.verified.engineRevision -or $version.dartSdkVersion -ne $pin.verified.dartVersion) { throw 'Pinned Flutter/Dart required.' }
        foreach ($case in @('native-only','dart-only','combined')) {
            $env:WP28_U2_HARNESS_BUILD=$null; $env:WP15_D3_DEVICE_BUILD=$null
            $arguments=@('build','windows','--debug','--no-pub','-t','lib/main.dart')
            switch ($case) {
                'native-only' { $env:WP28_U2_HARNESS_BUILD='1'; $expected='WP28_U2_HARNESS_BUILD=1 requires --dart-define=WP28_U2_HARNESS=true' }
                'dart-only' { $arguments+='--dart-define=WP28_U2_HARNESS=true'; $expected='WP28_U2_HARNESS=true requires WP28_U2_HARNESS_BUILD=1' }
                'combined' { $env:WP28_U2_HARNESS_BUILD='1'; $env:WP15_D3_DEVICE_BUILD='1'; $arguments+=@('--dart-define=WP28_U2_HARNESS=true','--dart-define=WP15_D3_DEVICE=true'); $expected='D3 and U2 harness builds cannot be combined' }
            }
            $log=Join-Path $logs "$case.log"
            & $Flutter @arguments *> $log
            $code=$LASTEXITCODE
            if ($code -eq 0 -or !(Get-Content $log -Raw).Contains($expected)) { throw "Wrong build rejection: $case (exit $code)." }
            $cases.Add(@{case=$case;exitCode=$code;expected=$expected;log=$log})
            # A rejected first configure leaves CMake's default Program Files
            # prefix cached before the Flutter template can set its bundle dir.
            # Quarantine only this build's cache, so the next configure is fresh.
            $cache=Join-Path $workspace 'build/windows/x64/CMakeCache.txt'
            if (Test-Path -LiteralPath $cache) { Move-Item -LiteralPath $cache -Destination (Join-Path $logs "$case-CMakeCache.txt") }
        }
    } else {
        if (!$MatrixReport) { throw 'Runtime gates require the just-passed diagnostic matrix report.' }
        $matrix=Get-Content -LiteralPath $MatrixReport -Raw | ConvertFrom-Json
        $exe=$matrix.exe
        if ($matrix.configuration -notin @('Debug','Release') -or
            [IO.Path]::GetFullPath($exe) -ne (Join-Path $workspace "build/windows/x64/runner/$($matrix.configuration)/compoise.exe")) { throw 'Runtime gates require this workspace diagnostic executable.' }
        if (!$matrix.passed -or $matrix.normalCandidate -ne $false -or
            (Get-FileHash -LiteralPath $exe).Hash -ne $matrix.executableSHA256) { throw 'Diagnostic matrix proof is stale or failed.' }
        $binary=[IO.File]::ReadAllBytes($exe)
        # Release may inline the method-name comparison without an ASCII literal.
        # These wide strings belong to the native entry gate in both configurations.
        $nativeText=[Text.Encoding]::Unicode.GetString($binary)
        if (!$nativeText.Contains('WP28_U2_RUN') -or
            !$nativeText.Contains('wp28-u2-device-')) { throw 'Runtime gates refuse an executable without the native diagnostic entry.' }
        $diagnosticSource=$matrix.source
        $namespace=[guid]::NewGuid().ToString()
        $root=Join-Path ([IO.Path]::GetTempPath()) "wp28-u2-device-$namespace"
        New-Item -ItemType Directory -Path $root | Out-Null
        $fileNamespace=[guid]::NewGuid().ToString()
        $fileRoot=Join-Path ([IO.Path]::GetTempPath()) "wp28-u2-device-$fileNamespace"
        [IO.File]::WriteAllText($fileRoot,'SYNTHETIC_REGULAR_FILE_ROOT')
        foreach ($case in @('missing-run','missing-guid','bad-guid','missing-root','temp-root','workspace-root','wrong-guid-root','dot-root','relative-root','file-root')) {
            $info=[Diagnostics.ProcessStartInfo]::new()
            $info.FileName=$exe; $info.WorkingDirectory=Split-Path -Parent $exe
            $info.UseShellExecute=$false; $info.CreateNoWindow=$true
            $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
            $info.EnvironmentVariables['WP28_U2_RUN']='1'
            $info.EnvironmentVariables['WP28_U2_NAMESPACE']=$namespace
            $info.EnvironmentVariables['WP28_U2_ROOT']=$root
            switch ($case) {
                'missing-run' { $info.EnvironmentVariables.Remove('WP28_U2_RUN') }
                'missing-guid' { $info.EnvironmentVariables.Remove('WP28_U2_NAMESPACE') }
                'bad-guid' { $info.EnvironmentVariables['WP28_U2_NAMESPACE']='------------------------------------' }
                'missing-root' { $info.EnvironmentVariables.Remove('WP28_U2_ROOT') }
                'temp-root' { $info.EnvironmentVariables['WP28_U2_ROOT']=[IO.Path]::GetTempPath().TrimEnd('\') }
                'workspace-root' { $info.EnvironmentVariables['WP28_U2_ROOT']=$workspace }
                'wrong-guid-root' { $info.EnvironmentVariables['WP28_U2_NAMESPACE']=[guid]::NewGuid().ToString() }
                'dot-root' { $info.EnvironmentVariables['WP28_U2_ROOT']=Join-Path $root '.' }
                'relative-root' { $info.EnvironmentVariables['WP28_U2_ROOT']=Split-Path -Leaf $root }
                'file-root' { $info.EnvironmentVariables['WP28_U2_ROOT']=$fileRoot; $info.EnvironmentVariables['WP28_U2_NAMESPACE']=$fileNamespace }
            }
            $process=[Diagnostics.Process]::new(); $process.StartInfo=$info
            if (!$process.Start()) { throw 'Native negative launch failed.' }
            $ownedPid=$process.Id; $started=$process.StartTime.ToUniversalTime().ToString('o')
            $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
            $timedOut=$false; $cleanup='not-needed'; $code=$null
            try {
                if (!$process.WaitForExit(15000)) { $timedOut=$true; throw 'Native runtime gate timed out.' }
                $code=$process.ExitCode
                $stdout.Result | Set-Content -LiteralPath (Join-Path $logs "$case.stdout.log")
                $stderr.Result | Set-Content -LiteralPath (Join-Path $logs "$case.stderr.log")
                if ($code -ne 2 -or $stdout.Result -or $stderr.Result -or @(Get-ChildItem -LiteralPath $root).Count) { throw 'Runtime gate reached COM/engine/data or returned the wrong exit.' }
            } finally {
                if (!$process.HasExited -and $process.Id -eq $ownedPid -and $process.Path -eq $exe -and $process.StartTime.ToUniversalTime().ToString('o') -eq $started) {
                    $process.Kill(); $process.WaitForExit(5000) | Out-Null; $cleanup='owned-process-killed-after-failure'
                }
                $cases.Add(@{case=$case;pid=$ownedPid;exitCode=$code;timedOut=$timedOut;alive=(!$process.HasExited);cleanup=$cleanup})
                $process.Dispose()
            }
        }
        # Exact owned, empty root only; never recurse or sweep earlier sessions.
        if ([IO.Path]::GetFullPath($root) -ne (Join-Path ([IO.Path]::GetTempPath()) "wp28-u2-device-$namespace")) { throw 'Cleanup root identity differs.' }
        Remove-Item -LiteralPath $root
        if ([IO.Path]::GetFullPath($fileRoot) -ne (Join-Path ([IO.Path]::GetTempPath()) "wp28-u2-device-$fileNamespace")) { throw 'File-root cleanup identity differs.' }
        Remove-Item -LiteralPath $fileRoot
    }
    $exitCode=0
} finally {
    $env:WP28_U2_HARNESS_BUILD=$priorU2; $env:WP15_D3_DEVICE_BUILD=$priorD3
    @{kind=$Kind;exitCode=$exitCode;commit=$revision;sourceAtCheck=$trace;diagnosticSource=$diagnosticSource;cases=$cases.ToArray()} | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $logs 'result.json') -Encoding utf8
    Write-Output "R2 gates: $logs/result.json; exit=$exitCode"
}
exit $exitCode
