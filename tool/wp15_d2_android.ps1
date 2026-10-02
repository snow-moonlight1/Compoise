param(
    [switch]$Run,
    [switch]$SoftwareRendering,
    [string]$Device,
    [string]$Flutter = 'D:/Dev_SDKs/Flutter_3.32.8/bin/flutter.bat',
    [string]$Adb = 'D:/Dev_SDKs/Android_studio_SDK/platform-tools/adb.exe',
    [string]$Aapt,
    [int]$TimeoutSeconds = 900
)
$ErrorActionPreference = 'Stop'
# An absent/disabled device leg is BLOCKED (2), never a successful acceptance.
if (-not $Run -or -not $Device) {
    Write-Error 'WP15-D2 device acceptance requires -Run and an explicit -Device.' -ErrorAction Continue
    exit 2
}
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Set-Location -LiteralPath $root
function Invoke-D2Adb([string[]]$Arguments) {
    $priorErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $Adb -s $Device @Arguments 2>&1
        $adbCode = $LASTEXITCODE
    } finally { $ErrorActionPreference = $priorErrorAction }
    if ($adbCode -ne 0) { throw "ADB failed ($adbCode): $Arguments $output" }
    return ($output -join "`n").Trim()
}
$exitCode = 2
$process = $null
$originalZone = $null
$originalAutoZone = $null
$package = 'com.matrixflow.app.wp15d2'
$logRoot = Join-Path $root 'build/wp15-d2'
New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
$log = Join-Path $logRoot 'android-drive.log'
$metadata = Join-Path $logRoot 'android-result.json'
try {
    $runLock = [IO.File]::Open((Join-Path $logRoot 'android-run.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
} catch {
    Write-Error 'Another WP15-D2 Android run owns this worktree; refusing concurrent device mutations.' -ErrorAction Continue
    exit 2
}
$revision = (& git rev-parse HEAD).Trim()
$dirty = [bool](& git status --porcelain --untracked-files=normal)
$result = @{ revision=$revision; dirty=$dirty; device=$Device; applicationId=$package }
$result.rendering = if ($SoftwareRendering) { 'software' } else { 'default' }
$renderingFlag = if ($SoftwareRendering) { ' --enable-software-rendering --no-enable-impeller' } else { '' }
try {
    $version = (& $Flutter --version --machine | Out-String) | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0 -or $version.frameworkVersion -ne '3.32.8') {
        throw 'Flutter 3.32.8 is required by toolchain.json.'
    }
    if ((Invoke-D2Adb -Arguments @('get-state')) -ne 'device') { throw 'Device is not ready.' }
    $result.api = Invoke-D2Adb -Arguments @('shell','getprop','ro.build.version.sdk')
    $result.abi = Invoke-D2Adb -Arguments @('shell','getprop','ro.product.cpu.abi')
    $result.emulator = (Invoke-D2Adb -Arguments @('shell','getprop','ro.kernel.qemu')) -eq '1'
    if ([int]$result.api -lt 26) {
        throw 'This runner needs cmd alarm set-timezone (API 26+); do not count older devices as passed.'
    }
    $originalZone = Invoke-D2Adb -Arguments @('shell','getprop','persist.sys.timezone')
    if (-not $originalZone -or $originalZone -notmatch '^[A-Za-z0-9_+./-]+$') {
        throw 'Cannot safely record and restore the device timezone.'
    }
    $originalAutoZone = Invoke-D2Adb -Arguments @('shell','settings','get','global','auto_time_zone')
    $result.originalZone = $originalZone
    $result.originalAutoZone = $originalAutoZone
    Invoke-D2Adb -Arguments @('shell','settings','put','global','auto_time_zone','0') | Out-Null
    Invoke-D2Adb -Arguments @('shell','cmd','alarm','set-timezone','Asia/Shanghai') | Out-Null
    if ((Invoke-D2Adb -Arguments @('shell','getprop','persist.sys.timezone')) -ne 'Asia/Shanghai') {
        throw 'Initial system timezone change failed.'
    }
    # Verify the compiled APK identity before allowing Flutter to install it.
    $buildLog = Join-Path $logRoot 'android-isolated-build.log'
    $buildCommand = '""{0}" build apk --debug --no-pub -t test/wp15_d2_device_test.dart --dart-define=WP15_D2_DEVICE=true --dart-define=WP15_D2_EXPECTED_ZONE=Asia/Shanghai --dart-define=WP15_D2_CHANGED_ZONE=Asia/Tokyo --dart-define=WP15_D2_COMMIT={1} > "{2}" 2>&1"' -f $Flutter,$revision,$buildLog
    $buildStart = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', "/d /s /c $buildCommand")
    $buildStart.WorkingDirectory = $root
    $buildStart.UseShellExecute = $false
    $buildStart.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($buildStart)
    $buildDeadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while (-not $process.WaitForExit(500)) {
        if ([DateTime]::UtcNow -ge $buildDeadline) { throw 'Isolated APK build timed out.' }
    }
    $result.buildExitCode = $process.ExitCode
    $process = $null
    if ($result.buildExitCode -ne 0) { $exitCode = $result.buildExitCode; throw 'Isolated APK build failed; see android-isolated-build.log.' }
    $apk = Join-Path $root 'build/app/outputs/flutter-apk/app-debug.apk'
    if (-not $Aapt) {
        $sdkLine = Get-Content (Join-Path $root 'android/local.properties') | Where-Object { $_ -like 'sdk.dir=*' } | Select-Object -First 1
        $sdkRoot = $sdkLine.Substring(8).Replace('\\','\').Replace('\:',':')
        $Aapt = (Get-ChildItem (Join-Path $sdkRoot 'build-tools') -Recurse -Filter aapt.exe | Sort-Object FullName -Descending | Select-Object -First 1).FullName
    }
    $badging = & $Aapt dump badging $apk
    if ($LASTEXITCODE -ne 0 -or -not ($badging -match "^package: name='com.matrixflow.app.wp15d2'")) {
        throw 'Refusing installation: APK does not have the isolated WP15-D2 identity.'
    }
    $result.apkIdentityVerified = $true
    # Only the dedicated applicationId is stopped/cleared. Normal packages are
    # never installed over, cleared, read, launched, or restored by this runner.
    & $Adb -s $Device shell am force-stop $package 2>&1 | Out-Null
    $command = '""{0}" drive --no-pub --use-application-binary="{4}" -d "{1}" --driver=test/wp15_d2_device_driver.dart --target=test/wp15_d2_device_test.dart --dart-define=WP15_D2_DEVICE=true --dart-define=WP15_D2_EXPECTED_ZONE=Asia/Shanghai --dart-define=WP15_D2_CHANGED_ZONE=Asia/Tokyo --dart-define=WP15_D2_COMMIT={2}{5} > "{3}" 2>&1"' -f $Flutter,$Device,$revision,$log,$apk,$renderingFlag
    $start = [System.Diagnostics.ProcessStartInfo]::new('cmd.exe', "/d /s /c $command")
    $start.WorkingDirectory = $root
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    [IO.File]::WriteAllText($log, '')
    $process = [System.Diagnostics.Process]::Start($start)
    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $changed = $false
    $shown = 0
    while (-not $process.HasExited) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'Flutter device run timed out.' }
        if (Test-Path -LiteralPath $log) {
            $lines = @(Get-Content -LiteralPath $log)
            if ($lines.Count -gt $shown) {
                $lines[$shown..($lines.Count-1)] | Write-Output
                $shown = $lines.Count
            }
            if (-not $changed -and ($lines -match 'WP15_D2_ZONE_READY')) {
                Invoke-D2Adb -Arguments @('shell','cmd','alarm','set-timezone','Asia/Tokyo') | Out-Null
                if ((Invoke-D2Adb -Arguments @('shell','getprop','persist.sys.timezone')) -ne 'Asia/Tokyo') {
                    throw 'Running system timezone change failed.'
                }
                $changed = $true
            }
        }
        Start-Sleep -Milliseconds 500
        $process.Refresh()
    }
    $process.WaitForExit()
    $exitCode = $process.ExitCode
    $result.flutterExitCode = $exitCode
    $lines = @(Get-Content -LiteralPath $log)
    if ($lines.Count -gt $shown) { $lines[$shown..($lines.Count-1)] | Write-Output }
    if ($exitCode -eq 0 -and (-not $changed -or -not ($lines -match 'WP15_D2_PASS android_live_zone_change') -or -not ($lines -match 'WP15_D2_RESULT'))) {
        throw 'Flutter exited 0 without all required device evidence.'
    }
    $result.liveZoneChanged = $changed
} catch {
    Write-Error $_ -ErrorAction Continue
    if ($exitCode -eq 0) { $exitCode = 1 }
    $result.error = $_.ToString()
} finally {
    if ($null -ne $process -and -not $process.HasExited) {
        # Kill only the process tree created by this run, never by process name.
        & taskkill /PID $process.Id /T /F 2>&1 | Out-Null
        $process.WaitForExit(10000) | Out-Null
    }
    try {
        if ($originalZone) {
            Invoke-D2Adb -Arguments @('shell','cmd','alarm','set-timezone',$originalZone) | Out-Null
            $result.restoredZone = Invoke-D2Adb -Arguments @('shell','getprop','persist.sys.timezone')
            if ($result.restoredZone -ne $originalZone) { throw 'System timezone restore failed.' }
        }
        if ($null -ne $originalAutoZone) {
            if ($originalAutoZone -eq 'null') {
                Invoke-D2Adb -Arguments @('shell','settings','delete','global','auto_time_zone') | Out-Null
            } else {
                Invoke-D2Adb -Arguments @('shell','settings','put','global','auto_time_zone',$originalAutoZone) | Out-Null
            }
            $result.restoredAutoZone = Invoke-D2Adb -Arguments @('shell','settings','get','global','auto_time_zone')
            if ($result.restoredAutoZone -ne $originalAutoZone) { throw 'Automatic timezone restore failed.' }
        }
        & $Adb -s $Device shell am force-stop $package 2>&1 | Out-Null
        # Remove this run's synthetic preferences even after a failing test.
        # flutter drive may already have uninstalled its integration APK.
        $installedPackages = Invoke-D2Adb -Arguments @('shell','pm','list','packages','--user','0',$package)
        if (($installedPackages -split '\r?\n') -contains "package:$package") {
            $cleared = Invoke-D2Adb -Arguments @('shell','pm','clear',$package)
            if ($cleared -ne 'Success') { throw 'Isolated package data cleanup failed.' }
            $result.syntheticDataCleared = $true
        } else { $result.syntheticDataCleared = 'package-not-installed' }
    } catch {
        Write-Error $_ -ErrorAction Continue
        $result.restoreError = $_.ToString()
        $exitCode = 1
    }
    $result.exitCode = $exitCode
    $result | ConvertTo-Json | Set-Content -LiteralPath $metadata -Encoding utf8
    $runLock.Dispose()
    Write-Output "WP15_D2_ANDROID_EXIT=$exitCode metadata=$metadata"
}
exit $exitCode
