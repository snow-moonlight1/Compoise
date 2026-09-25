param(
    [string]$Baseline = '9d3bbc4',
    [string]$Current = '9e30f01'
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$destination = Join-Path ([IO.Path]::GetTempPath()) ('matrixflow-focus-review-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $destination | Out-Null
Push-Location $repo
try {
    git archive --format=zip "--output=$destination/current.zip" $Current matrixflow-native
    if ($LASTEXITCODE -ne 0) { throw 'Current archive failed' }
    git archive --format=zip "--output=$destination/baseline.zip" $Baseline matrixflow-native/lib
    if ($LASTEXITCODE -ne 0) { throw 'Baseline archive failed' }
    Expand-Archive -LiteralPath "$destination/current.zip" -DestinationPath "$destination/current"
    Expand-Archive -LiteralPath "$destination/baseline.zip" -DestinationPath "$destination/baseline"
    $app = Join-Path $destination 'current/matrixflow-native'
    $baselineLib = [Uri]::new((Join-Path $destination 'baseline/matrixflow-native/lib')).AbsoluteUri.TrimEnd('/')
    $template = Get-Content -LiteralPath 'matrixflow-native/tool/review/focus_review_bench.dart.template' -Raw
    $template.Replace('@@BASE@@', $baselineLib) | Set-Content -LiteralPath "$app/focus_review.dart" -Encoding utf8
    $gradle = Get-Content -LiteralPath "$app/android/app/build.gradle.kts" -Raw
    if ($gradle -notmatch 'applicationId = "com.matrixflow.app"') { throw 'Unexpected app ID; inspect before preparing' }
    $gradle.Replace('applicationId = "com.matrixflow.app"', 'applicationId = "com.matrixflow.review20260925"') | Set-Content -LiteralPath "$app/android/app/build.gradle.kts" -Encoding utf8
    $manifest = Get-Content -LiteralPath "$app/android/app/src/main/AndroidManifest.xml" -Raw
    ($manifest -replace 'android:label="[^"]+"', 'android:label="MatrixFlow Review"') | Set-Content -LiteralPath "$app/android/app/src/main/AndroidManifest.xml" -Encoding utf8
    # The archived baseline still imports this dependency. Only the temporary
    # harness needs it; the maintained application's pubspec is untouched.
    $pubspec = Get-Content -LiteralPath "$app/pubspec.yaml" -Raw
    if ($pubspec -notmatch '(?m)^  hotkey_manager:') {
        $pubspec = $pubspec -replace '(?m)^dependencies:\s*$', "dependencies:`n  hotkey_manager: ^0.2.3"
        $pubspec | Set-Content -LiteralPath "$app/pubspec.yaml" -Encoding utf8
    }
    Write-Output "Prepared synthetic harness: $app"
    Write-Output 'Build with fixed Flutter SDK: flutter pub get; flutter build apk --profile --target focus_review.dart --no-pub'
    Write-Output 'No device installation was performed. Application ID: com.matrixflow.review20260925'
} finally {
    Pop-Location
}
