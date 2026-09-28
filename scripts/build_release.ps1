<#
.SYNOPSIS
    Compoise - release build, clean per-version staging and checksum manifest.
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

    Toolchain: the Flutter version in toolchain.json is required unless
    -AllowUnpinnedSdk is explicitly supplied.

    Platforms: this script stages Android and Windows artifacts only. The Linux
    desktop build is a preview; CI compiles it to prove the release toolchain
    still works, and no Linux installer or archive is published. See
    docs/RELEASE_VALIDATION.md.
.PARAMETER Platform
    Build target: 'All' (default), 'Android' or 'Windows'.
.PARAMETER OutputDir
    Parent directory for the per-version staging directory
    (default: <repo root>\release_dist).
.PARAMETER FlutterSdk
    Optional Flutter SDK directory. By default, flutter is located on PATH.
.PARAMETER ExpectedTag
    Release tag to compare with pubspec.yaml, for example 'v1.0.0' or 'v1.0.0+1'.
.PARAMETER ValidateOnly
    Check version/tag alignment and print the plan without building or writing
    any artifact. Signing prerequisites are reported, not enforced, so this can
    run as a preflight before credentials are installed.
.PARAMETER AllowUnpinnedSdk
    Continue when the active Flutter SDK does not match the OS24 pin recorded in
    toolchain.json.
.EXAMPLE
    powershell -File scripts\build_release.ps1 -Platform Windows -ExpectedTag v1.0.0
.EXAMPLE
    powershell -File scripts\build_release.ps1 -Platform Android -ExpectedTag v1.0.0+1
.EXAMPLE
    # Release preflight, also runnable under pwsh on Linux:
    pwsh -File scripts/build_release.ps1 -Platform All -ExpectedTag v1.0.0+1 -ValidateOnly
.NOTES
    Android release credentials come from android/key.properties (or
    android/app/key.properties, see android/key.properties.example) or from the
    ANDROID_KEYSTORE_PATH / ANDROID_KEY_ALIAS / ANDROID_KEY_PASSWORD /
    ANDROID_STORE_PASSWORD environment variables. Password values are never read
    back into the console output. A relative storeFile is resolved the way
    android/app/build.gradle.kts resolves it: the app module directory first,
    then the directory that holds the properties file.
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
$FlutterDir = $ProjectRoot

if (-not (Test-Path $FlutterDir)) {
    throw "Cannot find Flutter project root: $FlutterDir"
}

# Paths are combined with the host separator so the plan stage also runs under
# pwsh on the Linux release preflight runner.
function Join-RepoPath([string]$Base, [string[]]$Parts) {
    return [System.IO.Path]::Combine([string[]](@($Base) + $Parts))
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

# Resolution order mirrors android/app/build.gradle.kts so this script never
# refuses a layout Gradle accepts: an absolute path is used as declared,
# otherwise the app module directory first and then the directory that holds
# the properties file.
function Resolve-KeystorePath([string]$Declared, [string]$PropertiesDir) {
    if (-not $Declared) { return $null }
    $candidates = @()
    if ([System.IO.Path]::IsPathRooted($Declared)) {
        $candidates += $Declared
    } else {
        $candidates += (Join-RepoPath $FlutterDir @('android', 'app', $Declared))
        if ($PropertiesDir) { $candidates += (Join-Path $PropertiesDir $Declared) }
        $candidates += $Declared
    }
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    return $null
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
    $sdkFromLocal = Get-LocalPropertiesValue (Join-RepoPath $FlutterDir @('android', 'local.properties')) 'sdk.dir'
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

$PubspecPath = Join-Path $FlutterDir 'pubspec.yaml'
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
if ($OutputDirFull -match '^[A-Za-z]:\\?$' -or $OutputDirFull -eq [System.IO.Path]::DirectorySeparatorChar) {
    throw "Refusing to use the filesystem root $OutputDirFull as the release output directory."
}

$StagingDirName = "compoise-v$VersionLabel"
$StagingDir = [System.IO.Path]::GetFullPath((Join-Path $OutputDirFull $StagingDirName))
# Compare the parent directory instead of a separator-joined prefix so the check
# behaves the same on Windows and on the Linux preflight runner.
if ((Split-Path -Parent $StagingDir) -ne $OutputDirFull) {
    throw "Refusing to stage outside the output directory: $StagingDir"
}
if ((Split-Path -Leaf $StagingDir) -notmatch '^compoise-v[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$') {
    throw "Unexpected staging directory name: $StagingDir"
}

$AndroidArtifactName = "compoise-v$VersionLabel-android.apk"
$WindowsArtifactName = "compoise-v$VersionLabel-windows-portable.zip"

# --------------------------------------------------------------- toolchain ---

$FlutterBin = $null
if (-not [string]::IsNullOrWhiteSpace($FlutterSdk)) {
    # The SDK ships both launchers; pick the one the host can execute, because
    # running flutter.bat under a POSIX shell fails with 'Cannot run a document'.
    $LauncherNames = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        @('flutter.bat', 'flutter')
    } else {
        @('flutter', 'flutter.bat')
    }
    foreach ($launcher in $LauncherNames) {
        $candidate = Join-RepoPath $FlutterSdk @('bin', $launcher)
        if (Test-Path $candidate) { $FlutterBin = $candidate; break }
    }
    if (-not $FlutterBin) {
        throw "Flutter was not found under the supplied SDK directory: $FlutterSdk"
    }
} else {
    $FlutterCmd = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($FlutterCmd) {
        $FlutterBin = $FlutterCmd.Source
        $FlutterSdk = Split-Path -Parent (Split-Path -Parent $FlutterBin)
    } elseif ($ValidateOnly) {
        Write-Host 'Flutter SDK was not found; the validate-only run continues without a toolchain probe.'
    } else {
        throw 'Flutter SDK not found. Pass -FlutterSdk or add flutter to PATH.'
    }
}

$ToolchainPath = Join-Path $FlutterDir 'toolchain.json'
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

# 'not-probed' is never reported as compliance: a validate-only run may continue
# without a Flutter SDK, and must not claim the OS24 pin was satisfied.
$ToolchainPinState = 'not-probed'
$ToolchainPinDiff = @()
if ($Toolchain -and $FlutterInfo) {
    $ToolchainPinState = 'matches'
    foreach ($pair in @(
        @('frameworkVersion', $Toolchain.flutterVersion),
        @('frameworkRevision', $Toolchain.revision),
        @('engineRevision', $Toolchain.engineRevision),
        @('dartSdkVersion', $Toolchain.dartVersion)
    )) {
        if ($FlutterInfo.($pair[0]) -ne $pair[1]) {
            $ToolchainPinState = 'differs'
            $ToolchainPinDiff += "$($pair[0]) expected '$($pair[1])', actual '$($FlutterInfo.($pair[0]))'"
        }
    }
} elseif ($Toolchain -and $FlutterBin) {
    $ToolchainPinState = 'unreadable'
}

$ToolchainPinText = switch ($ToolchainPinState) {
    'matches' { 'matches toolchain.json' }
    'differs' { "differs from toolchain.json ($($ToolchainPinDiff -join '; '))" }
    'unreadable' { 'not verified (flutter --version --machine gave no readable output)' }
    default { 'not probed (Flutter SDK not found)' }
}

# --------------------------------------------------------------- signing ----

$KeyPropertiesCandidates = @(
    (Join-RepoPath $FlutterDir @('android', 'key.properties')),
    (Join-RepoPath $FlutterDir @('android', 'keystore.properties')),
    (Join-RepoPath $FlutterDir @('android', 'app', 'key.properties')),
    (Join-RepoPath $FlutterDir @('android', 'app', 'keystore.properties'))
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
    $KeystorePath = Resolve-KeystorePath $StoreFileValue (Split-Path -Parent $KeyPropertiesPath)
} elseif ([System.Environment]::GetEnvironmentVariable('ANDROID_KEYSTORE_PATH')) {
    $SigningSource = 'ANDROID_KEYSTORE_PATH environment variable'
    $EnvStore = [System.Environment]::GetEnvironmentVariable('ANDROID_KEYSTORE_PATH')
    $KeystorePath = Resolve-KeystorePath $EnvStore $null
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
Write-Host ' Compoise Release Build and Packaging' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host "Version:        v$AppVersion (build $BuildNumber)"
if ($ExpectedTag) {
    Write-Host "Expected tag:   $ExpectedTag (matched)"
}
Write-Host "Platform:       $Platform"
Write-Host "Flutter SDK:    $FlutterSdk"
Write-Host "Flutter:        $FlutterVersionText"
Write-Host "Dart:           $DartVersionText"
Write-Host "Toolchain pin:  $ToolchainPinText"
Write-Host "Staging dir:    $StagingDir"
Write-Host "Signing source: $SigningSource"
Write-Host '-------------------------------------------------'

if (-not $AllowUnpinnedSdk -and $Toolchain -and $FlutterBin -and $ToolchainPinState -ne 'matches') {
    throw "The active Flutter SDK does not match or cannot be read against the version recorded in toolchain.json. Install the pinned version or pass -AllowUnpinnedSdk to override deliberately."
}

$BuildsAndroid = ($Platform -eq 'All' -or $Platform -eq 'Android')
$BuildsWindows = ($Platform -eq 'All' -or $Platform -eq 'Windows')

if ($ValidateOnly) {
    Write-Host 'Validate-only run: no build, no artifact, no file written.' -ForegroundColor Yellow
    if ($BuildsAndroid) {
        Write-Host "Android artifact would be: $AndroidArtifactName"
        if ($SigningReady) {
            Write-Host "Android signing prerequisites: OK ($SigningSource; keystore $KeystorePath)"
        } else {
            Write-Host "Android signing prerequisites: MISSING - a real Android release would be refused. Reason: $SigningProblem" -ForegroundColor Yellow
        }
    }
    if ($BuildsWindows) {
        Write-Host "Windows artifact would be: $WindowsArtifactName (unsigned; Authenticode is not configured)"
    }
    Write-Host 'Linux desktop: preview only. CI compiles the release bundle to prove the toolchain still builds; this script stages and publishes no Linux artifact.'
    Write-Host "SHA256SUMS.txt would list only the artifacts staged by that run."
    exit 0
}

if ($BuildsAndroid -and -not $SigningReady) {
    throw "Formal release signing credentials are required. $SigningProblem. Refusing to build a debug-signed release APK. See android/key.properties.example."
}

if (Test-Path $StagingDir) {
    Write-Host "Cleaning previous staging directory: $StagingDir" -ForegroundColor Gray
    Remove-Item -Path $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null
$ExpectedArtifacts = @()
$AndroidProof = @()
$WindowsProof = @()
$WindowsSigning = 'not staged by this run'

# ---------------------------------------------------------------- Android ---

if ($BuildsAndroid) {
    Write-Host "`n[1/2] Building Android release APK..." -ForegroundColor Yellow
    $PreviousRequireSigning = $env:REQUIRE_RELEASE_SIGNING
    $env:REQUIRE_RELEASE_SIGNING = 'true'
    try {
        Push-Location $FlutterDir
        try {
            # Keep the complete Material glyph font in release builds. The
            # screenshot-backed Android smoke showed that tree shaking dropped
            # glyphs referenced through shared/dynamic IconData call sites.
            & $FlutterBin build apk --release --no-pub --no-tree-shake-icons
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

    $ApkSource = Join-RepoPath $FlutterDir @('build', 'app', 'outputs', 'flutter-apk', 'app-release.apk')
    if (-not (Test-Path $ApkSource)) {
        throw "Built APK not found at: $ApkSource"
    }

    $ApkTarget = Join-Path $StagingDir $AndroidArtifactName
    Copy-Item -Path $ApkSource -Destination $ApkTarget -Force
    $ExpectedArtifacts += $ApkTarget

    $GradlePath = Join-RepoPath $FlutterDir @('android', 'app', 'build.gradle.kts')
    $GradleText = Get-Content $GradlePath -Raw
    $ApplicationId = [regex]::Match($GradleText, 'applicationId\s*=\s*"([^"]+)"').Groups[1].Value
    $Namespace = [regex]::Match($GradleText, 'namespace\s*=\s*"([^"]+)"').Groups[1].Value
    $AndroidProof += "applicationId=$ApplicationId"
    $AndroidProof += "namespace=$Namespace"

    $ApkSigner = Find-BuildToolsExe 'apksigner'
    if ($ApkSigner) {
        $SignerOutput = (& $ApkSigner verify --print-certs $ApkTarget 2>&1 | Out-String)
        $SignerExit = $LASTEXITCODE
        $DnMatch = [regex]::Match($SignerOutput, '(?m)^(?:Signer #1 certificate DN|V[0-9]+ Signer: certificate DN):\s*(.+)')
        $SignerDn = if ($DnMatch.Success) { $DnMatch.Groups[1].Value.Trim() } else { 'unknown' }
        $DigestMatch = [regex]::Match($SignerOutput, '(?im)certificate SHA-256 digest:\s*([0-9a-f]{2,})')
        $SignerDigest = if ($DigestMatch.Success) { $DigestMatch.Groups[1].Value.Trim().ToLower() } else { 'unknown' }
        if ($SignerExit -ne 0) {
            if ($SignerOutput -match '(?i)does not verify|not signed|unsigned|Missing') {
                throw "apksigner reports that $AndroidArtifactName is not properly signed. Refusing to stage it as a formal release."
            }
            Write-Host '  WARNING: apksigner could not verify the staged APK; recorded as unverified.' -ForegroundColor Yellow
            $AndroidProof += 'apkSignature=unverified (apksigner could not run)'
        } elseif ($SignerDn -match 'CN=Android Debug') {
            throw "The staged APK is signed with the Android debug certificate (CN=Android Debug). Refusing to stage it as a formal release."
        } elseif ($SignerDn -eq 'unknown') {
            Write-Host '  WARNING: apksigner verified the APK but printed no signer certificate DN; the manifest records the signature as unparsed.' -ForegroundColor Yellow
            $AndroidProof += 'apkSignature=unparsed (no signer certificate DN in apksigner output)'
        } else {
            $AndroidProof += "apkSignatureDN=$SignerDn"
            $AndroidProof += "apkSignatureCertSha256=$SignerDigest"
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
    Push-Location $FlutterDir
    try {
        & $FlutterBin build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "Windows release build failed with exit code: $LASTEXITCODE"
        }
    } finally {
        Pop-Location
    }

    $WindowsReleaseDir = Join-RepoPath $FlutterDir @('build', 'windows', 'x64', 'runner', 'Release')
    if (-not (Test-Path $WindowsReleaseDir)) {
        throw "Windows Release output dir not found: $WindowsReleaseDir"
    }
    $ExePath = Join-Path $WindowsReleaseDir 'compoise.exe'
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
    if ($ExeInfo.ProductName -ne 'Compoise') {
        throw "The built executable reports ProductName '$($ExeInfo.ProductName)'; expected 'Compoise'."
    }
    # Flutter's Windows template writes FLUTTER_VERSION (for example 1.0.0+1) as
    # the version string while the numeric fields carry version plus build.
    if (@($VersionLabel, "$AppVersion.$BuildNumber") -notcontains $ExeInfo.FileVersion) {
        throw "The built executable reports FileVersion '$($ExeInfo.FileVersion)'; expected '$VersionLabel' or '$AppVersion.$BuildNumber'."
    }
    if ($ExeInfo.LegalCopyright -notmatch 'Compoise contributors') {
        throw "The built executable reports an unexpected LegalCopyright: '$($ExeInfo.LegalCopyright)'; expected the Compoise contributors notice."
    }
    if ($ExeInfo.CompanyName -ne 'Compoise') {
        throw "The built executable reports CompanyName '$($ExeInfo.CompanyName)'; expected 'Compoise'."
    }

    $Authenticode = Get-AuthenticodeSignature -FilePath $ExePath
    # A release is either cleanly unsigned (today) or carries a valid signature;
    # a broken or untrusted signature must never reach the staging directory.
    switch ($Authenticode.Status) {
        'Valid' {
            $WindowsSigning = "signed (Authenticode valid; signer $($Authenticode.SignerCertificate.Subject))"
        }
        'NotSigned' {
            $WindowsSigning = 'unsigned (Authenticode is not configured)'
        }
        default {
            throw "The Windows executable reports Authenticode status '$($Authenticode.Status)'. Refusing to stage a binary whose signature is broken or untrusted."
        }
    }
    # path_provider_windows builds the application-support directory out of
    # CompanyName and ProductName, so this pair decides which task library the
    # build opens. Changing either value moves the library: see
    # docs/RELEASE_VALIDATION.md before doing it.
    $WindowsAppDataDir = Join-Path ([Environment]::GetFolderPath('ApplicationData')) (Join-Path $ExeInfo.CompanyName $ExeInfo.ProductName)
    $WindowsProof += "productName=$($ExeInfo.ProductName)"
    $WindowsProof += "companyName=$($ExeInfo.CompanyName)"
    $WindowsProof += "appDataDir=$WindowsAppDataDir"
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
        # ZIP entries always use '/', independent of the host separator.
        $EntryNames = @($Archive.Entries | ForEach-Object { $_.FullName -replace '\\', '/' })
    } finally {
        $Archive.Dispose()
    }
    if ($EntryNames -notcontains 'compoise.exe') {
        throw 'The staged ZIP does not contain compoise.exe.'
    }
    if ($EntryNames -notcontains 'data/app.so') {
        throw 'The staged ZIP does not contain data/app.so.'
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
# Untracked noise counts as dirty: `flutter pub get` regenerates
# linux/flutter/generated_*, which the repository does not track. The paths are
# recorded so a reviewer can tell that apart from a real source change.
$GitStatus = @(& git -C $ProjectRoot status --porcelain 2>$null)
$GitDirty = $GitStatus.Count -gt 0
$GitDirtyPaths = (($GitStatus | ForEach-Object { $_.Trim() }) -join ' | ')
$TagRecord = if ($ExpectedTag) { $ExpectedTag } else { 'not-provided' }

$ManifestLines = @(
    'Compoise release manifest',
    "version=$AppVersion",
    "buildNumber=$BuildNumber",
    "tag=$TagRecord",
    "platform=$Platform",
    "stagedAtUtc=$([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))",
    "gitCommit=$GitCommit",
    "gitBranch=$GitBranch",
    "gitWorkingTreeDirty=$GitDirty",
    "gitWorkingTreePaths=$GitDirtyPaths",
    "flutterSdk=$FlutterSdk",
    "flutterVersion=$FlutterVersionText",
    "dartVersion=$DartVersionText",
    "toolchainPinState=$ToolchainPinState",
    "toolchainPinMatches=$($ToolchainPinState -eq 'matches')",
    "signingSource=$SigningSource",
    "windowsCodeSigning=$WindowsSigning",
    'license=GPL-3.0-only',
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
Write-Host ' Compoise packaging completed' -ForegroundColor Green
Write-Host '=================================================' -ForegroundColor Green
Write-Host "Staging dir: $StagingDir"
Write-Host 'Manifest:    RELEASE_MANIFEST.txt'
Write-Host 'Checksums:   SHA256SUMS.txt'
Get-ChildItem $StagingDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
