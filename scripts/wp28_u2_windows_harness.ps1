# Synthetic native acceptance. Run only binaries built with BOTH isolation gates:
# $env:WP28_U2_HARNESS_BUILD='1'
# flutter build windows --debug/--release --no-pub --dart-define=WP28_U2_HARNESS=true
# ReproU1 additionally uses -t test/wp28_u1_windows_probe.dart.
[CmdletBinding()]
param(
    [switch]$Run,
    [ValidateSet('Core', 'ReproU1')][string]$Mode = 'Core',
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [string[]]$Scenarios = @('mirror', 'slots', 'legacy-mirror', 'legacy-slots', 'empty', 'current', 'current-corrupt', 'corrupt', 'pointer', 'schedule-corrupt', 'slot-schedule-corrupt', 'envelope', 'retry', 'credentials-only', 'unconfirmed', 'race', 'concurrent'),
    [string]$EvidenceDirectory = ''
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$workspace = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (!$Run) { Write-Output 'Blocked: pass -Run for synthetic private-desktop acceptance.'; exit 2 }
if ($Mode -ne 'Core') { throw 'R2 requires the normal lib/main.dart diagnostic entry; the historical U1 probe is not desktop isolated.' }
if (@($Scenarios | Where-Object { $_ -notin @('mirror', 'slots', 'legacy-mirror', 'legacy-slots', 'empty', 'current', 'current-corrupt', 'corrupt', 'pointer', 'schedule-corrupt', 'slot-schedule-corrupt', 'envelope', 'retry', 'credentials-only', 'unconfirmed', 'race', 'concurrent') }).Count) { throw 'Unknown scenario.' }
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
if (!$EvidenceDirectory) { $EvidenceDirectory = Join-Path $workspace "build/wp28-r2/$Configuration" }
$runRoot = Join-Path ([IO.Path]::GetFullPath($EvidenceDirectory)) $runId
New-Item -ItemType Directory -Path $runRoot | Out-Null
$revision = (& git -C $workspace rev-parse HEAD).Trim()
$validator = Join-Path $workspace 'scripts/release_candidate.py'
$trace = (& python $validator source --directory $runRoot --platform Windows --tag v1.0.0+1 --commit $revision) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0) { throw 'Cannot trace diagnostic source.' }
$hostZone = (Get-TimeZone).Id
$buildProofPath = Join-Path $workspace "build/wp28-r2/diagnostic-$Configuration.json"
$buildProof = Get-Content -LiteralPath $buildProofPath -Raw | ConvertFrom-Json
if ($buildProof.normalCandidate -ne $false -or $buildProof.buildExitCode -ne 0 -or
    $buildProof.commit -ne $revision -or $buildProof.source.diffSha256 -ne $trace.diffSha256 -or
    $buildProof.executableSHA256 -ne (Get-FileHash -LiteralPath $exe).Hash) { throw 'Diagnostic build proof is stale or differs from this source.' }
function Assert-BuildBundle {
    $bundle = Split-Path -Parent $exe
    $files = @(Get-ChildItem -LiteralPath $bundle -File -Recurse)
    if ($files.Count -ne $buildProof.files.Count) { throw 'Diagnostic bundle file set differs from its build proof.' }
    foreach ($expected in $buildProof.files) {
        $path=Join-Path $bundle $expected.path
        if (!(Test-Path -LiteralPath $path -PathType Leaf) -or (Get-Item -LiteralPath $path).Length -ne $expected.bytes -or
            (Get-FileHash -LiteralPath $path).Hash -ne $expected.sha256) { throw 'Diagnostic bundle differs from its build proof.' }
    }
}
Assert-BuildBundle

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
    $info.EnvironmentVariables['WP28_U2_RUN'] = '1'
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
                if ($null -ne $candidate -and $candidate.pid -eq $Launch.Id) {
                    $native = $candidate.native
                    Assert-True ($native.nativeGate -eq $true -and $native.privateDesktop -eq $true -and $native.foregroundOwned -eq $false) 'Native desktop isolation failed.'
                    Assert-True ($native.pid -eq $Launch.Id -and $native.root -eq $Launch.Root -and $native.namespace -eq $Launch.Namespace -and $native.desktop -eq "wp28-u2-$($Launch.Namespace)") 'Native isolation identity differs.'
                    return $candidate
                }
            } catch [ArgumentException] { }
        }
        if ($Launch.Process.HasExited) {throw "Native process exited before $Name report (PID $($Launch.Id))."}
        Start-Sleep -Milliseconds 100
    }
    $Launch.TimedOut = $true
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
function Approve-Store($Launch) {
    [IO.File]::WriteAllText((Join-Path $Launch.Root "store-open-approved-$($Launch.Id)"),'synthetic evidence measured')
}
function Library-Json($Report) {
    @{tasks=$Report.tasks; boards=$Report.boards; schedule=$Report.schedule; config=$Report.config;
      settings=$Report.settings; activeBoard=$Report.activeBoard; onboarding=$Report.onboarding} | ConvertTo-Json -Depth 100 -Compress
}
function Backup-Library-Json($Report) {
    @{tasks=$Report.tasks; boards=$Report.boards; schedule=$Report.schedule; config=$Report.config;
      settings=$Report.settings} | ConvertTo-Json -Depth 100 -Compress
}
function Run-Backup($Origin) {
    $exported = Send-Command $Origin.Fixture $Origin.Launch 'export-backups'
    foreach ($version in @(3, 1, 2)) {
        $fixture = New-Fixture 'backup-v3'
        Copy-Item -LiteralPath (Join-Path $Origin.Fixture.Root "backup-v$version.json") -Destination (Join-Path $fixture.Root "backup-v$version.json")
        $file = Get-Content -LiteralPath (Join-Path $fixture.Root "backup-v$version.json") -Raw | ConvertFrom-Json
        $expected = @{boards=$file.boards; tasks=$file.tasks; schedule=@(); config=$file.aiConfig; settings=$file.settings}
        if ($version -eq 3) { $expected.schedule = $file.scheduleItems }
        $launch = Launch-App $fixture
        Read-Report $launch 'prepared-1' | Out-Null
        Approve-Store $launch
        Read-Report $launch 'ready' | Out-Null
        $imported = Send-Command $fixture $launch "import-v$version"
        if ($version -eq 3) {
            Assert-True ((Backup-Library-Json $exported) -eq (Backup-Library-Json $imported)) 'Native v3 import differs field by field.'
        } else {
            Assert-True ($imported.tasks.Count -eq $exported.tasks.Count -and $imported.schedule.Count -eq 0) 'Legacy backup failed to import tasks without schedules.'
            foreach ($task in $file.tasks) {
                $restored = @($imported.tasks | Where-Object id -eq $task.id)[0]
                Assert-True ($restored.boardId -eq $task.boardId -and $restored.title -eq $task.title) 'Legacy import changed stable identity.'
            }
            $loss = Read-Report $Origin.Launch "downgrade-v$version"
            Assert-True ($loss.ordinaryExportBlocked -eq $true -and $loss.lostScheduleItems -eq $exported.schedule.Count -and $loss.lossNotice.Contains("$($exported.schedule.Count) schedule records")) 'Downgrade loss count or notice missing.'
        }
        Send-Command $fixture $launch 'exit' $true | Out-Null
        Wait-Exit $launch
        $fixture.Command = 0
        $reopen = Launch-App $fixture
        Read-Report $reopen 'prepared-1' | Out-Null
        Approve-Store $reopen
        Read-Report $reopen 'ready' | Out-Null
        $again = Send-Command $fixture $reopen 'observe'
        Assert-True ((Library-Json $imported) -eq (Library-Json $again)) 'Backup restore changed on independent process reopen.'
        Send-Command $fixture $reopen 'exit' $true | Out-Null
        Wait-Exit $reopen
        $script:results.Add(@{scenario="backup-v$version"; passed=$true; root=$fixture.Root; origin=$Origin.Fixture.Root; initial=$imported; reopened=$again; artifact=(File-Metrics (Join-Path $fixture.Root "backup-v$version.json"))})
    }
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
    $seedLaunch = $first
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
        Assert-True (!(Test-Path -LiteralPath (Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json'))) 'Failed copy published a target.'
        $failedSource = Source-Hashes $fixture
        Send-Command $fixture $first 'retry' | Out-Null
        $prepared = Read-Report $first 'prepared-2'
        $retriedSource = Source-Hashes $fixture
        foreach ($name in $failedSource.Keys) { Assert-True ($failedSource[$name] -eq $retriedSource[$name]) 'Retry changed the failed copy source.' }
    }
    $sourceBefore = Source-Hashes $fixture
    $targetPath = Join-Path $fixture.Root 'Compoise/Compoise/shared_preferences.json'
    $targetOnUpgrade = File-Metrics $targetPath
    $sourcePreferences = File-Metrics (Join-Path $fixture.Root 'com.matrixflow/MatrixFlow AI/shared_preferences.json')
    $sourceCredential = File-Metrics (Join-Path $fixture.Root 'com.matrixflow/MatrixFlow AI/flutter_secure_storage.dat')
    Approve-Store $first
    if ($Scenario -in @('envelope','current-corrupt')) {
        $expectedStatus = if ($Scenario -eq 'current-corrupt') { 'currentUnreadable' } else { 'sourceUnreadable' }
        Assert-True ($prepared.status -eq $expectedStatus) 'Bad envelope did not block startup with current priority.'
        Send-Command $fixture $first 'close' $true | Out-Null
        Wait-Exit $first
        if ($Scenario -eq 'current-corrupt') { Assert-True ($targetOnUpgrade.sha256 -eq (File-Metrics $targetPath).sha256) 'Damaged current library was overwritten.' }
        $sourceAfter = Source-Hashes $fixture
        foreach ($name in $sourceBefore.Keys) { Assert-True ($sourceBefore[$name] -eq $sourceAfter[$name]) 'Unreadable/current-priority launch changed historical bytes.' }
        $script:results.Add(@{scenario=$Scenario; passed=$true; firstPid=$first.Id; firstExit=$first.ExitCode; sourceHashes=$sourceBefore})
        return
    }
    if ($prepared.showNotice -or $prepared.recovery) {Send-Command $fixture $first 'continue' | Out-Null}
    $ready = Read-Report $first 'ready'
    if ($Scenario -in @('corrupt', 'pointer','schedule-corrupt','slot-schedule-corrupt')) {
        Assert-True ($ready.recovery -eq $true) 'Damaged library did not enter recovery.'
        Assert-True ($ready.noticeRead -eq $false) 'Recovery lock acknowledged the notice.'
        Assert-True ($targetOnUpgrade.sha256 -eq (File-Metrics $targetPath).sha256) 'Recovery startup changed damaged target bytes.'
        Send-Command $fixture $first 'discard' | Out-Null
        Send-Command $fixture $first 'exit' $true | Out-Null
        Wait-Exit $first
        $fixture.Command = 0
        $second = Launch-App $fixture
        $reopened = Read-Report $second 'prepared-1'
        Assert-True ($reopened.status -eq 'currentProfile' -and $reopened.showNotice -eq $true) 'Recovery did not retain the unacknowledged notice.'
        Approve-Store $second
        Send-Command $fixture $second 'continue' | Out-Null
        $resolved = Send-Command $fixture $second 'observe'
        Assert-True ($resolved.recovery -eq $false -and $resolved.noticeRead -eq $true) 'Resolved recovery did not acknowledge after valid Store.'
        if ($Scenario -in @('schedule-corrupt','slot-schedule-corrupt')) {
            $expected = Get-Content -LiteralPath (Join-Path $fixture.Root 'expected-library.json') -Raw | ConvertFrom-Json
            $expected.schedule = @()
            Assert-True ((Library-Json $expected) -eq (Library-Json $resolved)) 'Schedule-only recovery changed unrelated task/board/config fields.'
        }
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
        $expected = Get-Content -LiteralPath (Join-Path $fixture.Root 'expected-library.json') -Raw | ConvertFrom-Json
        Assert-True ((Library-Json $expected) -eq (Library-Json $initial)) 'Initial upgrade differs field by field from synthetic seed.'
        Assert-True ($initial.tasks.Count -eq 3 -and $initial.boards.Count -eq 3 -and $initial.tasks[0].id -eq 'synthetic-task') 'Rich task migration failed.'
        Assert-True ($initial.tasks[0].subtasks[0].id -eq 'synthetic-subtask' -and $initial.tasks[0].plannedDate -eq 1790812800000) 'Task fields changed.'
        $scheduleCount = if ($Scenario.StartsWith('legacy-')) { 0 } else { 6 }
        Assert-True ($initial.schedule.Count -eq $scheduleCount) 'Schedule migration failed or legacy dates synthesized schedules.'
        $submission = Read-Report $seedLaunch 'screenshot-transaction'
        Assert-True ($submission.passed -eq $true -and $submission.publicSubmission -eq $true -and $submission.ocrLoaded -eq $false -and $submission.rejectedPointerCommit -eq $true -and $submission.statePreservedOnFailure -eq $true) 'Public screenshot submission evidence missing.'
    }
    if ($Scenario -eq 'current') {
        $expectedCurrent = Get-Content -LiteralPath (Join-Path $fixture.Root 'expected-current.json') -Raw | ConvertFrom-Json
        Assert-True ((Library-Json $expectedCurrent) -eq (Library-Json $initial)) 'Current library fields changed.'
    }
    if ($Scenario -eq 'race') {
        $expectedRace = Read-Report $seedLaunch 'raced-current'
        Assert-True ((Library-Json $expectedRace) -eq (Library-Json $initial)) 'Raced current library fields changed.'
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
    Approve-Store $second
    Read-Report $second 'ready' | Out-Null
    $again = Send-Command $fixture $second 'observe'
    Assert-True ((Library-Json $initial) -eq (Library-Json $again)) 'Reopen library differs field by field.'
    $edited = $again
    if ($Scenario -in @('mirror','slots','retry')) {$edited = Send-Command $fixture $second 'modify'}
    if ($Scenario -in @('mirror','slots')) {
        $edited = Send-Command $fixture $second 'import-failure-retry'
        $failedImport = Read-Report $second 'failed-import'
        Assert-True ($failedImport.commitRejected -eq $true -and $failedImport.memoryPreserved -eq $true -and $failedImport.committedStatePreserved -eq $true) 'Failed import rollback evidence missing.'
    }
    if ($Scenario -eq 'slots') { Run-Backup @{Fixture=$fixture; Launch=$second} }
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
    Approve-Store $third
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
    if ((Get-TimeZone).Id -ne $hostZone) { $failed = $true; $script:results.Add(@{passed=$false;failure='Host timezone changed.'}) }
    try { Assert-BuildBundle } catch { $failed=$true; $script:results.Add(@{passed=$false;failure=$_.Exception.Message}) }
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
        if ($launch.Process.HasExited) {
            $launch.Stdout.Result | Set-Content -LiteralPath (Join-Path $launch.Root "stdout-$($launch.Id).log")
            $launch.Stderr.Result | Set-Content -LiteralPath (Join-Path $launch.Root "stderr-$($launch.Id).log")
        }
    }
    $processes = @($script:launches | ForEach-Object {
        @{pid=$_.Id; exe=$_.Exe; startedUtc=$_.Started; root=$_.Root; namespace=$_.Namespace;
          arguments=$_.Arguments; timedOut=$_.TimedOut; exitCode=$_.ExitCode;
          alive=(!$_.Process.HasExited); cleanup=$_.Cleanup}
    })
    $report = @{mode=$Mode; configuration=$Configuration; passed=(!$failed); exe=$exe;
        commit=$revision; source=$trace; normalCandidate=$false; hostTimeZoneBefore=$hostZone; hostTimeZoneAfter=(Get-TimeZone).Id;
        diagnosticBuildProof=$buildProofPath;
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
