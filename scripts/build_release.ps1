<#
.SYNOPSIS
    MatrixFlow AI - release build, clean per-version staging and checksum manifest.
.DESCRIPTION
    Builds the Flutter Android release APK and/or the Windows portable ZIP for a
    single version, stages the artifacts in a clean per-version directory, and
    writes SHA256SUMS.txt plus RELEASE_MANIFEST.txt.

    Release rules enforced by this script:
      * pubspec.yaml must declare X.Y.Z+N, and -ExpectedTag must agree with it.
      * An Android release refuses to run without formal signing credentials, so
        a debug-signed APK can never be staged as a release by accident.
      * The staging directory is recreated for every run, so Android-only,
        Windows-only, All and repeated runs never mix artifacts from older runs.
      * Secrets are never printed. Only the credential source path is reported.
      * The Windows file version and, when the build tools exist, the APK
        package id, versionCode and signing certificate DN are checked against
        pubspec.yaml.

    Toolchain: the OS24 pin (Flutter 3.32.8) is used when available; the
    untouched fallback D:\Dev_SDKs\Flutter_SDK stays in place. Pass
    -AllowUnpinnedSdk only to build from the fallback SDK on purpose.
.PARAMETER Platform
    Build target: 'All' (default), 'Android' or 'Windows'.
.PARAMETER OutputDir
    Parent directory for the per-version staging directory
    (default: <repo root>\release_dist).
.PARAMETER FlutterSdk
    Flutter SDK directory. Default is D:\Dev_SDKs\Flutter_3.32.8 when that
    install exists; otherwise the untouched fallback D:\Dev_SDKs\Flutter_SDK.
.PARAMETER ExpectedTag
    Release tag to compare with pubspec.yaml, for example 'v1.0.0' or 'v1.0.0+1'.
.PARAMETER ValidateOnly
    Check version/tag alignment and print the plan without building or writing
    any artifact. Signing prerequisites are reported, not enforced, so this can
    run as a preflight before credentials are installed.
.PARAMETER AllowUnpinnedSdk
    Continue when the active Flutter SDK does not match the OS24 pin recorded in
    matrixflow-native/toolchain.json.
.EXAMPLE
    powershell -File scripts\build_release.ps1 -Platform Windows -ExpectedTag v1.0.0
.EXAMPLE
    powershell -File scripts\build_release.ps1 -Platform Android -ExpectedTag v1.0.0+1
.NOTES
    Android release credentials come from android/key.properties (or
    android/app/key.properties, see android/key.properties.example) or from the
    ANDROID_KEYSTORE_PATH / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD /
    ANDROID_STORE_PASSWORD environment variables. Password values are never read
    back into the console output.
#>

[CmdletBinding()]
param (
    [ValidateSet('All', 'Android', 'Windows')]
    [string]$Platform = 'All',

    [string]$OutputDir = '',

    [string]$FlutterSdk = '',

    [string]$ExpectedTag = '',

    [switch]$ValidateOnly,

    [switch]$AllowUnpinnedSdk
)

$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$NativeDir = Join-Path $ProjectRoot 'matrixflow-native'

if (-not (Test-Path $NativeDir)) {
    throw "Cannot find matrixflow-native directory: $NativeDir"
}

# Only the storeFile path is read back out of a keystore properties file.
# Password values are never read into the output stream.
function Resolve-StoreFileFromProperties([string]$Path) {
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*storeFile\s*=\s*(.+?)\s*$') {
            return $Matches[1]
        }
    }
    return $null
}

function Get-PropertiesKeyNames([string]$Path) {
    $names = @()
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*([A-Za-z0-9_.]+)\s*=') {
            $names += $Matches[1]
        }
    }
    return $names
}

function Get-LocalPropertiesValue([string]$Path, [string]$Key) {
    if (-not (Test-Path $Path)) { return $null }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        if ($line -match ('^\s*' + [regex]::Escape($Key) + '\s*=\s*(.+?)\s*$')) {
            return ($Matches[1] -replace '\\\\', '\')
        }
    }
    return $null
}

function Find-BuildToolsExe([string]$Name) {
    $candidates = @()
    $sdkFromLocal = Get-LocalPropertiesValue (Join-Path $NativeDir 'android\local.properties') 'sdk.dir'
    if ($sdkFromLocal) { $candidates += (Join-Path $sdkFromLocal 'build-tools') }
    foreach ($variable in @('ANDROID_HOME', 'ANDROID_SDK_ROOT')) {
        $value = [System.Environment]::GetEnvironmentVariable($variable)
        if ($value) { $candidates += (Join-Path $value 'build-tools') }
    }
    foreach ($dir in $candidates) {
        if (-not (Test-Path $dir)) { continue }
        foreach ($version in (Get-ChildItem $dir -Directory | Sort-Object Name -Descending)) {
            foreach ($candidate in @($Name, "$Name.bat", "$Name.exe")) {
                $exe = Join-Path $version.FullName $candidate
                if (Test-Path $exe) { return $exe }
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------- version ----

$PubspecPath = Join-Path $NativeDir 'pubspec.yaml'
$VersionLine = (Get-Content $PubspecPath | Where-Object { $_ -match '^version:' } | Select-Object -First 1)
if (-not $VersionLine) {
    throw "pubspec.yaml does not declare a version line."
}
if ($VersionLine -notmatch '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)\s*$') {
    throw "pubspec.yaml version must be X.Y.Z+N so releases carry a build number. Found: $($VersionLine.Trim())"
}
$AppVersion = $Matches[1]
$BuildNumber = [int]$Matches[2]
$VersionLabel = "$AppVersion+$BuildNumber"

if ($ExpectedTag) {
    $TagVersion = $ExpectedTag.Trim()
    if ($TagVersion.StartsWith('v')) { $TagVersion = $TagVersion.Substring(1) }
    if ($TagVersion -ne $AppVersion -and $TagVersion -ne $VersionLabel) {
        throw "-ExpectedTag points at $ExpectedTag but pubspec.yaml declares $VersionLabel. Refusing to stage a release whose tag and version disagree."
    }
}

# -------------------------------------------------------------- staging dir --

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'release_dist'
}
$OutputDirFull = [System.IO.Path]::GetFullPath($OutputDir)
if ($OutputDirFull -match '^[A-Za-z]:\\?$') {
    throw "Refusing to use the drive root $OutputDirFull as the release output directory."
}

$StagingDirName = "matrixflow-v$VersionLabel"
$StagingDir = [System.IO.Path]::GetFullPath((Join-Path $OutputDirFull $StagingDirName))
$OutputPrefix = $OutputDirFull.TrimEnd('\') + '\'
if (-not $StagingDir.StartsWith($OutputPrefix)) {
    throw "Refusing to stage outside the output directory: $StagingDir"
}
if ((Split-Path -Leaf $StagingDir) -notmatch '^matrixflow-v[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$') {
    throw "Unexpected staging directory name: $StagingDir"
}

$AndroidArtifactName = "matrixflow-v$VersionLabel-android.apk"
$WindowsArtifactName = "matrixflow-v$VersionLabel-windows-portable.zip"

# --------------------------------------------------------------- toolchain ---

if ([string]::IsNullOrWhiteSpace($FlutterSdk)) {
    $PinnedSdk = 'D:\Dev_SDKs\Flutter_3.32.8'
    $FallbackSdk = 'D:\Dev_SDKs\Flutter_SDK'
    if (Test-Path (Join-Path $PinnedSdk 'bin\flutter.bat')) {
        $FlutterSdk = $PinnedSdk
    } else {
        Write-Host "Pinned Flutter 3.32.8 was not found at $PinnedSdk. Using fallback $FallbackSdk."
        $FlutterSdk = $FallbackSdk
    }
}

$FlutterBin = Join-Path $FlutterSdk 'bin\flutter.bat'
if (-not (Test-Path $FlutterBin)) {
    $FlutterCmd = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($FlutterCmd) {
        $FlutterBin = $FlutterCmd.Source
    } elseif ($ValidateOnly) {
        Write-Host 'Flutter SDK was not found; the validate-only run continues without a toolchain probe.'
        $FlutterBin = $null
    } else {
        throw 'Flutter SDK not found. Pass -FlutterSdk or add flutter to PATH.'
    }
}

$ToolchainPath = Join-Path $NativeDir 'toolchain.json'
$Toolchain = $null
if (Test-Path $ToolchainPath) {
    $Toolchain = (Get-Content $ToolchainPath -Raw | ConvertFrom-Json).verified
}

function Get-FlutterVersionInfo([string]$FlutterExe) {
    $raw = & $FlutterExe --version --machine 2>&1 | Out-String
    try {
        return ($raw | ConvertFrom-Json)
    } catch {
        return $null
    }
}

$FlutterInfo = if ($FlutterBin) { Get-FlutterVersionInfo $FlutterBin } else { $null }
$FlutterVersionText = 'not-probed (Flutter SDK not found)'
if ($FlutterInfo) {
    $FlutterVersionText = "$($FlutterInfo.frameworkVersion) (revision $($FlutterInfo.frameworkRevision), engine $($FlutterInfo.engineRevision))"
}
$DartVersionText = if ($FlutterInfo) { $FlutterInfo.dartSdkVersion } else { 'unknown' }

$ToolchainMatch = $true
if ($Toolchain -and $FlutterInfo) {
    foreach ($pair in @(
        @('frameworkVersion', $Toolchain.flutterVersion),
        @('frameworkRevision', $Toolchain.revision),
        @('engineRevision', $Toolchain.engineRevision),
        @('dartSdkVersion', $Toolchain.dartVersion)
    )) {
        if ($FlutterInfo.($pair[0]) -ne $pair[1]) { $ToolchainMatch = $false }
    }
}
if ($Toolchain -and $FlutterBin -and -not $FlutterInfo) { $ToolchainMatch = $false }

# --------------------------------------------------------------- signing ----

$KeyPropertiesCandidates = @(
    (Join-Path $NativeDir 'android\key.properties'),
    (Join-Path $NativeDir 'android\keystore.properties'),
    (Join-Path $NativeDir 'android\app\key.properties'),
    (Join-Path $NativeDir 'android\app\keystore.properties')
)
$KeyPropertiesPath = $KeyPropertiesCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
$KeystorePath = $null
$SigningSource = 'missing'
$MissingSigningKeys = @()

if ($KeyPropertiesPath) {
    $SigningSource = "properties file $KeyPropertiesPath"
    $PropertyKeys = Get-PropertiesKeyNames $KeyPropertiesPath
    foreach ($required in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
        if ($PropertyKeys -notcontains $required) { $MissingSigningKeys += $required }
    }
    $StoreFileValue = Resolve-StoreFileFromProperties $KeyPropertiesPath
    if ($StoreFileValue) {
        $Candidate = Join-Path (Split-Path -Parent $KeyPropertiesPath) $StoreFileValue
        if (-not (Test-Path $Candidate)) { $Candidate = $StoreFileValue }
        if (Test-Path $Candidate) { $KeystorePath = $Candidate }
    }
} elseif ([System.Environment]::GetEnvironmentVariable('ANDROID_KEYSTORE_PATH')) {
    $SigningSource = 'ANDROID_KEYSTORE_PATH environment variable'
    $EnvStore = [System.Environment]::GetEnvironmentVariable('ANDROID_KEYSTORE_PATH')
    if (Test-Path $EnvStore) { $KeystorePath = $EnvStore }
    foreach ($variable in @('ANDROID_KEY_ALIAS', 'ANDROID_KEY_PASSWORD', 'ANDROID_STORE_PASSWORD')) {
        if (-not [System.Environment]::GetEnvironmentVariable($variable)) { $MissingSigningKeys += $variable }
    }
}

$SigningReady = ($KeystorePath -ne $null) -and ($MissingSigningKeys.Count -eq 0)
$SigningProblem = ''
if (-not $SigningReady) {
    if ($SigningSource -eq 'missing') {
        $SigningProblem = 'no android/key.properties or keystore.properties file and no ANDROID_KEYSTORE_PATH environment variable'
    } elseif ($KeystorePath -eq $null) {
        $SigningProblem = "the keystore file referenced by $SigningSource was not found"
    } else {
        $SigningProblem = "the signing source $SigningSource is missing entries: $($MissingSigningKeys -join ', ')"
    }
}

# ------------------------------------------------------------------- plan ---

Write-Host '=================================================' -ForegroundColor Cyan
Write-Host ' MatrixFlow AI Release Build and Packaging' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host "Version:        v$AppVersion (build $BuildNumber)"
if ($ExpectedTag) {
    Write-Host "Expected tag:   $ExpectedTag (matched)"
}
Write-Host "Platform:       $Platform"
Write-Host "Flutter SDK:    $FlutterSdk"
Write-Host "Flutter:        $FlutterVersionText"
Write-Host "Dart:           $DartVersionText"
Write-Host "Toolchain pin:  $(if ($ToolchainMatch) { 'matches matrixflow-native/toolchain.json' } else { 'differs from matrixflow-native/toolchain.json' })"
Write-Host "Staging dir:    $StagingDir"
Write-Host "Signing source: $SigningSource"
Write-Host '-------------------------------------------------'

if (-not $AllowUnpinnedSdk -and $Toolchain -and -not $ToolchainMatch) {
    throw "The active Flutter SDK does not match the OS24 pin in toolchain.json. Install D:\Dev_SDKs\Flutter_3.32.8 or pass -AllowUnpinnedSdk to override deliberately."
}

$BuildsAndroid = ($Platform -eq 'All' -or $Platform -eq 'Android')
$BuildsWindows = ($Platform -eq 'All' -or $Platform -eq 'Windows')

if ($ValidateOnly) {
    Write-Host 'Validate-only run: no build, no artifact, no file written.' -ForegroundColor Yellow
    if ($BuildsAndroid) {
        Write-Host "Android artifact would be: $AndroidArtifactName"
        if ($SigningReady) {
            Write-Host "Android signing prerequisites: OK ($SigningSource)"
        } else {
            Write-Host "Android signing prerequisites: MISSING - a real Android release would be refused. Reason: $SigningProblem" -ForegroundColor Yellow
        }
    }
    if ($BuildsWindows) {
        Write-Host "Windows artifact would be: $WindowsArtifactName (unsigned; Authenticode is not configured)"
    }
    Write-Host "SHA256SUMS.txt would list only the artifacts staged by that run."
    exit 0
}

if ($BuildsAndroid -and -not $SigningReady) {
    throw "Formal release signing credentials are required. $SigningProblem. Refusing to build a debug-signed release APK. See matrixflow-native/android/key.properties.example."
}

if (Test-Path $StagingDir) {
    Write-Host "Cleaning previous staging directory: $StagingDir" -ForegroundColor Gray
    Remove-Item -Path $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
$ExpectedArtifacts = @()
$AndroidProof = @()
$WindowsProof = @()

# ---------------------------------------------------------------- Android ---

if ($BuildsAndroid) {
    Write-Host "`n[1/2] Building Android release APK..." -ForegroundColor Yellow
    $PreviousRequireSigning = $env:REQUIRE_RELEASE_SIGNING
    $env:REQUIRE_RELEASE_SIGNING = 'true'
    try {
        Push-Location $NativeDir
        try {
            & $FlutterBin build apk --release --no-pub
            if ($LASTEXITCODE -ne 0) {
                throw "Android release build failed with exit code: $LASTEXITCODE"
            }
        } finally {
            Pop-Location
        }
    } finally {
        if ($null -eq $PreviousRequireSigning) {
            Remove-Item Env:\REQUIRE_RELEASE_SIGNING -ErrorAction SilentlyContinue
        } else {
            $env:REQUIRE_RELEASE_SIGNING = $PreviousRequireSigning
        }
    }

    $ApkSource = Join-Path $NativeDir 'build\app\outputs\flutter-apk\app-release.apk'
    if (-not (Test-Path $ApkSource)) {
        throw "Built APK not found at: $ApkSource"
    }

    $ApkTarget = Join-Path $StagingDir $AndroidArtifactName
    Copy-Item -Path $ApkSource -Destination $ApkTarget -Force
    $ExpectedArtifacts += $ApkTarget

    $GradlePath = Join-Path $NativeDir 'android\app\build.gradle.kts'
    $GradleText = Get-Content $GradlePath -Raw
    $ApplicationId = [regex]::Match($GradleText, 'applicationId\s*=\s*"([^"]+)"').Groups[1].Value
    $Namespace = [regex]::Match($GradleText, 'namespace\s*=\s*"([^"]+)"').Groups[1].Value
    $AndroidProof += "applicationId=$ApplicationId"
    $AndroidProof += "namespace=$Namespace"

    $ApkSigner = Find-BuildToolsExe 'apksigner'
    if ($ApkSigner) {
        $SignerOutput = (& $ApkSigner verify --print-certs $ApkTarget 2>&1 | Out-String)
        $SignerExit = $LASTEXITCODE
        $DnMatch = [regex]::Match($SignerOutput, 'Signer #1 certificate DN:\s*(.+)')
        $SignerDn = if ($DnMatch.Success) { $DnMatch.Groups[1].Value.Trim() } else { 'unknown' }
        if ($SignerExit -ne 0) {
            if ($SignerOutput -match '(?i)does not verify|not signed|unsigned|Missing') {
                throw "apksigner reports that $AndroidArtifactName is not properly signed. Refusing to stage it as a formal release."
            }
            Write-Host '  WARNING: apksigner could not verify the staged APK; recorded as unverified.' -ForegroundColor Yellow
            $AndroidProof += 'apkSignature=unverified (apksigner could not run)'
        } elseif ($SignerDn -match 'CN=Android Debug') {
            throw "The staged APK is signed with the Android debug certificate (CN=Android Debug). Refusing to stage it as a formal release."
        } else {
            $AndroidProof += "apkSignatureDN=$SignerDn"
        }
    } else {
        Write-Host '  WARNING: apksigner was not found in the Android build-tools; the staged APK signature stays unverified.' -ForegroundColor Yellow
        $AndroidProof += 'apkSignature=unverified (apksigner not found)'
    }

    $Aapt2 = Find-BuildToolsExe 'aapt2'
    if ($Aapt2) {
        $Badging = (& $Aapt2 dump badging $ApkTarget 2>&1 | Out-String)
        $PackageMatch = [regex]::Match($Badging, "package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'")
        if (-not $PackageMatch.Success) {
            $AndroidProof += 'apkPackage=unparsed'
        } else {
            if ($PackageMatch.Groups[1].Value -ne $ApplicationId) {
                throw "The staged APK declares package '$($PackageMatch.Groups[1].Value)' but applicationId is '$ApplicationId'. Refusing to stage a mismatched release."
            }
            if ($PackageMatch.Groups[2].Value -ne "$BuildNumber") {
                throw "The staged APK declares versionCode '$($PackageMatch.Groups[2].Value)' but pubspec.yaml declares build $BuildNumber."
            }
            if ($PackageMatch.Groups[3].Value -ne $AppVersion) {
                throw "The staged APK declares versionName '$($PackageMatch.Groups[3].Value)' but pubspec.yaml declares $AppVersion."
            }
            $AndroidProof += "apkPackage=$($PackageMatch.Groups[1].Value)"
            $AndroidProof += "apkVersionCode=$($PackageMatch.Groups[2].Value)"
            $AndroidProof += "apkVersionName=$($PackageMatch.Groups[3].Value)"
        }
    } else {
        Write-Host '  WARNING: aapt2 was not found in the Android build-tools; the APK package id and version stay unverified.' -ForegroundColor Yellow
        $AndroidProof += 'apkPackage=unverified (aapt2 not found)'
    }
}

# ---------------------------------------------------------------- Windows ---

if ($BuildsWindows) {
    Write-Host "`n[2/2] Building Windows release desktop application..." -ForegroundColor Yellow
    Push-Location $NativeDir
    try {
        & $FlutterBin build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "Windows release build failed with exit code: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $WindowsReleaseDir = Join-Path $NativeDir 'build\windows\x64\runner\Release'
    if (-not (Test-Path $WindowsReleaseDir)) {
        throw "Windows Release output dir not found: $WindowsReleaseDir"
    }
    $ExePath = Join-Path $WindowsReleaseDir 'matrixflow_native.exe'
    if (-not (Test-Path $ExePath)) {
        throw "Windows executable not found: $ExePath"
    }

    $ExeInfo = (Get-Item $ExePath).VersionInfo
    $VersionParts = $AppVersion.Split('.')
    $NumericExpected = @([int]$VersionParts[0], [int]$VersionParts[1], [int]$VersionParts[2], $BuildNumber)
    $NumericActual = @($ExeInfo.FileMajorPart, $ExeInfo.FileMinorPart, $ExeInfo.FileBuildPart, $ExeInfo.FilePrivatePart)
    if (($NumericActual -join '.') -ne ($NumericExpected -join '.')) {
        throw "The built executable carries numeric file version $($NumericActual -join '.') but pubspec.yaml implies $($NumericExpected -join '.')."
    }
    if ($ExeInfo.ProductName -ne 'MatrixFlow AI') {
        throw "The built executable reports ProductName '$($ExeInfo.ProductName)'; expected 'MatrixFlow AI'."
    }
    # Flutter's Windows template writes FLUTTER_VERSION (for example 1.0.0+1) as
    # the version string while the numeric fields carry version plus build.
    if (@($VersionLabel, "$AppVersion.$BuildNumber") -notcontains $ExeInfo.FileVersion) {
        throw "The built executable reports FileVersion '$($ExeInfo.FileVersion)'; expected '$VersionLabel' or '$AppVersion.$BuildNumber'."
    }
    if ($ExeInfo.LegalCopyright -notmatch 'com\.matrixflow') {
        throw "The built executable reports an unexpected LegalCopyright: '$($ExeInfo.LegalCopyright)'."
    }

    $Authenticode = Get-AuthenticodeSignature -FilePath $ExePath
    $WindowsProof += "productName=$($ExeInfo.ProductName)"
    $WindowsProof += "fileVersionString=$($ExeInfo.FileVersion)"
    $WindowsProof += "fileVersionNumeric=$(($NumericActual -join '.'))"
    $WindowsProof += "fileDescription=$($ExeInfo.FileDescription)"
    $WindowsProof += "originalFilename=$($ExeInfo.OriginalFilename)"
    $WindowsProof += "legalCopyright=$($ExeInfo.LegalCopyright)"
    $WindowsProof += "authenticode=$($Authenticode.Status)"

    $WindowsZipPath = Join-Path $StagingDir $WindowsArtifactName
    Write-Host 'Creating Windows portable ZIP archive...' -ForegroundColor Gray
    Compress-Archive -Path "$WindowsReleaseDir\*" -DestinationPath $WindowsZipPath -CompressionLevel Optimal
    $ExpectedArtifacts += $WindowsZipPath

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [System.IO.Compression.ZipFile]::OpenRead($WindowsZipPath)
    try {
        $EntryNames = @($Archive.Entries | ForEach-Object { $_.FullName -replace '/', '\' })
    } finally {
        $Archive.Dispose()
    }
    if ($EntryNames -notcontains 'matrixflow_native.exe') {
        throw 'The staged ZIP does not contain matrixflow_native.exe.'
    }
    if ($EntryNames -notcontains 'data\app.so') {
        throw 'The staged ZIP does not contain data\app.so.'
    }
    $WindowsProof += "zipEntries=$($EntryNames.Count)"
}

# ------------------------------------------------- staging and checksums ----

$StagedFiles = @(Get-ChildItem -Path $StagingDir -File | ForEach-Object { $_.FullName })
$ExpectedNames = @($ExpectedArtifacts | ForEach-Object { Split-Path -Leaf $_ })
foreach ($Staged in $StagedFiles) {
    if ($ExpectedNames -notcontains (Split-Path -Leaf $Staged)) {
        throw "The staging directory contains an unexpected file: $(Split-Path -Leaf $Staged). Old artifacts must not be mixed into a new release."
    }
}

$ChecksumLines = @()
foreach ($Artifact in $ExpectedArtifacts) {
    $FileName = Split-Path -Leaf $Artifact
    $FileHash = (Get-FileHash -Path $Artifact -Algorithm SHA256).Hash.ToLower()
    $FileSize = (Get-Item $Artifact).Length
    $ChecksumLines += "$FileHash  $FileName"
    Write-Host ("  {0}  {1} ({2:N0} bytes)" -f $FileHash, $FileName, $FileSize) -ForegroundColor Gray
}

$ChecksumFilePath = Join-Path $StagingDir 'SHA256SUMS.txt'
$ChecksumLines | Out-File -FilePath $ChecksumFilePath -Encoding ASCII -Force

# ------------------------------------------------------------- manifest -----

$GitCommit = (& git -C $ProjectRoot rev-parse HEAD 2>$null)
$GitBranch = (& git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null)
$GitDirty = @(& git -C $ProjectRoot status --porcelain 2>$null).Count -gt 0
$TagRecord = if ($ExpectedTag) { $ExpectedTag } else { 'not-provided' }

$ManifestLines = @(
    'MatrixFlow AI release manifest (OS26)',
    "version=$AppVersion",
    "buildNumber=$BuildNumber",
    "tag=$TagRecord",
    "platform=$Platform",
    "stagedAtUtc=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    "gitCommit=$GitCommit",
    "gitBranch=$GitBranch",
    "gitWorkingTreeDirty=$GitDirty",
    "flutterSdk=$FlutterSdk",
    "flutterVersion=$FlutterVersionText",
    "dartVersion=$DartVersionText",
    "toolchainPinMatches=$ToolchainMatch",
    "signingSource=$SigningSource",
    'windowsCodeSigning=unsigned (Authenticode not configured, see docs/OS26_NOTES.md)',
    ''
)
if ($AndroidProof.Count -gt 0) {
    $ManifestLines += '[android]'
    $ManifestLines += $AndroidProof
    $ManifestLines += ''
}
if ($WindowsProof.Count -gt 0) {
    $ManifestLines += '[windows]'
    $ManifestLines += $WindowsProof
    $ManifestLines += ''
}
$ManifestLines += '[artifacts]'
foreach ($Line in $ChecksumLines) { $ManifestLines += $Line }
$ManifestLines += ''
$ManifestLines += 'SHA256SUMS.txt lists exactly the artifact lines above, one per staged file.'

$ManifestPath = Join-Path $StagingDir 'RELEASE_MANIFEST.txt'
$ManifestLines | Out-File -FilePath $ManifestPath -Encoding UTF8 -Force

Write-Host ''
Write-Host '=================================================' -ForegroundColor Green
Write-Host ' MatrixFlow AI packaging completed' -ForegroundColor Green
Write-Host '=================================================' -ForegroundColor Green
Write-Host "Staging dir: $StagingDir"
Write-Host 'Manifest:    RELEASE_MANIFEST.txt'
Write-Host 'Checksums:   SHA256SUMS.txt'
Get-ChildItem $StagingDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
