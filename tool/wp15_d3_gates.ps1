param([switch]$Run, [int]$TimeoutSeconds=15)
$ErrorActionPreference='Stop'
if (-not $Run) { Write-Error 'D3 gate acceptance requires -Run (blocked 2).' -ErrorAction Continue; exit 2 }
$workspace=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace
$logs=Join-Path $workspace 'build/wp15-d3/gates'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
$accepted=Get-Content -LiteralPath 'build/wp15-d3/windows-result.json' -Raw | ConvertFrom-Json
$exe=(Resolve-Path 'build/windows/x64/runner/Debug/compoise.exe').Path
$sha=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
# Only the same successfully accepted diagnostic binary can be launched.
if ($accepted.exitCode -ne 0 -or $accepted.nativeExitCode -ne 0 -or $accepted.exeSha256 -ne $sha) { throw 'Run successful D3 native acceptance first; binary seal mismatch.' }
$evidence=Get-Content -LiteralPath (Join-Path $accepted.evidence 'driver-result.json') -Raw | ConvertFrom-Json
if ($evidence.native.nativeGate -ne $true -or $evidence.native.privateDesktop -ne $true) { throw 'Missing native/Dart isolation proof.' }
$namespace=[guid]::NewGuid().ToString()
$temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$root=Join-Path $temp "wp15-d3-device-$namespace"
New-Item -ItemType Directory -Path $root | Out-Null
$prior=@{}
foreach($key in @('WP15_D3_RUN','WP15_D3_NAMESPACE','WP15_D3_ROOT')) { $prior[$key]=[Environment]::GetEnvironmentVariable($key,'Process') }
$results=@()
$native=$null
$exitCode=1
try {
    foreach($case in @('missing_run','missing_namespace','malformed_namespace','missing_root','temp_root','workspace_root','mismatched_guid','dot_component','duplicate_mutex')) {
        $env:WP15_D3_RUN='1'; $env:WP15_D3_NAMESPACE=$namespace; $env:WP15_D3_ROOT=$root
        $mutex=$null
        switch($case) {
            'missing_run' { $env:WP15_D3_RUN=$null }
            'missing_namespace' { $env:WP15_D3_NAMESPACE=$null }
            'malformed_namespace' { $env:WP15_D3_NAMESPACE='not-a-guid' }
            'missing_root' { $env:WP15_D3_ROOT=$null }
            'temp_root' { $env:WP15_D3_ROOT=$temp }
            'workspace_root' { $env:WP15_D3_ROOT=$workspace }
            'mismatched_guid' { $env:WP15_D3_NAMESPACE=[guid]::NewGuid().ToString() }
            'dot_component' { $env:WP15_D3_ROOT="$root\." }
            'duplicate_mutex' { $mutex=[Threading.Mutex]::new($true,"Local\Compoise.WP15D3.$namespace") }
        }
        try {
            $stdout=Join-Path $logs "$case.stdout.log"; $stderr=Join-Path $logs "$case.stderr.log"
            $native=Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
            $null=$native.Handle
            $startTime=$native.StartTime
            if(-not $native.WaitForExit($TimeoutSeconds*1000)) { throw "Gate $case timed out." }
            $item=@{case=$case;pid=$native.Id;exitCode=$native.ExitCode;residual=[bool](Get-Process -Id $native.Id -ErrorAction SilentlyContinue)}
            $results+=$item
            if($item.exitCode -ne 2 -or $item.residual) { throw "Gate $case was not blocked before engine startup." }
            if((Get-Item -LiteralPath $stdout).Length -ne 0 -or (Get-Item -LiteralPath $stderr).Length -ne 0) { throw "Unexpected engine output for blocked gate $case." }
            Write-Output "WP15_D3_GATE $case exit=$($item.exitCode) residual=$($item.residual)"
            $native=$null
        } finally {
            if($native -and -not $native.HasExited) {
                $check=Get-Process -Id $native.Id -ErrorAction SilentlyContinue
                if($check -and $check.Path -eq $exe -and $check.StartTime -eq $startTime) { $native.Kill(); $native.WaitForExit() }
            }
            if($mutex) { $mutex.Dispose() }
        }
    }
    $exitCode=0
} finally {
    foreach($key in $prior.Keys) { [Environment]::SetEnvironmentVariable($key,$prior[$key],'Process') }
    $checked=[IO.Path]::GetFullPath($root)
    if([IO.Path]::GetDirectoryName($checked) -ne $temp -or [IO.Path]::GetFileName($checked) -ne "wp15-d3-device-$namespace") { throw 'Refusing cleanup outside owned exact temp leaf.' }
    if(Test-Path -LiteralPath $checked) { Remove-Item -LiteralPath $checked -Recurse -Force }
    @{exitCode=$exitCode;exeSha256=$sha;cases=$results;tempResidual=(Test-Path -LiteralPath $checked)} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logs 'runtime-result.json') -Encoding utf8
}
exit $exitCode
