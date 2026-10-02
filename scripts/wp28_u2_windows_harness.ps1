# Synthetic native acceptance. Run only binaries built with BOTH isolation gates:
# $env:WP28_U2_HARNESS_BUILD='1'
# flutter build windows --debug/--release --no-pub --dart-define=WP28_U2_HARNESS=true
# ReproU1 additionally uses -t test/wp28_u1_windows_probe.dart.
[CmdletBinding()]
param(
    [ValidateSet('Core', 'ReproU1')][string]$Mode = 'Core',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [string[]]$Scenarios = @('mirror', 'slots', 'empty', 'current', 'corrupt', 'pointer', 'envelope', 'retry', 'credentials-only', 'unconfirmed', 'race', 'concurrent')
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$exe = (Resolve-Path -LiteralPath (Join-Path $workspace "build/windows/x64/runner/$Configuration/compoise.exe")).Path
$config = Get-Content -LiteralPath (Join-Path $workspace 'windows/flutter/ephemeral/generated_config.cmake') -Raw
$nativeProject = Get-Content -LiteralPath (Join-Path $workspace 'build/windows/x64/runner/compoise.vcxproj') -Raw
$define = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('WP28_U2_HARNESS=true'))
if (!$config.Contains($define) -or !$nativeProject.Contains('WP28_U2_HARNESS')) {
    throw 'Refusing a binary without both Dart and native isolation build gates.'
}
$expectedTarget = if ($Mode -eq 'ReproU1') {'test/wp28_u1_windows_probe.dart'} else {'lib/main.dart'}
if (!$config.Contains("FLUTTER_TARGET=$expectedTarget")) {throw 'Unexpected compiled entry point.'}
$metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
if ($metadata.CompanyName -ne 'Compoise' -or $metadata.ProductName -ne 'Compoise') {throw 'Exe identity changed.'}
$script:launches = [Collections.Generic.List[object]]::new()
$script:results = [Collections.Generic.List[object]]::new()
$script:roots = [Collections.Generic.List[string]]::new()
$runId = [guid]::NewGuid().ToString()
$runRoot = Join-Path ([IO.Path]::GetTempPath()) "wp28-u2-run-$runId"
New-Item -ItemType Directory -Path $runRoot | Out-Null

function Assert-True([bool]$Condition, [string]$Message) {
    if (!$Condition) {throw $Message}
}
function New-Fixture([string]$Scenario, [bool]$U1 = $false) {
    $namespace = [guid]::NewGuid().ToString()
    $prefix = if ($U1) {'wp28-u1-device-'} else {'wp28-u2-device-'}
    $root = Join-Path ([IO.Path]::GetTempPath()) ($prefix + $namespace)
    New-Item -ItemType Directory -Path $root | Out-Null
    [IO.File]::WriteAllText((Join-Path $root 'fixture.json'), (@{scenario=$Scenario} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    $script:roots.Add($root)
    return @{Root=$root; Namespace=$namespace; Command=0}
}
function Launch-App($Fixture, [string]$Arguments = '') {
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $exe
    $info.WorkingDirectory = Split-Path -Parent $exe
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.EnvironmentVariables['WP28_U2_NAMESPACE'] = $Fixture.Namespace
    $info.EnvironmentVariables['WP28_U2_ROOT'] = $Fixture.Root
    $info.EnvironmentVariables['WP28_U1_PROBE_ROOT'] = $Fixture.Root
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    Assert-True ($process.Start()) 'Native app did not start.'
    $launch = @{Process=$process; Id=$process.Id; Exe=$exe; Root=$Fixture.Root; Namespace=$Fixture.Namespace;
        Started=$process.StartTime.ToUniversalTime().ToString('o'); Arguments=$Arguments;
        Stdout=$process.StandardOutput.ReadToEndAsync(); Stderr=$process.StandardError.ReadToEndAsync();
        TimedOut=$false; ExitCode=$null; Cleanup='not-needed'}
    $script:launches.Add($launch)
    return $launch
}
function Read-Report($Launch, [string]$Name, [int]$TimeoutMs = 30000) {
    $path = Join-Path $Launch.Root "$Name-$($Launch.Id).json"
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while ($watch.ElapsedMilliseconds -lt $TimeoutMs) {
        if (Test-Path -LiteralPath $path) {
            try {
                $candidate = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
                if ($null -ne $candidate -and $candidate.pid -eq $Launch.Id) {return $candidate}
            } catch {}
        }
        if ($Launch.Process.HasExited) {throw "Native process exited before $Name report (PID $($Launch.Id))."}
        Start-Sleep -Milliseconds 100
    }
    throw "Timed out awaiting $Name report (PID $($Launch.Id))."
}
function Send-Command($Fixture, $Launch, [string]$Action, [bool]$Exiting = $false) {
    $Fixture.Command++
    # Immutable per-process commands: Windows readers cannot block replacing a
    # shared command file, and a reopen cannot consume an old process's exit.
    $path = Join-Path $Fixture.Root "request-$($Launch.Id)-$($Fixture.Command).json"
    $stage = Join-Path $Fixture.Root "request-$($Launch.Id)-$($Fixture.Command).stage"
    [IO.File]::WriteAllText($stage, (@{id=$Fixture.Command; action=$Action} | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $stage -Destination $path
    if ($Exiting) {return (Read-Report $Launch 'exit-requested')}
    $report = Read-Report $Launch "command-$($Fixture.Command)"
    Assert-True ($report.passed -eq $true) "Native $Action command failed."
    Assert-True ($report.sourceUnchanged -eq $true) 'Historical preferences changed.'
    Assert-True (Test-Path -LiteralPath (Join-Path $Fixture.Root "ui-$($Fixture.Command)-$($Launch.Id).png")) 'Actual rendered UI capture missing.'
    return $report
}
function Wait-Exit($Launch, [int]$TimeoutMs = 45000) {
    $exited = $Launch.Process.WaitForExit($TimeoutMs)
    $Launch.TimedOut = !$exited
    if ($exited) {
        $Launch.ExitCode = $Launch.Process.ExitCode
        $Launch.Stdout.Result | Set-Content -LiteralPath (Join-Path $Launch.Root "stdout-$($Launch.Id).log")
        $Launch.Stderr.Result | Set-Content -LiteralPath (Join-Path $Launch.Root "stderr-$($Launch.Id).log")
    }
    Assert-True $exited "Native exit timeout (PID $($Launch.Id)); startup report is not exit evidence."
    Assert-True ($Launch.ExitCode -eq 0) "Native exit code $($Launch.ExitCode) (PID $($Launch.Id))."
}
function Library-Json($Report) {
    @{tasks=$Report.tasks; boards=$Report.boards; schedule=$Report.schedule; config=$Report.config;
      settings=$Report.settings; activeBoard=$Report.activeBoard; onboarding=$Report.onboarding} | ConvertTo-Json -Depth 100 -Compress
}
function Source-Hashes($Fixture) {
    $source = Join-Path $Fixture.Root 'com.matrixflow/MatrixFlow AI'
    $hashes = @{}
    if (Test-Path -LiteralPath $source) {
        foreach ($file in (Get-ChildItem -LiteralPath $source -File)) { $hashes[$file.Name] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
    }
    return $hashes
}
function File-Metrics([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {return @{exists=$false}}
    return @{exists=$true; bytes=(Get-Item -LiteralPath $Path).Length; sha256=(Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash}
}
function Run-Core([string]$Scenario) {
    $fixture = New-Fixture $Scenario
    $first = Launch-App $fixture
    if ($Scenario -eq 'concurrent') {
        Read-Report $first 'copy-wait' | Out-Null
        $duringCopy = Launch-App $fixture
        Wait-Exit $duringCopy 30000
        Assert-True (!(Test-Path -LiteralPath (Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json'))) 'Second launch raced the pending copy.'
    }
    $prepared = Read-Report $first 'prepared-1'
    $closedBeforeConfirmation = $null
    if ($Scenario -eq 'unconfirmed') {
        $beforeClose = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json')).Hash
        Send-Command $fixture $first 'close' $true | Out-Null
        Wait-Exit $first
        $closedBeforeConfirmation = $first.Id
        Assert-True ($beforeClose -eq (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json')).Hash) 'Close before Store changed the target.'
        $fixture.Command = 0
        $first = Launch-App $fixture
        $prepared = Read-Report $first 'prepared-1'
        Assert-True ($prepared.showNotice -eq $true) 'Unconfirmed close lost the notice.'
    }
    if ($Scenario -eq 'retry') {
        Assert-True ($prepared.status -eq 'failed') 'Injected first copy failure missing.'
        Send-Command $fixture $first 'retry' | Out-Null
        $prepared = Read-Report $first 'prepared-2'
    }
    $sourceBefore = Source-Hashes $fixture
    $targetPath = Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json'
    $targetOnUpgrade = File-Metrics $targetPath
    $sourcePreferences = File-Metrics (Join-Path $fixture.Root 'com.matrixflow/MatrixFlow AI/shared_preferences.json')
    $sourceCredential = File-Metrics (Join-Path $fixture.Root 'com.matrixflow/MatrixFlow AI/flutter_secure_storage.dat')
    if ($Scenario -eq 'envelope') {
        Assert-True ($prepared.status -eq 'sourceUnreadable') 'Bad envelope did not block startup.'
        Send-Command $fixture $first 'close' $true | Out-Null
        Wait-Exit $first
        $script:results.Add(@{scenario=$Scenario; passed=$true; firstPid=$first.Id; firstExit=$first.ExitCode; sourceHashes=$sourceBefore})
        return
    }
    if ($prepared.showNotice -or $prepared.recovery) {Send-Command $fixture $first 'continue' | Out-Null}
    $ready = Read-Report $first 'ready'
    if ($Scenario -in @('corrupt', 'pointer')) {
        Assert-True ($ready.recovery -eq $true) 'Damaged library did not enter recovery.'
        Assert-True ($ready.noticeRead -eq $false) 'Recovery lock acknowledged the notice.'
        Send-Command $fixture $first 'discard' | Out-Null
        Send-Command $fixture $first 'exit' $true | Out-Null
        Wait-Exit $first
        $fixture.Command = 0
        $second = Launch-App $fixture
        $reopened = Read-Report $second 'prepared-1'
        Assert-True ($reopened.status -eq 'currentProfile' -and $reopened.showNotice -eq $true) 'Recovery did not retain the unacknowledged notice.'
        Send-Command $fixture $second 'continue' | Out-Null
        $resolved = Send-Command $fixture $second 'observe'
        Assert-True ($resolved.recovery -eq $false -and $resolved.noticeRead -eq $true) 'Resolved recovery did not acknowledge after valid Store.'
        Send-Command $fixture $second 'exit' $true | Out-Null
        Wait-Exit $second
        $sourceAfter = Source-Hashes $fixture
        foreach ($name in $sourceBefore.Keys) {Assert-True ($sourceBefore[$name] -eq $sourceAfter[$name]) 'Damaged historical bytes changed.'}
        $script:results.Add(@{scenario=$Scenario; passed=$true; firstPid=$first.Id; firstExit=$first.ExitCode; reopenPid=$second.Id; reopenExit=$second.ExitCode; sourceHashes=$sourceBefore})
        return
    }
    $initial = Send-Command $fixture $first 'observe'
    Assert-True ($initial.recovery -eq $false) 'Unexpected recovery.'
    if ($Scenario -eq 'empty') {Assert-True ($initial.tasks.Count -eq 0 -and $initial.schedule.Count -eq 0) 'Legal empty target was replaced.'}
    elseif ($Scenario -in @('current','race')) {Assert-True ($initial.tasks[0].id -eq 'synthetic-current') 'Existing target lost priority.'}
    elseif ($Scenario -ne 'credentials-only') {
        Assert-True ($initial.tasks.Count -eq 1 -and $initial.tasks[0].id -eq 'synthetic-task') 'Task migration failed.'
        Assert-True ($initial.tasks[0].subtasks[0].id -eq 'synthetic-subtask' -and $initial.tasks[0].plannedDate -eq 1790812800000) 'Task fields changed.'
        Assert-True ($initial.schedule.Count -eq 1 -and $initial.schedule[0].timeZoneId -eq 'Asia/Shanghai') 'Schedule migration failed.'
    }
    $beforeSecond = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json')).Hash
    $secondary = Launch-App $fixture
    Wait-Exit $secondary 30000
    $payload = [Uri]::EscapeDataString('{"boardId":"synthetic-board","taskId":"synthetic-task"}')
    $notification = Launch-App $fixture ('--matrixflow-notification-payload=' + $payload)
    Wait-Exit $notification 30000
    $activated = Send-Command $fixture $first 'observe'
    Assert-True ($activated.activations -ge 2 -and $activated.notificationActivations -eq 1) 'Second-launch activation wiring failed.'
    $afterSecond = (Get-FileHash -LiteralPath (Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json')).Hash
    Assert-True ($beforeSecond -eq $afterSecond) 'Concurrent launch changed the target file.'
    $saved = Send-Command $fixture $first 'exit' $true
    Assert-True ($saved.saveComplete -eq $true) 'Initial exit save incomplete.'
    Wait-Exit $first
    $targetAfterInitialSave = File-Metrics $targetPath
    $fixture.Command = 0
    $second = Launch-App $fixture
    $reopened = Read-Report $second 'prepared-1'
    Assert-True ($reopened.status -eq 'currentProfile' -and $reopened.showNotice -eq $false) 'Reopen repeated credential gate.'
    Read-Report $second 'ready' | Out-Null
    $again = Send-Command $fixture $second 'observe'
    Assert-True ((Library-Json $initial) -eq (Library-Json $again)) 'Reopen library differs field by field.'
    $edited = $again
    if ($Scenario -in @('mirror','slots','retry')) {$edited = Send-Command $fixture $second 'modify'}
    if ($Scenario -eq 'mirror') {
        $configured = Send-Command $fixture $second 'configure'
        Assert-True ($configured.needsSetup -eq $false) 'Verified target secure write did not clear setup.'
    }
    $saved = Send-Command $fixture $second 'exit' $true
    Assert-True ($saved.saveComplete -eq $true) 'Edited exit save incomplete.'
    Wait-Exit $second
    $targetAfterEdit = File-Metrics $targetPath
    $fixture.Command = 0
    $third = Launch-App $fixture
    Read-Report $third 'prepared-1' | Out-Null
    Read-Report $third 'ready' | Out-Null
    $final = Send-Command $fixture $third 'observe'
    Assert-True ((Library-Json $edited) -eq (Library-Json $final)) 'Final reopen differs field by field.'
    if ($Scenario -eq 'mirror') {Assert-True ($final.needsSetup -eq $false) 'Secure configuration state did not survive reopening.'}
    Send-Command $fixture $third 'exit' $true | Out-Null
    Wait-Exit $third
    $sourceAfter = Source-Hashes $fixture
    foreach ($name in $sourceBefore.Keys) {Assert-True ($sourceBefore[$name] -eq $sourceAfter[$name]) 'Historical source bytes changed.'}
    $script:results.Add(@{scenario=$Scenario; passed=$true; root=$fixture.Root; firstPid=$first.Id; firstExit=$first.ExitCode;
        reopenPid=$second.Id; reopenExit=$second.ExitCode; finalPid=$third.Id; finalExit=$third.ExitCode; closedBeforeConfirmationPid=$closedBeforeConfirmation;
        secondaryExit=$secondary.ExitCode; notificationExit=$notification.ExitCode; sourceHashes=$sourceAfter;
        sourcePreferences=$sourcePreferences; sourceCredential=$sourceCredential; targetOnUpgrade=$targetOnUpgrade;
        targetAfterInitialSave=$targetAfterInitialSave; targetAfterEdit=$targetAfterEdit; targetFinal=(File-Metrics $targetPath);
        targetCredential=(File-Metrics (Join-Path $fixture.Root 'Compoise/Compoise/flutter_secure_storage.dat'));
        firstLibrary=$initial; finalLibrary=$final; saveComplete=$saved.saveComplete})
}
$failed = $false
try {
    if ($Mode -eq 'ReproU1') {
        $fixture = New-Fixture 'u1-reproduction' $true
        $launch = Launch-App $fixture
        Wait-Exit $launch
        $firstReport = Get-Content -LiteralPath (Join-Path $fixture.Root 'probe-migrated.json') -Raw | ConvertFrom-Json
        Assert-True ($firstReport.passed -eq $true) 'U1 first migration report failed.'
        $second = Launch-App $fixture
        Wait-Exit $second
        $secondReport = Get-Content -LiteralPath (Join-Path $fixture.Root 'probe-currentProfile.json') -Raw | ConvertFrom-Json
        Assert-True ($secondReport.passed -eq $true) 'U1 reopen report failed.'
        $script:results.Add(@{scenario='u1-reproduction'; root=$fixture.Root; pid=$launch.Id; passed=$true; exitCode=$launch.ExitCode;
            reopenPid=$second.Id; reopenExitCode=$second.ExitCode; firstReport=$firstReport; reopenReport=$secondReport})
    } else {
        foreach ($scenario in $Scenarios) { Run-Core $scenario }
    }
} catch {
    $failed = $true
    $script:results.Add(@{passed=$false; failure=$_.Exception.Message; stack=$_.ScriptStackTrace})
} finally {
    foreach ($launch in $script:launches) {
        if (!$launch.Process.HasExited) {
            # Verify the exact owned process object, image and creation time;
            # never enumerate/kill by PID or executable name.
            if ($launch.Process.Id -eq $launch.Id -and $launch.Process.Path -eq $launch.Exe -and
                $launch.Process.StartTime.ToUniversalTime().ToString('o') -eq $launch.Started) {
                try {
                    $launch.Process.Kill()
                    $launch.Cleanup = if ($launch.Process.WaitForExit(5000)) {'owned-process-killed-after-failure'} else {'owned-process-still-alive'}
                } catch {$launch.Cleanup = 'cleanup-failed: ' + $_.Exception.Message}
            } else {$launch.Cleanup = 'identity-unverified-preserved'}
            $failed = $true
        }
    }
    $processes = @($script:launches | ForEach-Object {
        @{pid=$_.Id; exe=$_.Exe; startedUtc=$_.Started; root=$_.Root; namespace=$_.Namespace;
          arguments=$_.Arguments; timedOut=$_.TimedOut; exitCode=$_.ExitCode;
          alive=(!$_.Process.HasExited); cleanup=$_.Cleanup}
    })
    $report = @{mode=$Mode; configuration=$Configuration; passed=(!$failed); exe=$exe;
        executableSHA256=(Get-FileHash -LiteralPath $exe).Hash; company=$metadata.CompanyName; product=$metadata.ProductName;
        roots=$script:roots.ToArray(); processes=$processes; results=$script:results.ToArray()}
    $report | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $runRoot 'harness.json') -Encoding utf8
    Write-Output "Report: $runRoot/harness.json"
    $processes | ConvertTo-Json -Depth 5
    $script:results | ForEach-Object {if ($_.ContainsKey('failure')) {Write-Output $_.failure}}
    Write-Output "Passed: $(!$failed); scenarios=$($script:results.Count); processes=$($processes.Count)"
    # Evidence directories are deliberately retained; no recursive cleanup of
    # old fixtures, unverified PIDs, user profiles or other sessions occurs.
}
if ($failed) {exit 1}
exit 0
