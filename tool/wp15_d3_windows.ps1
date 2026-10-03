param(
    [switch]$Run,
    [string]$Flutter = 'D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat',
    [int]$TimeoutSeconds = 900
)
$ErrorActionPreference = 'Stop'
if (-not $Run) { Write-Error 'D3 native acceptance requires -Run; disabled is blocked (2).' -ErrorAction Continue; exit 2 }
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $workspace
$logs = Join-Path $workspace 'build/wp15-d3'
New-Item -ItemType Directory -Path $logs -Force | Out-Null
try { $runLock = [IO.File]::Open((Join-Path $logs 'windows-run.lock'), 'OpenOrCreate', 'ReadWrite', 'None') }
catch { Write-Error 'Another D3 acceptance owns this worktree.' -ErrorAction Continue; exit 2 }
$revision = (& git rev-parse HEAD).Trim()
$dirty = [bool](& git status --porcelain --untracked-files=normal)
$namespace = [guid]::NewGuid().ToString()
$temp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
$dataRoot = Join-Path $temp "wp15-d3-device-$namespace"
$native = $null
$driver = $null
$exitCode = 2
$beforeZone = (Get-TimeZone).Id
$result = @{ revision=$revision; dirty=$dirty; namespace=$namespace; platform='windows'; originalZone=$beforeZone }
$prior = @{}
foreach ($name in @('WP15_D3_DEVICE_BUILD','WP15_D3_RUN','WP15_D3_ROOT','WP15_D3_NAMESPACE','VM_SERVICE_URL','WP15_D3_EXPECTED_PID','WP15_D3_EXPECTED_COMMIT')) {
    $prior[$name] = [Environment]::GetEnvironmentVariable($name,'Process')
}
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class D3WindowClose {
    public delegate bool EnumProc(IntPtr hwnd, IntPtr arg);
    [DllImport("user32.dll")] static extern bool EnumDesktopWindows(IntPtr desktop, EnumProc callback, IntPtr arg);
    [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenDesktop(string name, uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr w, IntPtr l);
    public static bool Close(uint ownedPid, string name) {
        var desktop=OpenDesktop(name,0,false,0x41); // ENUMERATE | WRITEOBJECTS
        if(desktop==IntPtr.Zero) return false;
        bool sent=false;
        EnumDesktopWindows(desktop,(hwnd, arg) => { uint pid; GetWindowThreadProcessId(hwnd, out pid);
            if(pid==ownedPid) sent=PostMessage(hwnd,0x10,IntPtr.Zero,IntPtr.Zero)||sent;
            return true; }, IntPtr.Zero);
        CloseDesktop(desktop);
        return sent;
    }
}
'@
try {
    $version = (& $Flutter --version --machine | Out-String) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $version.frameworkVersion -ne '3.32.8') { throw 'Flutter 3.32.8 required.' }
    $env:WP15_D3_DEVICE_BUILD = '1'
    $buildLog = Join-Path $logs 'device-build.log'
    $command = '""{0}" build windows --debug --no-pub -t test/wp15_d3_device_test.dart --dart-define=WP15_D3_DEVICE=true --dart-define=WP15_D3_COMMIT={1} > "{2}" 2>&1"' -f $Flutter,$revision,$buildLog
    $start = [Diagnostics.ProcessStartInfo]::new('cmd.exe', "/d /s /c $command")
    $start.WorkingDirectory=$workspace; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $driver=[Diagnostics.Process]::Start($start)
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $driver.WaitForExit(500)) { if ([DateTime]::UtcNow -gt $deadline) { throw 'Build timed out.' } }
    $result.buildExitCode=$driver.ExitCode
    if ($driver.ExitCode -ne 0) { $exitCode=$driver.ExitCode; throw 'D3 build failed; see device-build.log.' }
    $driver=$null
    $exe=(Resolve-Path -LiteralPath 'build/windows/x64/runner/Debug/compoise.exe').Path
    $config=Get-Content -LiteralPath 'windows/flutter/ephemeral/generated_config.cmake' -Raw
    $project=Get-Content -LiteralPath 'build/windows/x64/runner/compoise.vcxproj' -Raw
    $define=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('WP15_D3_DEVICE=true'))
    if (-not $config.Contains($define) -or -not $config.Contains('FLUTTER_TARGET=test/wp15_d3_device_test.dart') -or -not $project.Contains('WP15_D3_DEVICE')) { throw 'Refusing a binary without both D3 build gates and exact target.' }
    $identity=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
    if ($identity.CompanyName -ne 'Compoise' -or $identity.ProductName -ne 'Compoise') { throw 'Unexpected executable identity.' }
    $result.kernelSha256=(Get-FileHash -LiteralPath 'build/windows/x64/runner/Debug/data/flutter_assets/kernel_blob.bin' -Algorithm SHA256).Hash.ToLowerInvariant()
    $result.exeSha256=(Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant()
    New-Item -ItemType Directory -Path $dataRoot | Out-Null
    $env:WP15_D3_RUN='1'; $env:WP15_D3_ROOT=$dataRoot; $env:WP15_D3_NAMESPACE=$namespace
    $stdout=Join-Path $logs 'native-stdout.log'; $stderr=Join-Path $logs 'native-stderr.log'
    $native=Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $null=$native.Handle # Retain the native process handle before it exits.
    $result.pid=$native.Id
    $startTime=$native.StartTime
    $deadline=[DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $url=$null
    while (-not $url) {
        if ($native.HasExited) { $result.nativeExitCode=$native.ExitCode; throw 'Native app exited before VM service startup.' }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'VM service startup timed out.' }
        $out=Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
        if ($out -match '(http://127\.0\.0\.1:\d+/[^\s]*)') { $url=$Matches[1] }
        Start-Sleep -Milliseconds 250
    }
    $env:VM_SERVICE_URL=$url; $env:WP15_D3_EXPECTED_PID=[string]$native.Id; $env:WP15_D3_EXPECTED_COMMIT=$revision
    $dart=Join-Path (Split-Path $Flutter) 'dart.bat'
    $driverLog=Join-Path $logs 'driver.log'
    $command='""{0}" test/wp15_d3_device_driver.dart > "{1}" 2>&1"' -f $dart,$driverLog
    $start=[Diagnostics.ProcessStartInfo]::new('cmd.exe', "/d /s /c $command")
    $start.WorkingDirectory=$workspace; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $driver=[Diagnostics.Process]::Start($start)
    while (-not $driver.WaitForExit(500)) {
        if ([DateTime]::UtcNow -gt $deadline) { throw 'Windows page matrix timed out.' }
        if ($native.HasExited) { throw 'Native app disappeared during the page matrix.' }
    }
    $exitCode=$driver.ExitCode; $result.driverExitCode=$exitCode
    Get-Content -LiteralPath $driverLog -Tail 12
    if ($exitCode -ne 0) { throw 'Windows page matrix failed.' }
    if (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'driver-result.json'))) { throw 'Missing native process/identity evidence.' }
    $evidence=Join-Path $logs 'evidence'
    New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $dataRoot 'driver-result.json') -Destination $evidence -Force
    $capture=Join-Path $dataRoot 'planner-narrow-3x.png'
    if (-not (Test-Path -LiteralPath $capture)) { throw 'No rendered narrow production-page capture.' }
    Copy-Item -LiteralPath $capture -Destination $evidence -Force
} catch {
    Write-Error $_ -ErrorAction Continue
    $result.error=$_.ToString()
    if ($exitCode -eq 0) { $exitCode=1 }
} finally {
    if ($driver -and -not $driver.HasExited) { & taskkill /PID $driver.Id /T /F 2>&1 | Out-Null; $exitCode=1; $result.timeoutCleanup=$true }
    if ($native) {
        if (-not $native.HasExited) {
            $current=Get-Process -Id $native.Id -ErrorAction SilentlyContinue
            if ($current -and $current.Path -eq $exe -and $current.StartTime -eq $startTime) {
                [D3WindowClose]::Close([uint32]$native.Id, "wp15-d3-$namespace") | Out-Null
                if (-not $native.WaitForExit(15000)) { $native.Kill(); $native.WaitForExit(); $exitCode=1; $result.timeoutCleanup=$true }
            } else { $exitCode=1; $result.cleanupIdentityMismatch=$true }
        }
        if ($native.HasExited) { $result.nativeExitCode=$native.ExitCode; if ($native.ExitCode -ne 0) { $exitCode=1 } }
    }
    if ($native -and $native.HasExited) {
        $result.nativeResidual=[bool](Get-Process -Id $native.Id -ErrorAction SilentlyContinue)
        if ($result.nativeResidual) { $exitCode=1 }
    }
    # Preserve success and failure evidence before removing only our temp tree.
    $evidence=Join-Path $logs "evidence/$namespace"
    New-Item -ItemType Directory -Path $evidence -Force | Out-Null
    foreach ($leaf in @('driver-result.json','planner-narrow-3x.png')) {
        $source=Join-Path $dataRoot $leaf
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $evidence -Force }
    }
    $result.evidence=$evidence
    $result.restoredZone=(Get-TimeZone).Id
    if ($result.restoredZone -ne $beforeZone) { $exitCode=1; $result.zoneChangedExternally=$true }
    $checked=[IO.Path]::GetFullPath($dataRoot)
    if ([IO.Path]::GetDirectoryName($checked) -ne $temp -or [IO.Path]::GetFileName($checked) -ne "wp15-d3-device-$namespace") { throw 'Refusing cleanup outside exact task OS-temp root.' }
    if (Test-Path -LiteralPath $checked) { Remove-Item -LiteralPath $checked -Recurse -Force }
    $result.tempResidual=Test-Path -LiteralPath $checked
    foreach ($name in $prior.Keys) { [Environment]::SetEnvironmentVariable($name,$prior[$name],'Process') }
    $result.exitCode=$exitCode
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $logs 'windows-result.json') -Encoding utf8
    $runLock.Dispose()
    Write-Output "WP15_D3_WINDOWS_EXIT=$exitCode"
}
exit $exitCode
