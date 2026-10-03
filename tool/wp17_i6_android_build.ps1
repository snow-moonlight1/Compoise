<# Build only: optional official models plus a private debug identity. No install. #>
param(
    [Parameter(Mandatory=$true)][string]$PrivateRoot,
    [Parameter(Mandatory=$true)][string]$OfficialDeploy,
    [Parameter(Mandatory=$true)][string]$NcnnRoot,
    [string]$Flutter = 'D:\Dev_SDKs\Flutter_3.32.8',
    [string]$Sdk = 'D:\Dev_SDKs\Android_studio_SDK',
    [switch]$DeviceTest,
    [switch]$Normal
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$root = [IO.Path]::GetFullPath($PrivateRoot)
if ($root -eq [IO.Path]::GetFullPath($repo)) { throw 'Use an external private artifact directory' }
New-Item -ItemType Directory -Force -Path "$root/logs","$root/artifacts" | Out-Null
$properties = Join-Path $repo 'android/local.properties'
$before = if (Test-Path -LiteralPath $properties) { [IO.File]::ReadAllBytes($properties) } else { $null }
$status = 0
try {
    $lines = @("sdk.dir=$($Sdk.Replace('\','/'))", "flutter.sdk=$($Flutter.Replace('\','/'))")
    if (-not $Normal) {
        & python "$repo/native/ocr/tools/stage_official_bundle.py" --deploy $OfficialDeploy --out "$root/packaged-assets"
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        $lines += @('wp17OcrValidation=true', "wp17OcrModels=$($root.Replace('\','/'))/packaged-assets",
            "wp17OcrNcnnRoot=$($NcnnRoot.Replace('\','/'))", "wp17OcrStbDir=$($NcnnRoot.Replace('\','/'))/third_party")
    }
    [IO.File]::WriteAllLines($properties, $lines)
    $arguments = @('build','apk','--debug','--no-pub')
    $name = if ($Normal) { 'normal' } elseif ($DeviceTest) { 'device' } else { 'isolated' }
    if ($DeviceTest) {
        if ($Normal) { throw 'Device test must use the isolated identity' }
        $arguments += @('--target=test/wp17_i6_device_test.dart','--dart-define=WP17_I6_DEVICE=true')
    }
    # Windows PowerShell 5 treats ordinary native stderr warnings as errors.
    # The process exit code is authoritative; retain both streams in the log.
    $ErrorActionPreference = 'Continue'
    & "$Flutter/bin/flutter.bat" @arguments *> "$root/logs/build-$name.log"
    $status = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($status -eq 0) {
        $apk = "$repo/build/app/outputs/flutter-apk/app-debug.apk"
        $aapt = (Get-ChildItem -LiteralPath "$Sdk/build-tools" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName + '/aapt.exe'
        $facts = & $aapt dump badging $apk
        $expected = if ($Normal) { 'com.matrixflow.app' } else { 'com.matrixflow.app.wp17i6' }
        if (($facts | Select-String '^package:').Line -notmatch "name='$([Regex]::Escape($expected))'") {
            throw 'APK identity check failed; refuse installation'
        }
        $facts | Set-Content -LiteralPath "$root/logs/apk-$name-facts.txt"
        Copy-Item -LiteralPath $apk -Destination "$root/artifacts/wp17-i6-$name.apk"
        Get-FileHash -LiteralPath "$root/artifacts/wp17-i6-$name.apk" -Algorithm SHA256
    }
} finally {
    if ($null -ne $before) { [IO.File]::WriteAllBytes($properties, $before) }
    else { Remove-Item -LiteralPath $properties -ErrorAction SilentlyContinue }
}
exit $status
